#!/usr/bin/env python3
"""Compare a saved solver against the current one; clean all benchmark outputs."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--before', type=Path, required=True, help='Baseline binary beside its libomp.dylib')
parser.add_argument('--after', type=Path, default=root / 'build/Sui.app/Contents/Resources/solver/console_solver')
parser.add_argument('--resources', type=Path, default=root / 'build/Sui.app/Contents/Resources/solver/resources')
parser.add_argument('--preflight-input', type=Path, help='Optional large input; estimate only, never train it')
args = parser.parse_args()
binaries = {'before': args.before.resolve(), 'after': args.after.resolve()}
resources = args.resources.resolve()
cases = [
    ('river', 'Qs,8d,7h,2c,3s', 'AA,KK,QQ,JJ,AKs,AKo', 'T9s,JTs,43s', 0, 1),
    ('turn-exact', 'Qs,8d,7h,2c', '9cTc:1,9dTd:0.0001', 'JcQc:1,JhQh:0.2', 0, 1),
    ('flop', 'Qs,8d,7h', 'T9s', 'JTs,43s', 0, 1),
    ('flop-iso', 'Qs,8s,7h', 'T9s', 'JTs,43s', 1, 1),
    ('flop-four-threads', 'Qs,8d,7h', 'T9s', 'JTs,43s', 0, 4),
]
with tempfile.TemporaryDirectory(prefix='sui-memory-check-') as temp:
    work_root = Path(temp)
    # A fresh Python child per measurement gives per-solve ru_maxrss, without
    # inheriting the previous run's high-water mark. macOS reports this in bytes.
    runner = work_root / 'run.py'
    runner.write_text('import subprocess,resource,sys\nr=subprocess.run([sys.argv[1],"-i","input.txt","-r",sys.argv[2]])\nprint("PEAK_RSS_BYTES:",resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss)\nsys.exit(r.returncode)\n')
    report = []
    for name, board, ip, oop, iso, threads in cases:
        script = f'set_pot 4\nset_effective_stack 10\nset_board {board}\nset_range_ip {ip}\nset_range_oop {oop}\n'
        for player in ['ip', 'oop']:
            for street in ['flop', 'turn', 'river']:
                for action in ['bet', 'raise', 'donk']:
                    script += f'set_bet_sizes {player},{street},{action},33.333333,150\n'
        script += f'set_allin_threshold 1\nbuild_tree\nset_thread_num {threads}\nset_accuracy 0\nset_max_iteration 21\nset_print_interval 10\nset_use_isomorphism {iso}\nstart_solve\nset_dump_rounds 1\ndump_result result.json\n'
        outputs, stats = [], {}
        for label, binary in binaries.items():
            work = work_root / (name + '-' + label)
            work.mkdir(); (work / 'input.txt').write_text(script)
            start = time.monotonic()
            with (work / 'log.txt').open('w') as log:
                result = subprocess.run([sys.executable, str(runner), str(binary), str(resources)], cwd=work,
                                        stdout=log, stderr=log, env=dict(os.environ, SUI_SOLVER_MEMORY_LIMIT_MB='4096'), timeout=180)
            assert result.returncode == 0, (name, label, (work / 'log.txt').read_text()[-3000:])
            text = (work / 'log.txt').read_text()
            peak = int(re.search(r'PEAK_RSS_BYTES: (\d+)', text)[1])
            estimate = float(re.search(r'Sui estimated strategy storage: ([0-9.]+)', text)[1])
            outputs.append((json.loads((work / 'result.json').read_text()),
                            [(v['iteration'], v['exploitibility']) for v in map(json.loads, (work / 'tmp_log.txt').read_text().splitlines())]))
            stats[label] = dict(rssMiB=round(peak / 1024**2, 2), wallSeconds=round(time.monotonic() - start, 3), estimateMiB=estimate)
        assert outputs[0] == outputs[1], name + ': strategy or exploitability changed'
        print(name, json.dumps(stats), 'identical strategy and exploitability', flush=True)
        report.append(dict(case=name, **stats))
    if args.preflight_input:
        for label, binary in binaries.items():
            work = work_root / ('preflight-' + label); work.mkdir()
            (work / 'input.txt').write_text(args.preflight_input.read_text())
            with (work / 'log.txt').open('w') as log:
                result = subprocess.run([str(binary), '-i', 'input.txt', '-r', str(resources)], cwd=work,
                                        stdout=log, stderr=log, env=dict(os.environ, SUI_SOLVER_MEMORY_LIMIT_MB='0.000001'), timeout=30)
            text = (work / 'log.txt').read_text()
            assert result.returncode == 1 and 'SUI_MEMORY_LIMIT:' in text
            estimate = float(re.search(r'Sui estimated strategy storage: ([0-9.]+)', text)[1])
            print('Preflight only:', label, estimate, 'MiB', flush=True)
            report.append(dict(case='preflight-' + label, estimateMiB=estimate))
    print(json.dumps(report, indent=2))
