# National URPS baseline for cliff (sourced from mufflyaccess).

National URPS baseline for cliff (sourced from mufflyaccess).

## Usage

``` r
urps_baseline(
  include_urology = FALSE,
  geography = "national",
  year = 2023L,
  measure = "board_certified_active"
)
```

## Arguments

- include_urology:

  FALSE = ABOG-only; TRUE = ABOG + ABU net-new.

- geography:

  "national" (default) or "conus".

- year:

  measure year (default 2023).

- measure:

  "board_certified_active" (default; the active-workforce baseline) or
  "roster_snapshot".

## Value

integer active count (e.g. 2023/national/with-urology = 1306).
