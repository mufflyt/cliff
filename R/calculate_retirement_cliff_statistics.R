#' @title Safe Statistical Computations for Retirement Cliff Analysis
#'
#' @description
#' Provides robust statistical functions for analyzing physician retirement
#' patterns and workforce replacement gaps, including safeguards for small
#' samples and zero denominators.
#'
#' @family reporting-stats
#' @name calculate_retirement_cliff_stats
NULL

#!/usr/bin/env Rscript
# R/calculate_retirement_cliff_statistics.R
# ============================================================================
# Safe Statistical Computations for Retirement Cliff Analysis
# ============================================================================
#
# PURPOSE:
#   Provides robust statistical functions for analyzing physician retirement
#   patterns and workforce replacement gaps. These functions include safety
#   guards for small samples, zero denominators, and missing data.
#
# CONTEXT:
#   The "retirement cliff" refers to the projected wave of physician retirements
#   as a substantial portion of the workforce approaches retirement age (65+).
#   This module supports the SGS Abstract Pipeline by computing:
#     - Retirement risk rates by geography (rural vs metro)
#     - Replacement gap analysis (retirees vs fellowship graduates)
#     - State-level vulnerability rankings
#     - Confidence intervals for proportions
#
# KEY DEFINITIONS:
#   - At-risk: Physicians aged 65+ who may retire within 5 years
#   - Reference year: 2024 (current year for age calculations)
#   - Horizon year: 2029 (5-year projection window)
#   - Replacement ratio: Projected graduates / Projected retirees
#
# STATISTICAL METHODS:
#   - Two-proportion z-test for rural/metro comparisons
#   - Wilson score interval for proportion confidence intervals
#   - Minimum sample size of 30 for inferential statistics
#
# DEPENDENCIES:
#   - dplyr: Data manipulation
#   - stats: Statistical functions (prop.test, qnorm)
#   - tidyr: replace_na (used in replacement gap)
#
# USAGE:
#   source("R/calculate_retirement_cliff_statistics.R")
#   results <- calculate_rural_metro_comparison(rural_risk, rural_n, metro_risk, metro_n)
#
# AUTHOR: Isochrones Pipeline
# ============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# [CONSOLIDATION FIX] 2026-05-27: safe_divide() was previously defined here but
# clobbered the canonical implementation in R/safe_divide.R.
# The version in R/safe_divide.R now supports the 'na_value' parameter
# for backward compatibility with this module.


#' Safe Percentage Calculation
#'
#' Calculates percentage with protection against zero denominators.
#' Used throughout the pipeline for computing retirement risk rates,
#' replacement gaps, and coverage statistics.
#'
#' @param part `numeric`: value representing the count of interest (e.g.,
#'   at-risk physicians)
#' @param whole `numeric`: value representing the total count (e.g., all
#'   physicians)
#' @param round_digits Number of decimal places to round the result (default: 1)
#'
#' @return Percentage (0-100 scale) rounded to specified digits, or NA if
#'   calculation fails
#'
#' @examples
#' safe_percentage(25, 100)     # Returns 25.0
#' safe_percentage(1, 3, 2)     # Returns 33.33
#' safe_percentage(10, 0)       # Returns NA
#'
#' @family utility functions
#' @export
safe_percentage <- function(part, whole, round_digits = 1) {
  if (is.null(part) || is.null(whole)) return(NA_real_)
  if (!is.numeric(part)) part <- suppressWarnings(as.numeric(part))
  if (!is.numeric(whole)) whole <- suppressWarnings(as.numeric(whole))
  pct <- safe_divide(part, whole, NA_real_) * 100
  ifelse(is.na(pct), NA_real_, round(pct, round_digits))
}

# ============================================================================
# STATISTICAL TESTING FUNCTIONS
# ============================================================================

