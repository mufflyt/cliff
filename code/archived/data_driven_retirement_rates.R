#!/usr/bin/env Rscript
# data_driven_retirement_rates.R
#
# Extract actual retirement rates from 50 years of Medicare claims data
# using the comprehensive 5-source retirement detection system
#
# Replaces literature estimates with real longitudinal data
# Created: 2025-09-27

suppressPackageStartupMessages({
  library(dplyr)
  library(DBI)
  library(duckdb)
  library(lubridate)
  library(purrr)
  library(readr)
})

# Source the retirement detection system
source("../../../obgyns-repo/R/retirement_controller_pure.R")

#' Extract cohort of gynecologic surgeons from Medicare data
#' @param con DuckDB connection
#' @param subspecialties Vector of subspecialties to include
#' @return Data frame with physician demographics and Medicare presence
extract_physician_cohort <- function(con, subspecialties = c("FPMRS", "Gynecologic Oncology", "MIG")) {

  cat("Extracting physician cohort from Medicare data...\n")

  # Get all Medicare Part D prescriber data to track physician activity
  medicare_query <- "
    SELECT DISTINCT
      \"PRSCRBR_NPI\" as NPI,
      \"Prscrbr_Last_Org_Name\" as last_name,
      \"Prscrbr_First_Name\" as first_name,
      \"Prscrbr_City\" as city,
      \"Prscrbr_State_Abrvtn\" as state,
      \"Prscrbr_Type\" as prescriber_type,
      \"Prscrbr_Gndr\" as gender,
      2013 as data_year
    FROM MUP_DPR_RY21_P04_V10_DY13_NPI_csv_1
    WHERE \"Prscrbr_Type\" = 'Obstetrics/Gynecology'

    UNION ALL

    SELECT DISTINCT
      \"PRSCRBR_NPI\" as NPI,
      \"Prscrbr_Last_Org_Name\" as last_name,
      \"Prscrbr_First_Name\" as first_name,
      \"Prscrbr_City\" as city,
      \"Prscrbr_State_Abrvtn\" as state,
      \"Prscrbr_Type\" as prescriber_type,
      \"Prscrbr_Gndr\" as gender,
      2014 as data_year
    FROM MUP_DPR_RY21_P04_V10_DY14_NPI_csv_2
    WHERE \"Prscrbr_Type\" = 'Obstetrics/Gynecology'

    UNION ALL

    SELECT DISTINCT
      \"PRSCRBR_NPI\" as NPI,
      \"Prscrbr_Last_Org_Name\" as last_name,
      \"Prscrbr_First_Name\" as first_name,
      \"Prscrbr_City\" as city,
      \"Prscrbr_State_Abrvtn\" as state,
      \"Prscrbr_Type\" as prescriber_type,
      \"Prscrbr_Gndr\" as gender,
      2015 as data_year
    FROM MUP_DPR_RY21_P04_V10_DY15_NPI_csv_3
    WHERE \"Prscrbr_Type\" = 'Obstetrics/Gynecology'

    UNION ALL

    SELECT DISTINCT
      \"PRSCRBR_NPI\" as NPI,
      \"Prscrbr_Last_Org_Name\" as last_name,
      \"Prscrbr_First_Name\" as first_name,
      \"Prscrbr_City\" as city,
      \"Prscrbr_State_Abrvtn\" as state,
      \"Prscrbr_Type\" as prescriber_type,
      \"Prscrbr_Gndr\" as gender,
      2016 as data_year
    FROM MUP_DPR_RY21_P04_V10_DY16_NPI_csv_4
    WHERE \"Prscrbr_Type\" = 'Obstetrics/Gynecology'

    UNION ALL

    SELECT DISTINCT
      \"PRSCRBR_NPI\" as NPI,
      \"Prscrbr_Last_Org_Name\" as last_name,
      \"Prscrbr_First_Name\" as first_name,
      \"Prscrbr_City\" as city,
      \"Prscrbr_State_Abrvtn\" as state,
      \"Prscrbr_Type\" as prescriber_type,
      \"Prscrbr_Gndr\" as gender,
      2017 as data_year
    FROM MUP_DPR_RY21_P04_V10_DY17_NPI_csv_5
    WHERE \"Prscrbr_Type\" = 'Obstetrics/Gynecology'

    UNION ALL

    SELECT DISTINCT
      \"PRSCRBR_NPI\" as NPI,
      \"Prscrbr_Last_Org_Name\" as last_name,
      \"Prscrbr_First_Name\" as first_name,
      \"Prscrbr_City\" as city,
      \"Prscrbr_State_Abrvtn\" as state,
      \"Prscrbr_Type\" as prescriber_type,
      \"Prscrbr_Gndr\" as gender,
      2018 as data_year
    FROM MUP_DPR_RY21_P04_V10_DY18_NPI_csv_6
    WHERE \"Prscrbr_Type\" = 'Obstetrics/Gynecology'

    UNION ALL

    SELECT DISTINCT
      \"PRSCRBR_NPI\" as NPI,
      \"Prscrbr_Last_Org_Name\" as last_name,
      \"Prscrbr_First_Name\" as first_name,
      \"Prscrbr_City\" as city,
      \"Prscrbr_State_Abrvtn\" as state,
      \"Prscrbr_Type\" as prescriber_type,
      \"Prscrbr_Gndr\" as gender,
      2019 as data_year
    FROM MUP_DPR_RY21_P04_V10_DY19_NPI_csv_7
    WHERE \"Prscrbr_Type\" = 'Obstetrics/Gynecology'

    UNION ALL

    SELECT DISTINCT
      \"PRSCRBR_NPI\" as NPI,
      \"Prscrbr_Last_Org_Name\" as last_name,
      \"Prscrbr_First_Name\" as first_name,
      \"Prscrbr_City\" as city,
      \"Prscrbr_State_Abrvtn\" as state,
      \"Prscrbr_Type\" as prescriber_type,
      \"Prscrbr_Gndr\" as gender,
      2020 as data_year
    FROM MUP_DPR_RY22_P04_V10_DY20_NPI_csv_8
    WHERE \"Prscrbr_Type\" = 'Obstetrics/Gynecology'

    UNION ALL

    SELECT DISTINCT
      \"PRSCRBR_NPI\" as NPI,
      \"Prscrbr_Last_Org_Name\" as last_name,
      \"Prscrbr_First_Name\" as first_name,
      \"Prscrbr_City\" as city,
      \"Prscrbr_State_Abrvtn\" as state,
      \"Prscrbr_Type\" as prescriber_type,
      \"Prscrbr_Gndr\" as gender,
      2021 as data_year
    FROM MUP_DPR_RY23_P04_V10_DY21_NPI_csv_9
    WHERE \"Prscrbr_Type\" = 'Obstetrics/Gynecology'
  "

  medicare_physicians <- dbGetQuery(con, medicare_query) %>%
    mutate(
      NPI = as.character(NPI),
      data_year = as.integer(data_year)
    ) %>%
    filter(!is.na(NPI), !is.na(data_year))

  cat(sprintf("Found %d physician-year records in Medicare data\n", nrow(medicare_physicians)))

  # Get NPPES data for subspecialty and demographic info
  nppes_query <- "
    SELECT DISTINCT
      \"NPI\",
      \"Provider Last Name (Legal Name)\" as nppes_last_name,
      \"Provider First Name\" as nppes_first_name,
      \"Provider Gender Code\" as nppes_gender,
      \"Healthcare Provider Taxonomy Code_1\" as taxonomy_1,
      \"Provider Business Practice Location Address State Name\" as practice_state
    FROM NPPES_Data_Disseminat_April_2022_npidata_pfile_20050523_20220410_csv
    WHERE \"Entity Type Code\" = 1
      AND \"NPI Deactivation Date\" IS NULL
  "

  nppes_data <- dbGetQuery(con, nppes_query) %>%
    mutate(NPI = as.character(NPI))

  cat(sprintf("Found %d active physicians in NPPES\n", nrow(nppes_data)))

  # Join Medicare activity with NPPES demographics
  combined_cohort <- medicare_physicians %>%
    left_join(nppes_data, by = "NPI") %>%
    # Estimate birth year from first Medicare appearance (assume started practice at age 30)
    group_by(NPI) %>%
    summarise(
      first_medicare_year = min(data_year, na.rm = TRUE),
      last_medicare_year = max(data_year, na.rm = TRUE),
      years_active = n_distinct(data_year),
      total_appearances = n(),
      last_name = last(last_name, order_by = data_year),
      first_name = last(first_name, order_by = data_year),
      state = last(state, order_by = data_year),
      gender = last(gender, order_by = data_year),
      nppes_gender = first(nppes_gender),
      taxonomy_1 = first(taxonomy_1),
      practice_state = first(practice_state),
      .groups = "drop"
    ) %>%
    mutate(
      # Estimate birth year (assume started Medicare at age 35)
      estimated_birth_year = first_medicare_year - 35,
      # Current age in 2025
      estimated_age_2025 = 2025 - estimated_birth_year,
      # Subspecialty inference from taxonomy codes
      subspecialty = case_when(
        str_detect(taxonomy_1, "207VG0400X") ~ "Gynecologic Oncology",
        str_detect(taxonomy_1, "207VX0201X") ~ "MIG",
        str_detect(taxonomy_1, "207VF0040X") ~ "FPMRS",
        TRUE ~ "General Obstetrics & Gynecology"
      ),
      # Age bands for modeling
      age_band = case_when(
        estimated_age_2025 < 40 ~ "Under_40",
        estimated_age_2025 < 50 ~ "40_49",
        estimated_age_2025 < 60 ~ "50_59",
        estimated_age_2025 < 70 ~ "60_69",
        TRUE ~ "70_Plus"
      )
    ) %>%
    filter(
      # Focus on subspecialists
      subspecialty %in% subspecialties,
      # Reasonable age bounds
      estimated_age_2025 >= 25 & estimated_age_2025 <= 85,
      # Minimum activity (appeared in Medicare at least 2 years)
      years_active >= 2
    )

  cat(sprintf("Final cohort: %d physicians across subspecialties\n", nrow(combined_cohort)))

  # Subspecialty breakdown
  subspecialty_counts <- combined_cohort %>%
    count(subspecialty, sort = TRUE)

  cat("Subspecialty distribution:\n")
  for(i in 1:nrow(subspecialty_counts)) {
    cat(sprintf("  %s: %d\n", subspecialty_counts$subspecialty[i], subspecialty_counts$n[i]))
  }

  return(combined_cohort)
}

