# Per-year AGE COMPOSITION – the same recurrence as wc_project() / \_trajectory(), but recording the full (age, n) distribution after each projected year rather than only the aggregate. Returns a long data.frame(step, age, n). The per-step \`sum(n)\` equals wc_project_trajectory()\$active exactly (asserted in test-wc-engine-additions.R); it exposes the age structure an age-weighted clinical-FTE calculation needs. \`age_shift\` behaves exactly as in wc_project().

Per-year AGE COMPOSITION – the same recurrence as wc_project() /
\_trajectory(), but recording the full (age, n) distribution after each
projected year rather than only the aggregate. Returns a long
data.frame(step, age, n). The per-step \`sum(n)\` equals
wc_project_trajectory()\$active exactly (asserted in
test-wc-engine-additions.R); it exposes the age structure an
age-weighted clinical-FTE calculation needs. \`age_shift\` behaves
exactly as in wc_project().

## Usage

``` r
wc_project_ages(ages, entrants, hz, horizon = WC_HORIZON, age_shift = 0L)
```

## Arguments

- ages:

  \[numeric\]: Active-age distribution at the projection start.

- entrants:

  \[numeric\]: Annual entrants added at the entry age.

- hz:

  \[numeric\]: Named age-band hazard vector.

- horizon:

  \[integer\]: Projection horizon in years.

- age_shift:

  \[integer\]: Shift of the retirement-hazard curve along age; negative
  retires earlier.
