# Replacement Gap Analysis

Analyzes whether fellowship training programs are producing enough
graduates to replace retiring physicians. Compares projected retirees
against projected fellowship graduates over a 5-year horizon.

## Usage

``` r
calculate_replacement_gap(
  retirees_by_subspec,
  fellowship_grads,
  horizon_years = 5
)
```

## Arguments

- retirees_by_subspec:

  A tibble/data.frame with columns:

  subspecialty

  :   Character. Name of the subspecialty (e.g., "Maternal-Fetal
      Medicine")

  retiring_count

  :   Integer. Number of physicians projected to retire in 5-year window

- fellowship_grads:

  A tibble/data.frame with columns:

- horizon_years:

  \[integer\]: Projection horizon in years; graduates are accumulated
  over this window.

  subspecialty

  :   Character. Name of the subspecialty (must match
      retirees_by_subspec)

  graduates

  :   Integer. Number of fellowship graduates for that year

  year

  :   Integer. Year of graduation (typically 2022-2024 for recent data)

## Value

A list with two components:

- by_subspecialty:

  Tibble with columns: subspecialty, retiring_count, annual_grads,
  total_grads_3yr, projected_grads_5yr, replacement_ratio, net_gap,
  gap_percentage, adequate_replacement (logical)

- overall:

  List with: total_retiring, total_graduates_projected, net_gap,
  gap_percentage, replacement_ratio

## Details

A replacement ratio \< 1.0 indicates a gap where more physicians are
retiring than are being trained, suggesting potential workforce
shortages.

Calculations performed:

- annual_grads: Mean graduates per year from fellowship_grads data

- projected_grads_5yr: annual_grads \* 5 (matching 5-year retirement
  horizon)

- replacement_ratio: projected_grads_5yr / retiring_count

- net_gap: retiring_count - projected_grads_5yr (positive = shortage)

- gap_percentage: (net_gap / retiring_count) \* 100

- adequate_replacement: TRUE if replacement_ratio \>= 1.0

Subspecialties in retirees but not in fellowship_grads are assigned 0
graduates. This is common for subspecialties without formal fellowship
training.

The 5-year horizon aligns with the retirement cliff analysis window
(2024-2029).

## See also

[`calculate_rural_metro_comparison`](https://mufflyt.github.io/cliff/reference/calculate_rural_metro_comparison.md)
for geographic analysis

Other retirement cliff analysis functions:
[`calculate_rural_metro_comparison()`](https://mufflyt.github.io/cliff/reference/calculate_rural_metro_comparison.md),
[`calculate_state_vulnerability()`](https://mufflyt.github.io/cliff/reference/calculate_state_vulnerability.md)

## Examples

``` r
retirees <- tibble::tibble(
  subspecialty = c("Maternal-Fetal Medicine", "Gynecologic Oncology",
                   "Female Pelvic Medicine"),
  retiring_count = c(150, 80, 60)
)
grads <- tibble::tibble(
  subspecialty = rep(c("Maternal-Fetal Medicine", "Gynecologic Oncology",
                       "Female Pelvic Medicine"), each = 3),
  year = rep(2022:2024, 3),
  graduates = c(45, 48, 50, 22, 24, 25, 18, 20, 22)
)
results <- calculate_replacement_gap(retirees, grads)

# View subspecialty breakdown
print(results$by_subspecialty)
#> # A tibble: 3 × 9
#>   subspecialty           retiring_count annual_grads total_grads projected_grads
#>   <chr>                           <dbl>        <dbl>       <dbl>           <dbl>
#> 1 Female Pelvic Medicine             60         20            60            100 
#> 2 Gynecologic Oncology               80         23.7          71            118.
#> 3 Maternal-Fetal Medici…            150         47.7         143            238.
#> # ℹ 4 more variables: replacement_ratio <dbl>, net_gap <dbl>,
#> #   gap_percentage <dbl>, adequate_replacement <lgl>

# Check the overall balance. Per the Value section above, net_gap is
# retiring_count - projected_grads, so a POSITIVE value is a shortage and a
# negative one a surplus. It is a projection difference rather than a
# headcount and is fractional in general, hence %.1f rather than %d.
sprintf("Overall %s: %.1f physicians (%.1f%%)",
        ifelse(results$overall$net_gap > 0, "shortfall", "surplus"),
        abs(results$overall$net_gap), abs(results$overall$gap_percentage))
#> [1] "Overall surplus: 166.7 physicians (57.5%)"
```
