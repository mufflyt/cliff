# Apply a CHIA demand bridge to national Medicare FFS workload

Apply a CHIA demand bridge to national Medicare FFS workload

## Usage

``` r
apply_chia_demand_bridge(
  medicare_ffs,
  chia_bridge,
  age_col = "age",
  workload_col = "wrvu",
  population_col = "population",
  age_band_width = 5L
)
```

## Arguments

- medicare_ffs:

  National Medicare FFS utilization by age.

- chia_bridge:

  Output from calibrate_chia_demand_bridge().

- age_col:

  Age or lower bound of an age band.

- workload_col:

  Medicare FFS workload column.

- population_col:

  Medicare FFS population denominator.

- age_band_width:

  Width used in the CHIA calibration.

## Value

Age-specific calibrated national all-payer demand estimates.
