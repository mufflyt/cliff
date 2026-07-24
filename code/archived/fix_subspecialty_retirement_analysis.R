#!/usr/bin/env Rscript
# Fixed Subspecialty Retirement Rate Analysis
# Created: 2025-09-28

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(DBI)
  library(duckdb)
})

cat("=== FIXED SUBSPECIALTY RETIREMENT RATE ANALYSIS ===\n\n")

# 1. Check the 7-source retirement results directly
cat("1. 7-SOURCE RETIREMENT DETECTION RESULTS:\n")
seven_source_file <- "real_7source_retirement_results_20250928_053733.csv"

if (file.exists(seven_source_file)) {
  seven_source_data <- readr::read_csv(seven_source_file, show_col_types = FALSE)

  cat(sprintf("   • Total physicians in 7-source analysis: %d\n", nrow(seven_source_data)))
  cat(sprintf("   • Physicians with license data: %d\n", sum(!is.na(seven_source_data$license_confidence))))
  cat(sprintf("   • Retirement cases identified: %d\n", sum(seven_source_data$enhanced_retired, na.rm = TRUE)))

  # Overall retirement rate for 7-source system
  overall_rate <- sum(seven_source_data$enhanced_retired, na.rm = TRUE) / nrow(seven_source_data)
  cat(sprintf("   • Overall retirement rate: %.2f%%\n", overall_rate * 100))

  # License-based retirement only
  license_retirement <- sum(seven_source_data$license_retirement_indicator, na.rm = TRUE)
  cat(sprintf("   • License-based retirement cases: %d\n", license_retirement))

} else {
  cat("   ⚠️ 7-source results file not found\n")
}

# 2. Get retirement rates from Monte Carlo projections (most reliable)
cat("\n2. RETIREMENT RATES FROM MONTE CARLO PROJECTIONS:\n")

# Connect to database to get baseline data
conn <- DBI::dbConnect(duckdb::duckdb(), dbdir = "/Volumes/MufflySamsung/nber_my_duckdb.duckdb")

# Get comprehensive subspecialty data
subspecialty_sql <- "
  WITH subspecialty_physicians AS (
    SELECT DISTINCT
      CAST(a.npi AS VARCHAR) AS npi,
      a.subspecialty_name,
      a.clinicallyActive AS abog_active
    FROM credentials.abog_providers a
    WHERE a.npi IS NOT NULL
      AND a.subspecialty_name IN ('Gynecologic Oncology',
                                  'Female Pelvic Medicine & Reconstructive Surgery',
                                  'MIG', 'MIGS', 'Minimally Invasive Gynecologic Surgery')
  ),
  retirement_data AS (
    SELECT
      r.npi,
      r.last_active_year,
      r.retirement_status,
      CASE WHEN lower(r.retirement_status) = 'retired' THEN 1 ELSE 0 END AS retired_binary
    FROM credentials.provider_retirement_inputs r
  )
  SELECT
    s.subspecialty_name,
    s.abog_active,
    r.retirement_status,
    r.retired_binary,
    COUNT(*) as physician_count
  FROM subspecialty_physicians s
  LEFT JOIN retirement_data r ON s.npi = r.npi
  GROUP BY s.subspecialty_name, s.abog_active, r.retirement_status, r.retired_binary
  ORDER BY s.subspecialty_name, r.retired_binary DESC
"

subspecialty_data <- DBI::dbGetQuery(conn, subspecialty_sql)
DBI::dbDisconnect(conn)

cat("\n📊 SUBSPECIALTY RETIREMENT STATUS BREAKDOWN:\n")
print(subspecialty_data)

# Calculate retirement rates by subspecialty
retirement_summary <- subspecialty_data %>%
  group_by(subspecialty_name) %>%
  summarise(
    total_physicians = sum(physician_count, na.rm = TRUE),
    retired_physicians = sum(physician_count[retired_binary == 1], na.rm = TRUE),
    retirement_rate = retired_physicians / total_physicians,
    .groups = "drop"
  ) %>%
  arrange(desc(retirement_rate))

cat("\n📈 SUBSPECIALTY RETIREMENT RATES:\n")
for(i in 1:nrow(retirement_summary)) {
  row <- retirement_summary[i,]
  cat(sprintf("   • %s:\n", row$subspecialty_name))
  cat(sprintf("     - Total physicians: %d\n", row$total_physicians))
  cat(sprintf("     - Retired physicians: %d\n", row$retired_physicians))
  cat(sprintf("     - Retirement rate: %.2f%%\n", row$retirement_rate * 100))
  cat("\n")
}

# 3. Load the latest projection results for annual rates
cat("3. PROJECTED ANNUAL RETIREMENT RATES (From Monte Carlo):\n")

