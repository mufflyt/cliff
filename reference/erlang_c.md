# Erlang-C delay probability (probability an arrival must wait)

The Erlang-C formula C(s, a): in a stationary M/M/s queue with \`s\`
servers and offered load \`a = lambda / mu\` Erlangs, the probability
that an arriving customer finds all servers busy and joins the queue.
Derived from Erlang-B via \`C = s B / (s - a (1 - B))\`. Requires a
stable queue, \`a \< s\` (equivalently utilisation \`rho = a / s \<
1\`); an unstable load fails loudly.

## Usage

``` r
erlang_c(s, a)
```

## Arguments

- s:

  Number of parallel servers: a single positive integer.

- a:

  Offered load in Erlangs (\`lambda / mu\`): a single non-negative
  scalar, strictly less than \`s\` (stability).

## Value

A single probability in \`\[0, 1\]\`.

## See also

\[erlang_b()\]; \[mmc_wait_in_queue()\] for the mean wait this feeds.

Other wait-adequacy:
[`erlang_b()`](https://mufflyt.github.io/cliff/reference/erlang_b.md),
[`mmc_wait_in_queue()`](https://mufflyt.github.io/cliff/reference/mmc_wait_in_queue.md),
[`wait_to_adequacy()`](https://mufflyt.github.io/cliff/reference/wait_to_adequacy.md)

## Examples

``` r
erlang_c(3, 2)      # P(wait) with 3 servers, 2 Erlangs offered
#> [1] 0.4444444
```
