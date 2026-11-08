# Solver memory audit

Audit date: 2026-11-03. This examines the vendored console engine and the actual
Th/7c/6d, pot 6.5 BB, remaining stack 97.5 BB request. The memory-only comparison kept the betting tree, ranges, float precision,
raise limit and solve target unchanged. Those historical measurements used
engine raise_limit=4 (the opening bet plus up to three raises). The app now
separately exposes a 0–2 raise limit and
defaults to two, so new app solves use a smaller tree than that comparison.

## Changes implemented

Every discounted-CFR training state formerly owned two action-by-hand float
arrays (`r_plus`, `cum_r_plus`) and one hand-sized float array (`r_plus_sum`).
The last array is just the sum of positive regrets for that hand. It is now
computed in a scalar at its point of use, preserving the original sequence of
float additions for each hand. Updates also use a scalar rather than allocating
replacement scratch arrays. Persistent array storage falls from `(2A + 1)H`
floats to `2AH`, where A is action count and H is hand count. The per-state
vector header is also removed. The RAM estimator reflects the new layout.

`RiverCombs` formerly stored an unused board vector for every cached hand.
The board already identifies the cache entry in `RiverRangeManager`. Removing
that field and its constructor argument avoids a vector header and a separate
board allocation per cached hand. Hand ranks, sorting and reach indices stay
the same.

## Measurements

The old binary was saved before the change. Before/after engine runs used the
same input, 21 fixed iterations, 0 accuracy cutoff and current-street export.
Parsed exported strategy JSON and every logged exploitability reading were
identical for all five fixtures. Timings were observed under concurrent system
load; these are memory checks, not claims of faster solving.

| Fixture | Peak resident RAM before | After | Strategy-array estimate before / after |
| --- | ---: | ---: | ---: |
| River, mixed ranges | 133.23 MiB | 133.38 MiB | <0.1 / <0.1 MiB |
| Turn, exact combos including 0.0001 weight | 134.12 MiB | 134.03 MiB | 0.6 / 0.5 MiB |
| Flop, one thread | 259.70 MiB | 241.56 MiB | 115.0 / 93.9 MiB |
| Flop, suit isomorphism enabled | 212.47 MiB | 201.45 MiB | 115.0 / 93.9 MiB |
| Flop, four threads | 260.88 MiB | 243.00 MiB | 115.0 / 93.9 MiB |

For the user's large flop request, preflight alone reports **19,497.0 MiB →
16,348.3 MiB**, or **19.04 GiB → 15.97 GiB**: about **16.1% less estimated
training-state RAM**. This is not a measurement of that full solve's peak RSS
or convergence time; the large tree was deliberately rejected before training.
The small fixtures' total RSS improves less because hand-evaluator tables,
runtime libraries and other allocations contribute a relatively fixed cost.
The RAM budget is an estimate check, not an allocator-enforced process limit.

After adding the Re-raises / street picker, a separate preflight-only check of
the later Th/7c/6c request measured 20,076.3 MiB at raw engine limit 4 versus
16,176.6 MiB at raw limit 3. The latter corresponds to the new UI default of
two raises after the opening bet: about 19.61 → 15.80 GiB. This input has
different ranges/board from the earlier Th/7c/6d memory-layout comparison.

Reproduce against a baseline binary saved beside its OpenMP library:

```sh
python3 tests/solver-memory.py --before /path/to/baseline/console_solver
# Optional: estimate an existing large request without training it
python3 tests/solver-memory.py --before /path/to/baseline/console_solver \
  --preflight-input /path/to/input.txt
```

The comparison uses a fresh child process for each peak-RSS measurement and
cleans its temporary binaries' output/log directories. It does not ship the
baseline binary. `scripts/test.sh` remains the regular regression suite.

## Other opportunities, ranked

