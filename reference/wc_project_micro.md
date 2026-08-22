# Per-provider (individual-level) stochastic MICROSIMULATION of the same projection.

\`wc_project()\` above is an expected-value recurrence: it collapses the
individual ages to a count vector and removes the fraction \`count \*
hazard\` each year. This function instead carries EACH provider as an
individual and, every year, draws a Bernoulli departure per provider
from their age-band hazard, ages the survivors, and adds a stochastic
cohort of entrants (Poisson mean = \`entrants\`). Repeated \`n_sims\`
times it yields the full sampling distribution of the 2029 workforce,
with individual (aleatory) uncertainty the aggregate model cannot
express.

## Usage

``` r
wc_project_micro(
  ages,
  entrants,
  hz,
  horizon = WC_HORIZON,
  n_sims = 2000L,
  seed = 1L,
  stochastic_entry = TRUE
)
```

## Arguments

- ages:

  Integer vector of individual provider ages (one element per provider),
  e.g. an element of \`wc_active_ages()\`.

- entrants:

  Mean annual entrants (fellowship completers).

- hz:

  Named age-band hazard vector (as consumed by \[wc_haz_for()\]).

- horizon:

  Projection years (default \[WC_HORIZON\]).

- n_sims:

  Number of individual-level realizations (default 2000).

- seed:

  RNG seed for reproducibility.

- stochastic_entry:

  If TRUE (default) entrants ~ Poisson(entrants) each year; if FALSE,
  exactly \`round(entrants)\` enter each year.

## Value

list: \`active_2029\` (mean), \`active_sd\`, \`active_ci\` (2.5/97.5
pct), \`departures_4yr\` (mean), and the raw \`active_draws\` /
\`departures_draws\`.

## Details

Reduction guarantee (the "is it real, and is it right" check): because
\`E\[Bernoulli(h)\] = h\` and \`E\[Poisson(entrants)\] = entrants\`, the
MEAN of this microsimulation converges to \`wc_project()\`'s
deterministic \`active_2029\`. The regression test
\`test-wc-project-micro.R\` asserts they agree within Monte Carlo error,
so the per-provider engine is a true refinement of (not a departure
from) the validated aggregate model. Pass \`stochastic_entry = FALSE\`
for deterministic entry (round(entrants)/yr) when isolating departure
variance.
