# Sui solver fork

Upstream: https://github.com/bupticybee/TexasSolver/tree/6dfb65b4d7ed081da509e8d8c3d82138c4708267
Console branch archive downloaded 2026-10-22. Archive SHA256: 1f32c46aea34de39c49c4c6a9805ab0c0dc80a3f6e68f9a3e0a66a4874efc5d5

Local change: PrivateRangeConverter retains all positive input weights instead of discarding weights <=0.005. Upstream console branch already supports exact combos. Build uses scripts/solver/CMakeLists.txt to omit GUI, Python bindings and tests. Upstream AGPL-3.0 license retained.

Unused upstream GUI images, duplicate lookup resources, tests and Python/gtest dependencies are omitted from the vendored subset. The minimal build excludes the unused/incomplete CfrSolver.cpp (the console uses PCfrSolver). The app bundles the fork sources and build recipe. Lookup resources are in assets/solver/resources.

## Allocation cleanup — written for Sui by us
PCfrSolver moves returned chance utilities into results, borrows ordinary chance/action result vectors (copies only for suit permutations), removes the duplicate action-utility matrix, allocates regrets only for the updating player, and reuses a call-local opponent reach buffer across sequential actions. BestResponse removes its unused per-card reach cache/copy and reuses call-local reach matrices across sequential actions. DiscountedCfrTrainable computes each updated strategy probability directly at its use rather than allocating a temporary strategy vector. Arithmetic order and recursion/parallel ownership are preserved. Every changed code block is marked “Written for Sui by us”.

The app now requests2% exploitability for interactive solves; thread limit remains4, isomorphism remains disabled by the app. Fixed-input before/after checks are in scripts/check-allocation-results.py (requires the locally saved build/allocation-before binary).
