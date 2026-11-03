# Architecture

`Sources/main.swift` handles CLI commands and starts the AppKit UI in
`Desktop.swift`. `CardPicker.swift` supplies the board selector. `Core.swift`
parses hand ranges and creates grid charts with combination-weighted totals.

`Preflop.swift` follows imported libraries through position order, action
history, folds and raises. It carries cumulative exact hand weights, pot and
remaining stacks into heads-up postflop play. Only two entrants are supported
by the continuing UI; absent table positions reuse source charts as labeled.

`Postflop.swift` creates solver scripts and reads the exported strategy tree.
The selected sizes apply to both players' bets, raises and donks on every
street. All-in is optional; fractional sizes always cap at remaining stacks.
Raise sizes use the pot after calling. The fork preserves fractional wagers,
filters illegal sizes and deduplicates capped actions. Default sizes are
1/3 and 1.5x pot. Check/call/fold remain available where legal.

`Solver.swift` runs the console in a fresh output directory on a background
queue, with cancellation, no default timeout and progress from the
log. Strategy-array estimates above the user-selected RAM budget are
rejected before training. Its initial default is half physical RAM, capped
at 8 GiB. A typed storage-limit error carries the exact estimate into a
Cancel/retry sheet; retry explicitly raises the limit to the required whole
GiB and resubmits the same input in a new directory. The RAM budget is saved in
setup.json, carried between streets and remembered in the UI. Other scratch allocations are not included in that
estimate. Solves target 2% exploitability with up to four threads and 200
iterations. Current defaults disable suit isomorphism.

Future streets are modeled but only the current street is exported. After a
card is chosen, the app solves again using action-conditioned exact ranges,
current pot/stacks and the selected sizes. Changes to size checkboxes affect
the next solve, not an already-exported decision. Setup and solver logs are
saved in the system temporary directory's `sui-solves/` for app sessions.

The engine is compiled by `scripts/solver/CMakeLists.txt`, rather than the
upstream GUI build. `build-solver.sh` bundles its OpenMP dependency using a
relative loader path, expands the lookup tables and includes corresponding
engine source and licenses. `build.sh` compiles Swift and writes `Info.plist`.
The SDK/overlay fallback accommodates mixed Apple Swift 5.10 installations
without changing system files.

Tests run against an isolated copy, including real narrow-range solver calls.
Their workspace, output, and compiler caches are removed by `scripts/test.sh`.

Reset stays enabled during a solve. It cancels the current process, escalates
to SIGKILL if needed after two seconds, and waits for worker completion before
resetting the hand. Cancelled results are discarded. Each solve uses a fresh
controller, so cancellation cannot poison later solves. CLI users may still
set an explicit --timeout; the GUI has no deadline.