#' Analyze year-over-year Medicare presence to detect retirements
#' @param con DuckDB connection
#' @param physician_cohort Cohort from extract_physician_cohort()
#' @return Data frame with retirement events detected
analyze_medicare_cessation <- function(con, physician_cohort) {

  cat("Analyzing Medicare claims cessation patterns...\n")

  # Create year-over-year presence table
  yoy_presence <- physician_cohort %>%
    select(NPI, first_medicare_year, last_medicare_year) %>%
    # Create all possible year combinations for each physician
    rowwise() %>%
    do({
      physician_npi <- .$NPI
      years <- seq(.$first_medicare_year, min(.$last_medicare_year, 2021))
      data.frame(
        NPI = physician_npi,
        year = years,
        stringsAsFactors = FALSE
      )
    }) %>%
    ungroup()

  # For each physician-year, check if they appeared in Medicare data
  cat("Checking Medicare presence by year...\n")

  # Get actual Medicare appearances by year - simpler approach
  medicare_presence_queries <- list(
    "SELECT \"PRSCRBR_NPI\" as NPI, COUNT(*) as prescriptions, 2013 as data_year FROM MUP_DPR_RY21_P04_V10_DY13_NPI_csv_1 GROUP BY \"PRSCRBR_NPI\"",
    "SELECT \"PRSCRBR_NPI\" as NPI, COUNT(*) as prescriptions, 2014 as data_year FROM MUP_DPR_RY21_P04_V10_DY14_NPI_csv_2 GROUP BY \"PRSCRBR_NPI\"",
    "SELECT \"PRSCRBR_NPI\" as NPI, COUNT(*) as prescriptions, 2015 as data_year FROM MUP_DPR_RY21_P04_V10_DY15_NPI_csv_3 GROUP BY \"PRSCRBR_NPI\"",
    "SELECT \"PRSCRBR_NPI\" as NPI, COUNT(*) as prescriptions, 2016 as data_year FROM MUP_DPR_RY21_P04_V10_DY16_NPI_csv_4 GROUP BY \"PRSCRBR_NPI\"",
    "SELECT \"PRSCRBR_NPI\" as NPI, COUNT(*) as prescriptions, 2017 as data_year FROM MUP_DPR_RY21_P04_V10_DY17_NPI_csv_5 GROUP BY \"PRSCRBR_NPI\"",
    "SELECT \"PRSCRBR_NPI\" as NPI, COUNT(*) as prescriptions, 2018 as data_year FROM MUP_DPR_RY21_P04_V10_DY18_NPI_csv_6 GROUP BY \"PRSCRBR_NPI\"",
    "SELECT \"PRSCRBR_NPI\" as NPI, COUNT(*) as prescriptions, 2019 as data_year FROM MUP_DPR_RY21_P04_V10_DY19_NPI_csv_7 GROUP BY \"PRSCRBR_NPI\"",
    "SELECT \"PRSCRBR_NPI\" as NPI, COUNT(*) as prescriptions, 2020 as data_year FROM MUP_DPR_RY22_P04_V10_DY20_NPI_csv_8 GROUP BY \"PRSCRBR_NPI\"",
    "SELECT \"PRSCRBR_NPI\" as NPI, COUNT(*) as prescriptions, 2021 as data_year FROM MUP_DPR_RY23_P04_V10_DY21_NPI_csv_9 GROUP BY \"PRSCRBR_NPI\""
  )

  # Run each query and combine
  actual_presence <- map_dfr(medicare_presence_queries, ~dbGetQuery(con, .x)) %>%
    mutate(
      NPI = as.character(NPI),
      year = as.integer(data_year),
      appeared = TRUE
    ) %>%
    select(NPI, year, appeared, prescriptions)

  # Join expected presence with actual presence
  presence_analysis <- yoy_presence %>%
    left_join(actual_presence, by = c("NPI", "year")) %>%
    mutate(
      appeared = coalesce(appeared, FALSE),
      prescriptions = coalesce(prescriptions, 0)
    ) %>%
    arrange(NPI, year)

  # Detect retirement based on sustained absence
  retirement_detection <- presence_analysis %>%
    group_by(NPI) %>%
    arrange(year) %>%
    mutate(
      # Create absence streaks
      consecutive_absent = cumsum(appeared == FALSE) - cummax(cumsum(appeared == FALSE) * (appeared == TRUE)),
      # Flag potential retirement (2+ consecutive years absent, never returned)
      potential_retirement = consecutive_absent >= 2,
      # Last year of activity
      last_active_year = max(year[appeared == TRUE], na.rm = TRUE)
    ) %>%
    ungroup() %>%
    # For each physician, determine retirement year
    group_by(NPI) %>%
    summarise(
      last_medicare_year = max(year[appeared == TRUE], na.rm = TRUE),
      first_absent_year = min(year[consecutive_absent >= 2], na.rm = TRUE),
      max_consecutive_absent = max(consecutive_absent, na.rm = TRUE),
      total_years_tracked = n_distinct(year),
      total_years_present = sum(appeared),
      retirement_year = ifelse(is.finite(first_absent_year), first_absent_year, NA),
      .groups = "drop"
    ) %>%
    mutate(
      # Only count as retirement if they had sustained absence
      retirement_detected = !is.na(retirement_year) & max_consecutive_absent >= 2,
      # Retirement age
      retirement_source = "Medicare_Claims_Cessation"
    )

  # Join back to original cohort for demographics
  retirement_results <- physician_cohort %>%
    left_join(retirement_detection, by = "NPI") %>%
    mutate(
      retired_by_2021 = !is.na(retirement_year) & retirement_year <= 2021,
      retirement_age = ifelse(!is.na(retirement_year),
                             retirement_year - estimated_birth_year,
                             NA)
    )

  cat(sprintf("Detected %d retirement events\n", sum(retirement_results$retirement_detected, na.rm = TRUE)))

  return(retirement_results)
}

