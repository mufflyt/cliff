# URPS baseline-scenario comparison (contract v3.0.0)

**Purpose.** Show how the *choice of 2023 baseline* moves the 2025→2029 workforce
projection, as **three explicit scenarios** — instead of silently re-baselining
the published projection. This is the scientific follow-up to the mufflyaccess
v3.0.0 adoption: the published (legacy 1,295) projection is **reproduced from the
frozen record and never re-run or overwritten**.

## The three baselines

| Scenario | 2023 baseline | Cohort basis | Projected 2029 | % change | Avg retire/yr | Replacement ratio |
|---|---|---|---|---|---|---|
| **A. legacy** | **1,295** | primary-cert reconciliation (1031 ABOG + 264 ABU) | 1,505 | +16.2% | 11.4 | 5.61 |
| **B. 2023 active** | **1,306** | URPS-subspecialty-cert active (mufflyaccess v3.0.0) | 1,510 | +15.6% | 13.0 | 4.93 |
| **C. 2025 roster** | **1,339** | 2025 roster snapshot (full identified cohort) | 1,543 | +15.2% | 13.1 | 4.89 |

(Exact values in `urps_baseline_scenarios_v3.0.0.csv`.)

## Method

- **Scenario A** is the **published** frozen SGS projection, read verbatim from
  `data/workforce_projections_consolidated.csv`. It is **not recomputed** — the
  legacy 1,295 cohort (primary-cert basis) is not reconstructable from the v3.0.0
  artifact, and the published record is preserved exactly (a guard in the driver
  fails if that row ever changes).
- **Scenarios B and C** are re-run with cliff's **own age-structured recurrence**
  (`R/workforce_cliff_engine.R::wc_project`, reimplemented here without the duckdb
  dependency) on each cohort's **real age distribution** (from the isochrones
  v3.0.0 provider snapshot, aggregated to age-band counts — no physician-level
  rows). All published model parameters are held constant so only the baseline
  differs: **64 annual entrants** at age 34, the **fully-observable age-band
  retirement hazards** (events ÷ person-years, 2016–2021), **horizon = 4**.
- The Monte Carlo CI for B/C draws retirements as Binomial(count, band hazard)
  with the published seed (`20260718`), holding entrants fixed. **Note:** A's CI
  is the published one; B/C's CIs come from this age-band Monte Carlo, so the
  point estimates and retirement dynamics — not the interval widths — are the
  apples-to-apples comparison across A vs B/C.

## What it shows

The current cohorts (B, C) have an **older age distribution** (mean age ≈ 49) than
the legacy model assumed, so they **retire faster** (≈ 13/yr vs 11.4/yr) and grow
**more slowly** in percent terms, even though their absolute headcounts are higher.
The replacement ratio drops from 5.6 (legacy) to ≈ 4.9 (current cohorts).

**This does not revise the published projection.** It documents that a modern
re-baseline would shift the trajectory, and by how much — so any future decision
to re-anchor cliff's headline is made deliberately and transparently, with the
1,295 / 1,306 / 1,339 alternatives in view.

## Reproduce

```sh
# 1) materialize aggregate cohort ages from the pinned isochrones v3.0.0 snapshot
python3 scripts/urps_baseline_scenarios/extract_cohort_ages.py \
  <path>/urps_provider_snapshot.parquet \
  scripts/urps_baseline_scenarios/urps_cohort_ages_v3.0.0.csv
# 2) run the comparison (reads the frozen record for A; re-runs the engine for B/C)
Rscript scripts/urps_baseline_scenarios/urps_baseline_scenarios_v3.R
```

Outputs live only under `scripts/urps_baseline_scenarios/`. The frozen
`data/workforce_projections_consolidated.csv` is never modified.
