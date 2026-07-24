#!/usr/bin/env Rscript
#' Comprehensive Statistical Summaries for FPMRS Workforce Forecasting
#'
#' Generates standardized statistical summaries following Statistical Summary Agent specs
#' for the comprehensive forecasting results from Monte Carlo simulation
#'
#' Data source: Monte Carlo simulation with 1000 iterations using comprehensive
#' 5-source empirical retirement detection (5.56% base rate)

# Load required packages
library(dplyr)
library(readr)
library(scales)
library(tibble)
library(here)

# Source statistical summary functions
source("stat_summaries.R")

# Create timestamped output filename
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
output_file <- sprintf("workforce_statistical_summaries_%s.md", timestamp)

cat("Generating comprehensive statistical summaries for workforce forecasting...\n")

# Load the most recent workforce projection data
projection_data <- read_csv("results/workforce_projection_summary_20250928_020703.csv")

cat("Loaded projection data with", nrow(projection_data), "rows\n")

# Initialize markdown output
md_content <- c(
  sprintf("# Workforce Forecasting Statistical Summaries"),
  sprintf("*Generated: %s*", Sys.time()),
  "",
  "## Executive Summary",
  "",
  "This report provides standardized statistical summaries for the comprehensive FPMRS workforce forecasting analysis. Data comes from a Monte Carlo simulation with 1,000 iterations using comprehensive 5-source empirical retirement detection (5.56% base rate).",
  "",
  "### Key Subspecialties Analyzed:",
  "- **FPMRS**: Female Pelvic Medicine & Reconstructive Surgery",
  "- **Gynecologic Oncology**: GO subspecialty",
  "- **MIG**: Minimally Invasive Gynecology",
  "",
  "---",
  ""
)

# Process each subspecialty
subspecialties <- c("Female Pelvic Medicine & Reconstructive Surgery",
                   "Gynecologic Oncology",
                   "MIG")

for (subspec in subspecialties) {
  cat("Processing", subspec, "...\n")

  # Filter data for this subspecialty
  subspec_data <- projection_data |>
    filter(subspecialty_f == subspec)

  # Short name for headers
  short_name <- case_when(
    subspec == "Female Pelvic Medicine & Reconstructive Surgery" ~ "FPMRS",
    subspec == "Gynecologic Oncology" ~ "Gynecologic Oncology",
    subspec == "MIG" ~ "MIG",
    TRUE ~ subspec
  )

  md_content <- c(md_content,
    sprintf("## %s Analysis", short_name),
    ""
  )

  # 1. Active physician count summary (2025 baseline)
  baseline_2025 <- subspec_data |> filter(year == 2025)
  if (nrow(baseline_2025) > 0) {
    active_summary <- summarize_numeric(baseline_2025, "mean_active")

    md_content <- c(md_content,
      "### Active Physician Workforce (2025 Baseline)",
      sprintf("- **Mean ± SD**: %.1f ± %.1f physicians",
              active_summary$mean, active_summary$sd),
      sprintf("- **Median (IQR)**: %.1f (%d–%d) physicians",
              active_summary$median,
              round(active_summary$p25),
              round(active_summary$p75)),
      sprintf("- **Sample size**: %d simulations", active_summary$n),
      ""
    )
  }

  # 2. Change analysis: 2025 to 2029 (final year in data)
  change_analysis <- summarize_change_two_periods(
    subspec_data, "mean_active", "year", 2025, 2029
  )

  md_content <- c(md_content,
    "### Workforce Change (2025-2029)",
    sprintf("- %s", change_analysis$summary_sentence),
    ""
  )

  # 3. Retirement rate analysis
  retirement_summary <- summarize_numeric(subspec_data, "mean_retirement_rate")

  md_content <- c(md_content,
    "### Retirement Rate Analysis",
    sprintf("- **Mean ± SD**: %.1f%% ± %.1f%%",
            retirement_summary$mean * 100, retirement_summary$sd * 100),
    sprintf("- **Median (IQR)**: %.1f%% (%.1f%%–%.1f%%)",
            retirement_summary$median * 100,
            retirement_summary$p25 * 100,
            retirement_summary$p75 * 100),
    ""
  )

  # 4. Retirement rate change over time
  retirement_change <- summarize_change_two_periods(
    subspec_data, "mean_retirement_rate", "year", 2025, 2029, treat_as_percent = TRUE
  )

  md_content <- c(md_content,
    "### Retirement Rate Trends",
    sprintf("- %s", retirement_change$summary_sentence),
    ""
  )

  # 5. Projection confidence intervals (2029 final year)
  projection_2029 <- subspec_data |> filter(year == 2029)
  if (nrow(projection_2029) > 0) {
    p2029 <- projection_2029[1, ]

    md_content <- c(md_content,
      "### 2029 Projections with Confidence Intervals",
      sprintf("- **Point Estimate**: %s physicians",
              scales::comma(p2029$mean_active, accuracy = 1)),
      sprintf("- **90%% Confidence Interval**: %s–%s physicians",
              scales::comma(p2029$q05_active, accuracy = 1),
              scales::comma(p2029$q95_active, accuracy = 1)),
      sprintf("- **Interquartile Range**: %s–%s physicians",
              scales::comma(p2029$q25_active, accuracy = 1),
              scales::comma(p2029$q75_active, accuracy = 1)),
      ""
    )

    # Calculate percentage change from 2025 baseline
    baseline_2025_val <- subspec_data |> filter(year == 2025) |> pull(mean_active)
    pct_change <- ((p2029$mean_active - baseline_2025_val) / baseline_2025_val) * 100

    change_direction <- if (pct_change > 0) "growth" else "decline"

    md_content <- c(md_content,
      "### Overall Assessment",
      sprintf("- **Net Change**: %.1f%% %s from 2025 to 2029",
              abs(pct_change), change_direction),
      ""
    )
  }

  md_content <- c(md_content, "---", "")
}