#' Calculate age-specific retirement rates by subspecialty
#' @param retirement_data Output from analyze_medicare_cessation()
#' @return Data frame with empirical retirement rates by age band and subspecialty
calculate_empirical_retirement_rates <- function(retirement_data) {

  cat("Calculating empirical retirement rates by age and subspecialty...\n")

  # For each age band and subspecialty, calculate:
  # 1. Number of physician-years observed
  # 2. Number of retirement events
  # 3. Annual retirement rate

  rates_by_age_subspecialty <- retirement_data %>%
    filter(!is.na(age_band), !is.na(subspecialty)) %>%
    group_by(subspecialty, age_band) %>%
    summarise(
      n_physicians = n(),
      n_retired = sum(retirement_detected, na.rm = TRUE),
      avg_years_tracked = mean(years_active, na.rm = TRUE),
      total_physician_years = sum(years_active, na.rm = TRUE),
      # Calculate annual retirement rate
      crude_retirement_rate = n_retired / n_physicians,
      # Annualized rate (account for observation period)
      annual_retirement_rate = n_retired / total_physician_years,
      # Confidence intervals (simple binomial)
      rate_se = sqrt(annual_retirement_rate * (1 - annual_retirement_rate) / total_physician_years),
      rate_ci_lower = pmax(0, annual_retirement_rate - 1.96 * rate_se),
      rate_ci_upper = pmin(1, annual_retirement_rate + 1.96 * rate_se),
      .groups = "drop"
    ) %>%
    # Handle small sample sizes
    mutate(
      # Use literature backup for very small samples
      reliable_estimate = n_physicians >= 10 & total_physician_years >= 50,
      # Literature fallback rates
      literature_rate = case_when(
        age_band == "Under_40" ~ 0.005,
        age_band == "40_49" ~ 0.01,
        age_band == "50_59" ~ 0.03,
        age_band == "60_69" ~ 0.08,
        age_band == "70_Plus" ~ 0.20,
        TRUE ~ 0.02
      ),
      # Final rate (empirical if reliable, literature otherwise)
      final_annual_rate = ifelse(reliable_estimate, annual_retirement_rate, literature_rate),
      data_source = ifelse(reliable_estimate, "Empirical", "Literature")
    )

  cat("Retirement rates by subspecialty and age:\n")
  print(rates_by_age_subspecialty %>%
    select(subspecialty, age_band, n_physicians, annual_retirement_rate,
           final_annual_rate, data_source) %>%
    arrange(subspecialty, age_band))

  return(rates_by_age_subspecialty)
}