#' Two-Proportion Test with Small Sample Protection
#'
#' Performs a two-proportion z-test comparing success rates between two groups
#' (e.g., rural vs metro retirement risk). Includes safeguards for small samples
#' where inferential statistics would be unreliable.
#'
#' The function enforces a minimum sample size of 30 per group based on the
#' Central Limit Theorem requirements for proportion tests. When samples are
#' too small, it returns descriptive statistics only.
#'
#' @param x1 `integer`: Number of successes (e.g., at-risk physicians) in group
#'   1
#' @param n1 `integer`: Total count in group 1
#' @param x2 `integer`: Number of successes in group 2
#' @param n2 `integer`: Total count in group 2
#' @param min_sample_size Minimum sample size required for statistical testing
#'   (default: 30)
#'
#' @return A list containing:
#'   \describe{
#'     \item{method}{Character. Either "prop.test", "descriptive_only",
#' "insufficient_data", or "test_failed"}
#'     \item{p_value}{Numeric. P-value from the test, or NA if test not
#' performed}
#'     \item{p_value_formatted}{Character. Formatted p-value for display (e.g.,
#' "<0.001", "n<30")}
#'     \item{significant}{Logical. TRUE if p < 0.05, FALSE otherwise}
#'     \item{test_statistic}{Numeric. Chi-squared test statistic (only when test
#' performed)}
#'     \item{note}{Character. Description of the test or reason for not testing}
#'   }
#'
#' @details
#' The two-proportion z-test (implemented via prop.test) tests the null
#' hypothesis
#' that the two population proportions are equal. A significant result (p <
#' 0.05)
#' indicates that the difference between rural and metro retirement rates is
#' unlikely to have occurred by chance.
#'
#' P-value formatting:
#' \itemize{
#'   \item Values < 0.001 displayed as "<0.001"
#'   \item Values < 0.01 displayed with 3 decimal places
#'   \item Other values displayed with 2 decimal places
#' }
#'
#' @examples
#' # Compare rural (30% of 100) vs metro (20% of 500) retirement rates
#' result <- calculate_two_prop_test(30, 100, 100, 500)
#' result$p_value_formatted  # e.g., "0.04"
#' result$significant        # TRUE if p < 0.05
#'
#' # Small sample returns descriptive only
#' result <- calculate_two_prop_test(5, 20, 10, 25)
#' result$method  # "descriptive_only"
#'
#' @family statistical testing functions
#' @seealso \code{\link{calculate_rural_metro_comparison}} for the main comparison function
#' @export
calculate_two_prop_test <- function(x1, n1, x2, n2, min_sample_size = 30) {
  # Check for small samples
  if (n1 < min_sample_size || n2 < min_sample_size) {
    base::message(sprintf("[STAT] Small sample warning: n1=%d, n2=%d (min=%d)",
                         n1, n2, min_sample_size))

    return(list(
      method = "descriptive_only",
      p_value = NA_real_,
      p_value_formatted = "n<30",
      significant = FALSE,
      note = sprintf("Sample sizes too small for statistical test (n1=%d, n2=%d)", n1, n2)
    ))
  }

  # Check for zero denominators
  if (n1 == 0 || n2 == 0) {
    return(list(
      method = "insufficient_data",
      p_value = NA_real_,
      p_value_formatted = "insufficient data",
      significant = FALSE,
      note = "One or both groups have zero total"
    ))
  }

  # Perform test
  tryCatch({
    test_result <- stats::prop.test(c(x1, x2), c(n1, n2))

    p_val <- test_result$p.value
    significant <- p_val < 0.05

    # Format p-value
    p_val_fmt <- if (p_val < 0.001) {
      "<0.001"
    } else if (p_val < 0.01) {
      sprintf("%.3f", p_val)
    } else {
      sprintf("%.2f", p_val)
    }

    return(list(
      method = "prop.test",
      p_value = p_val,
      p_value_formatted = p_val_fmt,
      significant = significant,
      test_statistic = test_result$statistic,
      note = "Two-proportion z-test"
    ))

  }, error = function(e) {
    base::message(sprintf("[STAT] Two-proportion test failed: %s", conditionMessage(e)))

    return(list(
      method = "test_failed",
      p_value = NA_real_,
      p_value_formatted = "test failed",
      significant = FALSE,
      note = paste("Test error:", conditionMessage(e))
    ))
  })
}

