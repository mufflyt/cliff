# Read the simulation drive-time access surface (tract level)

Thin base-R I/O wrapper. Returns \`NULL\` when \`path\` is empty or
missing, so Module D cleanly falls back to the straight-line (v1)
metric.

## Usage

``` r
read_access_surface(path)
```

## Arguments

- path:

  path to an \`access_surface_v\*.csv\` (may be \`""\` / absent).
  Expected columns: \`demand_id\` (11-digit tract GEOID), \`access\`,
  \`population\`, and optionally \`access_scaled\`, \`n_providers\`, and
  provenance columns (\`isochrone_run_id\`, \`sigma\`, \`wait_scale\`,
  \`calibration_status\`).

## Value

\`list(data = data.frame, provenance = named list)\` or \`NULL\`.
