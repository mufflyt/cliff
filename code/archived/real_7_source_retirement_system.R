# Real 7-Source Retirement Detection System
# Uses actual state physician licensing data from Colorado, Illinois, and Washington
# No simulated data - only real legal retirement indicators
# Created: 2025-09-28

library(DBI)
library(duckdb)
library(dplyr)
library(lubridate)
library(jsonlite)

# Configuration
db_path <- here::here("data", "nber_my_duckdb.duckdb")
analysis_year <- 2025
current_year <- 2025

# Connect to database
conn <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)
on.exit({
  if (DBI::dbIsValid(conn)) {
    DBI::dbDisconnect(conn)
  }
})

cat("=== REAL 7-SOURCE RETIREMENT DETECTION SYSTEM ===\n")
cat("Using actual state physician licensing data from CO, IL, WA, FL\n\n")

# Real 7-Source Retirement Detection with State Licensing
detect_retirement_real_7_source <- function(physician_npis, analysis_year = 2025) {

  cat(sprintf("Analyzing %d physicians with real 7-source system...\n", length(physician_npis)))

  # Initialize results dataframe
  retirement_analysis <- data.frame(
    npi = physician_npis,
    tier_1_definitive = FALSE,
    tier_2_very_likely = FALSE,
    tier_3_likely = FALSE,
    tier_4_possible = FALSE,
    license_retirement_indicator = FALSE,
    final_confidence = 0,
    retirement_tier = "Active",
    evidence_sources = "",
    age_estimated = NA,
    last_activity_year = NA,
    license_status = "",
    license_expiry_year = NA,
    license_state = "",
    cessation_pattern = "",
    stringsAsFactors = FALSE
  )

  # ===== SOURCE 7: REAL STATE PHYSICIAN LICENSING =====
  cat("SOURCE 7: Analyzing real state physician licensing data...\n")

  # Get physician names and states for matching
  physician_context_sql <- sprintf("
    SELECT DISTINCT printf('%%010d', CAST(PRSCRBR_NPI AS BIGINT)) as npi,
           Prscrbr_Last_Org_Name as last_name,
           Prscrbr_First_Name as first_name,
           Prscrbr_State_Abrvtn as state,
           Prscrbr_Type as specialty
    FROM MUP_DPR_RY23_P04_V10_DY21_NPI_csv_9
    WHERE printf('%%010d', CAST(PRSCRBR_NPI AS BIGINT)) IN (%s)
  ", paste(sprintf("'%s'", physician_npis), collapse = ","))

  physician_context <- DBI::dbGetQuery(conn, physician_context_sql)

  cat(sprintf("Retrieved context for %d physicians\n", nrow(physician_context)))

  # Colorado licensing matches
  colorado_matches <- tryCatch({
    colorado_sql <- "
      SELECT licensenumber,
             physician_name,
             firstname,
             lastname,
             state_standardized as state,
             specialty,
             license_issue_date,
             license_renewed_date,
             license_expiration_date,
             estimated_retirement_year,
             retirement_status,
             confidence,
             retired_flag,
             'Colorado' as license_state
      FROM colorado_physician_licenses
      WHERE (retirement_status IN ('expired', 'revoked', 'cancelled') OR retired_flag = true)
        AND (specialty LIKE '%gynecol%' OR specialty LIKE '%obstet%' OR specialty = 'OB/GYN'
             OR specialty IS NULL)  -- Include records without specialty for broader matching
        AND (license_expiration_date >= '2019-01-01' OR estimated_retirement_year >= 2019)
    "

    colorado_data <- DBI::dbGetQuery(conn, colorado_sql)

    # Match by name and state (more flexible matching)
    matches <- physician_context %>%
      filter(state %in% c("CO", "Colorado")) %>%
      mutate(
        first_name_clean = toupper(trimws(first_name)),
        last_name_clean = toupper(trimws(last_name))
      ) %>%
      inner_join(
        colorado_data %>%
          filter(!is.na(firstname) & !is.na(lastname)) %>%
          mutate(
            firstname_clean = toupper(trimws(firstname)),
            lastname_clean = toupper(trimws(lastname))
          ),
        by = c("first_name_clean" = "firstname_clean", "last_name_clean" = "lastname_clean"),
        relationship = "many-to-many"
      ) %>%
      mutate(
        # Calculate approximate age based on license issue date
        license_issue_year = as.numeric(format(as.Date(license_issue_date), "%Y")),
        estimated_age_2025 = case_when(
          !is.na(license_issue_year) & license_issue_year >= 1990 ~
            (2025 - license_issue_year) + 28,  # Assume licensed at ~28
          TRUE ~ NA_real_
        ),

        years_since_expiry = 2025 - as.numeric(format(as.Date(license_expiration_date), "%Y")),

        # Enhanced retirement confidence with age validation
        license_confidence = case_when(
          # Explicit retirement indicators (age-independent)
          retirement_status == "revoked" & !is.na(estimated_age_2025) & estimated_age_2025 >= 60 ~ 0.95,
          retired_flag == TRUE ~ 0.90,

          # Age-dependent expired license logic
          retirement_status == "expired" & !is.na(estimated_age_2025) &
            estimated_age_2025 >= 65 & years_since_expiry >= 2 ~ 0.88,  # Likely retirement
          retirement_status == "expired" & !is.na(estimated_age_2025) &
            estimated_age_2025 >= 70 ~ 0.85,  # High age, recent expiry

          # Low confidence for young physicians with expired licenses
          retirement_status == "expired" & !is.na(estimated_age_2025) &
            estimated_age_2025 < 55 ~ 0.15,  # Likely career change/move

          # Voluntary cancellation with age context
          retirement_status == "cancelled" & !is.na(estimated_age_2025) &
            estimated_age_2025 >= 60 ~ 0.75,

          TRUE ~ 0.20
        ),

        # Strict retirement criteria with age validation
        license_retirement = case_when(
          retired_flag == TRUE ~ TRUE,
          retirement_status == "revoked" & !is.na(estimated_age_2025) & estimated_age_2025 >= 60 ~ TRUE,
          retirement_status == "expired" & !is.na(estimated_age_2025) &
            estimated_age_2025 >= 65 & years_since_expiry >= 2 ~ TRUE,
          TRUE ~ FALSE
        ),
        license_expiry_year = as.numeric(format(as.Date(license_expiration_date), "%Y")),
        match_source = "Colorado"
      )

    cat(sprintf("Colorado matches: %d\n", nrow(matches)))
    matches

  }, error = function(e) {
    cat("⚠️ Colorado matching failed:", e$message, "\n")
    data.frame()
  })

  # Illinois licensing matches (Complete Medical Board Data - 362,817 physicians)
  illinois_matches <- tryCatch({
    illinois_sql <- "
      SELECT license_number,
             first_name,
             last_name,
             license_status,
             license_type,
             original_issue_date,
             expiration_date,
             city,
             state,
             'Illinois' as license_state
      FROM illinois_physicians
      WHERE license_status IN ('DECEASED', 'INACTIVE', 'EXPIRED', 'CANCELLED')
        AND license_type = 'MEDICAL BOARD'
        AND first_name IS NOT NULL
        AND last_name IS NOT NULL
    "

    illinois_data <- DBI::dbGetQuery(conn, illinois_sql)

    # Match by name and state with improved cleaning
    matches <- physician_context %>%
      filter(state %in% c("IL", "Illinois")) %>%
      mutate(
        first_name_clean = toupper(trimws(first_name)),
        last_name_clean = toupper(trimws(last_name))
      ) %>%
      inner_join(
        illinois_data %>%
          mutate(
            first_name_clean = toupper(trimws(first_name)),
            last_name_clean = toupper(trimws(last_name)),
            # Calculate years since expiration for age validation context
            years_since_expiry = case_when(
              !is.na(expiration_date) & expiration_date != "" ~
                2025 - as.numeric(format(as.Date(expiration_date, format = "%m/%d/%Y"), "%Y")),
              TRUE ~ NA_real_
            ),
            # Estimate age from license issue date
            license_issue_year = as.numeric(format(as.Date(original_issue_date, format = "%m/%d/%Y"), "%Y")),
            estimated_age_2025 = case_when(
              !is.na(license_issue_year) & license_issue_year >= 1990 ~
                (2025 - license_issue_year) + 28,  # Assume licensed at ~28
              TRUE ~ NA_real_
            )
          ),
        by = c("first_name_clean", "last_name_clean"),
        relationship = "many-to-many"
      ) %>%
      mutate(
        # Enhanced Illinois retirement confidence with age validation
        license_confidence = case_when(
          # Death certificate - highest confidence
          license_status == "DECEASED" ~ 0.99,

          # Disciplinary/explicit retirement
          license_status == "CANCELLED" & !is.na(estimated_age_2025) & estimated_age_2025 >= 60 ~ 0.95,

          # Age-dependent expired license logic
          license_status == "EXPIRED" & !is.na(estimated_age_2025) &
            estimated_age_2025 >= 65 & years_since_expiry >= 2 ~ 0.88,
          license_status == "EXPIRED" & !is.na(estimated_age_2025) &
            estimated_age_2025 >= 70 ~ 0.85,

          # Low confidence for young physicians with expired licenses
          license_status == "EXPIRED" & !is.na(estimated_age_2025) &
            estimated_age_2025 < 55 ~ 0.15,

          # Inactive status with age context
          license_status == "INACTIVE" & !is.na(estimated_age_2025) & estimated_age_2025 >= 65 ~ 0.75,
          license_status == "INACTIVE" & !is.na(estimated_age_2025) & estimated_age_2025 < 55 ~ 0.20,

          TRUE ~ 0.25
        ),

        # Strict retirement criteria with age validation
        license_retirement = case_when(
          license_status == "DECEASED" ~ TRUE,
          license_status == "CANCELLED" & !is.na(estimated_age_2025) & estimated_age_2025 >= 60 ~ TRUE,
          license_status == "EXPIRED" & !is.na(estimated_age_2025) &
            estimated_age_2025 >= 65 & years_since_expiry >= 2 ~ TRUE,
          license_status == "INACTIVE" & !is.na(estimated_age_2025) & estimated_age_2025 >= 70 ~ TRUE,
          TRUE ~ FALSE
        ),

        license_expiry_year = case_when(
          !is.na(expiration_date) & expiration_date != "" ~
            as.numeric(format(as.Date(expiration_date, format = "%m/%d/%Y"), "%Y")),
          TRUE ~ NA_real_
        ),
        retirement_status = license_status,
        match_source = "Illinois"
      )

    cat(sprintf("Illinois matches: %d\n", nrow(matches)))
    matches

  }, error = function(e) {
    cat("⚠️ Illinois matching failed:", e$message, "\n")
    data.frame()
  })

  # Washington licensing matches with birth year validation
  washington_matches <- tryCatch({
    washington_sql <- "
      SELECT credentialnumber,
             lastname,
             firstname,
             credentialtype,
             status,
             birthyear,
             firstissuedate,
             lastissuedate,
             expirationdate,
             actiontaken,
             'Washington' as license_state
      FROM washington_physician_licenses
      WHERE credentialtype = 'Physician And Surgeon License'
        AND status IN ('EXPIRED', 'INACTIVE', 'CLOSED')
        AND firstname IS NOT NULL
        AND lastname IS NOT NULL
        AND birthyear IS NOT NULL
        AND (2025 - birthyear) BETWEEN 25 AND 100  -- Reasonable age range
    "

    washington_data <- DBI::dbGetQuery(conn, washington_sql)

    # Match by name and state with flexible matching
    matches <- physician_context %>%
      filter(state %in% c("WA", "Washington")) %>%
      mutate(
        first_name_clean = toupper(trimws(first_name)),
        last_name_clean = toupper(trimws(last_name))
      ) %>%
      inner_join(
        washington_data %>%
          mutate(
            firstname_clean = toupper(trimws(firstname)),
            lastname_clean = toupper(trimws(lastname))
          ),
        by = c("first_name_clean" = "firstname_clean", "last_name_clean" = "lastname_clean"),
        relationship = "many-to-many"
      ) %>%
      mutate(
        # Calculate exact age from birth year (much more accurate than license estimation)
        current_age_2025 = 2025 - birthyear,
        years_since_expiry = 2025 - as.numeric(format(as.Date(expirationdate), "%Y")),

        # Enhanced Washington retirement confidence with precise age validation
        license_confidence = case_when(
          # Disciplinary retirement with age validation
          status == "CLOSED" & actiontaken == "Yes" & current_age_2025 >= 60 ~ 0.95,

          # Age-dependent expired license logic (precise birth year)
          status == "EXPIRED" & current_age_2025 >= 70 ~ 0.90,  # Likely retirement
          status == "EXPIRED" & current_age_2025 >= 65 & years_since_expiry >= 2 ~ 0.88,
          status == "EXPIRED" & current_age_2025 >= 60 & years_since_expiry >= 3 ~ 0.85,

          # Low confidence for younger physicians with expired licenses
          status == "EXPIRED" & current_age_2025 < 55 ~ 0.15,

          # Medium confidence for middle-aged expired
          status == "EXPIRED" & current_age_2025 >= 55 & current_age_2025 < 65 ~ 0.35,

          # Inactive status with age context
          status == "INACTIVE" & current_age_2025 >= 70 ~ 0.80,
          status == "INACTIVE" & current_age_2025 >= 65 ~ 0.65,
          status == "INACTIVE" & current_age_2025 < 55 ~ 0.20,

          TRUE ~ 0.25
        ),

        # Strict retirement criteria with precise age validation
        license_retirement = case_when(
          status == "CLOSED" & actiontaken == "Yes" & current_age_2025 >= 60 ~ TRUE,
          status == "EXPIRED" & current_age_2025 >= 70 ~ TRUE,
          status == "EXPIRED" & current_age_2025 >= 65 & years_since_expiry >= 2 ~ TRUE,
          status == "INACTIVE" & current_age_2025 >= 70 ~ TRUE,
          TRUE ~ FALSE
        ),

        license_expiry_year = as.numeric(format(as.Date(expirationdate), "%Y")),
        retirement_status = status,
        match_source = "Washington"
      )

    cat(sprintf("Washington matches: %d\n", nrow(matches)))
    matches

  }, error = function(e) {
    cat("⚠️ Washington matching failed:", e$message, "\n")
    data.frame()
  })

  # Florida licensing matches (21,621 physicians)
  florida_matches <- tryCatch({
    florida_sql <- "
      SELECT license_number,
             first_name,
             last_name,
             profession_name,
             license_status_description,
             original_issue_date,
             expiration_date,
             mail_address,
             mail_city,
             mail_state,
             'Florida' as license_state
      FROM florida_physicians
      WHERE license_status_description IN ('Null And Void', 'Inactive', 'Deceased')
        AND profession_name LIKE '%Physician%'
        AND first_name IS NOT NULL
        AND last_name IS NOT NULL
    "

    florida_data <- DBI::dbGetQuery(conn, florida_sql)

    # Match by name and state with improved cleaning
    matches <- physician_context %>%
      filter(state %in% c("FL", "Florida")) %>%
      mutate(
        first_name_clean = toupper(trimws(first_name)),
        last_name_clean = toupper(trimws(last_name))
      ) %>%
      inner_join(
        florida_data %>%
          mutate(
            first_name_clean = toupper(trimws(first_name)),
            last_name_clean = toupper(trimws(last_name)),
            # Calculate years since expiration for age validation context
            years_since_expiry = case_when(
              !is.na(expiration_date) ~ 2025 - as.numeric(format(as.Date(expiration_date), "%Y")),
              TRUE ~ NA_real_
            ),
            # Estimate age from license issue date
            license_issue_year = as.numeric(format(as.Date(original_issue_date), "%Y")),
            estimated_age_2025 = case_when(
              !is.na(license_issue_year) & license_issue_year >= 1990 ~
                (2025 - license_issue_year) + 28,  # Assume licensed at ~28
              TRUE ~ NA_real_
            )
          ),
        by = c("first_name_clean", "last_name_clean"),
        relationship = "many-to-many"
      ) %>%
      mutate(
        # Enhanced Florida retirement confidence with age validation
        license_confidence = case_when(
          # Death certificate - highest confidence
          license_status_description == "Deceased" ~ 0.99,

          # Null and void with age validation (disciplinary or explicit retirement)
          license_status_description == "Null And Void" & !is.na(estimated_age_2025) & estimated_age_2025 >= 60 ~ 0.92,

          # Null and void for younger physicians (lower confidence - could be relocation)
          license_status_description == "Null And Void" & !is.na(estimated_age_2025) & estimated_age_2025 < 55 ~ 0.25,

          # Inactive status with age context
          license_status_description == "Inactive" & !is.na(estimated_age_2025) & estimated_age_2025 >= 65 ~ 0.75,
          license_status_description == "Inactive" & !is.na(estimated_age_2025) & estimated_age_2025 < 55 ~ 0.20,

          TRUE ~ 0.25
        ),

        # Strict retirement criteria with age validation
        license_retirement = case_when(
          license_status_description == "Deceased" ~ TRUE,
          license_status_description == "Null And Void" & !is.na(estimated_age_2025) & estimated_age_2025 >= 60 ~ TRUE,
          license_status_description == "Inactive" & !is.na(estimated_age_2025) & estimated_age_2025 >= 70 ~ TRUE,
          TRUE ~ FALSE
        ),

        license_expiry_year = as.numeric(format(as.Date(expiration_date), "%Y")),
        retirement_status = license_status_description,
        match_source = "Florida"
      )

    cat(sprintf("Florida matches: %d\n", nrow(matches)))
    matches

  }, error = function(e) {
    cat("⚠️ Florida matching failed:", e$message, "\n")
    data.frame()
  })

  # Combine all state licensing matches (handle different structures)
  all_license_matches <- bind_rows(
    # Colorado matches with estimated age
    if (nrow(colorado_matches) > 0) {
      colorado_matches %>% select(npi, license_confidence, license_retirement,
                                 license_expiry_year, retirement_status, match_source)
    } else { data.frame() },

    # Illinois matches (Complete Medical Board Data - 362,817 physicians)
    if (nrow(illinois_matches) > 0) {
      illinois_matches %>% select(npi, license_confidence, license_retirement,
                                 license_expiry_year, retirement_status, match_source)
    } else { data.frame() },

    # Washington matches with precise birth year age
    if (nrow(washington_matches) > 0) {
      washington_matches %>% select(npi, license_confidence, license_retirement,
                                   license_expiry_year, retirement_status, match_source)
    } else { data.frame() },

    # Florida matches (21,621 physicians)
    if (nrow(florida_matches) > 0) {
      florida_matches %>% select(npi, license_confidence, license_retirement,
                                license_expiry_year, retirement_status, match_source)
    } else { data.frame() }
  )

  if (nrow(all_license_matches) > 0) {
    # Summarize license data by NPI (highest confidence wins)
    license_summary <- all_license_matches %>%
      group_by(npi) %>%
      summarize(
        license_retirement_indicator = any(license_retirement, na.rm = TRUE),
        license_confidence = max(license_confidence, na.rm = TRUE),
        license_status = paste(unique(retirement_status), collapse = "; "),
        license_expiry_year = min(license_expiry_year, na.rm = TRUE),
        license_state = paste(unique(match_source), collapse = "; "),
        .groups = "drop"
      )

    cat(sprintf("📋 Real License Analysis Results:\n"))
    cat(sprintf("   • NPIs with real licensing data: %d\n", nrow(license_summary)))
    cat(sprintf("   • License-indicated retirement: %d\n", sum(license_summary$license_retirement_indicator)))
    cat(sprintf("   • Average license confidence: %.3f\n", mean(license_summary$license_confidence)))

    # Merge with main analysis (remove conflicting columns first)
    retirement_analysis <- retirement_analysis %>%
      select(-license_retirement_indicator, -license_status, -license_expiry_year, -license_state) %>%
      left_join(license_summary, by = "npi") %>%
      mutate(
        license_retirement_indicator = coalesce(license_retirement_indicator, FALSE),
        license_confidence = coalesce(license_confidence, 0),
        license_status = coalesce(license_status, "No Data"),
        license_expiry_year = coalesce(license_expiry_year, NA),
        license_state = coalesce(license_state, "")
      )

  } else {
    cat("ℹ️ No state licensing matches found\n")
    # Create empty license summary for consistency
    license_summary <- data.frame(
      npi = character(0),
      license_retirement_indicator = logical(0),
      license_confidence = numeric(0),
      license_status = character(0),
      license_expiry_year = numeric(0),
      license_state = character(0)
    )

    retirement_analysis <- retirement_analysis %>%
      mutate(
        license_retirement_indicator = FALSE,
        license_confidence = 0,
        license_status = "No Data",
        license_expiry_year = NA,
        license_state = ""
      )
  }

  # ===== INTEGRATE WITH EXISTING 6-SOURCE SYSTEM =====
  cat("\nIntegrating with existing 6-source retirement detection...\n")

  # Run 6-source analysis for comparison
  six_source_results <- tryCatch({
    source(here::here("deprecated", "research_forecasting", "comprehensive_forecasting", "tiered_confidence_retirement_system.R"))
    detect_retirement_tiered_confidence(physician_npis, analysis_year)
  }, error = function(e) {
    cat("⚠️ Could not run 6-source analysis, using license-only data\n")
    NULL
  })

  # Merge real 6-source with real 7-source (licensing)
  if (is.data.frame(six_source_results) && nrow(six_source_results) > 0) {
    enhanced_7_source <- six_source_results %>%
      left_join(
        retirement_analysis %>% select(npi, license_retirement_indicator, license_confidence,
                                     license_status, license_expiry_year, license_state),
        by = "npi"
      ) %>%
      mutate(
        # Real enhanced confidence scoring with state licensing
        enhanced_confidence = case_when(
          # Real license data trumps other sources when definitive
          license_confidence >= 0.95 ~ license_confidence,

          # Combine real license with existing confidence
          license_retirement_indicator & final_confidence >= 0.70 ~
            pmin(0.98, 0.6 * final_confidence + 0.4 * license_confidence),

          # Real license data alone with high confidence
          license_confidence >= 0.80 ~ license_confidence,

          # Existing confidence with moderate license support
          final_confidence >= 0.50 & license_confidence >= 0.50 ~
            pmin(0.95, 0.75 * final_confidence + 0.25 * license_confidence),

          # Use existing confidence if no strong license indicator
          TRUE ~ final_confidence
        ),

        # Enhanced retirement determination
        enhanced_retired = enhanced_confidence >= 0.50,

        # Real tier classification with license validation
        enhanced_tier = case_when(
          license_confidence >= 0.95 ~ "Tier 0 - License Definitive (Real)",
          enhanced_confidence >= 0.95 ~ "Tier 1 - Definitive",
          enhanced_confidence >= 0.85 ~ "Tier 2 - Very Likely",
          enhanced_confidence >= 0.70 ~ "Tier 3 - Likely",
          enhanced_confidence >= 0.50 ~ "Tier 4 - Possible",
          TRUE ~ "Active"
        ),

        # Enhanced evidence sources
        enhanced_evidence = case_when(
          license_retirement_indicator & evidence_sources != "None" ~
            paste("Real_State_License", evidence_sources, sep = ";"),
          license_retirement_indicator ~ "Real_State_License",
          TRUE ~ evidence_sources
        )
      )

  } else {
    # Fallback if 6-source analysis fails
    enhanced_7_source <- retirement_analysis %>%
      mutate(
        enhanced_confidence = license_confidence,
        enhanced_retired = license_retirement_indicator,
        enhanced_tier = case_when(
          license_confidence >= 0.95 ~ "Tier 0 - License Definitive (Real)",
          license_confidence >= 0.85 ~ "Tier 2 - Very Likely (License)",
          license_confidence >= 0.70 ~ "Tier 3 - Likely (License)",
          license_confidence >= 0.50 ~ "Tier 4 - Possible (License)",
          TRUE ~ "Active"
        ),
        enhanced_evidence = ifelse(license_retirement_indicator, "Real_State_License", "None")
      )
  }

  return(enhanced_7_source)
}

# ===== MAIN EXECUTION =====

cat("Loading physician data for real 7-source analysis...\n")

# Get all physicians for analysis (focus on states with licensing data)
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
  AND Prscrbr_State_Abrvtn IN ('CO', 'IL', 'WA', 'FL')  -- Focus on states with licensing data
  AND PRSCRBR_NPI IS NOT NULL
"

physician_data <- DBI::dbGetQuery(conn, physician_sql)

if (nrow(physician_data) == 0) {
  cat("❌ No physician data found in CO, IL, WA, FL\n")
  stop("No data available")
}

cat(sprintf("📊 Loaded %d physicians from CO, IL, WA, FL for real 7-source analysis\n", nrow(physician_data)))

# Run real 7-source analysis
npis_to_analyze <- unique(physician_data$npi)
real_7_source_results <- detect_retirement_real_7_source(npis_to_analyze, analysis_year = 2025)

# ===== RESULTS SUMMARY =====
cat("\n=== REAL 7-SOURCE RETIREMENT ANALYSIS RESULTS ===\n")

real_summary <- real_7_source_results %>%
  summarize(
    total_physicians = n(),
    license_data_available = sum(!is.na(license_confidence) & license_confidence > 0),
    license_indicated_retired = sum(license_retirement_indicator, na.rm = TRUE),
    total_retired_7source = sum(enhanced_retired, na.rm = TRUE),
    avg_enhanced_confidence = mean(enhanced_confidence[enhanced_retired], na.rm = TRUE),
    tier_0_license_definitive = sum(grepl("Tier 0.*Real", enhanced_tier), na.rm = TRUE),
    active_physicians = sum(!enhanced_retired, na.rm = TRUE)
  )

cat(sprintf("📊 REAL 7-SOURCE DISTRIBUTION:\n"))
cat(sprintf("   • Total physicians analyzed: %d\n", real_summary$total_physicians))
cat(sprintf("   • Real license data available: %d\n", real_summary$license_data_available))
cat(sprintf("   • License-indicated retirement: %d\n", real_summary$license_indicated_retired))
cat(sprintf("   • Tier 0 - License Definitive (Real): %d physicians\n", real_summary$tier_0_license_definitive))

# Show enhanced tier distribution
tier_distribution <- table(real_7_source_results$enhanced_tier)
for (tier in names(tier_distribution)) {
  cat(sprintf("   • %s: %d physicians\n", tier, tier_distribution[tier]))
}

cat(sprintf("\n📈 REAL RETIREMENT METRICS:\n"))
cat(sprintf("   • Total retired (≥50%% confidence): %d (%.2f%%)\n",
            real_summary$total_retired_7source,
            100 * real_summary$total_retired_7source / real_summary$total_physicians))
cat(sprintf("   • Average enhanced confidence: %.3f\n", real_summary$avg_enhanced_confidence))
cat(sprintf("   • Real license validation impact: +%d definitive cases\n",
            real_summary$tier_0_license_definitive))

# Current retirement prevalence (NOT an annual rate)
current_retirement_prevalence <- real_summary$total_retired_7source / real_summary$total_physicians

cat(sprintf("   • Current retirement prevalence: %.2f%% (cross-sectional)\n", 100 * current_retirement_prevalence))

# Save real results
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
results_file <- sprintf("real_7source_retirement_results_%s.csv", timestamp)
write.csv(real_7_source_results, results_file, row.names = FALSE)

# Real summary with licensing details
real_summary_data <- list(
  analysis_timestamp = timestamp,
  total_physicians = real_summary$total_physicians,
  data_sources = 7,

  # Real Source 7: State Licensing
  real_license_data_coverage = real_summary$license_data_available,
  real_license_indicated_retirements = real_summary$license_indicated_retired,
  states_covered = c("Colorado", "Illinois", "Washington", "Florida"),

  # Real enhanced tier breakdown
  real_tier_distribution = list(
    tier_0_license_definitive_real = real_summary$tier_0_license_definitive,
    tier_1_definitive = sum(real_7_source_results$enhanced_tier == "Tier 1 - Definitive", na.rm = TRUE),
    tier_2_very_likely = sum(real_7_source_results$enhanced_tier == "Tier 2 - Very Likely", na.rm = TRUE),
    tier_3_likely = sum(real_7_source_results$enhanced_tier == "Tier 3 - Likely", na.rm = TRUE),
    tier_4_possible = sum(real_7_source_results$enhanced_tier == "Tier 4 - Possible", na.rm = TRUE),
    active = real_summary$active_physicians
  ),

  # Real retirement metrics
  real_retirement_metrics = list(
    total_retired = real_summary$total_retired_7source,
    current_retirement_prevalence = current_retirement_prevalence,
    note_annual_rates = "Annual retirement rates from Monte Carlo model: FPMRS 6.24%, GO 7.43%, MIG 4.91%",
    average_enhanced_confidence = real_summary$avg_enhanced_confidence
  ),

  # Real licensing validation details
  real_licensing_validation = list(
    colorado_statuses = c("expired", "revoked", "cancelled"),
    illinois_statuses = c("DECEASED", "INACTIVE", "EXPIRED", "CANCELLED"),
    washington_statuses = c("EXPIRED", "INACTIVE", "CLOSED"),
    florida_statuses = c("Null And Void", "Inactive", "Deceased"),
    confidence_weighting = "Real license data receives highest priority",
    no_simulation = "All licensing data from actual state medical boards"
  )
)

summary_file <- sprintf("real_7source_summary_%s.json", timestamp)
writeLines(jsonlite::toJSON(real_summary_data, pretty = TRUE), summary_file)

cat(sprintf("\n💾 REAL 7-SOURCE RESULTS SAVED:\n"))
cat(sprintf("   • Detailed results: %s\n", results_file))
cat(sprintf("   • Summary: %s\n", summary_file))

cat(sprintf("\n🏆 REAL 7-SOURCE RETIREMENT DETECTION COMPLETE!\n"))
cat(sprintf("🎯 Real state licensing data provides genuine legal validation\n"))
cat(sprintf("⚖️ Actual license status changes from CO, IL, WA, FL medical boards\n"))
cat(sprintf("🔬 No simulated data - only real legal retirement indicators\n"))
