# Normalize physician name for ABOG table joining

Strips M.D., D.O., Jr., Sr., III, II, IV suffixes and lowercases. Used
to join \`credentials.abog_providers\` (has "Tyler M. Muffly, M.D.")
with \`credentials.abog_npi_matches\` (has "Tyler M. Muffly").

## Usage

``` r
normalize_abog_name(x)
```

## Arguments

- x:

  Character vector of physician names

## Value

Character vector of normalized names
