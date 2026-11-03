# Sui

A small native macOS poker range UI and assistant-friendly CLI. Swift + AppKit, with a bundled TexasSolver fork and no web server.

> **100% vibe coded — use at your own risk.** I can’t write Swift, and this is not the level of code quality I typically aim for. This is an experimental personal project; don’t assume the poker strategies or the code are correct.

## Build and open

```sh
./scripts/build.sh
open build/Sui.app
# Or, from a normal desktop terminal:
./build/sui view
```

The app starts **UTG**, six players, with the bundled **NL50-style** mixed charts. Choose **Table** for 2–9 players; changing the table or rake selection starts a new hand. **Reset** returns to the first preflop decision for the selected table, including after reaching postflop. Click an action under **ACTIONS** to load the next player's response. The grid shows action frequencies; selecting a hand shows its percentages. When betting ends heads-up, click **Choose flop…**, select three cards and click **Continue**. The same hand continues using the two remaining ranges, pot (including folded contributions), effective remaining stacks and seat names. There is no back/history UI.

Sui bundles its solver, lookup resources and preflop charts inside the app. There is no range-folder chooser. CLI `list`/`export` retain custom-folder support for inspecting files. No external TexasSolver installation is needed at runtime.

The sidebar shows the selected hand as a larger square split by action frequency,
plus a full-range stacked bar and Play/Fold totals. Full-range percentages count
actual combinations and current reach, including board blockers postflop. Limps,
calls and checks use green; preflop raises use orange, folds blue, and all-ins
purple. Postflop bets/raises progress from light to dark red as their size grows.
The sidebar scrolls when the action list is long, keeping the window size fixed.

## Preflop

Preflop navigation follows downloaded charts, **not newly solved strategies**. Tables use 100 BB stacks, 0.5/1 blinds and no ante. Positions include **HJ**, replacing the old MP label. Each action advances turn order; raises reopen action and folds remove players. The flow ends when everyone else folds or preflop betting is complete.

The NL50-style cash charts come from Poker Trainer's original `Cash_100_GTO` data, preserving published mixed frequencies. For 3–8 players, matching position charts are reused with absent early seats omitted, as labeled in the main window; they are not separately solved table sizes. Heads-up uses a dedicated SolvePoker MonkerSolver solution (5% rake, 2 BB cap), including limp/check branches and correct BB-first postflop order. The old NL500 pack remains available for **six players only**, with its limited source metadata labeled. No NL500 chart set is supplied for other sizes. Full source links, checksums, rake limitations and the independent six-player sanity comparison are in [chart provenance](../assets/solver/preflop/README.md). Source claims and data transfer were checked; these are not independent equilibrium certificates.

Actions retain the source's sizes: 2.5 BB opening raises, larger reraises, and a 3 BB SB opening size in the cash pack. Call and all-in appear where the chart contains them. A missing response displays **No stored response** instead of inventing a strategy or claiming the hand has ended. Sui carries each player's cumulative action range into postflop; HU conditional action frequencies multiply that player's previous reach. Once two players enter voluntarily, all other seats automatically fold; their posted blinds stay in the pot. A closing call goes directly to the flop; a reraise returns action to the other player. This navigation restriction does not remove the source charts' assumptions about players behind entering multiway pots. Called all-ins have no further decisions.

Interactive response charts condition cumulative weights on the acting player's earlier actions. Hands outside that player's reach are gray. Missing reachable weight defaults to Fold. Static CLI file previews still show raw file weights and can override the remainder with `--remainder unassigned|check`.

## Postflop

For a hand started preflop, click **Choose flop…** and select three cards. **Continue** computes the next responses, then the same action buttons carry on. The picker has four suit rows with A–2 across each row; selected cards are highlighted, and clicking them again removes them.

To start a standalone postflop spot instead, select **Postflop**, then enter:

- A board of 3–5 cards using **Choose board…**.
- Current pot and effective **remaining** stack in BB.
- OOP and IP ranges, either text such as `AA,AKs:0.5` or file paths. **File…** opens a range file picker.

