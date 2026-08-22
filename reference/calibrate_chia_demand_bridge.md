# Calibrate an all-payer demand bridge from CHIA claims

Estimates age-specific VOLUME ratios of all-payer utilization to
Medicare FFS utilization (\`all_workload / ffs_workload\`), so the
resulting \`bridge_multiplier\` carries the same meaning as
R/chia_medicare_bridge.R's \`1 / capture\` multiplier and
\[apply_chia_demand_bridge()\]'s \`ffs_workload \* multiplier\` recovers
an all-payer VOLUME. Workload may be measured using wRVUs, encounters,
or patients.

## Usage

``` r
calibrate_chia_demand_bridge(
  chia_claims,
  population,
  year_col = "year",
  age_col = "age",
  payer_col = "payer",
  ffs_values = c("Medicare FFS", "MEDICARE_FFS"),
  specialty_col = NULL,
  specialty_values = NULL,
  wrvu_col = "wrvu",
  encounter_col = NULL,
  patient_col = NULL,
  population_year_col = "year",
  population_age_col = "age",
  population_payer_col = "payer",
  population_n_col = "population",
  age_band_width = 5L,
  min_ffs_workload = 50,
  min_all_workload = 100,
  n_boot = 1000L,
  seed = 20260813L,
  save_dir = NULL
)
```

## Arguments

- chia_claims:

  Claims-level or summarized CHIA utilization.

- population:

  Population denominators by year, age band, and payer. Used for the
  informational \`\*\_rate_per_1000\` diagnostics only; the volume-ratio
  bridge multiplier does not depend on it.

- year_col:

  Column containing calendar year.

- age_col:

  Column containing patient age.

- payer_col:

  Column containing payer.

- ffs_values:

  Values identifying Medicare FFS.

- specialty_col:

  Optional specialty column.

- specialty_values:

  Optional specialty values to retain.

- wrvu_col:

  Optional work-RVU column.

- encounter_col:

  Optional encounter count column.

- patient_col:

  Optional patient identifier column.

- population_year_col:

  Population year column.

- population_age_col:

  Population age column.

- population_payer_col:

  Population payer column.

- population_n_col:

  Population denominator column.

- age_band_width:

  Width of age bands.

- min_ffs_workload:

  Minimum FFS workload for calibration.

- min_all_workload:

  Minimum all-payer workload for calibration.

- n_boot:

  Number of bootstrap replicates.

- seed:

  Random seed.

- save_dir:

  Optional directory for saved calibration artifacts.

## Value

A named list containing bridge estimates, diagnostics, and status.
