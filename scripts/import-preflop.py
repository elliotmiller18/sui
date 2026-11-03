#!/usr/bin/env python3
"""Written for Sui by us: extract public chart data without executing vendor JS.

Pass Poker Trainer's 7698 range chunk and SolvePoker's DCQOc778 HU chunk.
Source URLs and settings are recorded in assets/solver/preflop/README.md.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("cash_js", type=Path)
parser.add_argument("heads_up_js", type=Path)
args = parser.parse_args()

text = args.cash_js.read_text()
# h is explicitly assigned to this.Cash_100_GTO in this version of the source.
if "this.Cash_100_GTO=h" not in text:
    raise SystemExit("Vendor layout changed; inspect the GTO variable before importing")
match = re.search(r"\bh=JSON\.parse\('([^']*)'\)", text)
if not match:
    raise SystemExit("Could not locate the original Cash 100 BB GTO data")
cash = json.loads(match[1])
assert len(cash) == 271 and all(0 <= x <= 1 for row in cash.values() for x in row.values())
assert any(0 < x < 1 for x in cash["OpenEP1"].values())

text = args.heads_up_js.read_text()
body = text[text.index("=") + 1:text.rindex(";export")]
# This downloaded chunk is a static object. Translate literals, then require
# strict JSON parsing; no eval, import, or execution of downloaded code.
body = re.sub(r"([{,])([A-Za-z_$][\w$]*|\d+):", r'\1"\2":', body)
body = body.replace("!0", "true").replace("!1", "false")
body = re.sub(r"([:,\[])\.(\d)", r"\g<1>0.\2", body)
hu = json.loads(body)
assert hu["meta"]["depth"] == 100 and len(hu["spots"]) == 10
assert hu["meta"]["rake"] == "5% cap 2bb"
for spot in hu["spots"]:
    assert all(spot[k] is None or len(spot[k]) == 169 for k in ["a", "b", "reach"])
    assert all(0 <= x <= 100 for k in ["a", "b", "reach"] for x in (spot[k] or []))

destination = Path(__file__).resolve().parents[1] / "assets/solver/preflop"
destination.mkdir(parents=True, exist_ok=True)
for name, data in [("nl50-cash.json", cash), ("heads-up.json", hu)]:
    output = json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n"
    (destination / name).write_text(output)
    print(name, hashlib.sha256(output.encode()).hexdigest())
