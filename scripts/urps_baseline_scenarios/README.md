# URPS baseline scenario analysis (contract v3.0.0)

Separates two deliverables that must **not** be conflated, and makes the
baseline choice a *controlled* experiment rather than a mix of a frozen result
and fresh reruns.

## Deliverable 1 — published-result preservation (`table1_...csv`)

The frozen published SGS projection (legacy **1,295** → 1,505.4) is retained
**exactly and not recalculated**. Its purpose is reproducibility, not causal
comparison. `data/workforce_projections_consolidated.csv` is never modified; the
driver aborts if that row changes. `seed`/`draw_count` are `NA` and
`frozen_or_recalculated = frozen`.

## Deliverable 2 — controlled sensitivity (`table2_...csv`)

Every scenario is run through cliff's **actual** `wc_project()` engine (loaded
verbatim from `R/workforce_cliff_engine.R`; see equivalence below) with identical
hazards, entrant assumption, Monte-Carlo settings, and seed. **Index year is
honest** — a stock is projected from its own source year to 2029:

| scenario | status | index yr | horizon | baseline | projected 2029 | 95% CI | retire/yr |
|---|---|---|---|---|---|---|---|
| `legacy_rerun` | synthetic (count-scaled, 2023-active structure) | 2023 | 6 | 1,295 | 1,594 | 1,531–1,614 | 14.1 |
| `active_2023` | observed | 2023 | 6 | 1,306 | 1,605 | 1,541–1,625 | 14.2 |
| `roster_2025` | observed (**2025-indexed, not a 2023 baseline**) | 2025 | 4 | 1,339 | 1,543 | 1,502–1,555 | 13.1 |

- **1,339 is 2025-indexed** (horizon 4). It is never presented as a 2023 baseline.
- `legacy_rerun` is a **synthetic** count-scaled cohort (the true legacy 1,295
  primary-cert cohort is not reconstructable from the v3.0.0 artifact). It is run
  through the same engine and is **distinct from the frozen published result** —
  the frozen row is reproducibility evidence; the reruns are the comparison set.

## Deliverable 2b — same-horizon view (`table4_...csv`)

Removes the **horizon confound**: the 2023 stocks are *adopted as the 2025
baseline* — the frozen model's own convention (it uses a 2023-derived stock as
`baseline_2025`) — and all three are projected at horizon 4 to 2029. This makes
the baselines directly comparable **to each other and to the frozen published
result** (also index 2025, horizon 4).

| scenario | status | index yr | horizon | baseline | projected 2029 | 95% CI | retire/yr |
|---|---|---|---|---|---|---|---|
| `legacy_h4` | synthetic (2023-active structure, adopted as 2025) | 2025 | 4 | 1,295 | 1,499 | 1,459–1,512 | 13.0 |
| `active_h4` | 2023 stock adopted as 2025 baseline | 2025 | 4 | 1,306 | 1,510 | 1,469–1,523 | 13.0 |
| `roster_h4` | **genuine** 2025 roster | 2025 | 4 | 1,339 | 1,543 | 1,502–1,555 | 13.1 |
| _frozen published (reference)_ | _observed (published)_ | _2025_ | _4_ | _1,295_ | _1,505_ | _1,476–1,535_ | _11.4_ |

**The clean apples-to-apples.** `legacy_h4` and the frozen row share baseline
(1,295), index year (2025), horizon (4), and engine — they differ **only in the
age distribution**. The rerun lands at 1,499 vs the frozen 1,505 (retire 13.0 vs
11.4/yr), so the retirement-rate gap is attributable to **age structure** (the
frozen model assumed a younger age distribution than the v3.0.0 age proxy), not
to horizon or count. Projections are monotone in baseline (1,499 < 1,510 < 1,543)
with the horizon confound removed.

## Deliverable 3 — count vs age-composition decomposition (`table3_...csv`)

Controlled synthetic experiment at a **common 2023 origin / horizon 6**, so only
one thing changes at a time:

| contrast | baseline | age structure | projected | retire/yr | Δ proj | Δ retire/yr |
|---|---|---|---|---|---|---|
| reference (active 2023) | 1,306 | 2023-active | 1,605.1 | 14.15 | — | — |
| **count effect** | 1,295 | 2023-active | 1,594.3 | 14.11 | −10.8 | **−0.04** |
| **age effect** | 1,306 | 2025-roster | 1,606.5 | 13.92 | +1.4 | **−0.23** |
| combined | 1,339 | 2025-roster | 1,637.4 | 14.27 | +32.3 | +0.12 |

**Finding, correctly attributed.** The **count effect on the retirement rate is
≈0** (−0.04/yr for 11 fewer providers at the same age structure). So the earlier
observation that "current cohorts retire faster" is **not** a size effect — it is
driven by **age composition** (and, versus the frozen 11.4/yr, by index year /
horizon: a 2023-origin horizon-6 run ages the cohort two years longer). The
frozen-vs-rerun retirement difference is **not** a controlled comparison, because
the legacy cohort's age structure is unavailable and its horizon differs; only the
within-v3.0.0 count/age decomposition above is controlled.

## Engine equivalence (no reimplementation)

`wc_project()` is **not reimplemented**. `wc_engine_loader.R` parses
`R/workforce_cliff_engine.R` and evaluates only the pure projection definitions
(`wc_band_of`, `wc_haz_for`, `wc_project`), skipping the data/IO preamble
(readr/dplyr/duckdb/config) that the projection does not need.
`test-wc-engine-equivalence.R` proves:

- the loaded `wc_project` is **structurally identical** (body + formals) to the
  engine's definition; and
- it matches hand-computed fixtures (zero hazard, single band, boundary ages,
  zero/fixed entrants, 1- and 4-year horizons, deterministic + fixed-seed Monte
  Carlo) with **max abs diff 5.6e-17** (machine epsilon).

## Ages are an estimated proxy

`age_proxy_from_cert` is a **modelled age proxy** (certification-timing-derived),
**not observed age**. The extractor applies the same proxy rule to both cohorts,
excludes the 33 future-certified providers from the 2023-active cohort
(1,339 − 1,306 = 33), rejects impossible ages, and its age-band counts sum
**exactly** to 1,306 and 1,339 (verified in tests).

## Reproduce

```sh
python3 scripts/urps_baseline_scenarios/extract_cohort_ages.py \
  <path>/urps_provider_snapshot.parquet \
  scripts/urps_baseline_scenarios/urps_cohort_ages_v3.0.0.csv
Rscript scripts/urps_baseline_scenarios/urps_scenario_analysis_v3.R
```

Outputs live only under `scripts/urps_baseline_scenarios/`. The frozen
`data/workforce_projections_consolidated.csv` is never touched.
