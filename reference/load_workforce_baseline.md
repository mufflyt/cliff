# Load a qualified cliff workforce baseline from the mufflyaccess SSOT

The interface cliff's models call to obtain a baseline count; delegates
to \[urps_baseline()\] and attaches provenance that keeps the measure
year and the model start year distinct.

## Usage

``` r
load_workforce_baseline(
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

A list with \`n_providers\`, \`source_package\` (\`"mufflyaccess"\`),
\`measure\`, \`geography\`, \`measure_year\`, and \`model_start_year\`
(the projection start, DELIBERATELY separate from the measure year).

## See also

\[urps_baseline()\], \[project_urps_workforce()\].
