# Erlang-B blocking probability (numerically stable recursion)

The Erlang-B loss formula B(s, a) for an M/M/s/s system: the probability
that all \`s\` channels are busy given offered load \`a\` (Erlangs).
Computed by the standard iterative recurrence \`B(0) = 1\`, \`B(k) = a
B(k-1) / (k + a B(k-1))\`, which avoids the overflow of forming \`a^s /
s!\` directly. Used here only as the building block for \[erlang_c()\].

## Usage

``` r
erlang_b(s, a)
```

## Arguments

- s:

  Number of parallel service channels: a single positive integer (or
  integer-valued double).

- a:

  Offered load in Erlangs (\`lambda / mu\`): a single non-negative
  finite scalar. Need not be \`\< s\` (Erlang-B is defined for all
  loads).

## Value

A single probability in \`\[0, 1\]\`.

## See also

\[erlang_c()\], which converts this to the delay probability.

Other wait-adequacy:
[`erlang_c()`](https://mufflyt.github.io/cliff/reference/erlang_c.md),
[`mmc_wait_in_queue()`](https://mufflyt.github.io/cliff/reference/mmc_wait_in_queue.md),
[`wait_to_adequacy()`](https://mufflyt.github.io/cliff/reference/wait_to_adequacy.md)

## Examples

``` r
erlang_b(3, 2)      # offered load 2 Erlangs across 3 channels
#> [1] 0.2105263
```