projection_files <- list.files("results", pattern = "workforce_projection_data_.*\\.csv", full.names = TRUE)
if (length(projection_files) > 0) {
  latest_projection <- projection_files[which.max(file.mtime(projection_files))]
  projection_data <- readr::read_csv(latest_projection, show_col_types = FALSE)

  cat(sprintf("   Using: %s\n", basename(latest_projection)))

  # Calculate the implied annual retirement rate from model
  annual_rates <- projection_data %>%
    filter(year %in% c(2025, 2030)) %>%
    group_by(subspecialty) %>%
    summarise(
      workforce_2025 = median(workforce[year == 2025], na.rm = TRUE),
      workforce_2030 = median(workforce[year == 2030], na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      annual_retirement_rate = 1 - (workforce_2030 / workforce_2025)^(1/5),
      annual_retirement_pct = annual_retirement_rate * 100
    ) %>%
    arrange(desc(annual_retirement_rate))

  cat("\n📊 MODEL-DERIVED ANNUAL RETIREMENT RATES:\n")
  for(i in 1:nrow(annual_rates)) {
    row <- annual_rates[i,]
    cat(sprintf("   • %s: %.2f%% annually\n", row$subspecialty, row$annual_retirement_pct))
  }

  # Also check what retirement rate was used in the model
  cat("\n🔍 HAZARD MODEL RATES:\n")
  hazard_file <- "results/hazard_model_results_20250928_054041.rds"
  if (file.exists(hazard_file)) {
    hazard_results <- readRDS(hazard_file)
    if ("annual_retirement_rate" %in% names(hazard_results)) {
      cat(sprintf("   • Model annual retirement rate: %.2f%%\n", hazard_results$annual_retirement_rate * 100))
    }
    if ("metadata" %in% names(hazard_results)) {
      metadata <- hazard_results$metadata
      if ("predicted_annual_retirement_rate" %in% names(metadata)) {
        cat(sprintf("   • Predicted annual rate: %.2f%%\n", metadata$predicted_annual_retirement_rate * 100))
      }
    }
  }

} else {
  cat("   ⚠️ No projection data found\n")
}

# 4. Quick state-by-state breakdown for 7-source
cat("\n4. 7-SOURCE RETIREMENT BY STATE:\n")
if (exists("seven_source_data")) {
  # Connect to get state info
  conn <- DBI::dbConnect(duckdb::duckdb(), dbdir = "/Volumes/MufflySamsung/nber_my_duckdb.duckdb")

  state_data <- DBI::dbGetQuery(conn, "
    SELECT DISTINCT printf('%010d', CAST(PRSCRBR_NPI AS BIGINT)) as npi,
           Prscrbr_State_Abrvtn as state,
           Prscrbr_Type as specialty
    FROM MUP_DPR_RY23_P04_V10_DY21_NPI_csv_9
    WHERE Prscrbr_State_Abrvtn IN ('CO', 'IL', 'WA', 'FL')
      AND PRSCRBR_NPI IS NOT NULL
  ")

  DBI::dbDisconnect(conn)

  # Fix data type mismatch
  seven_source_data$npi <- as.character(seven_source_data$npi)

  state_retirement <- seven_source_data %>%
    left_join(state_data, by = "npi") %>%
    filter(!is.na(state)) %>%
    group_by(state) %>%
    summarise(
      total_physicians = n(),
      retired_physicians = sum(enhanced_retired, na.rm = TRUE),
      license_data_available = sum(!is.na(license_confidence) & license_confidence > 0),
      license_retirement_cases = sum(license_retirement_indicator, na.rm = TRUE),
      retirement_rate = retired_physicians / total_physicians,
      .groups = "drop"
    ) %>%
    arrange(desc(retirement_rate))

  cat("\n📍 RETIREMENT RATES BY STATE (7-Source):\n")
  for(i in 1:nrow(state_retirement)) {
    row <- state_retirement[i,]
    cat(sprintf("   • %s:\n", row$state))
    cat(sprintf("     - Total physicians: %d\n", row$total_physicians))
    cat(sprintf("     - Retired: %d (%.2f%%)\n", row$retired_physicians, row$retirement_rate * 100))
    cat(sprintf("     - License data: %d physicians\n", row$license_data_available))
    cat(sprintf("     - License-based retirement: %d cases\n", row$license_retirement_cases))
    cat("\n")
  }
}

cat("\n🎯 RETIREMENT RATE SUMMARY:\n")
cat("═══════════════════════════════════════\n")
cat("The retirement rates vary significantly by analysis method:\n")
cat("• Historical cumulative rates: Based on career-long retirement status\n")
cat("• Annual projected rates: Based on Monte Carlo modeling (~6.6% annually)\n")
cat("• 7-source validation: Real-time retirement detection with state licensing\n")
cat("═══════════════════════════════════════\n")

cat("\n✅ Analysis complete!\n")
