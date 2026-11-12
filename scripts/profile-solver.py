#!/usr/bin/env python3
"""Serial, bounded solver comparisons using Sui's bundled NL50 ranges. Outputs small JSON only."""
import argparse, hashlib, json, math, os, resource, subprocess, sys, tempfile, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
RANGES=json.loads((ROOT/'assets/solver/preflop/nl50-cash.json').read_text())

def range_text(name):
    return ','.join(f'{k}:{v}' for k,v in sorted(RANGES[name].items()) if v>0)

def cases():
    def case(name,board,ip='OpenBTN',oop='CallBBvsBTN',pot=5.5,stack=97.5,sizes='33.333333,150',raises=3,weight=1,iso=0):
        return dict(name=name,board=board,ip=range_text(ip),oop=range_text(oop),pot=pot,stack=stack,sizes=sizes,raises=raises,weight=weight,iso=iso,rangeSources=[ip,oop])
    rows=[case('srp-rainbow','Th,7c,6d',sizes='33.333333',raises=2,weight=3),
          case('srp-paired','Qs,Qd,4c',sizes='33.333333',raises=2,weight=2),
          case('srp-monotone','As,8s,3s',sizes='33.333333',raises=2,weight=2),
          case('threebet-flop','Kh,9c,4d','Call 3BetBTNvsSB','3BetSBvsBTN',21.5,90,weight=3),
          case('shortstack-flop','Js,Ts,2d',stack=20,pot=12,weight=1),
          case('srp-turn','Th,7c,6d,2h',pot=12,stack=94,weight=3),
          case('threebet-turn','Kh,9c,4d,Ac','Call 3BetBTNvsSB','3BetSBvsBTN',45,78,weight=2),
          case('srp-river','Th,7c,6d,2h,As',pot=26,stack=87,weight=2),
          case('threebet-river','Kh,9c,4d,Ac,9s','Call 3BetBTNvsSB','3BetSBvsBTN',80,60,weight=2),
          case('multi-size-river','Qs,8d,7h,2c,3s',sizes='25,33.333333,66.666667,75,150,300',weight=1)]
    rows += [dict(rows[5],name='exact-turn',ip='9cTc:1,9dTd:0.0001,AcKc:0.7,AhKh:0.2',oop='JcQc:1,JhQh:0.2,AdKd:0.5',weight=1,rangeSources=['exact diagnostic']),
             dict(rows[0],name='narrow-flop',ip='T9s',oop='JTs,43s',pot=4,stack=10,sizes='33.333333,150',raises=3,weight=0,rangeSources=['diagnostic']),
             dict(rows[0],name='default-deep-flop',sizes='33.333333,150',raises=3,weight=3),
             dict(rows[2],name='isomorphic-flop',ip='AA,KK,QQ,AKs,AQs',oop='JJ,TT,99,KQs,QJs',pot=8,stack=20,iso=1,weight=0,rangeSources=['isomorphism diagnostic'])]
    return rows

def script(c,iterations,accuracy,threads):
    text=f"set_pot {c['pot']}\nset_effective_stack {c['stack']}\nset_board {c['board']}\nset_range_ip {c['ip']}\nset_range_oop {c['oop']}\n"
    for p in ['ip','oop']:
        for st in ['flop','turn','river']:
            for a in ['bet','raise','donk']:text+=f"set_bet_sizes {p},{st},{a},{c['sizes']}\n"
    return text+f"set_allin_threshold 1\nset_raise_limit {c['raises']}\nbuild_tree\nset_thread_num {threads}\nset_accuracy {accuracy}\nset_max_iteration {iterations}\nset_print_interval 10\nset_use_isomorphism {c['iso']}\nstart_solve\nset_dump_rounds 1\ndump_result result.json\n"

