# TRUE for a roster row that is IN the active model baseline.

Vectorised, type-agnostic, and total: accepts the flag as \`logical\`,
\`numeric\`, \`character\`, or \`factor\`, and always returns
\`TRUE\`/\`FALSE\` — never \`NA\`.

## Usage

``` r
inmodel(x)
```

## Arguments

- x:

  \[vector\]: Values to test for membership in the in-model baseline.

## Details

Accepted as in-baseline : TRUE, 1, "TRUE", "true", "True", "1", and any
of those with surrounding whitespace (case- and space-insensitive).
Everything else : FALSE, including NA, "", "FALSE", 0.

This is the UNION of the four prior variants, so it is
behaviour-preserving on the committed rosters while being robust to a
character re-serialisation of the column. The one intentional
difference: a missing flag returns FALSE, where the bare \`== TRUE\`
form returned NA (which data.table happened to treat as FALSE in \`i\`,
but which propagates in a base-R subset).

Consumers:
`scripts/urps_module_[a_age_productivity,bc_corrected,bc_gate_audit]*.R`,
`scripts/urps_[demand_module_bc,plasticity_stage0_audit]*.R`,
scripts/urps_module_d_geographic_access_2026-07-23.R,
scripts/urps_concentration_equity_2026-08-01.R,
scripts/build_table1_urps_2026-07-23.R,
`scripts/enrich_rosters_[hpsa_point_in_polygon,medicare_procedures_2024_refresh]*.R`
