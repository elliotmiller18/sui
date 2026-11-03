# Preflop chart sources

Imported 2026-10-26. All packs use 100 BB and no ante. Published mixes are
preserved. Source-data checks do not independently certify equilibrium or
exploitability.

## NL50-style cash: Poker Trainer

- Primary viewer: https://app.pokertrainer.se/
- Provider's explanation of original GTO versus simplified PTO data:
  https://pokertrainer.se/opening-poker-hands/
- Source: https://app.pokertrainer.se/7698.92558be03cbed061.js
- Source SHA-256: `a4de692d8225b02f9c9afcb029182d5cb50ebca46442057026aae240fc5aeb76`
- `nl50-cash.json` SHA-256: `56e29ed6a0352f6b5efe2bba73d3de46ea4ec062504e4f0a2db50fa7de8fa83d`

The imported object is specifically `Cash_100_GTO`, not PTO, Simple or PRO.
It contains 271 scenario maps covering all nine positions, opening, responding
to opens, 3-bets, 4-bets and shoves. Frequencies retain up to nine decimal
places. Missing hand entries mean zero. It exactly matches the Cash_100_GTO
mirror at https://github.com/jensbaagaard/poker-practice . A mirror is not an
independent solver cross-check.

The provider describes NL50-style rake, but the data does not include the exact
rake cap or solve logs. Sui therefore labels it NL50-style, not a verified
PokerStars 5%/4BB-cap solve. Opens are 2.5 BB, SB 3 BB. The sizing profile
documented in the mirror uses 3x IP / 5x OOP 3-bets (minimum 7 BB), rounded
2x IP / 2.5x OOP 4-bets and 100 BB 5-bets.

For 3–8 players, the app reuses the corresponding position charts with absent
early seats omitted. The user explicitly accepted this, and the main window
labels it. These are not separately solved table sizes. Source positions run
EP1, EP2, EP3, LJ, HJ, CO, BTN, SB, BB. Sui uses UTG names for early seats and
HJ for hijack. Source ranges retain their assumptions about players behind
entering the pot. Automatic folds after two entrants only restrict navigation.

### Independent six-player sanity comparison

Compared RFI weights against the independent MonkerSolver output at
https://solvepoker.app/nlhe-preflop-charts . Percentages use 6/4/12 combinations
for pairs/suited/offsuit hands.

| Seat | Poker Trainer | SolvePoker |
| --- | ---: | ---: |
| UTG / LJ | 16.320% | 16.843% |
| HJ | 21.229% | 20.902% |
| CO | 27.657% | 27.730% |
| BTN | 42.068% | 43.436% |
| SB | 43.425% | 38.288% |

SolvePoker uses 5% rake / 2 BB cap, and its SB tree includes limps. Settings
differ, so this is a sanity comparison, not exact per-hand validation. A second
independent source with matching settings was not obtained for every size;
no such verification is claimed. The user accepted using one credible source.

## Heads-up: SolvePoker

- Primary charts/settings: https://solvepoker.app/nlhe-preflop-charts
- Source: https://solvepoker.app/_app/immutable/chunks/DCQOc778.js
- Source SHA-256: `d256ae09410e3a49f9613d08b215fa04a3791030cb6843f39da31b4c476d8ced`
- `heads-up.json` SHA-256: `9289b2087f2e3a089dd92df777035c5205888c841fea37a28294451f20b1d90a`

The provider reports MonkerSolver, 1,634,980,577,280 iterations, 100 BB, no ante,
5% rake capped at 2 BB. Ten decisions cover raised and limped pots through
shoves. Sui retains the source's percentage precision (often 0.5 or 0.1 points).
Published headline frequencies: BTN raises 69.1%, limps 17.1%; BB versus the
raise 3-bets 24.6%, calls 33.8%. This is a dedicated HU solution, not a
six-player blind battle. SB is the button and BB acts first postflop. The rake
is shown explicitly in the main window; this is not NL500 HU rake.

## Existing NL500 pack

The original TexasSolver `100bb 2.5x 500rake` files remain selectable for six
players. See ../PROVENANCE.md. The filename suggests NL500, but detailed rake,
solver authorship and convergence metadata are unavailable. Sui labels this
limitation. Other sizes do not substitute NL50 charts under an NL500 label.

## Reproduce extraction

Download the two exact source chunks above, then run:

```sh
python3 scripts/import-preflop.py /path/to/7698.92558be03cbed061.js /path/to/DCQOc778.js
```

The importer parses JSON/static literals without executing downloaded code,
rejects unexpected layouts and prints checksums. Only chart data is bundled.

Response grids divide cumulative action weights by the actor's prior range;
the postflop bridge retains cumulative weights. Unreachable hands stay gray;
residual reachable mass is Fold. The existing pack permits its original 0.002
absolute rounding between nodes; new cash data retains original precision.
HU percentages retain their published rounding tolerance. This fixes showing
cumulative reach weights as conditional action frequencies.
