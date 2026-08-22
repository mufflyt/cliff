# Mean wait in queue for a stationary M/M/s system

Expected time an arrival spends waiting \*before\* service (W_q,
excluding the service time itself) in an M/M/s queue with \`s\` servers,
per-server service rate \`mu\`, and utilisation \`rho\`. Uses \`W_q =
C(s, a) / (s mu (1 - rho))\` with \`a = rho s\`. Returned in the
reciprocal time unit of \`mu\` (if \`mu\` is patients per month, \`W_q\`
is in months).

## Usage

``` r
mmc_wait_in_queue(s, mu, rho)
```

## Arguments

- s:

  Number of parallel servers: a single positive integer.

- mu:

  Per-server service rate: a single positive finite scalar (completed
  visits per unit time per server).

- rho:

  Server utilisation \`lambda / (s mu)\`: a single scalar in \`(0, 1)\`.

## Value

A single non-negative mean wait, in \`1 / mu\` time units. Strictly
increasing in \`rho\`; \`-\> 0\` as \`rho -\> 0\` and \`-\> Inf\` as
\`rho -\> 1-\`.

## See also

\[wait_to_adequacy()\], the inverse of this map.

Other wait-adequacy:
[`erlang_b()`](https://mufflyt.github.io/cliff/reference/erlang_b.md),
[`erlang_c()`](https://mufflyt.github.io/cliff/reference/erlang_c.md),
[`wait_to_adequacy()`](https://mufflyt.github.io/cliff/reference/wait_to_adequacy.md)

## Examples

``` r
mmc_wait_in_queue(s = 4, mu = 2, rho = 0.8)
#> [1] 0.3727703
```
