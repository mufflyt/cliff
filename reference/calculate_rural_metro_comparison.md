# Rural vs Metro Retirement Risk Comparison

Compares retirement-at-risk rates between rural and metropolitan areas.
This is a key analysis for understanding geographic disparities in the
impending physician retirement cliff.

## Usage

``` r
calculate_rural_metro_comparison(
  rural_at_risk,
  rural_total,
  metro_at_risk,
  metro_total
)
```

## Arguments

- rural_at_risk:

  \`integer\`: Number of physicians aged 65+ in rural areas

- rural_total:

  \`integer\`: Total number of physicians in rural areas

- metro_at_risk:

  \`integer\`: Number of physicians aged 65+ in metro areas

- metro_total:

  \`integer\`: Total number of physicians in metro areas

## Value

A nested list with three components:

- rural:

  List with: at_risk, total, rate_pct, ci_lower (%), ci_upper (%)

- metro:

  List with: at_risk, total, rate_pct, ci_lower (%), ci_upper (%)

- comparison:

  List with: rate_difference_pct, p_value, p_value_formatted,
  significant (logical), test_method, note

## Details

The function computes:

- Point estimates for retirement-at-risk rates in each area type

- 95% confidence intervals using Wilson score method

- Statistical significance test (two-proportion z-test)

- Rate difference (rural - metro)

A positive rate_difference_pct indicates rural areas have higher
retirement risk rates than metro areas. A significant p-value (\< 0.05)
indicates the difference is statistically significant and unlikely due
to chance.

Rural/metro classification typically follows:

- RUCA (Rural-Urban Commuting Area) codes

- NCHS Urban-Rural Classification Scheme

The confidence intervals are computed using the Wilson score method and
converted to percentage scale (0-100) for easier interpretation.

## See also

[`calculate_replacement_gap`](https://mufflyt.github.io/cliff/reference/calculate_replacement_gap.md)
for replacement analysis

[`calculate_state_vulnerability`](https://mufflyt.github.io/cliff/reference/calculate_state_vulnerability.md)
for state rankings

Other retirement cliff analysis functions:
[`calculate_replacement_gap()`](https://mufflyt.github.io/cliff/reference/calculate_replacement_gap.md),
[`calculate_state_vulnerability()`](https://mufflyt.github.io/cliff/reference/calculate_state_vulnerability.md)

## Examples

``` r
# Rural: 45 of 150 at-risk (30%)
# Metro: 200 of 1000 at-risk (20%)
results <- calculate_rural_metro_comparison(45, 150, 200, 1000)
#> [STAT] Calculating rural vs metro comparison...
#> [STAT] Rural: 30.0% (45/150), Metro: 20.0% (200/1000), p=0.007

# Access results
sprintf("Rural: %.1f%%, Metro: %.1f%%, Difference: %.1f pp, p=%s",
        results$rural$rate_pct,
        results$metro$rate_pct,
        results$comparison$rate_difference_pct,
        results$comparison$p_value_formatted)
#> [1] "Rural: 30.0%, Metro: 20.0%, Difference: 10.0 pp, p=0.007"

# Check statistical significance
if (results$comparison$significant) {
  cat("The difference is statistically significant (p < 0.05)")
}
#> The difference is statistically significant (p < 0.05)
```
