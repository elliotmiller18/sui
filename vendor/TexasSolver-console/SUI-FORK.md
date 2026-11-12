# Sui solver fork

Upstream: https://github.com/bupticybee/TexasSolver/tree/6dfb65b4d7ed081da509e8d8c3d82138c4708267
Console branch archive downloaded 2026-10-22. Archive SHA256: 1f32c46aea34de39c49c4c6a9805ab0c0dc80a3f6e68f9a3e0a66a4874efc5d5

Local change: PrivateRangeConverter retains all positive input weights instead of discarding weights <=0.005. Upstream console branch already supports exact combos. Build uses scripts/solver/CMakeLists.txt to omit GUI, Python bindings and tests. Upstream AGPL-3.0 license retained.

Unused upstream GUI images, duplicate lookup resources, tests and Python/gtest dependencies are omitted from the vendored subset. The minimal build excludes the unused/incomplete CfrSolver.cpp (the console uses PCfrSolver). The app bundles the fork sources and build recipe. Lookup resources are in assets/solver/resources.

## Allocation cleanup — written for Sui by us
PCfrSolver moves returned chance utilities into results, borrows ordinary chance/action result vectors (copies only for suit permutations), removes the duplicate action-utility matrix, allocates regrets only for the updating player, and reuses a call-local opponent reach buffer across sequential actions. BestResponse removes its unused per-card reach cache/copy and reuses call-local reach matrices across sequential actions. DiscountedCfrTrainable computes each updated strategy probability directly at its use rather than allocating a temporary strategy vector. Arithmetic order and recursion/parallel ownership are preserved. Every changed code block is marked “Written for Sui by us”.

The app now requests2% exploitability for interactive solves; thread limit remains4, isomorphism remains disabled by the app. The historical allocation comparison used a saved pre-change binary; that machine-local fixture is not part of the shareable repository. Current regression checks run through scripts/test.sh.

## Postflop fractional sizes — written for Sui by us

GameTree's postflop sizing path preserves fractional BB wagers rather than rounding
and truncating to integers. This keeps quarter/third/half-pot options distinct and
preserves fractional all-ins. Raises add the call plus the selected fraction of
the pot after calling. Enforce the minimum bet/full raise, allow short all-ins,
deduplicate capped sizes and use the actual stack ceiling at all-in threshold 1.
The original preflop sizing path is unchanged. Every added block is marked
“Written for Sui by us”. The app lets users select 25%, 33⅓%, 66⅔%, 75%, 150%, 300% and an optional
all-in branch for bets, raises and donks on every postflop street. Defaults
are 33⅓% and 150%. Fractional sizes cap at the remaining stack.

## Memory preflight — written for Sui by us

PCfrSolver estimates regret/average-strategy arrays across future board states
before allocating trainables. It logs estimated MiB and honors
SUI_SOLVER_MEMORY_LIMIT_MB. The app initially budgets half physical RAM, capped at 8 GiB, for these
arrays in RAM, not on disk. Users can edit that limit or approve a whole-GiB increase after a
rejection. The engine emits SUI_MEMORY_REQUIRED_MB at full precision so the
UI can round the retry budget correctly; this excludes other solver/scratch allocations and is
not a guarantee about peak RSS. The estimate assumes no suit-isomorphism memory
savings. Oversized trees fail with SUI_MEMORY_LIMIT instead of attempting the
allocation. console.cpp catches exceptions and exits with an error, without
SIGABRT. set_raise_limit exposes the existing 0–4 raise-depth bound for explicit
tree configuration; it does not change the default (4).

## Repository packaging

Editor metadata, notebooks, upstream CI, and unused fmt tests/docs/build helpers
are omitted. The engine's source, headers and original licenses are retained;
Sui builds through scripts/solver/CMakeLists.txt. Lookup tables are stored as
deterministic gzip files and expanded into the app at build time. Sample
strategies, logs, and upstream example resources are not shipped.

The vendored fmt C-string view constructor counts code units directly instead
of instantiating std::char_traits for its custom C++17 char8_t enum. This avoids
a removed libc++ extension on newer Apple toolchains. The change is marked
“Written for Sui by us”.

## Persistent state reduction — written for Sui by us

DiscountedCfrTrainable no longer stores r_plus_sum per state. Current strategies
recompute each hand's sum in the original action order; regret/average updates
use a scalar sum for one hand at a time, without an extra scratch vector.
Preflight counts two action-by-hand arrays, rather than those arrays plus a
hand-sized cache. RiverCombs drops its unused per-hand board vector; the cache
already keys records by board. Fixed-iteration comparisons preserve exported
strategies and exploitability readings on river, turn, flop, suit-isomorphism
and four-thread fixtures. Measurements and future work: docs/solver-memory.md.

Sui's Re-raises / street picker offers 0–2 raises after the opening bet, defaults
to 2, and emits engine set_raise_limit=1–3. The engine counts the opening bet
as 1; this translation preserves the UI's bet → raise → reraise semantics.
The underlying console's raw 0–4 setting remains available to low-level inputs.

2026-11 performance experiments add an opt-in `--optimizations` switch (or
`SUI_SOLVER_OPTIMIZATIONS`). No switch selects the legacy behavior. Individual
flags preserve separate A/B paths for fixed stack accumulators, scalar payoff
access, cached masks, typed dispatch, discount coefficients, traversal scratch,
streamed opponent utility sums, dense evaluator lookup, indexed immutable rank
caches, compact cache records, packed state, future-card hand compaction,
canonical suit-state compaction, borrowed state access and weak parents.

`safe` selects exact representation/traversal experiments; `memory` adds bfloat16
cumulative-strategy storage; `all` additionally rounds regrets and changes check
scheduling. `mapped`, `recompute-cache` and phase logging are separate experiments.
Packed checkpoint/resume uses a versioned manifest, array checksums and atomic
file publication after complete iterations. These features are not a hard
resident-memory cap or a new sampling algorithm. Precision experiments are not
claimed to produce identical strategies. Details, validation and measured
tradeoffs: `docs/solver-optimization-experiments.md`; reproducible comparison
harness: `scripts/profile-solver.py`.

The GUI optionally sets `SUI_SOLVER_PREVIEW_PATH`. After each complete two-player
iteration, the engine atomically replaces that file with only the root decision's
average strategy and iteration number. It does not export future subtrees or
change training state. Ordinary CLI solves do not request preview output.

`SUI_SOLVER_STOP_PATH` requests a cooperative stop when that marker file appears.
The engine finishes both player traversals for the current iteration, checks final
exploitability if needed, then runs the ordinary strategy export. The GUI uses
this for **Stop now**; process termination remains the separate Cancel action.
