#!/usr/bin/env python3
"""Materialize AGGREGATE age-band counts for the URPS baseline scenarios.

Reads the isochrones v3.0.0 provider snapshot and emits an AGGREGATE table
(one row per age, counts per cohort) -- no physician-level rows leave here.
The two reconstructable cohorts:
  * roster (2025 snapshot)          -- all identified providers        -> 1339
  * active_2023 (v3.0.0 canonical)  -- active_2023 == TRUE             -> 1306

The legacy 1295 cohort (primary-cert reconciliation, 1031 ABOG + 264 ABU) is NOT
reconstructable from the v3.0.0 artifact; its projection comes from the frozen
published record, not a re-run (see the R driver).
"""
import csv
import sys
import pyarrow.parquet as pq
from collections import defaultdict

PARQUET = sys.argv[1] if len(sys.argv) > 1 else \
    "../mufflyaccess/tests/testthat/fixtures/isochrones-v3.0.0/urps_provider_snapshot.parquet"
OUT = sys.argv[2] if len(sys.argv) > 2 else \
    "scripts/urps_baseline_scenarios/urps_cohort_ages_v3.0.0.csv"

t = pq.read_table(PARQUET)
age = t.column("age_proxy_from_cert").to_pylist()
a2 = t.column("active_2023").to_pylist()

roster = defaultdict(int)
active = defaultdict(int)
for a, act in zip(age, a2):
    if a is None:
        continue
    roster[a] += 1
    if act:
        active[a] += 1

assert sum(roster.values()) == 1339, sum(roster.values())
assert sum(active.values()) == 1306, sum(active.values())

with open(OUT, "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["age", "n_roster_2025", "n_active_2023"])
    for a in sorted(roster):
        w.writerow([a, roster[a], active.get(a, 0)])

print(f"wrote {OUT}: roster={sum(roster.values())} active_2023={sum(active.values())} "
      f"(age-band aggregate, no PII)")
