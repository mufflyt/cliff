# URPS workforce scenario cube

A single precomputed table, `data/workforce_scenario_cube.csv`, holding a supply
projection for 2023-2040 (**972 rows**: 3 pathways x 2 geographies x 9 scenarios x
18 years). It **conforms to the mufflyaccess projection contract**
(`urps_projection_schema()`, 0.10.0) and passes `validate_urps_projection()`,
including the `baseline_tie` back to `urps_count()`. The Shiny apps read a slice of
this frozen table instead of re-running the projection interactively (the
NurseCast-style precompute-then-serve pattern).

Regenerate with:

```
Rscript scripts/urps_scenario_cube/build_scenario_cube.R
```

## Producer / owner split

cliff RUNS the projection and emits this cube; mufflyaccess OWNS the definitions it
keys on and validates/serves the result:

- **scenarios** come from the mufflyaccess registry `urps_scenarios()` (v1.0.0); the
  builder's `SCEN` list mirrors it exactly (a guard test cross-checks it).
- **clinical FTE** uses the mufflyaccess Phase-3 model (`urps_fte_weight()` /
  `URPS_FTE_PATHWAY_CLINICAL_TIME` / `urps_fte_age_curve()`); the builder currently
  inlines the same age curve + ABOG 1.0 / ABU 0.70 factor and the registry's
  late-career lever (0.75 from age 60), pending a live `library(mufflyaccess)` call
  once 0.10.0+ is installed here.
- **schema** is `urps_projection_schema()` exactly.

## Schema (= urps_projection_schema())

`year, scenario_id, specialty, certification_pathway, geography_type, geography_id,
supply_headcount, supply_clinical_fte, lower_95, upper_95, entrants, exits, net_change`

- `certification_pathway`: `ABOG`, `ABU_NET_NEW`, `ABOG_PLUS_ABU` (the count-contract
  vocabulary; `ABOG_PLUS_ABU = ABOG + ABU_NET_NEW`, additive in headcount and FTE).
- `supply_clinical_fte`: age-productivity- and pathway-clinical-time-weighted capacity
  index, scaled so combined-national-2023 effective FTE == headcount (1,306); NOT hours.
- flows are `NA` at the index year (2023); `net_change == entrants - exits` (the
  contract flow identity).

The 2023 baseline cells reconcile exactly to the mufflyaccess v3.0.0 SSOT: ABOG
1,027 (national) / 1,026 (conus); ABU_NET_NEW 279 / 277; ABOG_PLUS_ABU 1,306 / 1,303.

## Scenarios (= the 9 registry scenarios, urps_scenarios())

`baseline`, `retire_2yr_earlier`, `retire_5yr_earlier`, `retire_2yr_later`,
`fellowship_plus_10pct`, `fellowship_constrained`, `lower_late_career_fte`,
`combined_pessimistic`, `combined_investment`. Lever mapping to the engine:
`haz_shift = -retirement_shift_years` (registry sign: negative = earlier exit),
`entrant_multiplier` scales entrants, `late_career_fte_factor` (0.75) applies from
`late_career_fte_onset_age` (60).

## Reused, not reinvented

- **Engine:** `wc_project`'s recurrence via `wc_engine_loader.R` (pure projection defs, no duckdb), guarded by `test-wc-engine-equivalence.R`.
- **Hazards:** the published pooled GO+URPS age-band hazards.
- **Cohorts:** the 2023 board-certified active age structure per (pathway, geography), extracted from the isochrones v3.0.0 provider snapshot into `urps_cohort_ages_pathway_geo_v3.0.0.csv`; reconciles to the SSOT cells above.
- **Scenarios + FTE:** the mufflyaccess registry (`urps_scenarios()`) and Phase-3 FTE model.

## Caveats (this is a prototype, not a published estimand)

- **FTE is a normalized capacity index** (effective providers, combined-national-2023 = headcount), not absolute hours. Because ABU carries a 0.70 clinical-time factor, ABU effective FTE sits below its headcount and ABOG above; the two sum to the combined anchor.
- **Entrants are split by pathway** using the national active-stock share (~50 ABOG, ~14 ABU per year) and applied identically to conus (the 3 non-conus providers are negligible). A pathway-specific ACGME completion split would refine this.
- **No demand saturation.** With constant entrants and modest exits the stock grows roughly linearly (headcount nearly doubles by 2040). NurseCast bounds this with a demand side; that is deliberately out of scope for a supply-only prototype. Do NOT read the 2040 level as a forecast.
- `lower_late_career_fte` reduces FTE immediately at 2023 (the cohort already has physicians aged 60+), which is the intended structural late-career-effort assumption.

## Recommended next steps (the real architecture)

1. ~~Add per-pathway (ABOG / ABU) and per-geography (national / conus) rows.~~ **Done.**
2. ~~Move the scenario dictionary + headcount-to-FTE function into `mufflyaccess`.~~ **Done** (mufflyaccess `urps_scenarios()` 0.9.0 + the projection contract `urps_projection_schema()` 0.10.0 + the Phase-3 FTE model). This builder now conforms to that contract.
3. Replace the builder's inlined scenario levers + FTE curve with a live `library(mufflyaccess)` call once mufflyaccess 0.10.0+ is installed in this repo's renv (currently 0.6.0), so there is a single runtime source rather than a mirrored copy.
4. Region- and division-level geography (joined via isochrones) is the next geographic slice.
5. Point the Shiny apps at the cube slice (they already read frozen CSVs for the scenario-comparison tab).
