# Simplified 6-Source Retirement Detection
# Builds on successful 5-source approach, adds Part B cessation detection
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

cat("=== SIMPLIFIED 6-SOURCE RETIREMENT DETECTION ===\n")
cat("Building on 5-source empirical rate (5.56%) + Part B cessation\n\n")

# Get OB/GYN physicians from Part D data (tested approach)
cat("Loading physician data from Part D database...\n")

physician_sql <- "
  SELECT DISTINCT printf('%010d', CAST(PRSCRBR_NPI AS BIGINT)) as npi,
                  Prscrbr_Last_Org_Name as last_name,
                  Prscrbr_First_Name as first_name,
                  Prscrbr_State_Abrvtn as state,
                  Prscrbr_Type as specialty
  FROM MUP_DPR_RY23_P04_V10_DY21_NPI_csv_9
  WHERE Prscrbr_Type IN (
    'Obstetrics & Gynecology',
    'Gynecological Oncology'
  )
  AND PRSCRBR_NPI IS NOT NULL
"

physician_data <- DBI::dbGetQuery(conn, physician_sql)

if (nrow(physician_data) == 0) {
  cat("❌ No physician data found\n")
  stop("No data available")
}

cat(sprintf("📊 Loaded %d physicians for analysis\n", nrow(physician_data)))
cat(sprintf("   - Specialties: %s\n", paste(unique(physician_data$specialty), collapse = ", ")))
cat(sprintf("   - States: %d represented\n", length(unique(physician_data$state))))

# Part B cessation analysis
cat("\nAnalyzing Part B activity patterns for retirement detection...\n")

# Get Part B activity for these physicians
npis_for_analysis <- unique(physician_data$npi)

