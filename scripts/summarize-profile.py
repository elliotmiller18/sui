#!/usr/bin/env python3
"""Summarize one comparison matrix; never mix different workloads/builds/iteration targets."""
import argparse,json,statistics
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('report',type=Path);args=p.parse_args();data=json.loads(args.report.read_text());groups={}
for row in data['runs']:
    if row['rc'] or row.get('timedOut') or row.get('sampled'):continue
    groups.setdefault((row['case'],row['flags']),[]).append(row)
configs=data['configs'];baseline=configs[0];weights={c['name']:c['weight'] for c in data['cases']};common=[c for c in weights if weights[c]>0 and all((c,f) in groups for f in configs)];total=sum(weights[c] for c in common)
print('Comparable declared weight:',total,'of',sum(weights.values()),';',len(common),'cases')
print('| Configuration | Weighted wall s | Weighted peak MiB | Largest peak MiB | Max strategy delta |')
print('| --- | ---: | ---: | ---: | ---: |')
for flag in configs:
    wall=sum(weights[c]*statistics.median(r['wall'] for r in groups[c,flag]) for c in common)/total if total else float('nan')
    ram=sum(weights[c]*statistics.median(r['peakRSSMiB'] for r in groups[c,flag]) for c in common)/total if total else float('nan')
    rows=[r for (c,f),rs in groups.items() if f==flag for r in rs]
    deltas=[r['maxStrategyDelta'] for r in rows if 'maxStrategyDelta' in r]
    difference=f'{max(deltas):.6g}' if deltas and len(deltas)==len(rows) else 'unavailable'
    print(f"| {flag} | {wall:.3f} | {ram:.2f} | {max((r['peakRSSMiB'] for r in rows),default=0):.2f} | {difference} |")
print('\nPer-case medians:')
for c in weights:
    print(c, json.dumps({f:dict(n=len(groups[c,f]),wall=round(statistics.median(r['wall'] for r in groups[c,f]),3),rssMiB=round(statistics.median(r['peakRSSMiB'] for r in groups[c,f]),2)) for f in configs if (c,f) in groups}))
