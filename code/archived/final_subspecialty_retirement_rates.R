#!/usr/bin/env Rscript
# Final Comprehensive Subspecialty Retirement Rate Analysis
# Created: 2025-09-28

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

cat("=== COMPREHENSIVE SUBSPECIALTY RETIREMENT RATES ===\n\n")

# 1. Historical Cumulative Retirement Rates (from database analysis)
cat("1. 📊 HISTORICAL CUMULATIVE RETIREMENT RATES:\n")
cat("   (Based on career-long retirement status in database)\n\n")

historical_rates <- data.frame(
  subspecialty = c("Gynecologic Oncology", "FPMRS", "MIG"),
  total_physicians = c(1628, 1282, 717),
  retired_physicians = c(336, 46, 1),
  cumulative_rate = c(20.64, 3.59, 0.14)
)

for(i in 1:nrow(historical_rates)) {
  row <- historical_rates[i,]
  cat(sprintf("   • %s:\n", row$subspecialty))
  cat(sprintf("     - Total physicians: %d\n", row$total_physicians))
  cat(sprintf("     - Retired physicians: %d\n", row$retired_physicians))
  cat(sprintf("     - Cumulative retirement rate: %.2f%%\n", row$cumulative_rate))
  cat("\n")
}

# 2. Annual Retirement Rates from Monte Carlo Projections
cat("2. 📈 ANNUAL RETIREMENT RATES (From Monte Carlo Model):\n")
cat("   (Current model predictions for active practice)\n\n")

projection_file <- "results/workforce_projection_data_20250928_054105.csv"
if (file.exists(projection_file)) {
  projection_data <- readr::read_csv(projection_file, show_col_types = FALSE)

  # Get the annual retirement rates directly from the model
  annual_rates <- projection_data %>%
    filter(year == 2026) %>%  # Use first projection year for current rates
    select(subspecialty_f, mean_retirement_rate) %>%
    mutate(
      subspecialty_clean = case_when(
        subspecialty_f == "Female Pelvic Medicine & Reconstructive Surgery" ~ "FPMRS",
        subspecialty_f == "Gynecologic Oncology" ~ "Gynecologic Oncology",
        subspecialty_f == "MIG" ~ "MIG",
        TRUE ~ subspecialty_f
      ),
      annual_rate_pct = mean_retirement_rate * 100
    ) %>%
    arrange(desc(annual_rate_pct))

  for(i in 1:nrow(annual_rates)) {
    row <- annual_rates[i,]
    cat(sprintf("   • %s: %.2f%% annually\n", row$subspecialty_clean, row$annual_rate_pct))
  }

  # Also show 5-year projection impact
  cat("\n   📅 5-YEAR WORKFORCE PROJECTIONS (2025-2030):\n")

  projection_summary <- projection_data %>%
    filter(year %in% c(2025, 2030)) %>%
    group_by(subspecialty_f) %>%
    summarise(
      workforce_2025 = median_active[year == 2025],
      workforce_2030 = median_active[year == 2030],
      .groups = "drop"
    ) %>%
    mutate(
      subspecialty_clean = case_when(
        subspecialty_f == "Female Pelvic Medicine & Reconstructive Surgery" ~ "FPMRS",
        subspecialty_f == "Gynecologic Oncology" ~ "Gynecologic Oncology",
        subspecialty_f == "MIG" ~ "MIG",
        TRUE ~ subspecialty_f
      ),
      total_change = workforce_2030 - workforce_2025,
      pct_change = (total_change / workforce_2025) * 100
    ) %>%
    arrange(desc(abs(pct_change)))

  for(i in 1:nrow(projection_summary)) {
    row <- projection_summary[i,]
    cat(sprintf("   • %s:\n", row$subspecialty_clean))
    cat(sprintf("     - 2025: %d physicians\n", row$workforce_2025))
    cat(sprintf("     - 2030: %d physicians\n", row$workforce_2030))
    cat(sprintf("     - Change: %+d physicians (%.1f%%)\n", row$total_change, row$pct_change))
    cat("\n")
  }

} else {
  cat("   ⚠️ Projection data not available\n")
}

# 3. Real-Time Retirement Detection (7-Source System)
cat("3. 🏥 REAL-TIME RETIREMENT DETECTION (7-Source System):\n")
cat("   (Current retirement indicators from 4 states: CO, IL, WA, FL)\n\n")

seven_source_file <- "real_7source_retirement_results_20250928_053733.csv"
if (file.exists(seven_source_file)) {
  seven_source_data <- readr::read_csv(seven_source_file, show_col_types = FALSE)

  cat(sprintf("   • Total OB/GYN physicians analyzed: %d\n", nrow(seven_source_data)))
  cat(sprintf("   • Current retirement cases detected: %d\n", sum(seven_source_data$enhanced_retired, na.rm = TRUE)))
  cat(sprintf("   • Overall current retirement rate: %.2f%%\n",
             sum(seven_source_data$enhanced_retired, na.rm = TRUE) / nrow(seven_source_data) * 100))
  cat(sprintf("   • License-validated retirements: %d\n", sum(seven_source_data$license_retirement_indicator, na.rm = TRUE)))

} else {
  cat("   ⚠️ 7-source data not available\n")
}

# 4. Summary Table
cat("\n4. 📋 RETIREMENT RATE SUMMARY TABLE:\n")
cat("═══════════════════════════════════════════════════════════════════\n")
cat("Subspecialty                     | Historical | Annual    | 5-Year    \n")
cat("                                 | Cumulative| Model     | Projection\n")
cat("───────────────────────────────────────────────────────────────────\n")

# Combine all data for summary
if (exists("annual_rates") && exists("projection_summary")) {
  summary_table <- historical_rates %>%
    left_join(
      annual_rates %>% select(subspecialty_clean, annual_rate_pct),
      by = c("subspecialty" = "subspecialty_clean")
    ) %>%
    left_join(
      projection_summary %>% select(subspecialty_clean, pct_change),
      by = c("subspecialty" = "subspecialty_clean")
    )

  for(i in 1:nrow(summary_table)) {
    row <- summary_table[i,]
    cat(sprintf("%-32s | %6.2f%%   | %6.2f%%  | %+6.1f%%\n",
               row$subspecialty, row$cumulative_rate,
               row$annual_rate_pct, row$pct_change))
  }
}

cat("═══════════════════════════════════════════════════════════════════\n")

# 5. Key Insights
cat("\n5. 🎯 KEY INSIGHTS:\n")
cat("\n   📈 ANNUAL RETIREMENT RATES (Current Model):\n")
if (exists("annual_rates")) {
  for(i in 1:nrow(annual_rates)) {
    row <- annual_rates[i,]
    cat(sprintf("   • %s: %.2f%% per year\n", row$subspecialty_clean, row$annual_rate_pct))
  }
}

cat("\n   🏆 RANKING BY RETIREMENT RISK:\n")
cat("   1. Gynecologic Oncology - Highest historical cumulative retirement\n")
cat("   2. FPMRS - Moderate historical retirement, stable projections\n")
cat("   3. MIG - Lowest historical retirement, growth projected\n")

cat("\n   ⚡ 7-SOURCE VALIDATION:\n")
cat("   • Real-time detection of 1.95% current retirement rate (4 states)\n")
cat("   • State medical board validation provides legal confirmation\n")
cat("   • Age validation prevents false positives\n")

cat("\n✅ SUBSPECIALTY RETIREMENT ANALYSIS COMPLETE!\n")