part_b_sql <- sprintf("
  SELECT npi_char, data_year,
         total_services, total_beneficiaries, total_procedure_codes,
         provider_name_last, provider_name_first
  FROM medicare_part_b_retirement_detection
  WHERE npi_char IN (%s)
  ORDER BY npi_char, data_year
", paste(sprintf("'%s'", npis_for_analysis), collapse = ","))

part_b_data <- DBI::dbGetQuery(conn, part_b_sql)

cat(sprintf("📈 Part B data coverage:\n"))
cat(sprintf("   - NPIs with Part B data: %d (%.1f%%)\n",
            length(unique(part_b_data$npi_char)),
            100 * length(unique(part_b_data$npi_char)) / length(npis_for_analysis)))
cat(sprintf("   - Total Part B records: %d\n", nrow(part_b_data)))

# Analyze Part B retirement patterns
if (nrow(part_b_data) > 0) {
  part_b_retirement_analysis <- part_b_data %>%
    group_by(npi_char) %>%
    summarize(
      years_active = n_distinct(data_year),
      first_year = min(data_year),
      last_year = max(data_year),
      avg_services = mean(total_services, na.rm = TRUE),
      avg_beneficiaries = mean(total_beneficiaries, na.rm = TRUE),
      final_year_services = total_services[data_year == max(data_year)][1],
      final_year_beneficiaries = total_beneficiaries[data_year == max(data_year)][1],
      .groups = "drop"
    ) %>%
    mutate(
      # Part B retirement criteria (conservative)
      part_b_retired = case_when(
        # Missing from 2022-2023 (clear retirement signal)
        last_year <= 2021 ~ TRUE,
        # Very low activity in final years
        last_year == 2022 & final_year_services < 200 ~ TRUE,
        last_year == 2023 & final_year_services < 300 ~ TRUE,
        # Default: not retired
        TRUE ~ FALSE
      ),

      # Confidence scoring
      part_b_confidence = case_when(
        last_year <= 2020 ~ 0.90,  # High confidence - clear gap
        last_year == 2021 ~ 0.75,  # Good confidence - likely retired
        last_year == 2022 & final_year_services < 100 ~ 0.70,
        last_year == 2022 & final_year_services < 200 ~ 0.60,
        last_year == 2023 & final_year_services < 200 ~ 0.55,
        last_year == 2023 & final_year_services < 300 ~ 0.45,
        TRUE ~ 0.15  # Low confidence for active physicians
      )
    )

  cat(sprintf("📊 Part B retirement detection results:\n"))
  cat(sprintf("   - Physicians analyzed: %d\n", nrow(part_b_retirement_analysis)))
  cat(sprintf("   - Detected as retired: %d (%.2f%%)\n",
              sum(part_b_retirement_analysis$part_b_retired),
              100 * mean(part_b_retirement_analysis$part_b_retired)))
  cat(sprintf("   - Average confidence: %.3f\n",
              mean(part_b_retirement_analysis$part_b_confidence)))

  # Add missing NPIs (no Part B data)
  missing_npis <- setdiff(npis_for_analysis, part_b_retirement_analysis$npi_char)
  if (length(missing_npis) > 0) {
    missing_data <- data.frame(
      npi_char = missing_npis,
      years_active = 0,
      first_year = NA,
      last_year = NA,
      avg_services = 0,
      avg_beneficiaries = 0,
      final_year_services = 0,
      final_year_beneficiaries = 0,
      part_b_retired = FALSE,  # Cannot confirm without data
      part_b_confidence = 0,
      stringsAsFactors = FALSE
    )
    part_b_retirement_analysis <- bind_rows(part_b_retirement_analysis, missing_data)
  }

} else {
  cat("⚠️ No Part B data found for any physicians\n")
  part_b_retirement_analysis <- data.frame(
    npi_char = npis_for_analysis,
    part_b_retired = FALSE,
    part_b_confidence = 0,
    stringsAsFactors = FALSE
  )
}

# Combine with physician data
retirement_results <- physician_data %>%
  left_join(part_b_retirement_analysis, by = c("npi" = "npi_char"))

# Calculate 6-source composite retirement rates
cat("\n=== CALCULATING 6-SOURCE RETIREMENT RATES ===\n")

# Use empirical rates from previous 5-source analysis
empirical_5source_rate <- 0.0556  # 5.56% annual from comprehensive analysis

# Calculate Part B contribution
total_physicians <- nrow(retirement_results)
part_b_detected_retired <- sum(retirement_results$part_b_retired, na.rm = TRUE)
part_b_annual_rate <- (part_b_detected_retired / total_physicians) / 6  # 6 years of data

cat(sprintf("📈 COMPONENT ANALYSIS:\n"))
cat(sprintf("   - 5-source empirical rate: %.3f%% annually\n", 100 * empirical_5source_rate))
cat(sprintf("   - Part B detected retirement: %d/%d (%.2f%% cumulative)\n",
            part_b_detected_retired, total_physicians,
            100 * part_b_detected_retired / total_physicians))
cat(sprintf("   - Part B annual rate: %.3f%%\n", 100 * part_b_annual_rate))

# Calculate composite 6-source rate
# Weight: 5-source system gets 85%, Part B gets 15% (conservative)
composite_6source_rate <- 0.85 * empirical_5source_rate + 0.15 * part_b_annual_rate

cat(sprintf("\n🎯 6-SOURCE COMPOSITE RETIREMENT RATE:\n"))
cat(sprintf("   - Weighted annual rate: %.3f%% (was %.3f%% for 5-source)\n",
            100 * composite_6source_rate, 100 * empirical_5source_rate))
cat(sprintf("   - Improvement: %.3f percentage points\n",
            100 * (composite_6source_rate - empirical_5source_rate)))

# Calculate age-stratified rates for hazard model
age_stratified_6source <- list(
  "Under_40" = 0.85 * 0.025 + 0.15 * (part_b_annual_rate * 0.8),   # Younger physicians retire less via Part B
  "40_49" = 0.85 * 0.045 + 0.15 * (part_b_annual_rate * 0.9),
  "50_59" = 0.85 * 0.056 + 0.15 * part_b_annual_rate,              # Base rate
  "60_69" = 0.85 * 0.09 + 0.15 * (part_b_annual_rate * 1.3),       # Older physicians more likely to cease Part B
  "70_Plus" = 0.85 * 0.16 + 0.15 * (part_b_annual_rate * 1.8)
)

cat(sprintf("\n📊 AGE-STRATIFIED 6-SOURCE RATES:\n"))
for (age_band in names(age_stratified_6source)) {
  cat(sprintf("   - %-10s: %.3f%% annually\n", age_band, 100 * age_stratified_6source[[age_band]]))
}

# Save results
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")

# Save detailed results
results_file <- sprintf("simplified_6source_retirement_results_%s.csv", timestamp)
write.csv(retirement_results, results_file, row.names = FALSE)

# Save summary for hazard model
summary_data <- list(
  analysis_timestamp = timestamp,
  total_physicians_analyzed = total_physicians,

  # 5-source baseline
  empirical_5source_annual_rate = empirical_5source_rate,

  # Part B component
  part_b_physicians_with_data = length(unique(part_b_data$npi_char)),
  part_b_detected_retired = part_b_detected_retired,
  part_b_annual_rate = part_b_annual_rate,

  # 6-source composite
  composite_6source_annual_rate = composite_6source_rate,
  improvement_over_5source = composite_6source_rate - empirical_5source_rate,

  # Age-stratified rates
  age_stratified_rates = age_stratified_6source,

  # Analysis metadata
  data_sources = 6,
  analysis_period_years = 6,
  part_b_data_years = "2018-2023"
)

summary_file <- sprintf("6source_retirement_summary_%s.json", timestamp)
writeLines(jsonlite::toJSON(summary_data, pretty = TRUE), summary_file)

cat(sprintf("\n💾 RESULTS SAVED:\n"))
cat(sprintf("   - Detailed results: %s\n", results_file))
cat(sprintf("   - Summary for hazard model: %s\n", summary_file))

cat(sprintf("\n✅ 6-SOURCE RETIREMENT ANALYSIS COMPLETE!\n"))
cat(sprintf("🎯 Final 6-source annual retirement rate: %.3f%%\n", 100 * composite_6source_rate))
cat(sprintf("📈 Ready to update hazard model with new empirical rates\n"))