#' Calculate Confidence Interval for a Proportion
#'
#' Computes a confidence interval for a binomial proportion using the Wilson
#' score interval method, which has better coverage properties for small samples
#' and extreme proportions compared to the standard normal approximation.
#'
#' @param x `integer`: Number of successes (e.g., at-risk physicians)
#' @param n `integer`: Total number of trials (e.g., all physicians in area)
#' @param conf_level `numeric`: Confidence level between 0 and 1 (default: 0.95
#'   for 95% CI)
#'
#' @return A list containing:
#'   \describe{
#'     \item{proportion}{Numeric. Point estimate of the proportion (x/n)}
#'     \item{lower_ci}{Numeric. Lower bound of confidence interval (0-1 scale)}
#'     \item{upper_ci}{Numeric. Upper bound of confidence interval (0-1 scale)}
#'     \item{method}{Character. "Wilson" or "Normal approximation" if fallback
#' used}
#'     \item{note}{Character. Description including confidence level}
#'   }
#'
#' @details
#' The Wilson score interval is preferred over the Wald (normal approximation)
#' interval because:
#' \itemize{
#'   \item It never produces impossible intervals (outside 0-1)
#'   \item It has better coverage for small n
#'   \item It handles edge cases (p near 0 or 1) gracefully
#' }
#'
#' The formula uses the quadratic correction:
#' center = (p + z^2/(2n)) / (1 + z^2/n)
#' margin = z * sqrt(p(1-p)/n + z^2/(4n^2)) / (1 + z^2/n)
#'
#' @references
#' Wilson, E. B. (1927). Probable inference, the law of succession, and
#' statistical inference. Journal of the American Statistical Association, 22,
#' 209-212.
#'
#' Agresti, A. & Coull, B. A. (1998). Approximate is better than "exact" for
#' interval estimation of binomial proportions. The American Statistician, 52,
#' 119-126.
#'
#' @examples
#' # 30 at-risk out of 100 physicians
#' ci <- calculate_proportion_ci(30, 100)
#' sprintf("%.1f%% (%.1f%% - %.1f%%)",
#'         ci$proportion * 100, ci$lower_ci * 100, ci$upper_ci * 100)
#'
#' # Small sample with extreme proportion
#' ci <- calculate_proportion_ci(1, 10)
#' ci$method  # "Wilson"
#'
#' @family statistical testing functions
#' @export
calculate_proportion_ci <- function(x, n, conf_level = 0.95) {
  if (n == 0) {
    return(list(
      proportion = NA_real_,
      lower_ci = NA_real_,
      upper_ci = NA_real_,
      note = "Zero denominator"
    ))
  }

  prop <- x / n

  # Use Wilson score interval for better small-sample properties
  tryCatch({
    z <- stats::qnorm(1 - (1 - conf_level) / 2)
    denominator <- 1 + z^2 / n
    center <- (prop + z^2 / (2 * n)) / denominator
    margin <- z * sqrt(prop * (1 - prop) / n + z^2 / (4 * n^2)) / denominator

    return(list(
      proportion = prop,
      lower_ci = pmax(0, center - margin),
      upper_ci = pmin(1, center + margin),
      method = "Wilson",
      note = sprintf("%.0f%% confidence interval", conf_level * 100)
    ))

  }, error = function(e) {
    # Fallback to simple normal approximation
    se <- sqrt(prop * (1 - prop) / n)
    z <- stats::qnorm(1 - (1 - conf_level) / 2)
    margin <- z * se

    # R40 BUG FIX (2026-05-22): pmax/pmin clips the fallback normal-approximation CI,
    # making extreme proportions with high uncertainty appear artificially constrained.
    # The Wilson CI above is naturally bounded; this fallback should report raw bounds
    # so callers can detect when the normal approx breaks down at boundary proportions.
    return(list(
      proportion = prop,
      lower_ci = prop - margin,
      upper_ci = prop + margin,
      method = "Normal approximation",
      note = sprintf("%.0f%% confidence interval (fallback)", conf_level * 100)
    ))
  })
}

# ============================================================================
# RETIREMENT CLIFF ANALYSIS FUNCTIONS
# ============================================================================

