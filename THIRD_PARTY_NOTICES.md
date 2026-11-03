# Third-party components and data

| Component | Origin | Recorded license / status |
| --- | --- | --- |
| TexasSolver console engine | [bupticybee/TexasSolver](https://github.com/bupticybee/TexasSolver), revision `6dfb65b4d7ed081da509e8d8c3d82138c4708267` | [GNU AGPL v3](vendor/TexasSolver-console/LICENSE); changes recorded in [SUI-FORK.md](vendor/TexasSolver-console/SUI-FORK.md) |
| fmt | Vendored dependency of that engine | [MIT-style license](vendor/TexasSolver-console/ext/fmt/LICENSE.rst), copyright Victor Zverovich |
| LLVM OpenMP runtime | Local LLVM installation, copied during build | Apache 2.0 with LLVM exceptions; that installation's `LICENSE.TXT` is included in the app as `OpenMP-LICENSE.txt` |
| Hand-ranking lookup tables | Existing TexasSolver v0.2.0 installation | Origin recorded in [provenance](assets/solver/PROVENANCE.md); checksums in [resources](assets/solver/resources/README.md) |
| Original NL500 preflop pack | Existing TexasSolver installation | No separate redistribution license recorded |
| NL50-style preflop charts | Poker Trainer `Cash_100_GTO` | No redistribution permission recorded; [source details](assets/solver/preflop/README.md) |
| Heads-up preflop charts | SolvePoker | No redistribution permission recorded; [source details](assets/solver/preflop/README.md) |

Source availability and attribution do not establish permission to redistribute
the downloaded chart packs. This repository currently includes them for the
existing local app; their status must be resolved before public distribution.
The repository does not assert a new license over third-party data.

There is currently no root license for Sui's original source. Choose one
explicitly before presenting the project as licensed open-source software.
