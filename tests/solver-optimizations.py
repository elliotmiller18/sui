#!/usr/bin/env python3
"""Real-engine A/B and checkpoint regression; all solve artifacts live in temporary directories."""
import importlib.util,json,math,os,subprocess,tempfile,struct,sys
sys.dont_write_bytecode=True
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('bench',ROOT/'scripts/profile-solver.py');bench=importlib.util.module_from_spec(spec);spec.loader.exec_module(bench)
B=ROOT/'build/Sui.app/Contents/Resources/solver/console_solver';RES=B.parent/'resources'
with tempfile.TemporaryDirectory(prefix='sui-optimization-tests-') as tmp:
    work=Path(tmp)
    def run(name,config,flags='baseline',iterations=11,extra=(),ok=True,mode='holdem'):
        d=work/name;d.mkdir();(d/'input.txt').write_text(bench.script(config,iterations,0,config.get('threads',1)).replace('set_dump_rounds 1',f"set_dump_rounds {config.get('dumpRounds',1)}"))
        p=subprocess.run([str(B),'-i','input.txt','-r',str(RES),'-m',mode,'--optimizations',flags,*map(str,extra)],cwd=d,env=dict(os.environ,SUI_SOLVER_MEMORY_LIMIT_MB='2048'),capture_output=True,text=True,timeout=120)
        assert (p.returncode==0)==ok,(name,p.stdout[-1800:],p.stderr)
        if not ok:return None
        data=json.loads((d/'result.json').read_text());assert all(math.isfinite(v) for _,v in bench.flatten(data))
        return data,[(x['iteration'],x['exploitibility']) for x in map(json.loads,(d/'tmp_log.txt').read_text().splitlines())]
    fixtures=[dict(next(c for c in bench.cases() if c['name']=='narrow-flop'),raises=3),
              dict(next(c for c in bench.cases() if c['name']=='exact-turn'),stack=10,pot=4),
              dict(next(c for c in bench.cases() if c['name']=='isomorphic-flop'),stack=5,raises=2),
              dict(next(c for c in bench.cases() if c['name']=='srp-river'),ip='AA,KK,AKs:0.0001,AKo:0.5',oop='TT,99,QJs,JTs',stack=20)]
    for i,c in enumerate(fixtures):
        old=run(f'base-{i}',c)
        for flags in ['safe','safe,no-blocked','safe,no-slab,no-blocked','safe,no-cache,no-compact-cache','safe,no-borrow-state','safe,no-canonical-slabs']:
            new=run(f'exact-{i}-{flags}',c,flags);assert new==old,(i,flags,'exact behavior changed')
        for flags in ['memory','all','safe,mapped']:
            new=run(f'numeric-{i}-{flags}',c,flags);assert new is not None
            if flags=='safe,mapped':assert new==old
    iso_turn=dict(fixtures[2],board='As,8s,3h,2s',stack=3,pot=8,raises=1,dumpRounds=2)
    assert run('iso-turn-export-base',iso_turn)==run('iso-turn-export-packed',iso_turn,'safe')
    c=fixtures[-1]
    reference=run('flags-reference',c)
    for flag in ['borrow-state','canonical-slabs','stack','scalar','masks','dispatch','coefficients','br-copy','arena','stream','dense','cache','compact-cache','slab','blocked','weak-parent','lazy-br','phases']:
        assert run('flag-'+flag,c,flag)==reference,flag
    for i,config in enumerate(fixtures[:2]):
        assert run(f'parallel-base-{i}',dict(config,threads=4))==run(f'parallel-safe-{i}',dict(config,threads=4),'safe')
    full=run('full',c,'safe',iterations=21)
    checkpoint=work/'checkpoint.bin';run('first',c,'safe',iterations=11,extra=['--checkpoint',checkpoint,'--checkpoint-every',5])
    resumed=run('resumed',c,'safe',iterations=21,extra=['--resume',checkpoint]);assert resumed[0]==full[0];assert resumed[1][-1]==full[1][-1]
    memory_checkpoint=work/'memory-checkpoint.bin'
    run('memory-learning-path',c,'memory',iterations=11,extra=['--checkpoint',memory_checkpoint])
    def chunks(path):
        raw=path.read_bytes();offset=33+struct.unpack_from('<Q',raw,17)[0];groups=[]
        while offset<len(raw):
            group=[]
            for _ in range(5):
                length=struct.unpack_from('<Q',raw,offset)[0];offset+=16;group.append(raw[offset:offset+length]);offset+=length
            groups.append(group)
        assert offset==len(raw)
        return groups
    exact_chunks=chunks(checkpoint);memory_chunks=chunks(memory_checkpoint);assert len(exact_chunks)==len(memory_chunks)
    assert all(a[0]==b[0] and a[4]==b[4] for a,b in zip(exact_chunks,memory_chunks)), 'Average-only compression changed learning regrets'
    assert run('reset-all-to-safe',c,'all,safe')==reference
    assert run('reset-memory-to-safe',c,'memory,safe')==reference

    run('wrong-board',dict(c,board='Th,7c,6d,2h,Ks'),'safe',iterations=21,extra=['--resume',checkpoint],ok=False)
    run('wrong-representation',c,'memory',iterations=21,extra=['--resume',checkpoint],ok=False)
    corrupt=work/'corrupt.bin';raw=bytearray(checkpoint.read_bytes());raw[-5]^=128;corrupt.write_bytes(raw)
    run('corruption',c,'safe',iterations=21,extra=['--resume',corrupt],ok=False)
    corrupt.write_bytes(raw[:len(raw)//2]);run('truncated',c,'safe',iterations=21,extra=['--resume',corrupt],ok=False)
    run('bad-option',c,'not-a-real-option',ok=False)
    short=dict(c,board='As,Ks,Qs,Js,9d',ip='AA,KK,AKs',oop='TT,99,QJs')
    assert run('short-old',short,mode='shortdeck')==run('short-new',short,'safe',mode='shortdeck')
    for mode in ['holdem','shortdeck']:
        p=subprocess.run([str(B),'-r',str(RES),'--validate-evaluator',mode],cwd=work,capture_output=True,text=True,timeout=45)
        assert p.returncode==0,(p.stdout[-1000:],p.stderr)
        assert 'SUI_EVALUATOR_VALIDATED' in p.stdout
    assert not list(work.glob('*.tmp.*'))
print('Optimization checks passed: exact A/B, all flags, numerical finiteness, unchanged float32 learning regrets, preset reset, mmap, checkpoint/resume/corruption, short deck, exhaustive evaluator.')
