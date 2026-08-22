# Invert an observed clinic wait time into an adequacy estimate (M/M/s)

Recover the supply/demand adequacy implied by an observed mean
wait-in-queue, under a steady-state M/M/s (Erlang-C) model of the
clinic. Solves \`mmc_wait_in_queue(s, mu, rho) == wait\` for the
utilisation \`rho\` and reports \`adequacy = 1 / rho\` on cliff's
standard "supply / demand, 1.0 == balance" convention.

## Usage

``` r
wait_to_adequacy(wait, mu, s = 1L, rho_ceiling = WAIT_ADEQUACY_RHO_CEILING)
```

## Arguments

- wait:

  Observed mean wait in queue: a single positive finite scalar, in the
  SAME time unit as \`1 / mu\` (e.g. if \`mu\` is visits per month,
  \`wait\` is in months). \`wait \<= 0\` means no queue and is reported
  as unbounded surplus.

- mu:

  Per-server service rate: a single positive finite scalar (completed
  new-patient visits per unit time per parallel service channel).

- s:

  Number of parallel service channels (clinic capacity units): a single
  positive integer. Defaults to \`1\` (an M/M/1 clinic).

- rho_ceiling:

  Utilisation above which the inverse is declared not identified.
  Defaults to the SSOT \[WAIT_ADEQUACY_RHO_CEILING\].

## Value

A one-row \`data.frame\` with columns: \`wait\`, \`mu\`, \`s\` (the
inputs); \`rho\` (implied utilisation, \`NA\` if unidentified);
\`adequacy\` (\`1 / rho\`, \`NA\` if unidentified); \`identified\`
(logical); and \`reason\` (\`NA\` when identified, else why it refused).

## Details

The estimator is deliberately partial and says so. Because mean wait
strictly increases in \`rho\` over \`(0, 1)\`, every finite positive
wait implies \`rho \< 1\` and hence \`adequacy \> 1\`: wait time alone
can never evidence a shortage (\`adequacy \<= 1\`), so this function
never returns one — it refuses. It also refuses in the near-balance
region \`rho \>= WAIT_ADEQUACY_RHO_CEILING\`, where the wait curve is
effectively vertical and a band of adequacies is observationally
indistinguishable. Refusal is reported as \`identified = FALSE\` with
\`adequacy = NA_real\_\` and a human-readable \`reason\`, not by
erroring.

## See also

\[mmc_wait_in_queue()\] (the forward map this inverts);
\`shiny_urps_adequacy/model.R\` for the relative adequacy index this
could anchor; \`tests/testthat/test-ssot-wait-adequacy.R\` for the
guard.

Other wait-adequacy:
[`erlang_b()`](https://mufflyt.github.io/cliff/reference/erlang_b.md),
[`erlang_c()`](https://mufflyt.github.io/cliff/reference/erlang_c.md),
[`mmc_wait_in_queue()`](https://mufflyt.github.io/cliff/reference/mmc_wait_in_queue.md)

## Examples

``` r
# A 4-channel clinic serving ~2 new patients/channel/month, observed 0.5-month wait:
wait_to_adequacy(wait = 0.5, mu = 2, s = 4)
#>   wait mu s       rho adequacy identified reason
#> 1  0.5  2 4 0.8348549 1.197813       TRUE   <NA>
# Very long wait -> near balance -> refused rather than pinned:
wait_to_adequacy(wait = 1e6, mu = 2, s = 4)$identified
#> [1] FALSE
```