def worker(args):
    start=time.monotonic()
    with open('solver.log','w') as log:
        proc=subprocess.Popen([args.binary,'-i','input.txt','-r',args.resources,'--optimizations',args.flags],stdout=log,stderr=log,env=dict(os.environ,SUI_SOLVER_MEMORY_LIMIT_MB=str(args.budget*1024)))
        Path("pid.txt").write_text(str(proc.pid))
        timed_out=False
        try:rc=proc.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:timed_out=True;proc.terminate();
        if timed_out:
            try:rc=proc.wait(timeout=3)
            except subprocess.TimeoutExpired:proc.kill();rc=proc.wait()
    u=resource.getrusage(resource.RUSAGE_CHILDREN)
    result=dict(wall=time.monotonic()-start,user=u.ru_utime,system=u.ru_stime,peakRSSMiB=u.ru_maxrss/1024**2,rc=rc,timedOut=timed_out)
    text=Path('solver.log').read_text();import re
    est=re.search(r'Sui estimated strategy storage: ([0-9.]+)',text);result['estimateMiB']=float(est[1]) if est else None
    result['exploitability']=[float(x) for x in re.findall(r'Total exploitability ([^ ]+)',text)]
    if Path('tmp_log.txt').exists():result['checks']=[json.loads(line) for line in Path('tmp_log.txt').read_text().splitlines()]
    request=Path('input.txt').read_text();target=float(re.search(r'set_accuracy ([^\n]+)',request)[1]);cap=int(re.search(r'set_max_iteration (\d+)',request)[1]);result['converged']=bool(result.get('checks') and result['checks'][-1]['exploitibility']<=target);result['lastCheckedIteration']=result['checks'][-1]['iteration']+1 if result.get('checks') else None;result['completedIterations']=(result['checks'][-1]['iteration']+1 if result['converged'] else cap) if rc==0 else None
    if rc:result['error']=text[-1500:]
    Path('stats.json').write_text(json.dumps(result))

def flatten(x,path=''):
    if isinstance(x,dict):
        for k,v in x.items():yield from flatten(v,path+'/'+k)
    elif isinstance(x,list):
        for i,v in enumerate(x):yield from flatten(v,path+'/'+str(i))
    elif isinstance(x,(int,float)):yield path,float(x)

def conditioned_turn(c, root):
    """Mirror Postflop.advance and nextStreetInput for check / 1/3 bet / call."""
    ranks='23456789TJQKA';deck=[r+s for r in ranks for s in 'cdhs' if r+s not in c['board'].split(',')]
    def expand(text):
        classes={k:float(v) for k,v in (part.rsplit(':',1) for part in text.split(','))}
        result={}
        for i,a in enumerate(deck):
            for b in deck[:i]:
                key=a[0]+b[0]+('' if a[0]==b[0] else 's' if a[1]==b[1] else 'o')
                w=classes.get(a+b,classes.get(key,0))
                if w>0:result[a+b]=w
        return result
    reach=[expand(c['ip']),expand(c['oop'])];committed=[0.,0.];remaining=[c['stack']]*2;pot=c['pot'];path=[];node=root
    for prefix in ['CHECK','BET ','CALL']:
        actions=node['actions'];action=next(a for a in actions if a.startswith(prefix));idx=actions.index(action);player=node['player']
        reach[player]={hand:reach[player].get(hand,0)*v[idx] for hand,v in node['strategy']['strategy'].items()}
        payment=committed[1-player]-committed[player] if action=='CALL' else float(action.split()[1]) if action.startswith('BET ') else 0
        committed[player]+=payment;remaining[player]-=payment;pot+=payment;path.append(action)
        node=node.get('childrens',{}).get(action,{})
    card='2c'
    if card in c['board'].split(','):card='3d'
    def text(weights):
        weights={k:v for k,v in weights.items() if v>0 and card not in (k[:2],k[2:])};maximum=max(weights.values());return ','.join(f'{k}:{v/maximum:.17g}' for k,v in sorted(weights.items()))
    return dict(c,name='conditioned-turn',board=c['board']+','+card,ip=text(reach[0]),oop=text(reach[1]),pot=pot,stack=min(remaining),weight=3,iso=0,rangeSources=['Action-conditioned exact combos from '+c['name']],generatedFrom=dict(case=c['name'],actions=path,method='Sui Postflop.advance / nextStreetInput normalization'))

def paging_snapshot():
    import re
    try:
        text=subprocess.check_output(['/usr/bin/vm_stat'],text=True,stderr=subprocess.DEVNULL)
        names=['Swapins','Swapouts','Compressions','Decompressions']
        result={name:int(re.search(r'^'+name+r':\s*(\d+)',text,re.M)[1]) for name in names}
        result['pageBytes']=int(re.search(r'page size of (\d+)',text)[1]);return result
    except (OSError,subprocess.SubprocessError,TypeError):return {}

