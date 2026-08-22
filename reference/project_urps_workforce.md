# Project the URPS workforce forward from a qualified SSOT baseline

Minimal net-flow projection seeded from the mufflyaccess baseline: the
value at \`baseline_year\` equals the SSOT count for the requested cell,
and each subsequent year adds the net of \`entrants\` minus
\`retirements\`.

## Usage

``` r
project_urps_workforce(
  baseline_year = 2023L,
  include_urology = FALSE,
  geography = "national",
  measure = "board_certified_active",
  projection_years = NULL,
  entrants = 0,
  retirements = 0
)
```

## Arguments

- baseline_year:

  Measure year of the baseline cell (default 2023).

- include_urology:

  FALSE = ABOG-only; TRUE = ABOG + ABU net-new.

- geography:

  "national" (default) or "conus".

- measure:

  "board_certified_active" (default; the active-workforce baseline) or
  "roster_snapshot".

- projection_years:

  Integer vector of years; defaults to \`baseline_year\` through
  \`baseline_year + 12\`.

- entrants, retirements:

  Annual counts entering/leaving the workforce.

## Value

A data frame with \`year\` and \`n_providers\`.

## See also

\[load_workforce_baseline()\], \[urps_baseline()\].
