#' @title Workforce Statistics Helper Functions for Manuscript
#'
#' @description
#' Provides inline statistics accessor functions for R Markdown manuscript,
#' enabling dynamic text insertions like \code{get_baseline("FPMRS")}.
#'
#' @family manuscript-utils
#' @name workforce_statistics
NULL

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Workforce Statistics Helper Functions for Manuscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose: Provide inline statistics accessor functions for R Markdown manuscript
#          Enables dynamic text like `r get_baseline("FPMRS")` in Rmd
#
# Data Source: manuscript/data/workforce_projections_consolidated.csv
#
# Usage: source(here("manuscript/R/workforce_statistics.R"))
#
# Author: Tyler Muffly, MD / Claude Code
# Date: 2026-01-12
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
})

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Load Data
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Resolve data path: WORKFORCE_DATA_CSV env var overrides the default,
# matching the data-contract's resolve_workforce_data_path() precedence.
.workforce_data_path <- {
  env_path <- Sys.getenv("WORKFORCE_DATA_CSV", unset = "")
  if (nzchar(env_path)) env_path
  else {
    mp <- here::here("manuscript", "data", "workforce_projections_consolidated.csv")
    if (file.exists(mp)) mp else here::here("data", "workforce_projections_consolidated.csv")
  }
}

if (!file.exists(.workforce_data_path)) {
  warning(sprintf(paste0(
    "Data file not found: %s\n",
    "  Set WORKFORCE_DATA_CSV env var or run DAG Step 5.0 to generate this file."
  ), .workforce_data_path))
  .workforce_data <- tibble::tibble()
} else {
  .workforce_data <- read_csv(.workforce_data_path, show_col_types = FALSE)
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Accessor Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' Filter Workforce Data to a Single Subspecialty Row
#'
#' Internal helper that performs a case-insensitive partial-match search on
#' the \code{subspecialty} column of \code{.workforce_data}, falling back to
#' \code{subspecialty_abbrev} if the first search returns no rows.  Stops with
#' an informative error when no row matches or when the pattern is ambiguous
#' (matches more than one row).
#'
#' @param subspecialty_pattern [character(1)] A regular-expression-compatible
#'   string matched case-insensitively against the \code{subspecialty} and,
#'   if necessary, the \code{subspecialty_abbrev} columns of
#'   \code{.workforce_data}.  Examples: \code{"FPMRS"},
#'   \code{"Gynecologic Oncology"}, \code{"Minimally"}.
#'
#' @return A single-row data frame (the matching row of \code{.workforce_data})
#'   containing all projection columns for the requested subspecialty.  The
#'   function never returns zero rows — it stops with \code{stop()} if no
#'   match is found.
#'
#' @seealso [get_baseline()], [get_projected()], [get_ci_lower()],
#'   [get_ci_upper()], [get_percent_change()], [get_replacement_ratio()]
#'
#' @keywords internal
.filter_subspec <- function(subspecialty_pattern) {
  # Try full subspecialty name first
  result <- .workforce_data[str_detect(.workforce_data$subspecialty,
                                        regex(subspecialty_pattern, ignore_case = TRUE)), ]

  # If no match, try abbreviation column
  if (nrow(result) == 0) {
    result <- .workforce_data[str_detect(.workforce_data$subspecialty_abbrev,
                                          regex(subspecialty_pattern, ignore_case = TRUE)), ]
  }

  if (nrow(result) == 0) {
    stop(sprintf("No subspecialty found matching pattern: '%s'", subspecialty_pattern))
  }

  if (nrow(result) > 1) {
    stop(sprintf("Pattern '%s' matched multiple subspecialties: %s\nUse a more specific pattern.",
                 subspecialty_pattern,
                 paste(result$subspecialty, collapse = ", ")))
  }

  result
}

#' Get baseline workforce count (2025)
#'
#' @param subspecialty [character(1)] Partial name or abbreviation matching a
#'   single row in `.workforce_data` (e.g., `"FPMRS"`, `"Gynecologic
#' Oncology"`).
#' @return Formatted character string with comma thousands separator
#'   (e.g., `"1,283"`).  For use in inline R Markdown (`` `r
#' get_baseline("FPMRS")` ``).
#' @seealso [get_projected()], [.filter_subspec()]
#' @export
#' @examples
#' \dontrun{
#' get_baseline("FPMRS")      # "1,283"
#' get_baseline("Gynecologic") # "892"
#' }
get_baseline <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(baseline_2025) %>%
    format(big.mark = ",")
}

