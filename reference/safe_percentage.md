# Safe Percentage Calculation

Calculates percentage with protection against zero denominators. Used
throughout the pipeline for computing retirement risk rates, replacement
gaps, and coverage statistics.

## Usage

``` r
safe_percentage(part, whole, round_digits = 1)
```

## Arguments

- part:

  \`numeric\`: value representing the count of interest (e.g., at-risk
  physicians)

- whole:

  \`numeric\`: value representing the total count (e.g., all physicians)

- round_digits:

  Number of decimal places to round the result (default: 1)

## Value

Percentage (0-100 scale) rounded to specified digits, or NA if
calculation fails

## Examples

``` r
safe_percentage(25, 100)     # Returns 25.0
#> [1] 25
safe_percentage(1, 3, 2)     # Returns 33.33
#> [1] 33.33
safe_percentage(10, 0)       # Returns NA
#> [1] NA
```
