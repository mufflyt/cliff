# Per-tier calibration status of a demand contract (with fallback)

Returns the provenance of a single \`tier\`, preferring the per-tier
\`tier_calibration_status\` (via \[read_dpmm_demand_contract()\]'s
\`tier_status\`) and falling back to the object-level \`status\` when
the contract predates the per-tier column. Pure; no I/O.

## Usage

``` r
dpmm_tier_status(ct, tier = DPMM_DEFAULT_TIER)
```

## Arguments

- ct:

  list from \[read_dpmm_demand_contract()\] (or \`NULL\`).

- tier:

  denominator tier to look up. Default \`"tier3_prevalent_pfd"\`.

## Value

character scalar (the tier's status), or \`NA_character\_\`.
