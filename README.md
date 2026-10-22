# Sui

A small native macOS poker range UI and assistant-friendly CLI. Swift + AppKit, with a bundled TexasSolver fork and no web server.

> **100% vibe coded — use at your own risk.** I can’t write Swift, and this is not the level of code quality I typically aim for. This is an experimental personal project.

## Build and open

```sh
./scripts/build.sh
open build/Sui.app
# Or, from a normal desktop terminal:
./build/sui view
```

The app starts **UTG** in the installed `100bb 2.5x 500rake` library. Click an action under **ACTIONS** to load the next player's response. The grid shows action frequencies; selecting a hand shows its percentages. When betting ends heads-up, click **Choose flop…**, select three cards and click **Continue**. The same hand continues using the two remaining ranges, pot (including folded contributions), effective remaining stacks and seat names. There is no back/history UI.

Sui bundles its solver, lookup resources and default `100bb 2.5x 500rake` preflop library inside the app. The main UI always uses these ranges; there is no range-folder chooser. CLI `list`/`export` retain custom-folder support for inspecting files. The original Downloads installation is untouched and is no longer needed at runtime.

## Preflop

Preflop navigation follows downloaded charts, **not newly solved strategies**. It starts with six players, 100 BB stacks, 0.5/1 blinds and the selected library's rake assumptions. Each action advances turn order; raises reopen action and folds remove players. The flow ends when everyone else folds or preflop betting is complete.

Actions retain the library's actual sizes: 2.5 BB opening raises, larger reraises, and a 3 BB SB opening size. Call and all-in appear where the chart contains them. A missing response displays **No stored response** instead of inventing a strategy or claiming the hand has ended. At heads-up completion, Sui carries the latest stored action-range file for each remaining player into a postflop solve; it does not multiply earlier range weights again. BB/SB position is mapped correctly for postflop order. Once two players enter voluntarily, all other seats automatically fold; their posted blinds stay in the pot. A call that closes betting goes directly to the flop; a reraise returns action to the other player. This is a heads-up-only navigation restriction on the six-max charts. Called all-ins have no further betting decisions.

File weights are shown as supplied; nested ranges may be reach weights rather than conditional frequencies. Missing weight defaults to Fold. CLI previews can override that with `--remainder unassigned|check`.

## Postflop

For a hand started preflop, click **Choose flop…** and select three cards. **Continue** computes the next responses, then the same action buttons carry on. The picker has four suit rows with A–2 across each row; selected cards are highlighted, and clicking them again removes them.

To start a standalone postflop spot instead, select **Postflop**, then enter:

- A board of 3–5 cards using **Choose board…**.
- Current pot and effective **remaining** stack in BB.
- OOP and IP ranges, either text such as `AA,AKs:0.5` or file paths. **File…** opens a range file picker.

Click **Solve**. Sui runs the real `console_solver` off the UI thread, then displays its strategy. Click **Check**, **Bet pot / Raise pot**, **All-in**, **Call**, or **Fold** as offered by the solved tree. Calls/folds are available only when facing a bet. Pot sizing may collapse into all-in when stacks are short. Displayed wager amounts are the additional BB paid by that player.

Each solve models future play but exports only the current street. Clicking actions within that street loads the solved decisions. At the end of the street, click **Choose turn…** or **Choose river…**, select a card and click **Continue** to solve the next street using the action-conditioned exact combinations, current pot and remaining stacks. Previously used board cards are grayed out and disabled in the picker. Suit-specific weights are preserved. A new solve can differ from the previous tree’s future strategy. A native spinner, elapsed time, latest solver iteration and exploitability versus the 2% target appear in the existing grid area while solving; export is labeled when it begins. Progress comes from the solver log, not an estimated completion percentage. The window size stays unchanged. Failed next-street solves leave the prior state available to retry. River check/check, river calls, folds and called all-ins end the decision flow. The app does not deal hidden hole cards or determine a showdown winner.

Postflop is **heads-up, no rake**, using the bundled TexasSolver console fork’s incremental wager amounts. For the automatic handoff, setup comes from the completed preflop line; standalone solves use explicit inputs. Postflop remains no-rake even though the imported preflop library has its own rake assumptions. Folded-player card-removal effects are not modeled. The grid averages suit-specific strategies using the acting player's range weights and previous action frequencies. Board-blocked and zero-reach hands are gray, not folds. The solver's reported exploitability is visible; reaching the iteration cap is not a convergence guarantee.

Solves use up to 4 threads, a 2% accuracy target, a 200-iteration cap, no suit isomorphism and a current-street strategy dump. Large flop ranges/trees can take substantial memory and time. The UI timeout is 10 minutes. Input, setup, log and output (plus `preflop.json` with range snapshots and action history for automatic handoffs) are saved under the system temporary directory's `sui-solves/` folder. Closing the app terminates its active solve. Switching modes starts a new flow.

## CLI

```sh
# Preflop click-through from UTG:
./build/sui view

# Catalog and export (JSON; bundled default library):
./build/sui list --position UTG
# Use an exact spot ID from list with export --position UTG --spot ID

# Explicit chart preview, rather than a click-through session:
./build/sui view --position UTG

# Compute a real postflop tree, then open its clickable UI:
./build/sui postflop --board Qs,8d,7h,2c --pot 4 --stack 10 \
  --ip-range T9s --oop-range JTs,43s --out /tmp/my-new-postflop

# Low-level runner for arbitrary TexasSolver input files:
./build/sui solve --solver-home /path/to/TexasSolver \
  --input /path/to/commands.txt --out /tmp/my-new-solve --timeout 120
```

`postflop` also accepts `--solver-home` and `--timeout` (default 600 seconds). `list` produces exact spot IDs and source paths; `export` requires an exact `--spot` when more than one matches. JSON vectors follow the returned action order. Invalid ranges, duplicate hands, conflicting frequencies and reused output directories are rejected. Small chart export rounding (up to 0.2 percentage points above 100%) is normalized.

The runner uses `console_solver -i input.txt -r resources` in a fresh output directory. It checks process completion and strategy JSON; it never substitutes estimated strategy. macOS approval of the GUI does not necessarily approve the separate `console_solver` executable. The installed solver was successfully verified after the user approved it in Settings.

## Verification

```sh
python3 scripts/smoke.py          # Parsing and runner fixture checks
./scripts/check-flows.sh          # Navigation + real narrow-range turn solve
./scripts/check-flows.sh --flop   # Also solve and walk flop → turn → river
./scripts/check-flows.sh --handoff # Preflop handoff → real solve, narrow fixture
```

Requires Apple's developer tools. The build script uses a local compiler overlay for this machine's mixed Swift 5.10 installation; no system toolchain files are changed. The `.app` is local and unsigned. Native UI controls and a real turn solve have been exercised on the desktop.

## Bundled solver build

`vendor/TexasSolver-console/SUI-FORK.md` records the upstream revision and local patch: preserve positive weights below 0.5%. The upstream console parser already supports exact combinations. `scripts/build-solver.sh` builds only the console engine, with CMake, Apple Clang and OpenMP from the installed LLVM (`SUI_LLVM_ROOT` overrides `/opt/homebrew/opt/llvm`). No Qt or Python bindings are built. OpenMP is copied next to the binary with a relative loader path; end users do not need Homebrew. Builds target the host architecture; this is not yet a universal/notarized distribution. This machine’s bundled OpenMP requires macOS 26, and the app declares that minimum. Supporting older macOS versions requires building OpenMP for that older target. The app includes solver source and licenses. Default chart provenance is in `assets/solver/PROVENANCE.md`.
