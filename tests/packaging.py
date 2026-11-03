#!/usr/bin/env python3
"""Verify build resources, bundled runtime paths and actual engine failures."""
import hashlib
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

root = Path(__file__).resolve().parents[1]
home = root / 'build/Sui.app/Contents/Resources/solver'
expected = {
    'card5_dic_sorted.txt': '13e0f4bd3cb99388caec49b36f98b98b70ae30407cbd740d880db65ed4db5e7b',
    'card5_dic_sorted_shortdeck.txt': 'a608bd84cb340ae4918ceab1447faf754c24b22e8f6cb64e054c2fa6f7ec8d78',
}
for name, digest in expected.items():
    assert hashlib.sha256((home / 'resources/compairer' / name).read_bytes()).hexdigest() == digest
assert not (home / 'resources/outputs').exists()
assert not list((home / 'resources').rglob('*.gz'))
assert (home / 'TexasSolver-LICENSE').is_file()
assert (home / 'OpenMP-LICENSE.txt').is_file()
assert (home / 'fmt-LICENSE').is_file()
with tarfile.open(home / 'solver-source.tar.gz') as archive:
    names = archive.getnames()
    assert 'vendor/TexasSolver-console/src/GameTree.cpp' in names
    assert 'scripts/solver/CMakeLists.txt' in names
    assert not any('/.idea/' in name or '/test/' in name for name in names)
linked = subprocess.check_output(['otool', '-L', str(home / 'console_solver')], text=True)
assert '@executable_path/libomp.dylib' in linked
assert not any('/opt/homebrew/' in line or '/usr/local/' in line for line in linked.splitlines()[1:])

# A small real river tree with an intentionally tiny budget must fail before
# training. This exercises the C++ preflight rather than a fake shell process.
script = '''set_pot 6.5
set_effective_stack 20.5
set_board Qs,8d,7h,2c,3s
set_range_ip T9s
set_range_oop JTs,43s
'''
for player in ['ip', 'oop']:
    for action in ['bet', 'raise', 'donk']:
        script += f'set_bet_sizes {player},river,{action},33.333333,150\n'
script += 'set_allin_threshold 1\nbuild_tree\nset_thread_num 1\nset_max_iteration 1\nstart_solve\ndump_result result.json\n'
with tempfile.TemporaryDirectory(prefix='sui-engine-errors-') as directory:
    work = Path(directory)
    (work / 'input.txt').write_text(script)
    env = dict(os.environ, SUI_SOLVER_MEMORY_LIMIT_MB='0.000001')
    result = subprocess.run([str(home / 'console_solver'), '-i', 'input.txt', '-r', str(home / 'resources')],
                            cwd=work, env=env, capture_output=True, text=True, timeout=30)
    assert result.returncode == 1, (result.returncode, result.stdout, result.stderr)
    assert 'SUI_MEMORY_LIMIT:' in result.stdout + result.stderr
    assert 'SUI_MEMORY_REQUIRED_MB:' in result.stdout + result.stderr
    assert not (work / 'result.json').exists()
print('Packaging passed: lookup hashes, clean resources, licenses, source, relative OpenMP and real memory rejection.')
