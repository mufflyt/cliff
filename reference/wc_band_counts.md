# Age-band person-year + event counts over a window (GO+URPS primary rows by default).

Age-band person-year + event counts over a window (GO+URPS primary rows
by default).

## Usage

``` r
wc_band_counts(coh, win = WC_WIN, rows = which(coh$ab %in% WC_PRIMARY))
```

## Arguments

- coh:

  \[data.frame\]: Cohort from \`wc_load_cohort()\`.

- win:

  \[integer(2)\]: Observation window, start and end year.

- rows:

  \[integer\]: Row indices of \`coh\` to count; defaults to the primary
  cohorts.