#' Rural vs Metro Retirement Risk Comparison
#'
#' Compares retirement-at-risk rates between rural and metropolitan areas.
#' This is a key analysis for understanding geographic disparities in the
#' impending physician retirement cliff.
#'
#' The function computes:
#' \itemize{
#'   \item Point estimates for retirement-at-risk rates in each area type
#'   \item 95% confidence intervals using Wilson score method
#'   \item Statistical significance test (two-proportion z-test)
#'   \item Rate difference (rural - metro)
#' }
#'
#' @param rural_at_risk `integer`: Number of physicians aged 65+ in rural areas
#' @param rural_total `integer`: Total number of physicians in rural areas
#' @param metro_at_risk `integer`: Number of physicians aged 65+ in metro areas
#' @param metro_total `integer`: Total number of physicians in metro areas
#'
#' @return A nested list with three components:
#'   \describe{
#'     \item{rural}{List with: at_risk, total, rate_pct, ci_lower (%), ci_upper
#' (%)}
#'     \item{metro}{List with: at_risk, total, rate_pct, ci_lower (%), ci_upper
#' (%)}
#'     \item{comparison}{List with: rate_difference_pct, p_value,
#' p_value_formatted,
#'           significant (logical), test_method, note}
#'   }
#'
#' @details
#' A positive rate_difference_pct indicates rural areas have higher retirement
#' risk rates than metro areas. A significant p-value (< 0.05) indicates the
#' difference is statistically significant and unlikely due to chance.
#'
#' Rural/metro classification typically follows:
#' \itemize{
#'   \item RUCA (Rural-Urban Commuting Area) codes
#'   \item NCHS Urban-Rural Classification Scheme
#' }
#'
#' The confidence intervals are computed using the Wilson score method and
#' converted to percentage scale (0-100) for easier interpretation.
#'
#' @examples
#' # Rural: 45 of 150 at-risk (30%)
#' # Metro: 200 of 1000 at-risk (20%)
#' results <- calculate_rural_metro_comparison(45, 150, 200, 1000)
#'
#' # Access results
#' sprintf("Rural: %.1f%%, Metro: %.1f%%, Difference: %.1f pp, p=%s",
#'         results$rural$rate_pct,
#'         results$metro$rate_pct,
#'         results$comparison$rate_difference_pct,
#'         results$comparison$p_value_formatted)
#'
#' # Check statistical significance
#' if (results$comparison$significant) {
#'   cat("The difference is statistically significant (p < 0.05)")
#' }
#'
#' @family retirement cliff analysis functions
#' @seealso \code{\link{calculate_replacement_gap}} for replacement analysis
#' @seealso \code{\link{calculate_state_vulnerability}} for state rankings
#' @export
calculate_rural_metro_comparison <- function(rural_at_risk, rural_total,
                                           metro_at_risk, metro_total) {
  base::message("[STAT] Calculating rural vs metro comparison...")

  # Basic rates
  rural_rate <- safe_percentage(rural_at_risk, rural_total)
  metro_rate <- safe_percentage(metro_at_risk, metro_total)

  # Confidence intervals
  rural_ci <- calculate_proportion_ci(rural_at_risk, rural_total)
  metro_ci <- calculate_proportion_ci(metro_at_risk, metro_total)

  # Statistical test
  test_result <- calculate_two_prop_test(rural_at_risk, rural_total,
                                       metro_at_risk, metro_total)

  # Rate difference
  rate_diff <- if (!is.na(rural_rate) && !is.na(metro_rate)) {
    rural_rate - metro_rate
  } else {
    NA_real_
  }

  # Compile results
  results <- list(
    rural = list(
      at_risk = rural_at_risk,
      total = rural_total,
      rate_pct = rural_rate,
      ci_lower = rural_ci$lower_ci * 100,
      ci_upper = rural_ci$upper_ci * 100
    ),
    metro = list(
      at_risk = metro_at_risk,
      total = metro_total,
      rate_pct = metro_rate,
      ci_lower = metro_ci$lower_ci * 100,
      ci_upper = metro_ci$upper_ci * 100
    ),
    comparison = list(
      rate_difference_pct = rate_diff,
      p_value = test_result$p_value,
      p_value_formatted = test_result$p_value_formatted,
      significant = test_result$significant,
      test_method = test_result$method,
      note = test_result$note
    )
  )

  base::message(sprintf("[STAT] Rural: %.1f%% (%d/%d), Metro: %.1f%% (%d/%d), p=%s",
                       rural_rate %||% NA, rural_at_risk, rural_total,
                       metro_rate %||% NA, metro_at_risk, metro_total,
                       test_result$p_value_formatted))

  return(results)
}

