# Sui

A native macOS poker range viewer and postflop solver. Built with Swift/AppKit
and a bundled [TexasSolver fork](vendor/TexasSolver-console/SUI-FORK.md), with
no web server.

> **100% vibe coded — use at your own risk.** I can’t write Swift, and this is
> not the level of code quality I typically aim for. This is an experimental
> personal project; don’t assume the poker strategies or the code are correct.

## Build and run

Requires macOS, Xcode Command Line Tools, Python 3, CMake, and LLVM/OpenMP.
Using Homebrew:

```sh
xcode-select --install       # If the developer tools are not installed
brew install cmake llvm python
./scripts/build.sh
open build/Sui.app
```

The build finds LLVM through `brew --prefix llvm`. For another installation,
set `SUI_LLVM_ROOT=/path/to/llvm`. All generated files go in ignored `build/`.
Lookup tables are bundled as compressed data and unpacked during the build;
no poker data is downloaded by the build.

The app bundles OpenMP, charts, lookup tables, engine source and license notices.
Recipients do not need Homebrew to run an app built for their machine. Builds
are for the host architecture, unsigned for distribution and not notarized.
The minimum macOS version also depends on the bundled OpenMP runtime and is
recorded in the app's `Info.plist`; building on a newer Mac does not guarantee
compatibility with older macOS versions.

## Use

Start with preflop charts for 2–9 players, or choose **Postflop** to enter a
board, pot, stacks and ranges. Select bet sizes before solving: **1/4, 1/3,
2/3, 3/4, 1.5x, 3x, All-in**. Defaults are 1/3 and 1.5x. At least one size
is required; more sizes increase time and memory use. **Re-raises / street** offers
0, 1 or 2, with a default and maximum of **2**. The opening bet does not count: bet → raise → reraise reaches that cap. **RAM budget (GiB)**
sets the estimated RAM limit for solver strategy arrays (not disk space) and is remembered for future solves. If an
estimate exceeds it, a popup offers **Cancel** or a retry with the required
budget rounded up to a whole GiB. The limit only increases when you choose to
retry or edit the field; total memory use can exceed the strategy estimate. Solves have no time limit by default; **Cancel** stops an
active solver (the button says **Reset** when idle) and starts a fresh hand.

A separate **Hand history** strip shows colored player/action tiles with BB
amounts, grouped by street. It follows the hand from preflop through the river.
Table, rake and pre/postflop selectors appear only during setup; Reset brings
them back. Bet sizes, RAM and re-raise settings appear before each street's
solve and are hidden while navigating the solved street. You can choose new
sizes before solving the turn or river.

Click the **♠** at the lower-left of the selected-hand square to expand its
suit combinations. Suited hands show four breakdowns; offsuit hands use a
3-column × 4-row grid with percentages on hover. Pairs show six cells.
Postflop cells use exact combo strategies; blocked or unreachable hands are
gray. Preflop charts share hand-class frequencies across suits.

Postflop is heads-up and no-rake. Preflop charts are imported data, not fresh
solves; reused table sizes and source assumptions are labeled in the app.
See [usage and CLI examples](docs/usage.md),
[architecture](docs/architecture.md), [solver memory audit](docs/solver-memory.md),
and [data provenance](assets/solver/PROVENANCE.md).

## Regression checks

```sh
./scripts/test.sh             # Full suite, including real solver runs
./scripts/test.sh --preflop   # Preflop checks and CLI fixtures
./scripts/test.sh --sizes     # All size choices, custom subsets and stack caps
```

Tests copy the source into a temporary workspace, build there, and remove it
on success, failure or interruption. Binaries, compiler caches, solver logs,
strategies and fixtures stay out of the working tree. Existing `build/` and
user solve directories are not touched. The full suite checks parsing, error
handling, 2–9 player preflop navigation, selected sizes, carried ranges/stacks,
preflop handoff, and flop → turn → river → showdown. Small fixtures do not
establish broad-range convergence or performance.

## Repository layout

| Path | Contents |
| --- | --- |
| `Sources/` | Native app, poker flow, CLI and solver runner |
| `assets/solver/` | Chart data, compressed runtime tables and provenance |
| `vendor/TexasSolver-console/` | Engine source, minimal fmt dependency and licenses |
| `scripts/` | Build, isolated test runner and chart import tools |
| `tests/` | CLI and real-solver regression suites |
| `docs/` | Usage, architecture and sharing notes |

## Sharing

See [sharing checklist](docs/sharing.md) and
[third-party notices](THIRD_PARTY_NOTICES.md) before making the repository public
or distributing app bundles. Downloaded chart redistribution permissions have
not been established. The project's own license also needs an explicit choice;
third-party licenses remain in their respective directories.

Generated apps, solve outputs and local IDE files are ignored. The largest
source asset is a ~6.4 MiB compressed lookup table. The initial Git commit
contains old uncompressed tables and a sample strategy output; deleting them
from the current tree does not remove them from existing Git history.
