#!/usr/bin/env python3
"""Exercise complete, changing, per-iteration frames without retaining solve artifacts."""
import json,os,subprocess,tempfile,time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
home=root/'build/Sui.app/Contents/Resources/solver'
script=(root/'docs/performance/2026-11-11/alloc.input.txt').read_text()
with tempfile.TemporaryDirectory(prefix='sui-preview-test-') as tmp:
    for flags in ['baseline','safe']:
        final=[]
        for enabled in [False,True]:
            work=Path(tmp)/(flags+str(enabled));work.mkdir();(work/'input.txt').write_text(script)
            env=dict(os.environ,SUI_SOLVER_MEMORY_LIMIT_MB='2048');env.pop('SUI_SOLVER_PREVIEW_PATH',None)
            if enabled:env['SUI_SOLVER_PREVIEW_PATH']='preview.json'
            frames=set()
            with (work/'log').open('w') as log:
                proc=subprocess.Popen([str(home/'console_solver'),'-i','input.txt','-r',str(home/'resources'),'--optimizations',flags],cwd=work,env=env,stdout=log,stderr=log)
                deadline=time.monotonic()+60
                while proc.poll() is None:
                    if time.monotonic()>deadline:proc.kill();proc.wait();raise AssertionError('preview fixture timed out')
                    try:data=(work/'preview.json').read_bytes()
                    except FileNotFoundError:pass
                    else:
                        frame=json.loads(data);frames.add(frame['iteration'])
                        assert frame['node_type']=='action_node' and frame['actions']==frame['strategy']['actions']
                    time.sleep(.005)
                assert proc.returncode==0,(work/'log').read_text()[-1000:]
            result=json.loads((work/'result.json').read_text());final.append(result)
            if enabled:
                frame=json.loads((work/'preview.json').read_text());assert frame['iteration']==11
                assert frame['strategy']==result['strategy'] and frame['player']==result['player']
                assert len(frames)>1,frames
                assert not (work/'preview.json.tmp').exists()
            else:assert not (work/'preview.json').exists()
        assert final[0]==final[1],'preview changed final strategy'
# Stop is cooperative and still produces the normal, playable final export.
with tempfile.TemporaryDirectory(prefix='sui-stop-test-') as temp:
    work=Path(temp);(work/'input.txt').write_text(script.replace('set_max_iteration 11','set_max_iteration 200'))
    env=dict(os.environ,SUI_SOLVER_MEMORY_LIMIT_MB='2048',SUI_SOLVER_PREVIEW_PATH='preview.json',SUI_SOLVER_STOP_PATH='stop-request')
    with (work/'log').open('w') as log:
        proc=subprocess.Popen([str(home/'console_solver'),'-i','input.txt','-r',str(home/'resources'),'--optimizations','safe'],cwd=work,env=env,stdout=log,stderr=log)
        requested=False;deadline=time.monotonic()+60
        while proc.poll() is None:
            if time.monotonic()>deadline:proc.kill();proc.wait();raise AssertionError('stop timed out')
            if not requested and (work/'preview.json').exists():
                frame=json.loads((work/'preview.json').read_bytes())
                if frame['iteration']>=2:(work/'stop-request').touch();requested=True
            time.sleep(.005)
        assert proc.returncode==0 and requested
    frame=json.loads((work/'preview.json').read_bytes());iteration=frame['iteration'];assert 2<=iteration<200
    stopped=json.loads((work/'result.json').read_bytes());assert stopped['strategy']==frame['strategy']
    assert f'Iter: {iteration}\n' in (work/'log').read_text()
    (work/'input.txt').write_text(script.replace('set_max_iteration 11',f'set_max_iteration {iteration}'))
    env.pop('SUI_SOLVER_STOP_PATH');env.pop('SUI_SOLVER_PREVIEW_PATH')
    with (work/'reference.log').open('w') as log:
        reference=subprocess.run([str(home/'console_solver'),'-i','input.txt','-r',str(home/'resources'),'--optimizations','safe'],cwd=work,env=env,stdout=log,stderr=log,timeout=60)
    assert reference.returncode==0 and stopped==json.loads((work/'result.json').read_bytes())
print('Preview passed: changing atomic iteration frames, final agreement, unchanged baseline/safe strategies.')
