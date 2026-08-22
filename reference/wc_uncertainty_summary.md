# Summarize a workforce-projection Monte Carlo as median + interval + decision probabilities.

Summarize a workforce-projection Monte Carlo as median + interval +
decision probabilities.

## Usage

``` r
wc_uncertainty_summary(
  final_draws,
  ratio_draws = NULL,
  baseline,
  shortage_pct = 0,
  improve_pct = 0,
  interval = 0.95
)
```

## Arguments

- final_draws:

  Numeric vector: projected end-of-horizon workforce, one per MC draw.
  Non-finite values are dropped.

- ratio_draws:

  Numeric vector aligned to \`final_draws\`: replacement ratio (entrants
  / departures) per draw. Pass \`NULL\` to skip below-replacement
  probability. Non-finite values are dropped pairwise for the ratio
  metric.

- baseline:

  Positive scalar: the baseline (start-of-horizon) workforce the
  shortage/improvement thresholds are measured against.

- shortage_pct:

  Non-negative scalar: "shortage exceeds X workforce falls to at most
  \`baseline \* (1 - shortage_pct/100)\`. Default 0 =\> any net decline.

- improve_pct:

  Non-negative scalar: "access improves" means the workforce reaches at
  least \`baseline \* (1 + improve_pct/100)\`. Default 0 =\> any growth.

- interval:

  Two-sided prediction-interval width in (0,1). Default 0.95.

## Value

A one-row data.frame with baseline, median, mean, sd, pi_lower,
pi_upper, pi_level, p_shortage_exceeds, shortage_pct, p_access_improves,
improve_pct, p_below_replacement (NA if no ratio), and n_draws.
