# Hand-ranking lookup tables

The console solver requires these two upstream lookup tables. They are stored
as deterministic gzip files to keep the source checkout small; `build-solver.sh`
unpacks them into the generated app. No download is needed at build time.

SHA-256 of the uncompressed files:

| Table | Bytes | SHA-256 |
| --- | ---: | --- |
| `card5_dic_sorted.txt` | 51,971,652 | `13e0f4bd3cb99388caec49b36f98b98b70ae30407cbd740d880db65ed4db5e7b` |
| `card5_dic_sorted_shortdeck.txt` | 7,394,256 | `a608bd84cb340ae4918ceab1447faf754c24b22e8f6cb64e054c2fa6f7ec8d78` |

The app uses Hold'em. The short-deck table is retained for the upstream console
engine. Sample output, logs, example game trees and upstream helper scripts are
not runtime resources and are excluded.