def run(args):
    source=json.loads(args.fixtures.read_text())['cases'] if args.fixtures else cases()
    selected=[c for c in source if not args.cases or c['name'] in args.cases.split(',')]
    flags=args.configs.split(';')
    report=dict(schema=1,binarySHA256=hashlib.sha256(Path(args.binary).read_bytes()).hexdigest(),weights='Declared workload weights, not observed usage telemetry; flop-heavy, actual bundled NL50 ranges',iterations=args.iterations,accuracy=args.accuracy,threads=args.threads,budgetGiB=args.budget,repeats=args.repeats,configs=flags,cases=selected,runs=[])
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='sui-profile-') as temp:
        for repeat in range(args.repeats):
            for c in selected:
                baseline=None;baseline_ex=None
                # Rotate order across repeats but always load baseline for correctness comparison.
                order=flags if repeat%2==0 else [flags[0]]+list(reversed(flags[1:]))
                for spec in order:
                    with tempfile.TemporaryDirectory(dir=temp) as path:
                        d=Path(path);(d/'input.txt').write_text(script(c,args.iterations,args.accuracy,args.threads))
                        command=[sys.executable,str(Path(__file__).resolve()),'--worker','--binary',str(args.binary),'--resources',str(args.resources),'--flags',spec,'--timeout',str(args.timeout),'--budget',str(args.budget)]
                        paging_before=paging_snapshot()
                        subprocess.run(command,cwd=d,check=True,timeout=args.timeout+20)
                        paging_after=paging_snapshot()
                        row=json.loads((d/'stats.json').read_text());row.update(case=c['name'],flags=spec,repeat=repeat)
                        if paging_before and paging_after:row['systemPagingDelta']={k:paging_after[k]-paging_before[k] for k in ['Swapins','Swapouts','Compressions','Decompressions']};row['pageBytes']=paging_after.get('pageBytes')
                        if row['rc']==0:
                            raw=(d/'result.json').read_text();parsed=json.loads(raw);values=dict(flatten(parsed));row['strategySHA256']=hashlib.sha256(json.dumps(parsed,sort_keys=True).encode()).hexdigest()
                            if spec==flags[0]:
                                baseline=values;baseline_ex=row['exploitability'][-1] if row['exploitability'] else None
                                if c['name']=='threebet-flop' and not any(x['name']=='conditioned-turn' for x in selected):
                                    generated=conditioned_turn(c,parsed);generated['generatedFrom']['iterations']=args.iterations;generated['generatedFrom']['flags']=spec;selected.append(generated)
                            if baseline is not None:
                                row['sameNumericKeys']=values.keys()==baseline.keys();diff=[abs(v-baseline[k]) for k,v in values.items() if k in baseline and '/strategy/strategy/' in k];row['maxStrategyDelta']=max(diff,default=0);row['meanStrategyDelta']=sum(diff)/len(diff) if diff else 0
                                row['finalExploitabilityDelta']=row['exploitability'][-1]-baseline_ex if row['exploitability'] and baseline_ex is not None else None
                        report['runs'].append(row);args.output.write_text(json.dumps(report,indent=2)+'\n');print(c['name'],spec,round(row['wall'],2),round(row['peakRSSMiB'],1),row['rc'],row.get('maxStrategyDelta'),flush=True)
    return report

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--worker',action='store_true');p.add_argument('--fixtures',type=Path);p.add_argument('--binary',type=Path,default=ROOT/'build/Sui.app/Contents/Resources/solver/console_solver');p.add_argument('--resources',type=Path,default=ROOT/'build/Sui.app/Contents/Resources/solver/resources');p.add_argument('--output',type=Path,default=Path('/tmp/sui-performance-results.json'));p.add_argument('--flags',default='baseline');p.add_argument('--configs',default='baseline;safe;memory;all');p.add_argument('--cases',default='');p.add_argument('--iterations',type=int,default=21);p.add_argument('--accuracy',type=float,default=0);p.add_argument('--threads',type=int,default=4);p.add_argument('--repeats',type=int,default=1);p.add_argument('--timeout',type=float,default=180);p.add_argument('--budget',type=float,default=3);a=p.parse_args();a.binary=str(Path(a.binary).resolve());a.resources=str(Path(a.resources).resolve());worker(a) if a.worker else run(a)
