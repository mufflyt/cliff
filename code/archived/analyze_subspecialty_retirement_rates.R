#!/usr/bin/env Rscript
# Analyze Retirement Rates by Subspecialty
# From both comprehensive nationwide analysis and 7-source system
# Created: 2025-09-28

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(DBI)
  library(duckdb)
})

cat("=== SUBSPECIALTY RETIREMENT RATE ANALYSIS ===\n\n")

# 1. Load comprehensive workforce analysis results
cat("1. COMPREHENSIVE WORKFORCE ANALYSIS (Nationwide):\n")
hazard_file <- "results/hazard_model_results_20250928_054041.rds"
if (file.exists(hazard_file)) {
  hazard_results <- readRDS(hazard_file)
  cohort_data <- hazard_results$data

  cat(sprintf("   • Total subspecialty physicians: %d\n", nrow(cohort_data)))

  # Retirement rates by subspecialty
  subspecialty_rates <- cohort_data %>%
    group_by(subspecialty_name) %>%
    summarise(
      total_physicians = n(),
      retired_physicians = sum(retired_binary, na.rm = TRUE),
      retirement_rate = retired_physicians / total_physicians,
      annual_retirement_rate = retirement_rate,  # This is already annualized from the model
      .groups = "drop"
    ) %>%
    arrange(desc(retirement_rate))

  cat("\n📊 SUBSPECIALTY RETIREMENT RATES (Comprehensive Analysis):\n")
  for(i in 1:nrow(subspecialty_rates)) {
    row <- subspecialty_rates[i,]
    cat(sprintf("   • %s:\n", row$subspecialty_name))
    cat(sprintf("     - Total physicians: %d\n", row$total_physicians))
    cat(sprintf("     - Retired physicians: %d\n", row$retired_physicians))
    cat(sprintf("     - Retirement rate: %.2f%% (%.3f annually)\n",
               row$retirement_rate * 100, row$annual_retirement_rate))
    cat("\n")
  }

  # Age-stratified rates by subspecialty
  cat("📈 AGE-STRATIFIED RETIREMENT RATES:\n")
  age_subspecialty_rates <- cohort_data %>%
    filter(!is.na(age_band)) %>%
    group_by(subspecialty_name, age_band) %>%
    summarise(
      n_physicians = n(),
      n_retired = sum(retired_binary, na.rm = TRUE),
      rate = n_retired / n_physicians,
      .groups = "drop"
    ) %>%
    filter(n_physicians >= 10)  # Only show age bands with sufficient sample

  for(subspecialty in unique(age_subspecialty_rates$subspecialty_name)) {
    cat(sprintf("\n   %s:\n", subspecialty))
    subset_data <- age_subspecialty_rates %>% filter(subspecialty_name == subspecialty)
    for(j in 1:nrow(subset_data)) {
      row <- subset_data[j,]
      cat(sprintf("     • %s: %.1f%% (%d/%d physicians)\n",
                 row$age_band, row$rate * 100, row$n_retired, row$n_physicians))
    }
  }

} else {
  cat("   ⚠️ Hazard model results not found\n")
}

