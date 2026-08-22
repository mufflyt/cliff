#' @title Workforce Statistics Helper Functions for Manuscript
#' @description This script provides a set of accessor functions to be used for inline
#' statistics in the R Markdown manuscript. It enables dynamic text generation, such as
#' `r get_baseline("FPMRS")`, to ensure the manuscript always reflects the latest data.
#' @author Tyler Muffly, MD / Claude Code
#' @date 2026-01-12
#' @seealso \code{\link{00_RUN_ALL.R}}, \code{\link{manuscript/manuscript_WORKFORCE_CLIFF.Rmd}}

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

# The 'suppressPackageStartupMessages' function prevents package startup messages from being printed.
suppressPackageStartupMessages({
  # The 'tidyverse' library is a collection of R packages designed for data science.
  # It includes ggplot2, dplyr, tidyr, readr, purrr, and tibble.
  library(tidyverse)
  # The 'here' library helps to create reproducible paths to files.
  library(here)
})

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Load Data
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.workforce_data_path <- here("data/workforce_projections_consolidated.csv")

if (!file.exists(.workforce_data_path)) {
  stop(sprintf("Data file not found: %s\nRun cliff/code/manuscript_consolidate_existing_results.R first.",
               .workforce_data_path))
}

.workforce_data <- read_csv(.workforce_data_path, show_col_types = FALSE)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Accessor Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# The '.filter_subspec' function is a helper function that filters the workforce data
# by subspecialty using partial matching on the full name or abbreviation.
# Helper to filter by subspecialty (uses partial matching on full name or abbreviation)
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

#' @title Get baseline workforce count (2025)
#' @param subspecialty Partial name match (e.g., "FPMRS", "Gynecologic", "Minimally")
#' @return Formatted string with comma separator (e.g., "1,283")
get_baseline <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(baseline_2025) %>%
    format(big.mark = ",")
}

#' @title Get projected workforce count (2029)
#' @param subspecialty Partial name match
#' @return Formatted string with comma separator
get_projected <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(projected_2029) %>%
    round() %>%
    format(big.mark = ",")
}

#' @title Get lower 95% confidence interval
#' @param subspecialty Partial name match
#' @return Formatted string with comma separator
get_ci_lower <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(ci95_lower) %>%
    format(big.mark = ",")
}

#' @title Get upper 95% confidence interval
#' @param subspecialty Partial name match
#' @return Formatted string with comma separator
get_ci_upper <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(ci95_upper) %>%
    format(big.mark = ",")
}

#' @title Get percent change (absolute value)
#' @param subspecialty Partial name match
#' @return Formatted string (e.g., "7.0")
get_percent_change <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(percent_change) %>%
    abs() %>%
    sprintf("%.1f", .)
}

#' @title Get percent change with sign
#' @param subspecialty Partial name match
#' @return Formatted string with sign (e.g., "-7.0" or "+8.4")
get_percent_change_signed <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(percent_change) %>%
    sprintf("%+.1f", .)
}

#' @title Get annual retirement rate
#' @param subspecialty Partial name match
#' @return Formatted string (e.g., "4.4")
get_annual_rate <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(annual_retirement_rate) %>%
    sprintf("%.1f", .)
}

#' @title Get replacement ratio
#' @param subspecialty Partial name match
#' @return Formatted string (e.g., "0.85")
get_replacement_ratio <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(replacement_ratio) %>%
    sprintf("%.2f", .)
}

#' @title Get replacement assessment classification
#' @param subspecialty Partial name match
#' @return String: "Adequate", "Marginal", or "Insufficient"
get_replacement_assessment <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(replacement_assessment)
}

#' @title Get total fellowship graduates over 5 years
#' @param subspecialty Partial name match
#' @return Formatted string with comma separator
get_fellowship_total <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(fellowship_total_5yr) %>%
    format(big.mark = ",")
}

#' @title Get annual fellowship entrants
#' @param subspecialty Partial name match
#' @return Numeric value
get_annual_entrants <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(annual_entrants)
}

#' @title Get average annual retirements
#' @param subspecialty Partial name match
#' @return Formatted string (e.g., "55.6")
get_avg_retirements <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(avg_annual_retirements) %>%
    sprintf("%.1f", .)
}

#' @title Get standard deviation for 2029 projection
#' @param subspecialty Partial name match
#' @return Formatted string (e.g., "15.2")
get_sd <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(sd_2029) %>%
    sprintf("%.1f", .)
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Summary Statistics (Aggregate)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' @title Get total baseline workforce across all subspecialties
#' @return Formatted string with comma separator
get_total_baseline <- function() {
  sum(.workforce_data$baseline_2025) %>%
    format(big.mark = ",")
}

#' @title Get total projected workforce across all subspecialties
#' @return Formatted string with comma separator
get_total_projected <- function() {
  sum(.workforce_data$projected_2029) %>%
    round() %>%
    format(big.mark = ",")
}

#' @title Get net change across all subspecialties
#' @return Formatted string with sign and comma separator
get_total_net_change <- function() {
  net_change <- sum(.workforce_data$projected_2029) - sum(.workforce_data$baseline_2025)
  sprintf("%s%s",
          ifelse(net_change >= 0, "+", ""),
          format(round(net_change), big.mark = ","))
}

#' @title Get total percent change across all subspecialties
#' @return Formatted string with sign (e.g., "-3.8")
get_total_percent_change <- function() {
  pct_change <- 100 * (sum(.workforce_data$projected_2029) - sum(.workforce_data$baseline_2025)) /
                sum(.workforce_data$baseline_2025)
  sprintf("%+.1f", pct_change)
}

#' @title Count subspecialties by replacement assessment
#' @param assessment "Adequate", "Marginal", or "Insufficient"
#' @return Integer count
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