# Add methodological notes
md_content <- c(md_content,
  "## Methodology Notes",
  "",
  "### Data Source",
  "- **Simulation Method**: Monte Carlo with 1,000 iterations",
  "- **Retirement Detection**: Comprehensive 5-source empirical approach",
  "- **Base Retirement Rate**: 5.56% annually",
  "- **Data Sources**: NPPES deactivation, Medicare Part D, Open Payments, NPPES snapshots, Physician Compare",
  "",
  "### Statistical Reporting Standards",
  "- **Central Tendency**: Mean ± standard deviation reported to 1 decimal place",
  "- **Spread**: Median with interquartile range (25th–75th percentiles)",
  "- **Percentages**: Reported to 1 decimal place",
  "- **Sample Sizes**: All analyses based on n=1,000 simulation iterations",
  "- **Significance Testing**: Two-sample t-tests for period comparisons",
  "",
  "### Data Quality",
  sprintf("- **Analysis Date**: %s", Sys.Date()),
  "- **Missing Data**: Handled via na.rm=TRUE in all calculations",
  "- **Precision**: Results rounded appropriately for clinical interpretation",
  "",
  sprintf("*Report generated automatically using Statistical Summary Agent protocols*")
)

# Write the markdown file
writeLines(md_content, output_file)

cat("Statistical summaries written to:", output_file, "\n")

# Also create a summary table for quick reference
summary_table <- tibble()

for (subspec in subspecialties) {
  subspec_data <- projection_data |> filter(subspecialty_f == subspec)

  baseline_2025 <- subspec_data |> filter(year == 2025) |> pull(mean_active)
  projection_2029 <- subspec_data |> filter(year == 2029) |> pull(mean_active)
  pct_change <- ((projection_2029 - baseline_2025) / baseline_2025) * 100

  baseline_retire_rate <- subspec_data |> filter(year == 2025) |> pull(mean_retirement_rate)
  final_retire_rate <- subspec_data |> filter(year == 2029) |> pull(mean_retirement_rate)

  short_name <- case_when(
    subspec == "Female Pelvic Medicine & Reconstructive Surgery" ~ "FPMRS",
    subspec == "Gynecologic Oncology" ~ "GO",
    subspec == "MIG" ~ "MIG",
    TRUE ~ subspec
  )

  summary_table <- bind_rows(summary_table, tibble(
    subspecialty = short_name,
    baseline_2025 = round(baseline_2025, 1),
    projection_2029 = round(projection_2029, 1),
    percent_change = round(pct_change, 1),
    baseline_retirement_rate = round(baseline_retire_rate * 100, 2),
    final_retirement_rate = round(final_retire_rate * 100, 2)
  ))
}

# Save summary table
summary_table_file <- sprintf("workforce_summary_table_%s.csv", timestamp)
write_csv(summary_table, summary_table_file)

cat("Summary table written to:", summary_table_file, "\n")

# Print key findings to console
cat("\n=== KEY STATISTICAL FINDINGS ===\n")
for (i in 1:nrow(summary_table)) {
  row <- summary_table[i, ]
  cat(sprintf("%s: %.1f%% change (%.1f → %.1f physicians, %.2f%% → %.2f%% retirement rate)\n",
              row$subspecialty, row$percent_change,
              row$baseline_2025, row$projection_2029,
              row$baseline_retirement_rate, row$final_retirement_rate))
}

cat("\nStatistical summary generation complete.\n")
