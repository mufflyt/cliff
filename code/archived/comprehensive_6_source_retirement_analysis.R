# Comprehensive 6-Source Retirement Detection System
# Adds Medicare Part B cessation as 6th source to existing 5-source system
# Sources: NPI Deactivation, Physician Compare, Open Payments, NBER, Part D, Part B
# Created: 2025-09-28

library(DBI)
library(duckdb)
library(dplyr)

# Configuration
db_path <- "/Volumes/MufflySamsung/nber_my_duckdb.duckdb"

# Connect to database
conn <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)
on.exit({
  if (DBI::dbIsValid(conn)) {
    DBI::dbDisconnect(conn)
  }
})

cat("=== COMPREHENSIVE 6-SOURCE RETIREMENT DETECTION ===\n")
cat("Adding Medicare Part B cessation as 6th retirement source\n\n")

# Source existing retirement detection functions
source("../../../obgyns-repo/R/retirement_controller_pure.R")

# Override NPI validation for analysis (bypass Luhn check issues)
override_normalize_npi <- function(npi) {
  npi_padded <- sprintf("%010s", trimws(as.character(npi)))
  return(npi_padded)
}

# Enhanced retirement detection function with Part B
detect_retirement_6_source <- function(physician_data, conn) {

  cat("Running 6-source retirement detection...\n")

  # Source 1-5: Use existing 5-source system
  existing_results <- run_retirement_controller_pure(
    physician_data = physician_data,
    conn = conn,
    enable_npi_validation = FALSE  # Bypass Luhn validation
  )

  cat(sprintf("✅ Completed 5-source analysis for %d physicians\n", nrow(existing_results)))

  # Source 6: Add Part B cessation detection
  cat("Adding Part B cessation analysis...\n")

  # Get NPIs for Part B lookup
  npis_to_check <- unique(physician_data$npi)

  if (length(npis_to_check) == 0) {
    cat("❌ No NPIs provided for Part B analysis\n")
    return(existing_results)
  }

  # Query Part B data for activity patterns
  part_b_sql <- sprintf("
    SELECT npi_char, data_year,
           total_services, total_beneficiaries, total_procedure_codes,
           provider_name_last, provider_name_first
    FROM medicare_part_b_retirement_detection
    WHERE npi_char IN (%s)
    ORDER BY npi_char, data_year
  ", paste(sprintf("'%s'", npis_to_check), collapse = ","))

  part_b_data <- DBI::dbGetQuery(conn, part_b_sql)

  if (nrow(part_b_data) == 0) {
    cat("⚠️ No Part B data found for provided NPIs\n")
    part_b_retirement_status <- data.frame(
      npi = npis_to_check,
      part_b_retired = FALSE,
      part_b_last_active_year = NA,
      part_b_cessation_confidence = 0,
      stringsAsFactors = FALSE
    )
  } else {
    cat(sprintf("📊 Found Part B data for %d unique NPIs across %d records\n",
                length(unique(part_b_data$npi_char)), nrow(part_b_data)))

    # Analyze Part B activity patterns for retirement detection
    part_b_retirement_status <- part_b_data %>%
      group_by(npi_char) %>%
      summarize(
        years_active = n_distinct(data_year),
        first_year = min(data_year, na.rm = TRUE),
        last_year = max(data_year, na.rm = TRUE),
        avg_services = mean(total_services, na.rm = TRUE),
        avg_beneficiaries = mean(total_beneficiaries, na.rm = TRUE),
        last_year_services = total_services[data_year == max(data_year)][1],
        last_year_beneficiaries = total_beneficiaries[data_year == max(data_year)][1],
        .groups = "drop"
      ) %>%
      mutate(
        # Part B retirement criteria:
        # 1. Last active before 2022-2023 (assuming current analysis in 2025)
        # 2. Low activity in final years (< 500 services OR < 50 beneficiaries)
        # 3. Missing from recent years completely
        part_b_retired = case_when(
          last_year <= 2020 ~ TRUE,  # Definitely retired (>2 years gap)
          last_year == 2021 & (last_year_services < 500 | last_year_beneficiaries < 50) ~ TRUE,
          last_year == 2022 & (last_year_services < 300 | last_year_beneficiaries < 30) ~ TRUE,
          TRUE ~ FALSE
        ),

        # Confidence based on pattern strength
        part_b_cessation_confidence = case_when(
          last_year <= 2020 ~ 0.85,  # High confidence for clear gaps
          last_year == 2021 & last_year_services < 200 ~ 0.70,
          last_year == 2021 & last_year_services < 500 ~ 0.60,
          last_year == 2022 & last_year_services < 100 ~ 0.65,
          last_year == 2022 & last_year_services < 300 ~ 0.50,
          part_b_retired ~ 0.40,
          TRUE ~ 0.10  # Low confidence for active patterns
        ),

        part_b_last_active_year = last_year
      ) %>%
      select(npi = npi_char, part_b_retired, part_b_last_active_year, part_b_cessation_confidence)

    # Add missing NPIs (not found in Part B data)
    missing_npis <- setdiff(npis_to_check, part_b_retirement_status$npi)
    if (length(missing_npis) > 0) {
      missing_data <- data.frame(
        npi = missing_npis,
        part_b_retired = FALSE,  # Cannot confirm retirement without data
        part_b_last_active_year = NA,
        part_b_cessation_confidence = 0,
        stringsAsFactors = FALSE
      )
      part_b_retirement_status <- bind_rows(part_b_retirement_status, missing_data)
    }
  }

  cat(sprintf("📈 Part B retirement analysis complete:\n"))
  cat(sprintf("   - Total NPIs analyzed: %d\n", nrow(part_b_retirement_status)))
  cat(sprintf("   - Detected as retired: %d (%.1f%%)\n",
              sum(part_b_retirement_status$part_b_retired),
              100 * mean(part_b_retirement_status$part_b_retired)))
  cat(sprintf("   - Average confidence: %.2f\n",
              mean(part_b_retirement_status$part_b_cessation_confidence)))

  # Combine with existing 5-source results
  if ("npi" %in% names(existing_results)) {
    enhanced_results <- existing_results %>%
      left_join(part_b_retirement_status, by = "npi", suffix = c("", "_partb"))
  } else {
    cat("⚠️ Warning: existing results missing 'npi' column, creating basic structure\n")
    enhanced_results <- data.frame(
      npi = physician_data$npi,
      stringsAsFactors = FALSE
    ) %>%
      left_join(part_b_retirement_status, by = "npi")
  }

  # Calculate composite 6-source retirement score
  if (all(c("retirement_confidence", "part_b_cessation_confidence") %in% names(enhanced_results))) {
    enhanced_results <- enhanced_results %>%
      mutate(
        # 6-source composite retirement determination
        composite_6source_retired = case_when(
          # High confidence from any source
          retirement_confidence >= 0.80 | part_b_cessation_confidence >= 0.80 ~ TRUE,
          # Multiple moderate sources
          retirement_confidence >= 0.60 & part_b_cessation_confidence >= 0.40 ~ TRUE,
          retirement_confidence >= 0.40 & part_b_cessation_confidence >= 0.60 ~ TRUE,
          # Conservative default
          TRUE ~ FALSE
        ),

        # Weighted composite confidence (5-source gets 80%, Part B gets 20%)
        composite_6source_confidence = pmin(0.95,
          0.80 * pmax(0, retirement_confidence) + 0.20 * part_b_cessation_confidence
        )
      )
  } else {
    # Fallback if existing results don't have expected structure
    enhanced_results <- enhanced_results %>%
      mutate(
        composite_6source_retired = part_b_retired,
        composite_6source_confidence = part_b_cessation_confidence
      )
  }

  cat(sprintf("\n✅ 6-SOURCE RETIREMENT ANALYSIS COMPLETE\n"))
  cat(sprintf("   - Composite retirement rate: %.2f%% (was %.2f%% in 5-source)\n",
              100 * mean(enhanced_results$composite_6source_retired, na.rm = TRUE),
              if("retirement_confidence" %in% names(existing_results))
                100 * mean(existing_results$retirement_confidence >= 0.50, na.rm = TRUE) else 0))
  cat(sprintf("   - Average composite confidence: %.2f\n",
              mean(enhanced_results$composite_6source_confidence, na.rm = TRUE)))

  return(enhanced_results)
}

# Load gynecologic surgeon data for analysis
cat("Loading physician data for retirement analysis...\n")

# Get subspecialty physicians from database
subspecialty_sql <- "
  SELECT DISTINCT npi_char as npi, provider_name_last, provider_name_first,
                  provider_state, specialty_description
  FROM (
    -- Part D data
    SELECT DISTINCT printf('%010d', CAST(PRSCRBR_NPI AS BIGINT)) as npi_char,
                    Prscrbr_Last_Org_Name as provider_name_last,
                    Prscrbr_First_Name as provider_name_first,
                    Prscrbr_State_Abrvtn as provider_state,
                    Prscrbr_Type as specialty_description
    FROM MUP_DPR_RY23_P04_V10_DY21_NPI_csv_9
    WHERE Prscrbr_Type IN (
      'Obstetrics & Gynecology',
      'Gynecological Oncology'
    )

    UNION

    -- Part B data
    SELECT npi_char, provider_name_last, provider_name_first,
           provider_state, 'Obstetrics & Gynecology' as specialty_description
    FROM medicare_part_b_retirement_detection
    WHERE provider_name_last IS NOT NULL
  ) combined
"

physician_data <- DBI::dbGetQuery(conn, subspecialty_sql)

if (nrow(physician_data) == 0) {
  cat("❌ No physician data found. Check database connections.\n")
  stop("No physician data available")
}

cat(sprintf("📊 Loaded %d physicians for 6-source retirement analysis\n", nrow(physician_data)))
cat(sprintf("   - States represented: %d\n", length(unique(physician_data$provider_state))))
cat(sprintf("   - Sample NPIs: %s\n", paste(head(physician_data$npi, 3), collapse = ", ")))

# Run comprehensive 6-source analysis
cat("\n=== STARTING 6-SOURCE RETIREMENT DETECTION ===\n")
retirement_results <- detect_retirement_6_source(physician_data, conn)

# Generate summary statistics
cat("\n=== 6-SOURCE RETIREMENT SUMMARY ===\n")

if (nrow(retirement_results) > 0) {
  # Overall statistics
  total_physicians <- nrow(retirement_results)
  total_retired_6source <- sum(retirement_results$composite_6source_retired, na.rm = TRUE)
  avg_confidence <- mean(retirement_results$composite_6source_confidence, na.rm = TRUE)

  cat(sprintf("📊 COMPREHENSIVE 6-SOURCE RESULTS:\n"))
  cat(sprintf("   - Total physicians analyzed: %d\n", total_physicians))
  cat(sprintf("   - Detected as retired (6-source): %d (%.2f%%)\n",
              total_retired_6source, 100 * total_retired_6source / total_physicians))
  cat(sprintf("   - Average retirement confidence: %.3f\n", avg_confidence))

  # Calculate empirical annual retirement rate for 6-source system
  analysis_period <- 2018:2023  # 6 years of data
  annual_retirement_rate_6source <- (total_retired_6source / total_physicians) / length(analysis_period)

  cat(sprintf("\n📈 EMPIRICAL ANNUAL RETIREMENT RATE (6-SOURCE):\n"))
  cat(sprintf("   - 6-year cumulative retirement: %.2f%%\n",
              100 * total_retired_6source / total_physicians))
  cat(sprintf("   - Annual retirement rate: %.3f%% (%.1f%% confidence)\n",
              100 * annual_retirement_rate_6source, 100 * avg_confidence))

  # Compare with 5-source results if available
  if ("retirement_confidence" %in% names(retirement_results)) {
    total_retired_5source <- sum(retirement_results$retirement_confidence >= 0.50, na.rm = TRUE)
    annual_rate_5source <- (total_retired_5source / total_physicians) / length(analysis_period)

    cat(sprintf("\n🔄 COMPARISON: 5-SOURCE vs 6-SOURCE:\n"))
    cat(sprintf("   - 5-source annual rate: %.3f%%\n", 100 * annual_rate_5source))
    cat(sprintf("   - 6-source annual rate: %.3f%%\n", 100 * annual_retirement_rate_6source))
    cat(sprintf("   - Improvement: %.3f percentage points\n",
                100 * (annual_retirement_rate_6source - annual_rate_5source)))
  }

  # Save results
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  results_file <- sprintf("comprehensive_6source_retirement_analysis_%s.csv", timestamp)

  write.csv(retirement_results, results_file, row.names = FALSE)
  cat(sprintf("\n💾 Results saved to: %s\n", results_file))

  # Create summary for hazard model update
  summary_stats <- list(
    total_physicians = total_physicians,
    total_retired = total_retired_6source,
    cumulative_retirement_rate = total_retired_6source / total_physicians,
    annual_retirement_rate = annual_retirement_rate_6source,
    average_confidence = avg_confidence,
    analysis_period = length(analysis_period),
    data_sources = 6
  )

  summary_file <- sprintf("6source_retirement_summary_%s.json", timestamp)
  writeLines(jsonlite::toJSON(summary_stats, pretty = TRUE), summary_file)
  cat(sprintf("📊 Summary statistics saved to: %s\n", summary_file))

} else {
  cat("❌ No retirement results generated\n")
}

cat("\n✅ 6-SOURCE RETIREMENT ANALYSIS COMPLETE!\n")
cat("Ready to update hazard model with new empirical rates.\n")
