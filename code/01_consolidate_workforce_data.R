#' @title Step 1: Consolidate Workforce Projection Data
#' @description This script loads existing Monte Carlo simulation results and applies updated
#' fellowship assumptions to recalculate workforce projections.
#' @author Tyler Muffly, MD / Claude Code
#' @date 2026-01-12
#' @param scenario_name The name of the fellowship scenario to use (e.g., "default", "optimistic"). Defaults to "default".
#' @return A CSV file with the consolidated workforce projections.
#' @seealso \code{\link{00_RUN_ALL.R}}

#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 1: Consolidate Workforce Projection Data with Updated Fellowship Assumptions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose: Load existing Monte Carlo simulation results and apply updated
#          fellowship assumptions to recalculate projections
#
# Inputs:  - enhanced_comparison_table_20250928_030546.csv (archived results)
#          - Updated fellowship assumptions (2026 data)
#
# Outputs: - cliff/data/workforce_projections_consolidated.csv
#
# Author: Tyler Muffly, MD / Claude Code
# Date: 2026-01-12
#
# Usage:
#   Rscript cliff/code/01_consolidate_workforce_data.R
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# The 'suppressPackageStartupMessages' function prevents package startup messages from being printed.
suppressPackageStartupMessages({
  library(tidyverse)
  # The 'here' library helps to create reproducible paths to files.
  library(here)
  # The 'yaml' library is used to read YAML configuration files.
  library(yaml)
})

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Configuration
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

INPUT_CSV <- here(
  "docs/isochrones_deep_archive/2025-12-07",
  "legacy_matching_strategies_2025-12-05",
  "research_forecasting/comprehensive_forecasting",
  "enhanced_comparison_table_20250928_030546.csv"
)

OUTPUT_CSV <- here("data/workforce_projections_consolidated.csv")

# Load fellowship assumptions from config file
# Command line usage: Rscript script.R [scenario_name]
# Example: Rscript 01_consolidate_workforce_data.R optimistic
# The 'commandArgs' function retrieves command-line arguments passed to the script.
args <- commandArgs(trailingOnly = TRUE)
scenario_name <- if (length(args) > 0) args[1] else "default"

CONFIG_FILE <- here("config/fellowship_assumptions.yml")
if (!file.exists(CONFIG_FILE)) {
  stop(sprintf("Config file not found: %s", CONFIG_FILE))
}

# The 'read_yaml' function reads a YAML file and returns it as a list.
config <- read_yaml(CONFIG_FILE)

if (!scenario_name %in% names(config)) {
  stop(sprintf("Scenario '%s' not found in config. Available: %s",
               scenario_name, paste(names(config), collapse = ", ")))
}

fellowship_data <- config[[scenario_name]]

# The 'tribble' function creates a tibble (a modern data frame) from data entered row-by-row.
# Convert to tribble format for processing
FELLOWSHIP_UPDATED <- tribble(
  ~subspecialty, ~annual_entrants,
  "FPMRS",       fellowship_data$FPMRS,
  "GO",          fellowship_data$GO,
  "MIG",         fellowship_data$MIG
)

# Display which scenario is being used
cat(sprintf("\n=== Using Fellowship Scenario: '%s' ===\n", scenario_name))
cat(sprintf("  FPMRS: %d fellows/year\n", fellowship_data$FPMRS))
cat(sprintf("  GO: %d fellows/year\n", fellowship_data$GO))
cat(sprintf("  MIG: %d fellows/year\n\n", fellowship_data$MIG))

# Standard deviations from enhanced_workforce_statistical_summaries document
SD_VALUES <- tribble(
  ~subspecialty, ~sd_2029,
  "FPMRS",       15.2,
  "GO",          16.1,
  "MIG",         11.0
)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main Processing
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat(paste0("[", Sys.time(), "] Loading archived simulation results\n"))

# Verify input file exists
if (!file.exists(INPUT_CSV)) {
  stop(sprintf("Input file not found: %s", INPUT_CSV))
}

# The 'read_csv' function reads a comma-separated value (CSV) file into a tibble.
# Load existing CSV
enhanced_table <- read_csv(INPUT_CSV, show_col_types = FALSE)

