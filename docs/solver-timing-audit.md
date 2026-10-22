# Solver timing audit — 2026-10-22

Conclusion: available evidence does NOT establish 16 minutes as normal or necessary. Earlier completion checks established that this implementation can take about9–10 minutes on broad flop ranges, not that it is well optimized.

## Existing user runs

Wall times below are input-file to result-file modification times; solver-reported times exclude initial setup and measure before the latest best-response evaluation. These are separate measurements.

| Board | Latest solver report | Wall time to result | Evidence |
|---|---|---|---|
| Qs,8d,5h | Iter: 181; Total exploitability 0.4569739 precent; time used: 575.572 | 582.327 s | [log](/var/folders/_r/b4g_tw1j3tq6b46wzlwc_8h00000gn/T/sui-solves/0CC171AC-6A62-474E-867C-D2667CE9A95D/solver.log) |
| 8d,Jh,6h | Iter: 131; Total exploitability 0.774525 precent; time used: 582.982 | No result | [log](/var/folders/_r/b4g_tw1j3tq6b46wzlwc_8h00000gn/T/sui-solves/B95C000E-ED44-4839-84A6-35C9669160A3/solver.log) |
| 7c,6c,6h | Iter: 0; Total exploitability 263.4503 precent | No result | [log](/var/folders/_r/b4g_tw1j3tq6b46wzlwc_8h00000gn/T/sui-solves/3D425950-B9AB-4FAD-A432-36AF500FF5D0/solver.log) |
| Qs,8d,5h,2c | Iter: 171; Total exploitability 0.49442193 precent; time used: 2.51 | 4.425 s | [log](/var/folders/_r/b4g_tw1j3tq6b46wzlwc_8h00000gn/T/sui-solves/D9B6D379-E438-40DC-8E76-2175D1DAC50C/solver.log) |

The 7c6c6h log stayed at iteration0 across observations several minutes apart, with no output. This establishes lack of recorded progress, not its cause: it could have been cancelled, terminated, suspended or stalled. Existing logs do not record process exit/cancellation, so they cannot distinguish these. Activity Monitor later showed no console_solver process. No completed16-minute run was found in this directory. The UI runner has a600-second timeout; a16-minute displayed wait needs independent investigation rather than being called normal solving time.

## Controlled short replay

Replayed the exact7c6c6h pot6.5/stack97.5 ranges (47 IP hand-class entries,55 OOP) in sequential runs, using the bundled optimized arm64 binary. Limited both to11 iterations and printed every iteration for a bounded diagnostic; kept four threads, tree, target and ranges the same. These partial strategies are NOT converged solutions and were not installed in the GUI.

| Setting | Solver time at iteration11 | Wall time including setup/export | Exploitability at iteration11 |
|---|---:|---:|---:|
| Current, suit isomorphism OFF |29.165s|33.842s|52.8356%|
| Suit isomorphism ON |19.215s|22.937s|52.66339%|

Measured wall reduction32.2% (~1.48× throughput), one trial per setting. This cannot be extrapolated into a guaranteed full convergence time. Solver targets were not relaxed. Log/input/output evidence: [/tmp/sui-timing-audit-current](/tmp/sui-timing-audit-current), [/tmp/sui-timing-audit-isomorphism](/tmp/sui-timing-audit-isomorphism). Reproduction inputs are build/timing-audit/current.txt and isomorphism.txt.

Sui currently disables suit isomorphism globally. The fork already supports it for class ranges and disables it automatically for exact-combo inputs (src/runtime/PokerSolver.cpp), protecting suit-dependent turn/river ranges. This is a measured optimization candidate; application defaults were NOT changed in this audit. The compiler uses -O3/-DNDEBUG, so this is not an unoptimized debug binary.

Upstream publishes a172-second flop benchmark at0.275% with6threads: https://github.com/bupticybee/TexasSolver/tree/console#speed-benchmark-with-piosolver . Different tree/ranges/hardware; it is context, not a comparable expectation for this hand.

Next investigation: enable/test class-range suit symmetry, measure full convergence, and add explicit worker lifecycle/exit timestamps to distinguish stalls/cancellations from ongoing calculation. Investigate background suspension/App Nap only as a hypothesis; not proven by these logs. Do not treat a spinning UI or a growing elapsed counter as evidence the solver is working.
