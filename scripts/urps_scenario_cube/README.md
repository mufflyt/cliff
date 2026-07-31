# URPS workforce scenario cube (prototype)

A single precomputed table, `data/workforce_scenario_cube.csv`, holding a
`year x scenario x (supply_headcount, supply_clinical_fte)` supply projection for
2023-2040. It is a **prototype** of the NurseCast-style "precompute all supported
combinations, serve a slice" pattern: the Shiny apps should read this frozen table
instead of re-running the projection interactively.

Regenerate with:

```
Rscript scripts/urps_scenario_cube/build_scenario_cube.R
```

## Why this exists

cliff already has the pieces (an age-structured `wc_project` recurrence, Monte Carlo
intervals, ~8 scenario families, and an age-productivity clinical-FTE model in
`shiny_urps_adequacy`), but they are scattered: the headcount projection is one row
per subspecialty, the FTE model lives in a separate app, and the scenarios are in
separate CSVs. This cube unifies them into one schema carrying **headcount and FTE
per (year, scenario)** so an app reads a slice rather than recomputing.

## Schema

| column | type | meaning |
|---|---|---|
| `year` | int | 2023-2040 |
| `scenario_id` | chr | one of the four scenarios below |
| `pathway` | chr | `combined` (both-pathway; per-pathway split is a next slice) |
| `geography_type` | chr | `national` (per-geography is a next slice) |
| `geography_id` | chr | `US` |
| `supply_headcount` | int | projected active physician headcount |
| `supply_clinical_fte` | num | age-productivity-weighted capacity index, normalized so `effective(2023) == headcount(2023)`; a relative capacity unit, NOT absolute hours |
| `lower_95`, `upper_95` | int | 95% Monte Carlo interval on headcount (Binomial draws, seed 20260718, 2,000 draws) |
| `entrants` | int | new entrants that year |
| `exits` | num | modeled exits that year |
| `net_change` | int | `supply_headcount(t) - supply_headcount(t-1)` |

## Scenarios

| `scenario_id` | definition |
|---|---|
| `baseline` | observed pooled GO+URPS age-band exit hazards (events/PY 2016-2021); standard age-productivity FTE |
| `earlier_exit_2yr` | exit shifted 2 years earlier (each cohort faces the hazard of age+2) |
| `lower_late_career_fte` | clinical FTE reduced 15% from age 60 (headcount unchanged) |
| `fellowship_expansion_10pct` | entrants +10% (64 -> 70 per year) |

## Reused, not reinvented

- **Engine:** `wc_project`'s recurrence via `wc_engine_loader.R` (pure projection defs, no duckdb), so the cube uses the same math the manuscript uses (guarded by `test-wc-engine-equivalence.R`).
- **Hazards:** the published pooled GO+URPS age-band hazards.
- **Cohort:** the 2023 board-certified active age structure (n=1,306, both pathways) from `urps_cohort_ages_v3.0.0.csv`.
- **FTE:** the age-productivity curve from `shiny_urps_adequacy/data/urps_module_a_age_productivity_2026-07-23.csv`. The pathway clinical-time blend is a constant and cancels in the `effective(2023)==headcount(2023)` normalization, so only the age curve is needed here.

## Caveats (this is a prototype, not a published estimand)

- **FTE is a normalized capacity index** (effective providers, 2023 = headcount), not absolute hours.
- **National, combined-pathway only.** Per-geography and per-pathway (ABOG / ABU) are the documented next slice; the schema already carries the columns.
- **No demand saturation.** With constant entrants and modest exits the stock grows roughly linearly (headcount nearly doubles by 2040). NurseCast bounds this with a demand side; that is deliberately out of scope for a supply-only prototype. Do NOT read the 2040 level as a forecast.
- `lower_late_career_fte` reduces FTE immediately at 2023 (the cohort already has physicians aged 60+), which is the intended structural late-career-effort assumption.

## Recommended next steps (the real architecture)

1. Add per-pathway (ABOG / ABU) and per-geography (national / conus, then region) rows using the enriched rosters, which carry pathway + geography per provider.
2. Move the **scenario dictionary** (the `scenario_id` definitions) and the **headcount-to-FTE function** into `mufflyaccess`, and publish this cube as a versioned dataset there, so cliff / twostep / isochrones consume one canonical table and none of them independently defines "baseline", "active", or "clinical FTE".
3. Point the Shiny apps at the cube slice (they already read frozen CSVs for the scenario-comparison tab).
