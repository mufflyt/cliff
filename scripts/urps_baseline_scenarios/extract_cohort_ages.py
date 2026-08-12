#!/usr/bin/env python3
"""Materialize AGGREGATE ESTIMATED-AGE-PROXY band counts for the URPS scenarios.

`age_proxy_from_cert` is a MODELED age PROXY (derived from certification timing +
the prespecified age-proxy method), NOT an observed age. This emits an AGGREGATE
table (one row per proxy-age, counts per cohort) -- no physician-level rows.

The two cohorts reconstructable from the isochrones v3.0.0 provider snapshot:
  * roster_2025  -- all identified providers                 -> 1339 (2025 roster)
  * active_2023  -- active_2023 == TRUE (URPS-subspecialty-cert basis) -> 1306

Inclusion criteria are asserted here: active_2023 excludes the future-certified
providers (roster - active = 33), and the same age-proxy rule is applied to both.
The legacy 1,295 cohort (primary-cert reconciliation) is NOT reconstructable from
this artifact; its projection comes from the frozen published record (see the R
driver), and its rerun is a clearly-labeled SYNTHETIC count-scaled cohort.
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

roster, active = defaultdict(int), defaultdict(int)
for a, act in zip(age, a2):
    if a is None:
        continue
    assert 25 <= a <= 100, f"impossible proxy age {a}"        # no impossible ages
    roster[a] += 1
    if act:
        active[a] += 1

n_roster, n_active = sum(roster.values()), sum(active.values())
assert n_roster == 1339, n_roster
assert n_active == 1306, n_active
assert n_roster - n_active == 33, "roster minus active must equal the 33 future-certified"
# active is a strict subset of roster at every age
for a in active:
    assert active[a] <= roster[a], f"active exceeds roster at age {a}"

with open(OUT, "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["age_proxy", "n_roster_2025", "n_active_2023"])
    for a in sorted(roster):
        w.writerow([a, roster[a], active.get(a, 0)])

print(f"wrote {OUT}: roster_2025={n_roster} active_2023={n_active} "
      f"excluded_future_certified={n_roster - n_active} "
      f"(estimated age-proxy band aggregate, no PII)")
