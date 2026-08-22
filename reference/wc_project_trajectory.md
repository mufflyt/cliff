# Per-year projection PATH – the same recurrence as wc_project(), but recording each projected year instead of only the endpoint. Returns a data.frame with one row per year: \`step\` (1..horizon), \`active\` (headcount after that year's exits + entrants), \`entrants\`, \`departures\` (exits that year). By construction the final \`active\` equals wc_project()\$active_2029 and \`sum(departures)\` equals wc_project()\$departures_4yr for the same inputs (asserted in test-wc-engine-equivalence.R); it just exposes the intermediate years the projection contract needs. \`age_shift\` behaves exactly as in wc_project().

Per-year projection PATH – the same recurrence as wc_project(), but
recording each projected year instead of only the endpoint. Returns a
data.frame with one row per year: \`step\` (1..horizon), \`active\`
(headcount after that year's exits + entrants), \`entrants\`,
\`departures\` (exits that year). By construction the final \`active\`
equals wc_project()\$active_2029 and \`sum(departures)\` equals
wc_project()\$departures_4yr for the same inputs (asserted in
test-wc-engine-equivalence.R); it just exposes the intermediate years
the projection contract needs. \`age_shift\` behaves exactly as in
wc_project().

## Usage

``` r
wc_project_trajectory(ages, entrants, hz, horizon = WC_HORIZON, age_shift = 0L)
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
