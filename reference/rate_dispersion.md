# Distribution of a per-provider access rate

Summarizes the spread of, e.g., urogynecologists-per-100k-women-65+
carried by each provider's own county. A wide 90:10 ratio is a
maldistribution signal even when the national count looks adequate.

## Usage

``` r
rate_dispersion(rate)
```

## Arguments

- rate:

  Numeric per-provider rate; NA/NaN dropped.

## Value

One-row tibble: n, median, p10, p25, p75, p90, ratio_90_10.
