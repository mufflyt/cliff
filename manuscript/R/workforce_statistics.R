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

.workforce_data_path <- here("manuscript/data/workforce_projections_consolidated.csv")

if (!file.exists(.workforce_data_path)) {
  warning(sprintf(paste0(
    "Data file not found: %s\n",
    "  Run DAG Step 5.0 to generate this file:\n",
    "    TEST_MODE=1 Rscript 00_MASTER_PUBLICATION_PIPELINE.R  # generates stub\n",
    "  Or run directly:\n",
    "    Rscript R/manuscript_consolidate_existing_results.R\n",
    "  See WORKFORCE_SOURCE_CSV env var to point at a custom input CSV.\n",
    "  Accessor functions will error until the data file is present."
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
    abs() %>%
    sprintf("%.1f", .)
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
    sprintf("%.2f", .)
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
    pull(fellowship_total_5yr) %>%
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
