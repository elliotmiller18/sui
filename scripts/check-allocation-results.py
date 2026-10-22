#!/usr/bin/env python3
# Written for Sui by us: compare the saved pre-change binary with the current fork.
# Fixed iteration limits isolate allocation changes from the new UI accuracy target.
import json, pathlib, subprocess, tempfile, time
root = pathlib.Path(__file__).resolve().parents[1]
old = root / 'build/allocation-before/console_solver'
new = root / 'build/Sui.app/Contents/Resources/solver/console_solver'
resources = root / 'assets/solver/resources'
base = "set_pot 4\nset_effective_stack 10\nset_board Qs,8d,7h\nset_range_ip T9s\nset_range_oop JTs,43s\n"
for player in ['ip','oop']:
    for street in ['flop','turn','river']:
        for action in ['bet','raise','donk']:
            base += f'set_bet_sizes {player},{street},{action},100\n'
        base += f'set_bet_sizes {player},{street},allin\n'
base += 'set_allin_threshold 1\nbuild_tree\nset_thread_num 4\nset_accuracy 0\nset_max_iteration 40\nset_print_interval 10\nset_use_isomorphism 0\nstart_solve\nset_dump_rounds 1\ndump_result result.json\n' 
cases = [('flop', 'Qs,8d,7h', 'T9s', 'JTs,43s', 0),
         ('flop-symmetry', 'Qs,8s,7h', 'T9s', 'JTs,43s', 1),
         ('river-exact', 'Qs,8d,7h,2c,3s', '9cTc:1,9dTd:0.0001', 'JcQc:1,JhQh:0.2', 0)]
artifacts = pathlib.Path(tempfile.mkdtemp(prefix='sui-allocation-check-'))
for name, board, ip, oop, iso in cases:
    overrides = {'set_board':board,'set_range_ip':ip,'set_range_oop':oop,'set_pot':'4','set_effective_stack':'10',
                 'set_accuracy':'0','set_max_iteration':'40','set_print_interval':'10','set_use_isomorphism':str(iso)}
    lines = [line.split(' ')[0]+' '+overrides[line.split(' ')[0]] if line.split(' ')[0] in overrides else line for line in base.splitlines()]
    outputs = []
    for label, binary in [('before',old),('after',new)]:
        directory = artifacts / (name+'-'+label); directory.mkdir()
        (directory/'input.txt').write_text('\n'.join(lines)+'\n')
        with (directory/'solver.log').open('w') as log:
            subprocess.run([str(binary),'-i','input.txt','-r',str(resources)],cwd=directory,stdout=log,stderr=log,check=True,timeout=120)
        outputs.append(json.loads((directory/'result.json').read_text()))
    assert outputs[0] == outputs[1], name+' strategy changed'
    print(name+': identical strategy JSON',flush=True)
print('Artifacts:',artifacts)
