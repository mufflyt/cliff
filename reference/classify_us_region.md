# Canonical US Census Region Classification

Classifies a state abbreviation or full state name into Census regions.
Covers all 50 states + DC + PR. Returns "Unknown" for unrecognized
values.

## Usage

``` r
classify_us_region(state_abbr)
```

## Arguments

- state_abbr:

  Character vector of state abbreviations or names

## Value

Character vector of region names
