# Two-Proportion Test with Small Sample Protection

Performs a two-proportion z-test comparing success rates between two
groups (e.g., rural vs metro retirement risk). Includes safeguards for
small samples where inferential statistics would be unreliable.

## Usage

``` r
calculate_two_prop_test(x1, n1, x2, n2, min_sample_size = 30)
```

## Arguments

- x1:

  \`integer\`: Number of successes (e.g., at-risk physicians) in group 1

- n1:

  \`integer\`: Total count in group 1

- x2:

  \`integer\`: Number of successes in group 2

- n2:

  \`integer\`: Total count in group 2

- min_sample_size:

  Minimum sample size required for statistical testing (default: 30)

## Value

A list containing:

- method:

  Character. Either "prop.test", "descriptive_only",
  "insufficient_data", or "test_failed"

- p_value:

  Numeric. P-value from the test, or NA if test not performed

- p_value_formatted:

  Character. Formatted p-value for display (e.g., "\<0.001", "n\<30")

- significant:

  Logical. TRUE if p \< 0.05, FALSE otherwise

- test_statistic:

  Numeric. Chi-squared test statistic (only when test performed)

- note:

  Character. Description of the test or reason for not testing

## Details

The function enforces a minimum sample size of 30 per group based on the
Central Limit Theorem requirements for proportion tests. When samples
are too small, it returns descriptive statistics only.

The two-proportion z-test (implemented via prop.test) tests the null
hypothesis that the two population proportions are equal. A significant
result (p \< 0.05) indicates that the difference between rural and metro
retirement rates is unlikely to have occurred by chance.

P-value formatting:

- Values \< 0.001 displayed as "\<0.001"

- Values \< 0.01 displayed with 3 decimal places

- Other values displayed with 2 decimal places

## See also

[`calculate_rural_metro_comparison`](https://mufflyt.github.io/cliff/reference/calculate_rural_metro_comparison.md)
for the main comparison function

Other statistical testing functions:
[`calculate_proportion_ci()`](https://mufflyt.github.io/cliff/reference/calculate_proportion_ci.md)

## Examples

``` r
# Compare rural (30% of 100) vs metro (20% of 500) retirement rates
result <- calculate_two_prop_test(30, 100, 100, 500)
result$p_value_formatted  # e.g., "0.04"
#> [1] "0.04"
result$significant        # TRUE if p < 0.05
#> [1] TRUE

# Small sample returns descriptive only
result <- calculate_two_prop_test(5, 20, 10, 25)
#> [STAT] Small sample warning: n1=20, n2=25 (min=30)
result$method  # "descriptive_only"
#> [1] "descriptive_only"
```
