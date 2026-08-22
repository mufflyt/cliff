# Load the ABOG cohort, optionally applying the non-Open-Payments departure anchor. Returns npi, ab, cert_year, ry (anchored), ret, age, sex. Identical to the block previously duplicated in each script (plus a harmless \`sex\` column).

Load the ABOG cohort, optionally applying the non-Open-Payments
departure anchor. Returns npi, ab, cert_year, ry (anchored), ret, age,
sex. Identical to the block previously duplicated in each script (plus a
harmless \`sex\` column).

## Usage

``` r
wc_load_cohort(apply_anchor = TRUE, here_fn = here::here)
```

## Arguments

- apply_anchor:

  \[logical\]: Apply the non-Open-Payments departure anchor.

- here_fn:

  \[function\]: Path resolver, injectable so a caller outside the source
  tree can supply its own.
