# Normalize a Street Address for Comparison

Strips suite/apt/floor, uppercases, normalizes common abbreviations.
Extracts street number and key street tokens for matching.

## Usage

``` r
normalize_street_address(addr)
```

## Arguments

- addr:

  Character scalar street address

## Value

Named list with: normalized (full string), street_number, street_tokens
