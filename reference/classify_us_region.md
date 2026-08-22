# Canonical US Census Region Classification

Classifies a 2-character state abbreviation into Census regions. Covers
all 50 states + DC + PR. Returns "Unknown" for unrecognized values.

## Usage

``` r
classify_us_region(state_abbr)
```

## Arguments

- state_abbr:

  Character vector of 2-character state abbreviations

## Value

Character vector of region names
