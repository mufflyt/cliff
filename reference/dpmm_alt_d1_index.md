# Align + rebase a DPMM demand-contract tier to a set of projection years

Pure transform. Given the tidy DPMM demand contract (as produced by the
simulation repo's \`export_demand_contract.R\`) and a vector of
projection years, return the demand index for \`tier\`, aligned to
\`years\` and rebased so that \`base_year == 100\`. Years absent from
the contract yield \`NA\`. If \`base_year\` is absent from the contract
(or its value is non-positive), the tier's own index is returned
unchanged (passthrough) rather than erroring — the caller decides
usability via \[dpmm_series_usable()\].

## Usage

``` r
dpmm_alt_d1_index(contract, years, base_year = 2025L, tier = DPMM_DEFAULT_TIER)
```

## Arguments

- contract:

  data.frame with columns \`denominator_tier\`, \`calendar_year\`,
  \`denominator_index\`.

- years:

  integer vector of projection years to align to.

- base_year:

  year to normalise the index to (= 100). Default 2025.

- tier:

  denominator tier to extract. Default \`"tier3_prevalent_pfd"\`.

## Value

numeric vector of \`length(years)\`.