#' Get projected workforce count (2029)
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return Formatted character string of the rounded 2029 projection with
#'   comma thousands separator (e.g., `"1,195"`).
#' @seealso [get_baseline()], [get_ci_lower()], [get_ci_upper()]
#' @export
#' @examples
#' \dontrun{
#' get_projected("FPMRS")  # "1,195"
#' }
get_projected <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(projected_2029) %>%
    round() %>%
    format(big.mark = ",")
}

#' Get lower bound of the 95% projection confidence interval
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return Formatted character string with comma thousands separator.
#' @seealso [get_ci_upper()], [get_projected()]
#' @export
#' @examples
#' \dontrun{
#' get_ci_lower("FPMRS")  # "1,140"
#' }
get_ci_lower <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(ci95_lower) %>%
    format(big.mark = ",")
}

#' Get upper bound of the 95% projection confidence interval
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return Formatted character string with comma thousands separator.
#' @seealso [get_ci_lower()], [get_projected()]
#' @export
#' @examples
#' \dontrun{
#' get_ci_upper("FPMRS")  # "1,350"
#' }
get_ci_upper <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(ci95_upper) %>%
    format(big.mark = ",")
}

#' Get magnitude of percent change 2025–2029 (unsigned)
#'
#' Returns the absolute value of the 5-year percent change, formatted to one
#' decimal place.  Use [get_percent_change_signed()] when direction matters.
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return Formatted character string (e.g., `"7.0"`).
#' @seealso [get_percent_change_signed()]
#' @export
#' @examples
#' \dontrun{
#' get_percent_change("FPMRS")  # "7.0"
#' }
get_percent_change <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(percent_change) %>%
    sprintf("%+.1f", .)
}

#' Get signed percent change 2025–2029
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return Formatted character string with explicit `+` or `-` sign and one
#'   decimal place (e.g., `"-7.0"` or `"+8.4"`).
#' @seealso [get_percent_change()] for the unsigned version.
#' @export
#' @examples
#' \dontrun{
#' get_percent_change_signed("FPMRS")  # "-7.0"
#' }
get_percent_change_signed <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(percent_change) %>%
    sprintf("%+.1f", .)
}

#' Get annual retirement rate (percent per year)
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return Formatted character string to one decimal place (e.g., `"4.4"`).
#' @seealso [get_replacement_ratio()]
#' @export
#' @examples
#' \dontrun{
#' get_annual_rate("FPMRS")  # "4.4"
#' }
get_annual_rate <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(annual_retirement_rate) %>%
    sprintf("%.1f", .)
}

#' Get fellowship replacement ratio
#'
#' The replacement ratio is `annual_entrants / avg_annual_retirements`.
#' Values below 1.0 indicate a shrinking workforce.
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return Formatted character string to two decimal places (e.g., `"0.85"`).
#' @seealso [get_replacement_assessment()], [get_annual_rate()]
#' @export
#' @examples
#' \dontrun{
#' get_replacement_ratio("FPMRS")  # "0.85"
#' }
get_replacement_ratio <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(replacement_ratio) %>%
    sprintf("%.1f", .)
}

#' Get workforce replacement assessment classification
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return One of `"Adequate"`, `"Marginal"`, or `"Insufficient"` — derived
#'   from the `replacement_ratio` column in the projection data.
#' @seealso [get_replacement_ratio()], [count_by_assessment()]
#' @export
#' @examples
#' \dontrun{
#' get_replacement_assessment("FPMRS")  # "Insufficient"
#' }
get_replacement_assessment <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(replacement_assessment)
}

#' Get total fellowship graduates over 5 years (2025–2029)
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return Formatted character string with comma thousands separator.
#' @seealso [get_annual_entrants()]
#' @export
#' @examples
#' \dontrun{
#' get_fellowship_total("FPMRS")  # "275"
#' }
get_fellowship_total <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(fellowship_total_4yr) %>%
    format(big.mark = ",")
}

#' Get annual fellowship entrants (raw numeric)
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return Numeric scalar (unformatted).  Use [get_fellowship_total()] for the
#'   formatted 5-year total.
#' @seealso [get_fellowship_total()], [get_avg_retirements()]
#' @export
#' @examples
#' \dontrun{
#' get_annual_entrants("FPMRS")  # 55
#' }
get_annual_entrants <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(annual_entrants)
}

#' Get average annual retirements
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return Formatted character string to one decimal place (e.g., `"55.6"`).
#' @seealso [get_annual_entrants()], [get_replacement_ratio()]
#' @export
#' @examples
#' \dontrun{
#' get_avg_retirements("FPMRS")  # "55.6"
#' }
get_avg_retirements <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(avg_annual_retirements) %>%
    sprintf("%.1f", .)
}

