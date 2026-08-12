#!/usr/bin/env python3
"""Materialize AGGREGATE ESTIMATED-AGE-PROXY x PATHWAY counts for the URPS
projection's clinical-FTE layer.

Same source + age-proxy caveats as extract_cohort_ages.py: `age_proxy_from_cert`
is a MODELED age PROXY (from certification timing), NOT an observed age; this
emits an AGGREGATE table (one row per proxy-age x pathway) with no physician-level
rows.

Adds the `board_pathway` dimension so the projection can apply the pathway-specific
clinical-time weight (mufflyaccess URPS_FTE_PATHWAY_CLINICAL_TIME: ABOG 1.00,
ABU 0.70). board_pathway ABOG -> "ABOG", ABU_NET_NEW -> "ABU" (the FTE-model keys).
Restricted to the 2023-active URPS-subspecialty-cert cohort (sums to 1306 =
ABOG 1027 + ABU 279). Summing over pathway reproduces urps_cohort_ages_v3.0.0.csv.
"""
import csv
import sys
import pyarrow.parquet as pq
from collections import defaultdict

PARQUET = sys.argv[1] if len(sys.argv) > 1 else \
    "../mufflyaccess/tests/testthat/fixtures/isochrones-v3.0.0/urps_provider_snapshot.parquet"
OUT = sys.argv[2] if len(sys.argv) > 2 else \
    "scripts/urps_baseline_scenarios/urps_cohort_ages_by_pathway_v3.0.0.csv"

PATHWAY_MAP = {"ABOG": "ABOG", "ABU_NET_NEW": "ABU"}

t = pq.read_table(PARQUET)
age = t.column("age_proxy_from_cert").to_pylist()
act = t.column("active_2023").to_pylist()
bp = t.column("board_pathway").to_pylist()

cells = defaultdict(int)                                    # (age, pathway) -> n
for a, ok, p in zip(age, act, bp):
    if not ok or a is None:
        continue
    assert 25 <= a <= 100, f"impossible proxy age {a}"
    pw = PATHWAY_MAP.get(p)
    assert pw is not None, f"unexpected board_pathway {p!r} in the active cohort"
    cells[(a, pw)] += 1

by_pw = defaultdict(int)
for (a, pw), n in cells.items():
    by_pw[pw] += n
assert by_pw["ABOG"] == 1027, by_pw["ABOG"]
assert by_pw["ABU"] == 279, by_pw["ABU"]
assert sum(by_pw.values()) == 1306, sum(by_pw.values())

with open(OUT, "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["age_proxy", "pathway", "n_active_2023"])
    for (a, pw) in sorted(cells):
        w.writerow([a, pw, cells[(a, pw)]])

print(f"wrote {OUT}: {len(cells)} age x pathway cells; "
      f"ABOG {by_pw['ABOG']} + ABU {by_pw['ABU']} = {sum(by_pw.values())}")
