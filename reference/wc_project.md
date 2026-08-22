# Deterministic age-structured projection. Returns list(active_2029, departures_4yr). \`age_shift\` shifts the retirement-hazard curve along age: at age \`a\` a provider faces the hazard of age \`a - age_shift\`, so a NEGATIVE age_shift retires people earlier (they face an older age's hazard). Default \`0L\` is byte-identical to the original engine. This is the lever mufflyaccess's scenario dictionary calls \`retirement_shift_years\` (pass it straight through).

Deterministic age-structured projection. Returns list(active_2029,
departures_4yr). \`age_shift\` shifts the retirement-hazard curve along
age: at age \`a\` a provider faces the hazard of age \`a - age_shift\`,
so a NEGATIVE age_shift retires people earlier (they face an older age's
hazard). Default \`0L\` is byte-identical to the original engine. This
is the lever mufflyaccess's scenario dictionary calls
\`retirement_shift_years\` (pass it straight through).

## Usage

``` r
wc_project(ages, entrants, hz, horizon = WC_HORIZON, age_shift = 0L)
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