#' Get standard deviation of the 2029 projection
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return Formatted character string to one decimal place (e.g., `"15.2"`).
#' @seealso [get_ci_lower()], [get_ci_upper()]
#' @export
#' @examples
#' \dontrun{
#' get_sd("FPMRS")  # "54.2"
#' }
get_sd <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(sd_2029) %>%
    sprintf("%.1f", .)
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Summary Statistics (Aggregate)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' Get total baseline workforce across all 7 subspecialties (2025)
#'
#' Sums `baseline_2025` across all rows in `.workforce_data`.
#'
#' @return Formatted character string with comma thousands separator
#'   (e.g., `"7,042"`).
#' @seealso [get_total_projected()], [get_baseline()]
#' @export
#' @examples
#' \dontrun{
#' get_total_baseline()  # "7,042"
#' }
get_total_baseline <- function() {
  sum(.workforce_data$baseline_2025) %>%
    format(big.mark = ",")
}

#' Get total projected workforce across all 7 subspecialties (2029)
#'
#' Sums and rounds `projected_2029` across all rows in `.workforce_data`.
#'
#' @return Formatted character string with comma thousands separator.
#' @seealso [get_total_baseline()], [get_total_net_change()]
#' @export
#' @examples
#' \dontrun{
#' get_total_projected()  # "6,780"
#' }
get_total_projected <- function() {
  sum(.workforce_data$projected_2029) %>%
    round() %>%
    format(big.mark = ",")
}

#' Get net workforce change across all 7 subspecialties (2025–2029)
#'
#' Computes `sum(projected_2029) - sum(baseline_2025)` and formats the
#' result with an explicit `+` or `-` sign and comma thousands separator.
#'
#' @return Formatted character string (e.g., `"-262"` or `"+15"`).
#' @seealso [get_total_percent_change()]
#' @export
#' @examples
#' \dontrun{
#' get_total_net_change()  # "-262"
#' }
get_total_net_change <- function() {
  net_change <- sum(.workforce_data$projected_2029) - sum(.workforce_data$baseline_2025)
  sprintf("%s%s",
          ifelse(net_change >= 0, "+", ""),
          format(round(net_change), big.mark = ","))
}

#' Get total percent change across all 7 subspecialties (2025–2029)
#'
#' Returns `"N/A"` if the baseline sum is zero (division-by-zero guard added
#' in BUG FIX CC1 on 2026-01-29).
#'
#' @return Formatted character string with explicit sign and one decimal place
#'   (e.g., `"-3.8"`), or `"N/A"` when the baseline is zero.
#' @seealso [get_total_net_change()]
#' @export
#' @examples
#' \dontrun{
#' get_total_percent_change()  # "-3.7"
#' }
get_total_percent_change <- function() {
  # BUG FIX CC1 (2026-01-29): Guard against division by zero.
  # If baseline is 0 (no physicians), returns Inf which breaks sprintf output.
  baseline_sum <- sum(.workforce_data$baseline_2025)
  if (baseline_sum <= 0) {
    return("N/A")
  }
  pct_change <- 100 * (sum(.workforce_data$projected_2029) - baseline_sum) / baseline_sum
  sprintf("%+.1f", pct_change)
}

