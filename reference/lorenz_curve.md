# Lorenz-curve coordinates for a count vector

Lorenz-curve coordinates for a count vector

## Usage

``` r
lorenz_curve(x)
```

## Arguments

- x:

  Numeric vector of counts per unit (include zeros for full geography).

## Value

A tibble with `cum_unit_share` and `cum_value_share`, prepended with the
origin (0, 0), units ordered fewest-to-most.
