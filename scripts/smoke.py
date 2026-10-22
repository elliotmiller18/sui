#!/usr/bin/env python3
"""Small CLI regression smoke; no packages, no actual poker solve."""
import json
import pathlib
import subprocess
import tempfile

binary = pathlib.Path(__file__).resolve().parents[1] / 'build/sui'

def run(*args, ok=True):
    result = subprocess.run([str(binary), *map(str, args)], capture_output=True, text=True, timeout=15)
    assert (result.returncode == 0) == ok, (args, result.stdout, result.stderr)
    return result

with tempfile.TemporaryDirectory(prefix='sui smoke ') as temp:
    root = pathlib.Path(temp)
    (root / 'B_raise.txt').write_text('AA,AKs:0.25,KAo:0.4,22:0')
    (root / 'B_call.txt').write_text('AKs:0.5,AKo:0.2')
    spots = json.loads(run('list', '--ranges', root, '--position', 'BTN').stdout)
    assert len(spots) == 1 and len(spots[0]['actions']) == 2
    args = ('export', '--ranges', root, '--position', 'BTN')
    chart = json.loads(run(*args).stdout)
    assert len(chart['frequencies']) == 169
    assert chart['frequencies']['AKs'] == [0.5, 0.25, 0.25]
    assert chart['frequencies']['AA'] == [0, 1, 0]
    assert chart['actions'][-1] == 'Fold'
    assert abs(sum(chart['frequencies']['AKo']) - 1) < 1e-9
    assert json.loads(run(*args, '--remainder', 'unassigned').stdout)['actions'][-1] == 'Unassigned'
    (root / 'B_call.txt').write_text('AA:0.5')
    assert 'totals' in run(*args, ok=False).stderr
    (root / 'B_call.txt').write_text('AKs:nan')
    assert 'Invalid range weight' in run(*args, ok=False).stderr
    (root / 'B_call.txt').write_text('AKs:0.5,AKs:0.2')
    assert 'Duplicate' in run(*args, ok=False).stderr
    run('list', '--bogus', 'x', ok=False)
    # Isolated executable fixture tests process arguments, paths with spaces,
    # result validation and timeout, not solver correctness.
    home = root / 'solver'; home.mkdir(); (home / 'resources').mkdir()
    fake = home / 'console_solver'
    fake.write_text('#!/bin/sh\nprintf \'{"strategy":{}}\' > result.json\n')
    fake.chmod(0o755)
    source = root / 'spot.txt'
    source.write_text('set_board As,Kd,2c\nstart_solve\ndump_result old.json\n')
    solve = ('solve', '--solver-home', home, '--input', source)
    run(*solve, '--out', root / 'new run')
    assert (root / 'new run/result.json').exists()
    assert not (root / 'old.json').exists()
    run(*solve, '--out', root / 'new run', ok=False)
    fake.write_text('#!/bin/sh\nexec /bin/sleep 10\n')
    assert 'timed out' in run(*solve, '--out', root / 'timeout', '--timeout', '0.1', ok=False).stderr
print('Smoke passed: parsing, mixed frequencies, validation, isolated runner, timeout.')
