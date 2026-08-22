# Guard against OOM from distm() on large point sets

Guard against OOM from distm() on large point sets

## Usage

``` r
.guard_distm_size(n_points, block_label = "global")
```

## Arguments

- n_points:

  Integer number of points.

- block_label:

  Character label for error messages.