Before solving, use the **Bet sizes · pot** checkboxes to add or remove **1/4, 1/3, 2/3, 3/4, 1.5x, 3x, and All-in**. Select at least one; 1/3 and 1.5x are selected by default. The picker also appears before a preflop handoff and remains available for the next turn/river solve. Changes apply to the next solve; existing solved decisions retain their original sizes.

Click **Solve**. Sui runs the real `console_solver` off the UI thread, then displays its strategy. Selected sizes apply to bets, raises and donks on every street. Check, call and fold appear where legal. Selecting All-in adds a separate shove option. Other sizes cap at the remaining stack, and duplicate shoves collapse into one purple action. Sizes below the minimum legal bet/raise are omitted. Fractional BB wagers are preserved by the solver fork. Raise fractions apply to the pot after calling; the displayed BB amount includes that call and is the additional amount paid. More selected sizes increase solve time and memory use.

Each solve models future play but exports only the current street. Clicking actions within that street loads the solved decisions. At the end of the street, click **Choose turn…** or **Choose river…**, select a card and click **Continue** to solve the next street using the action-conditioned exact combinations, current pot and remaining stacks. Previously used board cards are grayed out and disabled in the picker. Suit-specific weights are preserved. A new solve can differ from the previous tree’s future strategy. A native spinner, elapsed time, latest solver iteration and exploitability versus the 2% target appear in the existing grid area while solving; export is labeled when it begins. Progress comes from the solver log, not an estimated completion percentage. The window size stays unchanged. Failed next-street solves leave the prior state available to retry. River check/check, river calls, folds and called all-ins end the decision flow. The app does not deal hidden hole cards or determine a showdown winner.

Postflop is **heads-up, no rake**, using the bundled TexasSolver console fork’s incremental wager amounts. For the automatic handoff, setup comes from the completed preflop line; standalone solves use explicit inputs. Postflop remains no-rake even though the imported preflop library has its own rake assumptions. Folded-player card-removal effects are not modeled. The grid averages suit-specific strategies using the acting player's range weights and previous action frequencies. Board-blocked and zero-reach hands are gray, not folds. The solver's reported exploitability is visible; reaching the iteration cap is not a convergence guarantee.

Solves use up to 4 threads, a 2% accuracy target, a 200-iteration cap, no suit isomorphism and a current-street strategy dump. Large flop ranges/trees can take substantial memory and time. There is no default time limit. **Reset** stops the active solver, releases its memory and starts a fresh hand. Input, setup, log and output (plus `preflop.json` with range snapshots and action history for automatic handoffs) are saved under the system temporary directory's `sui-solves/` folder. Closing the app terminates its active solve. Switching modes starts a new flow.

The fork estimates the RAM needed for strategy arrays before training, not disk space. **RAM budget
(GiB)** is adjustable before each solve and is remembered between app launches.
Its initial default is half physical RAM, capped at 8 GiB. When the estimate
exceeds the selected budget, a popup offers **Cancel** or **Raise to N GiB and
Retry**, where N is the estimate rounded up to a whole GiB (and above the old
budget). A 19.04 GiB estimate therefore suggests 20 GiB. Cancel leaves the
current budget and betting setup available to adjust. Retry uses the same
board, ranges and bet sizes in a fresh solve directory. This also works for
preflop handoffs and next-street solves.

The popup says: “If this size is too large, consider reducing the number of bet
sizes.” The estimate excludes other RAM used by the solver, so increasing the budget
does not guarantee a successful allocation or convergence.

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

`postflop` also accepts `--solver-home` and `--timeout` (optional; no time limit by default). `list` produces exact spot IDs and source paths; `export` requires an exact `--spot` when more than one matches. JSON vectors follow the returned action order. Invalid ranges, duplicate hands, conflicting frequencies and reused output directories are rejected. Small chart export rounding (up to 0.2 percentage points above 100%) is normalized.

The runner uses `console_solver -i input.txt -r resources` in a fresh output directory. It checks process completion and strategy JSON; it never substitutes estimated strategy. macOS approval of the GUI does not necessarily approve the separate `console_solver` executable. Builds are currently local and not notarized.

