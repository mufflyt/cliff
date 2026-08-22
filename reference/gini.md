# Gini coefficient of a non-negative count/weight vector

Uses the standard covariance/rank formula. A vector of length `n` with
all mass in a single unit tends to `(n-1)/n`; an even split gives 0.
Include zero-valued units (e.g. counties with no provider) to measure
concentration across the FULL geography rather than only occupied units.

## Usage

``` r
gini(x)
```

## Arguments

- x:

  Numeric vector of non-negative counts or weights.

## Value

Gini coefficient in \[0, 1), or `NA_real_` if the total is 0.

## Examples

``` r
gini(c(25, 25, 25, 25))   # 0 (perfectly even)
#> [1] 0
gini(c(100, 0, 0, 0))     # 0.75
#> [1] 0.75
```
