# URPS workforce scenario cube (prototype)

A single precomputed table, `data/workforce_scenario_cube.csv`, holding a
`pathway x geography x scenario x year -> (supply_headcount, supply_clinical_fte)`
supply projection for 2023-2040 (**432 rows**: 3 pathways x 2 geographies x 4
scenarios x 18 years). It is a **prototype** of the NurseCast-style "precompute all
supported combinations, serve a slice" pattern: the Shiny apps should read a slice
of this frozen table instead of re-running the projection interactively.

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
per (pathway, geography, scenario, year)** so an app reads a slice rather than recomputing.

## Schema

| column | type | meaning |
|---|---|---|
| `year` | int | 2023-2040 |
| `scenario_id` | chr | one of the four scenarios below |
| `pathway` | chr | `ABOG`, `ABU`, or `combined` (`combined = ABOG + ABU`, additive) |
| `geography_type` | chr | `national` or `conus` |
| `geography_id` | chr | `US` (national) or `CONUS` |
| `supply_headcount` | int | projected active physician headcount |
| `supply_clinical_fte` | num | age-productivity- and pathway-clinical-time-weighted capacity index, on a single global scale so `effective(combined, national, 2023) == headcount (1,306)`; a relative capacity unit, NOT absolute hours. Additive across pathway/geography rows |
| `lower_95`, `upper_95` | int | 95% Monte Carlo interval on headcount (Binomial draws, seed 20260718, 2,000 draws; combined = summed ABOG+ABU draws) |
| `entrants` | int | new entrants that year |
| `exits` | num | modeled exits that year |
| `net_change` | int | `supply_headcount(t) - supply_headcount(t-1)` |

The 2023 starting cells reconcile exactly to the mufflyaccess v3.0.0 SSOT: ABOG
1,027 (national) / 1,026 (conus); ABU 279 / 277; combined 1,306 / 1,303.

## Scenarios

| `scenario_id` | definition |
|---|---|
| `baseline` | observed pooled GO+URPS age-band exit hazards (events/PY 2016-2021); standard age-productivity FTE |
| `earlier_exit_2yr` | exit shifted 2 years earlier (each cohort faces the hazard of age+2) |
| `lower_late_career_fte` | clinical FTE reduced 15% from age 60 (headcount unchanged) |
| `fellowship_expansion_10pct` | entrants +10% |

## Reused, not reinvented

- **Engine:** `wc_project`'s recurrence via `wc_engine_loader.R` (pure projection defs, no duckdb), guarded by `test-wc-engine-equivalence.R`.
- **Hazards:** the published pooled GO+URPS age-band hazards.
- **Cohorts:** the 2023 board-certified active age structure per (pathway, geography), extracted from the isochrones v3.0.0 provider snapshot into `urps_cohort_ages_pathway_geo_v3.0.0.csv`; reconciles to the SSOT cells above.
- **FTE:** the age-productivity curve from `shiny_urps_adequacy` plus the pathway clinical-time factor (ABOG 1.0, ABU 0.70). A single global scale anchors combined-national-2023 effective FTE to its headcount, so FTE is additive across rows (ABOG FTE + ABU FTE = combined FTE).

## Caveats (this is a prototype, not a published estimand)

- **FTE is a normalized capacity index** (effective providers, combined-national-2023 = headcount), not absolute hours. Because ABU carries a 0.70 clinical-time factor, ABU effective FTE sits below its headcount and ABOG above; the two sum to the combined anchor.
- **Entrants are split by pathway** using the national active-stock share (~50 ABOG, ~14 ABU per year) and applied identically to conus (the 3 non-conus providers are negligible). A pathway-specific ACGME completion split would refine this.
- **No demand saturation.** With constant entrants and modest exits the stock grows roughly linearly (headcount nearly doubles by 2040). NurseCast bounds this with a demand side; that is deliberately out of scope for a supply-only prototype. Do NOT read the 2040 level as a forecast.
- `lower_late_career_fte` reduces FTE immediately at 2023 (the cohort already has physicians aged 60+), which is the intended structural late-career-effort assumption.

## Recommended next steps (the real architecture)

1. ~~Add per-pathway (ABOG / ABU) and per-geography (national / conus) rows.~~ **Done.** Region- and division-level geography (joined via isochrones) is the next geographic slice.
2. Move the **scenario dictionary** (the `scenario_id` definitions) and the **headcount-to-FTE function** into `mufflyaccess`, and publish this cube as a versioned dataset there, so cliff / twostep / isochrones consume one canonical table and none of them independently defines "baseline", "active", or "clinical FTE".
3. Point the Shiny apps at the cube slice (they already read frozen CSVs for the scenario-comparison tab).
