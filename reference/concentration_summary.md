# One-row concentration summary for a geography level

One-row concentration summary for a geography level

## Usage

``` r
concentration_summary(
  counts,
  n_units_total = length(counts),
  label = NA_character_,
  weight = NULL
)
```

## Arguments

- counts:

  Named or unnamed numeric vector of provider counts for the OCCUPIED
  units at this geography level.

- n_units_total:

  Size of the full unit universe at this level (e.g. 3143 US counties,
  51 states incl. DC). Zero-provider units are padded in so Gini and the
  zero-share reflect the whole geography. Defaults to `length(counts)`
  (occupied-only).

- label:

  Character geography label for the output row.

- weight:

  Optional numeric vector, same length/order as `counts`, giving a
  per-unit population denominator. When supplied, a population-weighted
  maldistribution Gini is added (providers ordered by
  provider-per-population). Occupied units only.

## Value

A one-row tibble.