cat(sprintf("  Loaded %d rows from %s\n", nrow(enhanced_table), basename(INPUT_CSV)))
cat("\nOriginal data structure:\n")
print(enhanced_table)

# Apply fellowship assumptions from selected scenario
cat("\n[", as.character(Sys.time()), "] Applying fellowship assumptions from scenario: ", scenario_name, "\n", sep = "")
cat("  Fellowship numbers being applied:\n")
cat(sprintf("    - FPMRS: %d fellows/year\n", fellowship_data$FPMRS))
cat(sprintf("    - Gynecologic Oncology: %d fellows/year\n", fellowship_data$GO))
cat(sprintf("    - MIGS: %d fellows/year\n\n", fellowship_data$MIG))

consolidated <- enhanced_table %>%
  # The 'mutate' function adds new variables to a tibble.
  # Save original abbreviation before expanding
  mutate(
    subspecialty_abbrev = subspecialty,
    subspecialty_full = case_when(
      subspecialty == "FPMRS" ~ "Female Pelvic Medicine & Reconstructive Surgery",
      subspecialty == "GO" ~ "Gynecologic Oncology",
      subspecialty == "MIG" ~ "Minimally Invasive Gynecologic Surgery",
      TRUE ~ subspecialty
    )
  ) %>%
  # The 'select' function keeps or drops variables from a tibble.
  # Replace fellowship numbers with updated values
  select(-annual_entrants) %>%
  # The 'left_join' function joins two tibbles based on a common variable.
  left_join(FELLOWSHIP_UPDATED, by = c("subspecialty_abbrev" = "subspecialty")) %>%
  # Recalculate replacement ratio with new fellowship numbers
  mutate(
    replacement_ratio = annual_entrants / avg_annual_retirements
  ) %>%
  # Recalculate projected workforce based on new replacement ratios
  # Formula: projected = baseline - (4 years * retirements) + (4 years * entrants)
  mutate(
    projected_workforce = baseline_workforce - (4 * avg_annual_retirements) + (4 * annual_entrants),
    percent_change = 100 * (projected_workforce - baseline_workforce) / baseline_workforce
  ) %>%
  # Join with standard deviations
  left_join(SD_VALUES, by = c("subspecialty_abbrev" = "subspecialty")) %>%
  # Calculate 95% CI using parametric method (mean ± 1.96 * SD)
  mutate(
    ci95_lower = round(projected_workforce - 1.96 * sd_2029),
    ci95_upper = round(projected_workforce + 1.96 * sd_2029),
    # Ensure no negative values
    ci95_lower = pmax(ci95_lower, 0)
  ) %>%
  # The 'transmute' function is similar to 'mutate', but it drops all other variables.
  # Select and rename columns for manuscript use
  transmute(
    subspecialty = subspecialty_full,
    subspecialty_abbrev = subspecialty_abbrev,
    baseline_2025 = baseline_workforce,
    projected_2029 = projected_workforce,
    sd_2029 = sd_2029,
    ci95_lower = ci95_lower,
    ci95_upper = ci95_upper,
    percent_change = percent_change,
    annual_retirement_rate = avg_retirement_rate,
    avg_annual_retirements = avg_annual_retirements,
    annual_entrants = annual_entrants,
    replacement_ratio = replacement_ratio,
    # Classification based on replacement ratio
    replacement_assessment = case_when(
      replacement_ratio >= 1.2 ~ "Adequate",
      replacement_ratio >= 0.8 ~ "Marginal",
      TRUE ~ "Insufficient"
    ),
    # Calculate total 5-year fellowship output
    fellowship_total_5yr = annual_entrants * 5,
    # Calculate total projected retirements over 4 years
    total_retirements_4yr = round(avg_annual_retirements * 4)
  )

# Display processed data
cat("\nConsolidated data with updated assumptions:\n")
print(consolidated, width = Inf)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Validation
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n[", as.character(Sys.time()), "] Running validation checks\n", sep = "")

# Check 1: No missing values in critical columns
critical_cols <- c("baseline_2025", "projected_2029", "replacement_ratio")
missing_check <- consolidated %>%
  select(all_of(critical_cols)) %>%
  summarise(across(everything(), ~sum(is.na(.))))

if (any(missing_check > 0)) {
  cat("WARNING: Missing values detected:\n")
  print(missing_check)
} else {
  cat("  ✓ No missing values in critical columns\n")
}