#' Replacement Gap Analysis
#'
#' Analyzes whether fellowship training programs are producing enough graduates
#' to replace retiring physicians. Compares projected retirees against projected
#' fellowship graduates over a 5-year horizon.
#'
#' A replacement ratio < 1.0 indicates a gap where more physicians are retiring
#' than are being trained, suggesting potential workforce shortages.
#'
#' @param retirees_by_subspec A tibble/data.frame with columns:
#'   \describe{
#'     \item{subspecialty}{Character. Name of the subspecialty (e.g.,
#' "Maternal-Fetal Medicine")}
#'     \item{retiring_count}{Integer. Number of physicians projected to retire
#' in 5-year window}
#'   }
#' @param fellowship_grads A tibble/data.frame with columns:
#'   \describe{
#'     \item{subspecialty}{Character. Name of the subspecialty (must match
#' retirees_by_subspec)}
#'     \item{graduates}{Integer. Number of fellowship graduates for that year}
#'     \item{year}{Integer. Year of graduation (typically 2022-2024 for recent
#' data)}
#'   }
#'
#' @return A list with two components:
#'   \describe{
#'     \item{by_subspecialty}{Tibble with columns: subspecialty, retiring_count,
#'           annual_grads, total_grads_3yr, projected_grads_5yr,
#' replacement_ratio,
#'           net_gap, gap_percentage, adequate_replacement (logical)}
#'     \item{overall}{List with: total_retiring, total_graduates_projected,
#' net_gap,
#'           gap_percentage, replacement_ratio}
#'   }
#'
#' @details
#' Calculations performed:
#' \itemize{
#'   \item annual_grads: Mean graduates per year from fellowship_grads data
#'   \item projected_grads_5yr: annual_grads * 5 (matching 5-year retirement
#' horizon)
#'   \item replacement_ratio: projected_grads_5yr / retiring_count
#'   \item net_gap: retiring_count - projected_grads_5yr (positive = shortage)
#'   \item gap_percentage: (net_gap / retiring_count) * 100
#'   \item adequate_replacement: TRUE if replacement_ratio >= 1.0
#' }
#'
#' Subspecialties in retirees but not in fellowship_grads are assigned 0
#' graduates.
#' This is common for subspecialties without formal fellowship training.
#'
#' The 5-year horizon aligns with the retirement cliff analysis window
#' (2024-2029).
#'
#' @examples
#' retirees <- tibble::tibble(
#'   subspecialty = c("Maternal-Fetal Medicine", "Gynecologic Oncology",
#'                    "Female Pelvic Medicine"),
#'   retiring_count = c(150, 80, 60)
#' )
#' grads <- tibble::tibble(
#'   subspecialty = rep(c("Maternal-Fetal Medicine", "Gynecologic Oncology",
#'                        "Female Pelvic Medicine"), each = 3),
#'   year = rep(2022:2024, 3),
#'   graduates = c(45, 48, 50, 22, 24, 25, 18, 20, 22)
#' )
#' results <- calculate_replacement_gap(retirees, grads)
#'
#' # View subspecialty breakdown
#' print(results$by_subspecialty)
#'
#' # Check overall gap
#' sprintf("Overall gap: %d physicians (%.1f%% shortfall)",
#'         results$overall$net_gap, results$overall$gap_percentage)
#'
#' @family retirement cliff analysis functions
#' @seealso \code{\link{calculate_rural_metro_comparison}} for geographic analysis
#' @export
calculate_replacement_gap <- function(retirees_by_subspec, fellowship_grads,
                                      horizon_years = 5) {
  # SSOT: mufflyaccess owns this. The same function lived here, in isochrones
  # (a byte-identical copy of this file), and in simulation -- and the three
  # DISAGREED. One name, one apparent meaning, three answers.
  #
  # The horizon is now a PARAMETER. This version multiplied by a literal 5 next
  # to a comment reading "horizon - reference = 5 years", so moving the horizon
  # silently left the arithmetic behind. Two output columns are renamed to match:
  # projected_grads_5yr -> projected_grads, total_grads_3yr -> total_grads.
  # Names that hardcode a window are wrong the moment the window is an argument.
  #
  # DEN-055 is preserved: retiring_count = 0 yields replacement_ratio = NA (not
  # 0), so adequate_replacement is NA rather than FALSE. An infinite surplus is
  # not "inadequate". mufflyaccess uses safe_divide(default = NA_real_) and the
  # behavioural tests in this repo still assert it.
  mufflyaccess::calculate_replacement_gap(retirees_by_subspec, fellowship_grads,
                                          horizon_years = horizon_years)
}

