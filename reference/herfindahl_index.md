# Herfindahl-Hirschman Index of market/provider share

Herfindahl-Hirschman Index of market/provider share

## Usage

``` r
herfindahl_index(counts, normalized = FALSE)
```

## Arguments

- counts:

  Numeric vector of counts per unit. Zero/negative entries are dropped
  (they contribute no share).

- normalized:

  If `TRUE`, return the size-corrected HHI\* \\(H - 1/n)/(1 - 1/n)\\ so
  values are comparable across differing numbers of occupied units.
  Default `FALSE` (raw HHI in \[0, 1\]).

## Value

HHI in \[0, 1\]; 1 = monopoly, \\1/n\\ = even split. `NA_real_` if the
total is 0.

## Examples

``` r
herfindahl_index(c(50, 30, 20))              # 0.38
#> [1] 0.38
herfindahl_index(c(50, 30, 20), TRUE)        # normalized
#> [1] 0.07
```
