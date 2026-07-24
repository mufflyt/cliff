#!/usr/bin/env Rscript
#' Enhanced Statistical Summaries for FPMRS Workforce Forecasting
#'
#' Uses raw simulation data to generate proper variance measures
#' following Statistical Summary Agent specifications

# Load required packages
library(dplyr)
library(readr)
library(scales)
library(tibble)

# Source statistical summary functions
source("stat_summaries.R")

# Create timestamped output filename
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
output_file <- sprintf("enhanced_workforce_statistical_summaries_%s.md", timestamp)

cat("Generating enhanced statistical summaries using raw simulation data...\n")

# Load the raw simulation data
simulation_results <- readRDS("results/projection_results_20250928_022307.rds")
raw_data <- simulation_results$raw_simulations
entrants_data <- simulation_results$entrants_plan

cat("Loaded simulation data with", nrow(raw_data), "individual simulation runs\n")

# Initialize markdown output
md_content <- c(
  sprintf("# Enhanced Workforce Forecasting Statistical Summaries"),
  sprintf("*Generated: %s*", Sys.time()),
  "",
  "## Executive Summary",
  "",
  "This report provides enhanced statistical summaries using raw simulation data (n=1,000 iterations per year/subspecialty) from the comprehensive FPMRS workforce forecasting analysis. Standard deviations and confidence intervals are derived from the actual distribution of simulation outcomes.",
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
  subspec_data <- raw_data |>
    filter(subspecialty_f == subspec)

  # Get entrant data for this subspecialty
  entrant_data <- entrants_data |>
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

  # 1. Baseline workforce analysis (2025)
  baseline_2025 <- subspec_data |> filter(year == 2025)

  if (nrow(baseline_2025) > 0) {
    # Use active_start as the baseline workforce measure
    active_summary <- summarize_numeric(baseline_2025, "active_start")

    md_content <- c(md_content,
      "### Baseline Workforce (2025)",
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

  # 2. Final workforce analysis (2029)
  final_2029 <- subspec_data |> filter(year == 2029)

  if (nrow(final_2029) > 0) {
    final_summary <- summarize_numeric(final_2029, "active_end")

    md_content <- c(md_content,
      "### Projected Workforce (2029)",
      sprintf("- **Mean ± SD**: %.1f ± %.1f physicians",
              final_summary$mean, final_summary$sd),
      sprintf("- **Median (IQR)**: %.1f (%d–%d) physicians",
              final_summary$median,
              round(final_summary$p25),
              round(final_summary$p75)),
      ""
    )
  }

  # 3. Change analysis: 2025 to 2029
  change_data <- subspec_data |>
    filter(year %in% c(2025, 2029)) |>
    mutate(workforce_measure = ifelse(year == 2025, active_start, active_end))

  change_analysis <- summarize_change_two_periods(
    change_data, "workforce_measure", "year", 2025, 2029
  )

  md_content <- c(md_content,
    "### Workforce Change (2025-2029)",
    sprintf("- %s", change_analysis$summary_sentence),
    ""
  )

  # 4. Retirement rate analysis across all years
  retirement_summary <- summarize_numeric(subspec_data, "retirement_rate")

  md_content <- c(md_content,
    "### Retirement Rate Analysis (All Years)",
    sprintf("- **Mean ± SD**: %.1f%% ± %.1f%%",
            retirement_summary$mean * 100, retirement_summary$sd * 100),
    sprintf("- **Median (IQR)**: %.1f%% (%.1f%%–%.1f%%)",
            retirement_summary$median * 100,
            retirement_summary$p25 * 100,
            retirement_summary$p75 * 100),
    ""
  )

  # 5. Retirement rate trend analysis
  retirement_change <- summarize_change_two_periods(
    subspec_data, "retirement_rate", "year", 2025, 2029, treat_as_percent = TRUE
  )

  md_content <- c(md_content,
    "### Retirement Rate Trends",
    sprintf("- %s", retirement_change$summary_sentence),
    ""
  )

  # 6. Annual retirement counts
  retired_summary <- summarize_numeric(subspec_data, "retired_count")

  md_content <- c(md_content,
    "### Annual Retirement Volume",
    sprintf("- **Mean ± SD**: %.1f ± %.1f physicians retiring annually",
            retired_summary$mean, retired_summary$sd),
    sprintf("- **Median (IQR)**: %.1f (%d–%d) physicians",
            retired_summary$median,
            round(retired_summary$p25),
            round(retired_summary$p75)),
    ""
  )

  # 7. Fellowship entrant information
  if (nrow(entrant_data) > 0) {
    annual_entrants <- unique(entrant_data$n_new)[1]

    md_content <- c(md_content,
      "### Fellowship Training Pipeline",
      sprintf("- **Annual Fellowship Entrants**: %d physicians per year",
              annual_entrants),
      sprintf("- **Total Entrants (2025-2029)**: %d physicians",
              annual_entrants * 5),
      ""
    )
  }

  # 8. Replacement ratio analysis
  if (nrow(entrant_data) > 0 && nrow(baseline_2025) > 0) {
    annual_entrants <- unique(entrant_data$n_new)[1]
    avg_annual_retirements <- retired_summary$mean
    replacement_ratio <- annual_entrants / avg_annual_retirements

    adequacy <- case_when(
      replacement_ratio >= 1.5 ~ "more than adequate",
      replacement_ratio >= 1.0 ~ "adequate",
      replacement_ratio >= 0.75 ~ "marginal",
      TRUE ~ "insufficient"
    )

    md_content <- c(md_content,
      "### Replacement Ratio Assessment",
      sprintf("- **Replacement Ratio**: %.2f (%.1f entrants / %.1f retirees annually)",
              replacement_ratio, annual_entrants, avg_annual_retirements),
      sprintf("- **Assessment**: %s replacement capacity", adequacy),
      ""
    )
  }

  md_content <- c(md_content, "---", "")
}

# Add comparative analysis section
md_content <- c(md_content,
  "## Comparative Analysis Across Subspecialties",
  ""
)

# Create comparative summary table
comparison_table <- tibble()

for (subspec in subspecialties) {
  subspec_data <- raw_data |> filter(subspecialty_f == subspec)
  entrant_data <- entrants_data |> filter(subspecialty_f == subspec)

  baseline_2025 <- subspec_data |> filter(year == 2025) |> pull(active_start)
  final_2029 <- subspec_data |> filter(year == 2029) |> pull(active_end)

  pct_change <- ((mean(final_2029) - mean(baseline_2025)) / mean(baseline_2025)) * 100
  annual_entrants <- unique(entrant_data$n_new)[1]
  avg_retirements <- mean(subspec_data$retired_count)
  replacement_ratio <- annual_entrants / avg_retirements

  short_name <- case_when(
    subspec == "Female Pelvic Medicine & Reconstructive Surgery" ~ "FPMRS",
    subspec == "Gynecologic Oncology" ~ "GO",
    subspec == "MIG" ~ "MIG",
    TRUE ~ subspec
  )

  comparison_table <- bind_rows(comparison_table, tibble(
    subspecialty = short_name,
    baseline_workforce = round(mean(baseline_2025), 1),
    projected_workforce = round(mean(final_2029), 1),
    percent_change = round(pct_change, 1),
    annual_entrants = annual_entrants,
    avg_annual_retirements = round(avg_retirements, 1),
    replacement_ratio = round(replacement_ratio, 2),
    avg_retirement_rate = round(mean(subspec_data$retirement_rate) * 100, 1)
  ))
}

# Add comparative table to markdown
md_content <- c(md_content,
  "### Summary Statistics by Subspecialty",
  "",
  "| Subspecialty | 2025 Baseline | 2029 Projection | % Change | Annual Entrants | Avg Retirements | Replacement Ratio | Avg Retirement Rate |",
  "|--------------|---------------|-----------------|----------|-----------------|-----------------|------------------|-------------------|"
)

for (i in 1:nrow(comparison_table)) {
  row <- comparison_table[i, ]
  md_content <- c(md_content,
    sprintf("| %s | %s | %s | %+.1f%% | %d | %.1f | %.2f | %.1f%% |",
            row$subspecialty,
            scales::comma(row$baseline_workforce, accuracy = 1),
            scales::comma(row$projected_workforce, accuracy = 1),
            row$percent_change,
            row$annual_entrants,
            row$avg_annual_retirements,
            row$replacement_ratio,
            row$avg_retirement_rate)
  )
}

md_content <- c(md_content, "", "")

# Add methodology notes
md_content <- c(md_content,
  "## Methodology Notes",
  "",
  "### Enhanced Data Analysis",
  "- **Raw Simulation Data**: 1,000 Monte Carlo iterations per year/subspecialty combination",
  "- **Total Observations**: 15,000 individual simulation runs analyzed",
  "- **Variance Measures**: Standard deviations calculated from actual distribution of outcomes",
  "- **Confidence Intervals**: Derived from empirical quantiles of simulation results",
  "",
  "### Statistical Reporting Standards",
  "- **Central Tendency**: Mean ± standard deviation reported to 1 decimal place",
  "- **Spread**: Median with interquartile range (25th–75th percentiles)",
  "- **Percentages**: Reported to 1 decimal place",
  "- **Significance Testing**: Two-sample t-tests for period comparisons",
  "",
  "### Key Assumptions",
  "- **Retirement Detection**: Comprehensive 5-source empirical approach",
  "- **Fellowship Entrants**: Constant annual intake based on current capacity",
  "- **Practice Patterns**: Stable geographic and practice type distributions",
  "",
  sprintf("*Enhanced report generated: %s using Statistical Summary Agent protocols*", Sys.time())
)

# Write the enhanced markdown file
writeLines(md_content, output_file)

# Also save the comparison table as CSV
comparison_table_file <- sprintf("enhanced_comparison_table_%s.csv", timestamp)
write_csv(comparison_table, comparison_table_file)

cat("Enhanced statistical summaries written to:", output_file, "\n")
cat("Comparison table written to:", comparison_table_file, "\n")

# Print key findings to console
cat("\n=== ENHANCED STATISTICAL FINDINGS ===\n")
for (i in 1:nrow(comparison_table)) {
  row <- comparison_table[i, ]
  adequacy <- case_when(
    row$replacement_ratio >= 1.5 ~ "excellent",
    row$replacement_ratio >= 1.0 ~ "adequate",
    row$replacement_ratio >= 0.75 ~ "marginal",
    TRUE ~ "insufficient"
  )

  cat(sprintf("%s: %+.1f%% change (%.1f → %.1f physicians)\n",
              row$subspecialty, row$percent_change,
              row$baseline_workforce, row$projected_workforce))
  cat(sprintf("  Replacement: %.2f ratio (%s), %.1f%% retirement rate\n",
              row$replacement_ratio, adequacy, row$avg_retirement_rate))
  cat("\n")
}

cat("Enhanced analysis complete.\n")