1. **Compact the hand-evaluator lookup.** `Dic5Compairer` stores the 2,598,960
   five-card lookup entries in an `unordered_map<uint64_t, int>`. A dense
   combinatorial index with 16-bit ranks would need about 5 MiB for ranks,
   instead of millions of separately allocated hash nodes and buckets. This
   could reduce the relatively fixed ~133 MiB small-solve footprint substantially.
   It needs exhaustive lookup validation, missing-key handling, and a rank-query
   speed comparison for both Hold'em and short deck. Not implemented in this
   pass; it is smaller than the multi-GiB training-state saving above.
2. **Compact cached hand records.** River caches still copy `PrivateCards`,
   including its two-card vector, into every ranked record. A compact record
   containing rank, reach index and card IDs/mask could avoid that allocation.
   Borrowing pointers into the original ranges is another option, but needs
   an explicit lifetime contract. This is a cache optimization, not a reduction
   of the two main strategy arrays.
3. **Avoid storing board-blocked hand slots.** Future-state arrays currently
   retain the original flop-compatible hand dimensions even when later cards
   collide with some hands. At a flop, excluding these slots is approximately
   4.1% on the turn and 8.1% on the river, averaged over future boards. It needs
   stable compact hand-index maps across CFR, best response and strategy export;
   this is more invasive than deleting a redundant cache.
4. **Use proven suit symmetries where available.** The fork already implements
   this, but it is disabled by the app and disabled by the engine for exact
   combo inputs. Preflight also currently assumes no symmetry reduction. The
   user's rainbow Th/7c/6d board has no interchangeable suits under the current
   algorithm, so enabling this flag would not solve that particular case.
   Monotone/two-suit boards can benefit. Validating weighted range symmetries
   and a symmetry-aware estimate would be necessary before changing defaults.
5. **Reduce transient allocation churn.** Moving the initial trainable-slot
   vector rather than copying it, and reusing traversal scratch, can improve
   setup/allocator traffic. These are smaller peak-RAM wins than persistent
   per-state arrays. Several traversal copy reductions were already present.

Reduced-precision floats or smaller betting trees can save much more, but
change numerical behavior or the poker model. They are not interchangeable
with the exact-layout optimizations above. There is no action-abstraction or
precision change in this pass.

## Disk-backed work: two separate features

**Checkpoint/resume** saves a consistent training state and lets the process
exit. It does not, by itself, let an oversized state fit into RAM when resumed.
The existing strategy JSON is not a checkpoint: it contains normalized average
strategies, not the complete regret and cumulative-strategy arrays.
`DiscountedCfrTrainable::dump_strategy(true)` currently explicitly rejects state
storage, so resumability is not an existing hidden switch.

A first checkpoint design should stop only after a complete iteration (both
player updates). Save the iteration, both arrays for every allocated
node/public-deal state, stable node/deal/hand indices, exact ranges/weights,
board, pot/stacks, betting settings, algorithm parameters and source/format
version. The sum cache removed above need not be saved. Preserve float bits.
Use a manifest, checksums and temporary files followed by an atomic publish;
reject mismatched trees and incomplete checkpoints. Cached hand rankings can
be rebuilt. Test resumed versus uninterrupted results at fixed iteration
counts, including cancellation during save and corrupted checkpoint files.

**Bounded-RAM training** additionally needs an evictable backing store, not just
save/load. A plausible next design is contiguous regret/average slabs grouped
by public deal/subtree, with an index, a bounded cache and pinned pages for
active recursive/OpenMP users. Scheduling should process a chunk while it is
resident, then flush/evict it. A file mapping alone delegates eviction to the
OS and does not provide a strict RAM budget.

This solver visits future states during each player traversal and best-response
pass. Loading and rewriting multi-GiB state every pass can produce substantial
SSD traffic; paging without a locality-aware traversal could replace the RAM
problem with I/O stalls. Parent payoff aggregation and two-player update order
must stay consistent. A design should therefore specify cache ownership,
pinning, parallelism, dirty-write recovery and I/O limits before implementation.

Recommendation: keep the two verified low-cost reductions first, profile the
compact evaluator/cache opportunities next, then design checkpoint/resume as a
separate feature. Treat bounded-RAM out-of-core training as a further project,
with measured I/O costs and an explicit consistency model.