# Check 2: Replacement ratios match calculated values
ratio_check <- consolidated %>%
  mutate(
    calculated_ratio = annual_entrants / avg_annual_retirements,
    ratio_diff = abs(calculated_ratio - replacement_ratio)
  )

max_diff <- max(ratio_check$ratio_diff, na.rm = TRUE)
if (max_diff > 0.01) {
  cat(sprintf("WARNING: Replacement ratio mismatch (max diff: %.3f)\n", max_diff))
  print(select(ratio_check, subspecialty_abbrev, replacement_ratio, calculated_ratio, ratio_diff))
} else {
  cat("  ✓ Replacement ratios mathematically correct\n")
}

# Check 3: Confidence intervals sensible (CI width <50% of mean)
ci_check <- consolidated %>%
  mutate(
    ci_width = ci95_upper - ci95_lower,
    ci_percent = 100 * ci_width / projected_2029
  )

if (any(ci_check$ci_percent > 50, na.rm = TRUE)) {
  cat("WARNING: Very wide confidence intervals detected\n")
  print(select(ci_check, subspecialty_abbrev, projected_2029, ci95_lower, ci95_upper, ci_percent))
} else {
  cat("  ✓ Confidence intervals reasonable (all <50% of mean)\n")
}

# Check 4: No negative projections
if (any(consolidated$projected_2029 < 0 | consolidated$ci95_lower < 0)) {
  cat("ERROR: Negative workforce projections detected!\n")
  print(select(consolidated, subspecialty_abbrev, projected_2029, ci95_lower, ci95_upper))
} else {
  cat("  ✓ All workforce projections positive\n")
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Save Output
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Create output directory if needed
dir.create(dirname(OUTPUT_CSV), recursive = TRUE, showWarnings = FALSE)

# The 'write_csv' function writes a tibble to a CSV file.
# Write consolidated data
write_csv(consolidated, OUTPUT_CSV)

cat(sprintf("\n[%s] SUCCESS: Consolidated data saved to:\n", Sys.time()))
cat(sprintf("  %s\n", OUTPUT_CSV))
cat(sprintf("  %d rows, %d columns\n", nrow(consolidated), ncol(consolidated)))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Summary Statistics
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("SUMMARY: Updated Workforce Projections (2025-2029)\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

summary_table <- consolidated %>%
  transmute(
    Subspecialty = subspecialty_abbrev,
    `2025` = format(baseline_2025, big.mark = ","),
    `2029` = sprintf("%s ± %.1f", format(round(projected_2029), big.mark = ","), sd_2029),
    `95% CI` = sprintf("[%s, %s]",
                       format(ci95_lower, big.mark = ","),
                       format(ci95_upper, big.mark = ",")),
    `Change` = sprintf("%.1f%%", percent_change),
    `Fellows/yr` = annual_entrants,
    `Ratio` = sprintf("%.2f (%s)", replacement_ratio, replacement_assessment)
  )

print(summary_table, width = Inf)

cat("\nKey Findings:\n")
cat(sprintf("  • Total baseline workforce: %s physicians\n",
            format(sum(consolidated$baseline_2025), big.mark = ",")))
cat(sprintf("  • Total projected 2029: %s physicians\n",
            format(round(sum(consolidated$projected_2029)), big.mark = ",")))
cat(sprintf("  • Net change: %+.0f physicians (%.1f%%)\n",
            sum(consolidated$projected_2029) - sum(consolidated$baseline_2025),
            100 * (sum(consolidated$projected_2029) - sum(consolidated$baseline_2025)) / sum(consolidated$baseline_2025)))
cat(sprintf("  • Subspecialties with adequate replacement: %d/3\n",
            sum(consolidated$replacement_ratio >= 1.2)))
cat(sprintf("  • Subspecialties with marginal replacement: %d/3\n",
            sum(consolidated$replacement_ratio >= 0.8 & consolidated$replacement_ratio < 1.2)))
cat(sprintf("  • Subspecialties with insufficient replacement: %d/3\n",
            sum(consolidated$replacement_ratio < 0.8)))

cat("\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Script Complete
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if (!interactive()) {
  cat("\n[", as.character(Sys.time()), "] Script completed successfully\n", sep = "")
}