#' Count subspecialties by replacement assessment category
#'
#' @param assessment [character(1)] One of `"Adequate"`, `"Marginal"`, or
#'   `"Insufficient"`.
#' @return Integer scalar — number of subspecialties in that category.
#' @seealso [get_replacement_assessment()]
#' @export
#' @examples
#' \dontrun{
#' count_by_assessment("Insufficient")  # 4
#' count_by_assessment("Adequate")      # 1
#' }
count_by_assessment <- function(assessment) {
  sum(.workforce_data$replacement_assessment == assessment)
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Temporal back-test accessor
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' Maximum age-band calibration error for well-populated bands.
#'
#' Reads the age-band back-test artifact and returns the maximum absolute
#' percentage error across bands with at least `min_n` physicians. Used in
#' the manuscript's inline statistic: "calibration to within about X%".
#'
#' @param min_n Minimum cohort size to include a band (default 50).
#' @return Character scalar formatted as "N" (no decimal, no percent sign).
get_backtest_band_maxerr <- function(min_n = 50L) {
  bt_path <- here::here("data", "temporal_backtest_ageband.csv")
  if (!file.exists(bt_path)) return(NA_character_)
  bt <- utils::read.csv(bt_path, stringsAsFactors = FALSE, check.names = FALSE)
  well <- bt[bt$n_base >= min_n, , drop = FALSE]
  if (nrow(well) == 0) return("0")
  sprintf("%.0f", max(abs(well$pct_error), na.rm = TRUE))
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Aggregate entrant getters
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' Total annual entrants across all subspecialties.
get_total_annual_entrants <- function() {
  format(sum(.workforce_data$annual_entrants), big.mark = ",")
}

#' Fellowship total over the 4-year projection horizon (alias kept for compat).
get_fellowship_total_5yr <- function(subspecialty) {
  get_fellowship_total(subspecialty)
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Direction / growth-word helpers
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.pct_for <- function(ab) {
  r <- .workforce_data[.workforce_data$subspecialty_abbrev == ab, , drop = FALSE]
  if (nrow(r) == 0) stop(sprintf("No subspecialty found matching abbreviation: '%s'", ab))
  r$percent_change[1]
}

#' "growth" or "decline" depending on percent_change sign.
get_direction <- function(subspecialty) {
  pct <- .pct_for(subspecialty)
  if (pct >= 0) "growth" else "decline"
}

#' "increase" or "decrease" depending on percent_change sign.
get_change_noun <- function(subspecialty) {
  pct <- .pct_for(subspecialty)
  if (pct >= 0) "increase" else "decrease"
}

#' "increasing" or "decreasing" depending on percent_change sign.
get_change_verb <- function(subspecialty) {
  pct <- .pct_for(subspecialty)
  if (pct >= 0) "increasing" else "decreasing"
}

#' Absolute magnitude of percent change, formatted "n.n" (no sign, no trailing zero noise).
get_percent_change_magnitude <- function(subspecialty) {
  pct <- .pct_for(subspecialty)
  sprintf("%.1f", abs(pct))
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Policy-target helpers
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' Number of annual fellowship positions needed to meet the replacement buffer threshold.
get_positions_for_adequate <- function(subspecialty) {
  r <- .filter_subspec(subspecialty)
  as.integer(ceiling(r$avg_annual_retirements * WORKFORCE_REPLACEMENT_BUFFER))
}

#' Replacement buffer threshold as a character string (e.g., "1.2").
get_adequate_threshold <- function() {
  sprintf("%.1f", WORKFORCE_REPLACEMENT_BUFFER)
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Per-subspecialty net-change and fellowship-total getters
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' Net change in workforce headcount from 2025 to 2029 (signed integer).
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return Formatted character string with explicit sign (e.g., `"+210"`, `"-74"`).
get_net_change_4yr <- function(subspecialty) {
  r <- .filter_subspec(subspecialty)
  net <- as.integer(round(r$projected_2029)) - as.integer(r$baseline_2025)
  sprintf("%+d", net)
}

#' Total fellowship graduates over the 4-year projection horizon (annual_entrants * 4).
#'
#' @param subspecialty [character(1)] Partial name or abbreviation.
#' @return Formatted character string with comma thousands separator.
get_fellowship_total_4yr <- function(subspecialty) {
  r <- .filter_subspec(subspecialty)
  format(as.integer(r$annual_entrants) * 4L, big.mark = ",")
}

#' Range of graduate-drop percentages that would tip a subspecialty below replacement,
#' scaled by a conversion factor \code{conv} (fraction of graduates actually entering
#' the counted workforce).
#'
#' @param conv [numeric(1)] Conversion fraction, 0 < conv <= 1.  Default 1.0.
#' @return Character string of the form `"X% to Y%"`.
get_tipping_missed_range <- function(conv = 1.0) {
  b_path <- here::here("data", "breakeven_thresholds.csv")
  if (!file.exists(b_path)) return("0% to 0%")
  b <- utils::read.csv(b_path, stringsAsFactors = FALSE, check.names = FALSE)
  ssot <- .workforce_data
  drops <- vapply(seq_len(nrow(b)), function(i) {
    ab  <- b$subspecialty_abbrev[i]
    row <- ssot[ssot$subspecialty_abbrev == ab, , drop = FALSE]
    if (nrow(row) == 0) return(0)
    ent <- row$annual_entrants[1] * conv
    bg  <- b$breakeven_graduates[i]
    if (ent <= 0) 0 else max(0, 100 * (1 - bg / ent))
  }, numeric(1))
  sprintf("%d%% to %d%%", floor(min(drops)), ceiling(max(drops)))
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Sensitivity-artifact getters
# Each function reads its named CSV (listed here so the contract test can grep
# for every registered artifact filename in this source file):
#   mortality_sensitivity.csv
#   consistent_definition_baseline_sensitivity.csv
#   inactivity_threshold_sensitivity.csv
#   hierarchical_hazard_comparison.csv
#   graduate_growth_scenarios.csv
#   baseline_lag_decomposition.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.op_load <- function(fname) {
  p <- here::here("data", fname)
  if (!file.exists(p)) stop(sprintf("sensitivity artifact not found: %s", p))
  utils::read.csv(p, stringsAsFactors = FALSE, check.names = FALSE)
}

#' Mortality-adjusted replacement ratio (all missed deaths).
get_mortality_ratio_all <- function(ab) {
  d <- .op_load("mortality_sensitivity.csv")
  r <- d[d$subspecialty_abbrev == ab, , drop = FALSE]
  if (nrow(r) == 0) stop(sprintf("no row for %s in mortality_sensitivity.csv", ab))
  sprintf("%.1f", r$ratio_adj_all_missed[1])
}

#' Mortality-adjusted replacement ratio (half missed deaths).
get_mortality_ratio_half <- function(ab) {
  d <- .op_load("mortality_sensitivity.csv")
  r <- d[d$subspecialty_abbrev == ab, , drop = FALSE]
  if (nrow(r) == 0) stop(sprintf("no row for %s in mortality_sensitivity.csv", ab))
  sprintf("%.1f", r$ratio_adj_half_missed[1])
}

#' Consistent-definition baseline sensitivity ratio.
get_consistent_ratio <- function(ab) {
  d <- .op_load("consistent_definition_baseline_sensitivity.csv")
  r <- d[d$subspecialty_abbrev == ab, , drop = FALSE]
  if (nrow(r) == 0) stop(sprintf("no row for %s in consistent_definition_baseline_sensitivity.csv", ab))
  sprintf("%.1f", r$ratio_consistent[1])
}

#' Inactivity-threshold sensitivity ratio.
#' @param threshold_years integer threshold (2, 3, or 4).
get_inactivity_ratio <- function(threshold_years, ab) {
  d <- .op_load("inactivity_threshold_sensitivity.csv")
  r <- d[d$subspecialty_abbrev == ab & d$threshold_years == threshold_years, , drop = FALSE]
  if (nrow(r) == 0) stop(sprintf("no row for %s/threshold=%s in inactivity_threshold_sensitivity.csv", ab, threshold_years))
  sprintf("%.1f", r$replacement_ratio[1])
}

#' Hierarchical partial-pooling replacement ratio.
#' @param method one of "unpooled", "pooled", "partial_pooled".
get_hier_ratio <- function(method, ab) {
  d <- .op_load("hierarchical_hazard_comparison.csv")
  r <- d[d$method == method & d$subspecialty_abbrev == ab, , drop = FALSE]
  if (nrow(r) == 0) stop(sprintf("no row for %s/%s in hierarchical_hazard_comparison.csv", method, ab))
  sprintf("%.1f", r$replacement_ratio[1])
}

#' Graduate-supply scenario replacement ratio.
#' @param scenario one of "flat_recent_mean", "cohort_accounting", "contraction", "cautious_trend".
get_grad_scenario_ratio <- function(scenario, ab) {
  d <- .op_load("graduate_growth_scenarios.csv")
  r <- d[d$scenario == scenario & d$subspecialty_abbrev == ab, , drop = FALSE]
  if (nrow(r) == 0) stop(sprintf("no row for %s/%s in graduate_growth_scenarios.csv", scenario, ab))
  sprintf("%.1f", r$replacement_ratio[1])
}

#' Baseline-lag decomposition: directly-supported fraction.
get_lag_direct_fraction <- function(ab) {
  d <- .op_load("baseline_lag_decomposition.csv")
  r <- d[d$subspecialty_abbrev == ab, , drop = FALSE]
  if (nrow(r) == 0) stop(sprintf("no row for %s in baseline_lag_decomposition.csv", ab))
  sprintf("%.0f%%", 100 * r$directly_supported[1] / (r$baseline_total[1] - r$abu_net_new[1]))
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Validation
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Verify all expected subspecialties present
expected_subspecs <- c("Female Pelvic Medicine", "Gynecologic Oncology", "Minimally Invasive")

for (subspec in expected_subspecs) {
  tryCatch({
    result <- .filter_subspec(subspec)
    if (nrow(result) == 0) {
      warning(sprintf("Expected subspecialty pattern '%s' not found in data", subspec))
    }
  }, error = function(e) {
    warning(sprintf("Error validating subspecialty pattern '%s': %s", subspec, e$message))
  })
}

# Success message
if (interactive()) {
  cat("✓ Workforce statistics functions loaded successfully\n")
  cat(sprintf("  Data source: %s\n", basename(.workforce_data_path)))
  cat(sprintf("  Subspecialties: %d\n", nrow(.workforce_data)))
  cat(sprintf("  Total baseline: %s physicians\n", get_total_baseline()))
}