# 2. Load 7-source retirement detection results
cat("\n\n2. 7-SOURCE RETIREMENT DETECTION (4 States: CO, IL, WA, FL):\n")
seven_source_file <- "real_7source_retirement_results_20250928_053733.csv"
if (file.exists(seven_source_file)) {
  seven_source_data <- readr::read_csv(seven_source_file, show_col_types = FALSE)

  cat(sprintf("   • Total physicians analyzed: %d\n", nrow(seven_source_data)))

  # Get subspecialty data by connecting to Medicare data
  conn <- DBI::dbConnect(duckdb::duckdb(), dbdir = "/Volumes/MufflySamsung/nber_my_duckdb.duckdb")

  medicare_subspecialty <- DBI::dbGetQuery(conn, "
    SELECT DISTINCT printf('%010d', CAST(PRSCRBR_NPI AS BIGINT)) as npi,
           Prscrbr_Type as specialty
    FROM MUP_DPR_RY23_P04_V10_DY21_NPI_csv_9
    WHERE Prscrbr_Type IN ('Obstetrics & Gynecology', 'Gynecological Oncology')
      AND Prscrbr_State_Abrvtn IN ('CO', 'IL', 'WA', 'FL')
      AND PRSCRBR_NPI IS NOT NULL
  ")

  DBI::dbDisconnect(conn)

  # Merge with 7-source results
  seven_source_with_specialty <- seven_source_data %>%
    left_join(medicare_subspecialty, by = "npi") %>%
    filter(!is.na(specialty))

  seven_source_rates <- seven_source_with_specialty %>%
    group_by(specialty) %>%
    summarise(
      total_physicians = n(),
      retired_physicians = sum(enhanced_retired, na.rm = TRUE),
      retirement_rate = retired_physicians / total_physicians,
      avg_confidence = mean(enhanced_confidence[enhanced_retired], na.rm = TRUE),
      license_data_available = sum(!is.na(license_confidence) & license_confidence > 0),
      license_retirement_cases = sum(license_retirement_indicator, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(desc(retirement_rate))

  cat("\n📊 SUBSPECIALTY RETIREMENT RATES (7-Source System):\n")
  for(i in 1:nrow(seven_source_rates)) {
    row <- seven_source_rates[i,]
    cat(sprintf("   • %s:\n", row$specialty))
    cat(sprintf("     - Total physicians: %d\n", row$total_physicians))
    cat(sprintf("     - Retired physicians: %d\n", row$retired_physicians))
    cat(sprintf("     - Retirement rate: %.2f%%\n", row$retirement_rate * 100))
    cat(sprintf("     - Average confidence: %.3f\n", row$avg_confidence))
    cat(sprintf("     - License data available: %d physicians\n", row$license_data_available))
    cat(sprintf("     - License-based retirement: %d cases\n", row$license_retirement_cases))
    cat("\n")
  }

} else {
  cat("   ⚠️ 7-source results not found\n")
}

# 3. Load Monte Carlo projection results for future retirement rates
cat("\n3. PROJECTED RETIREMENT RATES (2025-2030):\n")
projection_files <- list.files("results", pattern = "workforce_projection_data_.*\\.csv", full.names = TRUE)
if (length(projection_files) > 0) {
  latest_projection <- projection_files[which.max(file.mtime(projection_files))]
  projection_data <- readr::read_csv(latest_projection, show_col_types = FALSE)

  cat(sprintf("   Using: %s\n", basename(latest_projection)))

  # Calculate annual retirement rates from projections
  annual_rates <- projection_data %>%
    filter(year %in% c(2025, 2030)) %>%
    group_by(subspecialty) %>%
    summarise(
      workforce_2025 = median(workforce[year == 2025], na.rm = TRUE),
      workforce_2030 = median(workforce[year == 2030], na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      total_loss = workforce_2025 - workforce_2030,
      total_loss_rate = total_loss / workforce_2025,
      annual_retirement_rate = 1 - (workforce_2030 / workforce_2025)^(1/5),  # Compound annual rate
      annual_retirement_pct = annual_retirement_rate * 100
    ) %>%
    arrange(desc(annual_retirement_rate))

  cat("\n📈 PROJECTED ANNUAL RETIREMENT RATES (2025-2030):\n")
  for(i in 1:nrow(annual_rates)) {
    row <- annual_rates[i,]
    cat(sprintf("   • %s:\n", row$subspecialty))
    cat(sprintf("     - 2025 workforce: %.0f physicians\n", row$workforce_2025))
    cat(sprintf("     - 2030 workforce: %.0f physicians\n", row$workforce_2030))
    cat(sprintf("     - Total loss: %.0f physicians (%.1f%%)\n", row$total_loss, row$total_loss_rate * 100))
    cat(sprintf("     - Annual retirement rate: %.2f%%\n", row$annual_retirement_pct))
    cat("\n")
  }

} else {
  cat("   ⚠️ Projection data not found\n")
}

# 4. Summary comparison
cat("\n📋 RETIREMENT RATE SUMMARY COMPARISON:\n")
cat("═══════════════════════════════════════════\n")
cat("Method                    | Data Scope           | Key Finding\n")
cat("──────────────────────────────────────────────────────────────\n")
cat("Comprehensive Analysis    | Nationwide (3,627)   | Empirical rates by age/subspecialty\n")
cat("7-Source Detection        | 4 States (4,827)     | Real license validation\n")
cat("Monte Carlo Projections   | Nationwide (2025-30) | Future workforce impact\n")
cat("═══════════════════════════════════════════\n")

cat("\n🎯 Analysis complete! See subspecialty-specific retirement rates above.\n")
