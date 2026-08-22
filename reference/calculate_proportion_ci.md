# Calculate Confidence Interval for a Proportion

Computes a confidence interval for a binomial proportion using the
Wilson score interval method, which has better coverage properties for
small samples and extreme proportions compared to the standard normal
approximation.

## Usage

``` r
calculate_proportion_ci(x, n, conf_level = 0.95)
```

## Arguments

- x:

  \`integer\`: Number of successes (e.g., at-risk physicians)

- n:

  \`integer\`: Total number of trials (e.g., all physicians in area)

- conf_level:

  \`numeric\`: Confidence level between 0 and 1 (default: 0.95 for 95%
  CI)

## Value

A list containing:

- proportion:

  Numeric. Point estimate of the proportion (x/n)

- lower_ci:

  Numeric. Lower bound of confidence interval (0-1 scale)

- upper_ci:

  Numeric. Upper bound of confidence interval (0-1 scale)

- method:

  Character. "Wilson" or "Normal approximation" if fallback used

- note:

  Character. Description including confidence level

## Details

The Wilson score interval is preferred over the Wald (normal
approximation) interval because:

- It never produces impossible intervals (outside 0-1)

- It has better coverage for small n

- It handles edge cases (p near 0 or 1) gracefully

The formula uses the quadratic correction: center = (p + z^2/(2n)) /
(1 + z^2/n) margin = z \* sqrt(p(1-p)/n + z^2/(4n^2)) / (1 + z^2/n)

## References

Wilson, E. B. (1927). Probable inference, the law of succession, and
statistical inference. Journal of the American Statistical Association,
22, 209-212.

Agresti, A. & Coull, B. A. (1998). Approximate is better than "exact"
for interval estimation of binomial proportions. The American
Statistician, 52, 119-126.

## See also

Other statistical testing functions:
[`calculate_two_prop_test()`](https://mufflyt.github.io/cliff/reference/calculate_two_prop_test.md)

## Examples

``` r
# 30 at-risk out of 100 physicians
ci <- calculate_proportion_ci(30, 100)
sprintf("%.1f%% (%.1f%% - %.1f%%)",
        ci$proportion * 100, ci$lower_ci * 100, ci$upper_ci * 100)
#> [1] "30.0% (21.9% - 39.6%)"

# Small sample with extreme proportion
ci <- calculate_proportion_ci(1, 10)
ci$method  # "Wilson"
#> [1] "Wilson"
```
