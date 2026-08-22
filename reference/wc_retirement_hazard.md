# Resolve the retirement hazard the projection will run on.

Resolve the retirement hazard the projection will run on.

## Usage

``` r
wc_retirement_hazard(
  source = WC_RETIREMENT_SOURCES,
  band_labels,
  band_of,
  legacy_band_ev = NULL,
  legacy_band_py = NULL,
  confirmation_window_months = 12L,
  ns = "mufflyaccess"
)
```

## Arguments

- source:

  One of \`WC_RETIREMENT_SOURCES\`. Default \`"legacy_modeled"\`.

- band_labels:

  The engine's age-band labels (\`eng\$WC_BAND_LABELS\`) – the order the
  returned \`band_ev\` / \`band_py\` / \`hz_point\` vectors follow.

- band_of:

  A function age -\> band label (\`eng\$wc_band_of\`), reused so the
  observed hazard is banded EXACTLY as the engine bands ages (no
  reimplementation).

- legacy_band_ev, legacy_band_py:

  The frozen band event / person-year counts, required for
  \`"legacy_modeled"\` (passed straight through, so the legacy path is
  byte-identical to the caller's own constants).

- confirmation_window_months:

  Recorded in provenance; should mirror the mufflyaccess manifest
  \`exit_confirmation_months\` (default 12).

- ns:

  The mufflyaccess namespace (overridable in tests with a stub env).

## Value

A list: \`retirement_source\`, \`band_labels\`, \`band_ev\`,
\`band_py\`, \`hz_point\` (named by \`band_labels\`; \`NA\` for a band
with no person-years, which the engine fills with the max hazard), and
\`provenance\` (a named list carrying \`retirement_source\`,
\`hazard_artifact\`, \`hazard_version\`, \`hazard_hash\`,
\`ascertainment_status\`, \`confirmation_window_months\`,
\`uncertainty_method\`).