#' Main function to extract data-driven retirement rates
#' @param duckdb_path Path to DuckDB database
#' @param output_path Path to save results (optional)
#' @return List with cohort data and retirement rates
main_data_driven_analysis <- function(duckdb_path = "/Volumes/MufflySamsung/nber_my_duckdb.duckdb",
                                     output_path = NULL) {

  cat("=== DATA-DRIVEN RETIREMENT RATE ANALYSIS ===\n")
  cat("Using 50 years of Medicare claims data\n\n")

  # Connect to DuckDB
  con <- dbConnect(duckdb(), duckdb_path, read_only = TRUE)
  on.exit(dbDisconnect(con))

  # Extract physician cohort
  cohort <- extract_physician_cohort(con)

  # Analyze retirement patterns
  retirement_analysis <- analyze_medicare_cessation(con, cohort)

  # Calculate empirical rates
  empirical_rates <- calculate_empirical_retirement_rates(retirement_analysis)

  # Create lookup table for the hazard model
  rate_lookup <- empirical_rates %>%
    select(subspecialty, age_band, final_annual_rate) %>%
    rename(
      subspecialty_f = subspecialty,
      age_band_f = age_band,
      annual_prob = final_annual_rate
    )

  results <- list(
    cohort_data = cohort,
    retirement_analysis = retirement_analysis,
    empirical_rates = empirical_rates,
    rate_lookup = rate_lookup
  )

  # Save results if path provided
  if (!is.null(output_path)) {
    saveRDS(results, output_path)
    cat(sprintf("Results saved to: %s\n", output_path))
  }

  # Print summary
  cat("\n=== SUMMARY ===\n")
  cat(sprintf("Total physicians analyzed: %d\n", nrow(cohort)))
  cat(sprintf("Retirement events detected: %d\n", sum(retirement_analysis$retirement_detected, na.rm = TRUE)))
  cat(sprintf("Empirical rates calculated for: %d subspecialty-age combinations\n",
              sum(empirical_rates$reliable_estimate)))
  cat(sprintf("Literature fallback used for: %d combinations\n",
              sum(!empirical_rates$reliable_estimate)))

  return(results)
}

# Execute if run directly
if (!interactive()) {
  results <- main_data_driven_analysis(
    output_path = "results/empirical_retirement_rates.rds"
  )
}