#' State Vulnerability Ranking
#'
#' Ranks states by their vulnerability to the physician retirement cliff.
#' Combines retirement rate with workforce size to identify states most
#' at risk of workforce shortages.
#'
#' @param state_impacts A tibble/data.frame with columns:
#'   \describe{
#'     \item{state}{Character. Two-letter state abbreviation (e.g., "WY", "AK")}
#'     \item{count_active}{Integer. Total active physicians in the state}
#'     \item{count_at_risk}{Integer. Physicians aged 65+ in the state}
#'     \item{pct_loss_if_retire}{Numeric. Percentage of workforce at retirement
#' risk}
#'     \item{zero_coverage_if_retire}{Logical or Integer. Count of areas/tracts
#' that would
#'           have zero physician coverage if at-risk physicians retire}
#'   }
#' @param top_n `integer`: Number of most vulnerable states to return (default:
#'   10)
#'
#' @return A tibble with top_n rows (or fewer if less data available)
#'   containing:
#'   state, count_active, count_at_risk, pct_loss_if_retire,
#'   zero_coverage_if_retire, vulnerability_score
#'
#' @details
#' The vulnerability_score is calculated as:
#'
#' \code{pct_loss_if_retire * log10(max(1, count_active))}
#'
#' This formula:
#' \itemize{
#'   \item Prioritizes states with high retirement rates (pct_loss_if_retire)
#'   \item Weights by log of workforce size to account for absolute impact
#'   \item Uses log scale to prevent very large states from dominating purely by
#' size
#'   \item The max(1, ...) prevents log(0) errors for states with 0 physicians
#' }
#'
#' Results are sorted by pct_loss_if_retire (descending) to show states with the
#' highest proportional retirement risk first. This means small rural states
#' with
#' high retirement rates will rank above large states with moderate rates.
#'
#' States with NA values for pct_loss_if_retire are excluded from the ranking.
#'
#' @examples
#' state_data <- tibble::tibble(
#'   state = c("WY", "AK", "MT", "CA", "NY", "TX"),
#'   count_active = c(50, 75, 100, 5000, 4000, 3500),
#'   count_at_risk = c(20, 25, 30, 1000, 700, 600),
#'   pct_loss_if_retire = c(40, 33.3, 30, 20, 17.5, 17.1),
#'   zero_coverage_if_retire = c(5, 3, 4, 10, 8, 12)
#' )
#' top_vulnerable <- calculate_state_vulnerability(state_data, top_n = 5)
#'
#' # Wyoming ranks first due to highest pct_loss_if_retire (40%)
#' print(top_vulnerable)
#'
#' @family retirement cliff analysis functions
#' @seealso \code{\link{calculate_rural_metro_comparison}} for rural/metro analysis
#' @export
calculate_state_vulnerability <- function(state_impacts, top_n = 10) {
  base::message("[STAT] Calculating state vulnerability ranking...")

  vulnerability_ranking <- state_impacts %>%
    dplyr::filter(!is.na(.data$pct_loss_if_retire)) %>%
    dplyr::mutate(
      vulnerability_score = .data$pct_loss_if_retire *
                           log10(pmax(1, .data$count_active))  # Weight by log(active count)
    ) %>%
    dplyr::arrange(dplyr::desc(.data$pct_loss_if_retire)) %>%
    dplyr::slice_head(n = top_n) %>%
    dplyr::select(
      .data$state,
      .data$count_active,
      .data$count_at_risk,
      .data$pct_loss_if_retire,
      .data$zero_coverage_if_retire,
      .data$vulnerability_score
    )

  base::message(sprintf("[STAT] Top %d vulnerable states identified", nrow(vulnerability_ranking)))

  return(vulnerability_ranking)
}

# ============================================================================
# MODULE VALIDATION
# ============================================================================
# Ensure critical functions are properly defined when this module is sourced

if (!exists("calculate_rural_metro_comparison", mode = "function")) {
  stop("calculate_rural_metro_comparison function not properly defined")
}
if (!exists("calculate_replacement_gap", mode = "function")) {
  stop("calculate_replacement_gap function not properly defined")
}
if (!exists("calculate_state_vulnerability", mode = "function")) {
  stop("calculate_state_vulnerability function not properly defined")
}
