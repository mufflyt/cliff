# Share of the total held by the k largest units

Share of the total held by the k largest units

## Usage

``` r
top_k_share(counts, k = 5L)
```

## Arguments

- counts:

  Numeric vector of counts per unit.

- k:

  Number of top units to sum. Default 5.

## Value

Fraction in \[0, 1\], or `NA_real_` if the total is 0.
