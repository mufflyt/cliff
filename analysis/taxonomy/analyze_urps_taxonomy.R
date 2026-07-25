source(here::here("R", "wc_path.R"))
library(dplyr)
library(DBI)
library(duckdb)
library(readr)

# Load ABOG data with URPS subspecialty
abog_file <- "data/0-Download/output/abog_comprehensive_with_recent_grads_20250926_040524.csv"
abog_urps <- readr::read_csv(abog_file, show_col_types = FALSE) %>%
  filter(subspecialty_name %in% c("URPS", "FPMRS", "FPM", "Female Pelvic Medicine and Reconstructive Surgery",
                                   "Urogynecology and Reconstructive Pelvic Surgery")) %>%
  filter(!is.na(NPI)) %>%
  mutate(NPI = as.character(NPI)) %>%
  select(NPI, physician_name, subspecialty_name, city, state)

cat("Found", nrow(abog_urps), "ABOG physicians with URPS/FPMRS subspecialty\n")

# Connect to NBER database
con <- DBI::dbConnect(duckdb::duckdb(), wc_duckdb_path(), read_only = TRUE)

# Get their NPPES taxonomy codes
if(nrow(abog_urps) > 0) {
  npi_list <- paste0("'", abog_urps$NPI, "'", collapse = ",")

  query <- sprintf("
    SELECT
      NPI,
      \"Healthcare Provider Taxonomy Code_1\" as taxonomy_code_1,
      \"Healthcare Provider Taxonomy Code_2\" as taxonomy_code_2,
      \"Healthcare Provider Taxonomy Code_3\" as taxonomy_code_3,
      \"Provider First Name\" as nppes_first_name,
      \"Provider Last Name (Legal Name)\" as nppes_last_name,
      \"Provider Business Practice Location Address City Name\" as nppes_city,
      \"Provider Business Practice Location Address State Name\" as nppes_state
    FROM npidata
    WHERE NPI IN (%s)
  ", npi_list)

  nppes_urps <- DBI::dbGetQuery(con, query) %>%
    mutate(NPI = as.character(NPI))

  # Join ABOG and NPPES data
  urps_analysis <- abog_urps %>%
    left_join(nppes_urps, by = "NPI") %>%
    mutate(
      # Check if they have the correct URPS taxonomy code (207VG0400X) in any position
      has_correct_code = case_when(
        taxonomy_code_1 == "207VG0400X" ~ TRUE,
        taxonomy_code_2 == "207VG0400X" ~ TRUE,
        taxonomy_code_3 == "207VG0400X" ~ TRUE,
        TRUE ~ FALSE
      ),
      # What code do they have as primary?
      primary_taxonomy = case_when(
        is.na(taxonomy_code_1) ~ "NO_NPPES_RECORD",
        taxonomy_code_1 == "207VG0400X" ~ "CORRECT_URPS",
        taxonomy_code_1 == "207V00000X" ~ "GENERAL_Otolaryngology",
        taxonomy_code_1 == "207VX0201X" ~ "GYNECOLOGY",
        taxonomy_code_1 == "207VX0000X" ~ "Otolaryngology_IN_TRAINING",
        grepl("^207V", taxonomy_code_1) ~ "OTHER_Otolaryngology",
        TRUE ~ "NON_Otolaryngology"
      )
    ) %>%
    mutate(
      abog_location = paste0(city, ", ", state)
    ) %>%
    select(
      NPI,
      physician_name,
      abog_subspecialty = subspecialty_name,
      abog_location,
      nppes_city,
      nppes_state,
      has_correct_urps_code = has_correct_code,
      primary_taxonomy_code = taxonomy_code_1,
      primary_taxonomy_category = primary_taxonomy,
      secondary_code = taxonomy_code_2,
      tertiary_code = taxonomy_code_3
    ) %>%
    arrange(desc(has_correct_urps_code), physician_name)

  # Summary statistics
  cat("\n📊 URPS Taxonomy Code Analysis:\n")
  summary_stats <- urps_analysis %>%
    summarise(
      total_urps_physicians = n(),
      with_nppes_record = sum(primary_taxonomy_category != "NO_NPPES_RECORD"),
      with_correct_code = sum(has_correct_urps_code),
      correct_code_percentage = round(100 * sum(has_correct_urps_code) / n(), 1),
      correct_as_primary = sum(primary_taxonomy_category == "CORRECT_URPS"),
      general_otolaryngology_instead = sum(primary_taxonomy_category == "GENERAL_Otolaryngology"),
      no_nppes_record = sum(primary_taxonomy_category == "NO_NPPES_RECORD")
    )

  print(summary_stats)

  cat("\n📊 Primary Taxonomy Distribution for URPS Physicians:\n")
  taxonomy_dist <- urps_analysis %>%
    count(primary_taxonomy_category, sort = TRUE) %>%
    mutate(percentage = round(100 * n / sum(n), 1))

  print(taxonomy_dist)

  # Save to CSV files
  # 1. Full analysis
  write_csv(urps_analysis, "validation_results/urps_taxonomy_full_analysis.csv")
  cat("\n✅ Saved full analysis to: validation_results/urps_taxonomy_full_analysis.csv\n")

  # 2. Those with correct code
  urps_correct <- urps_analysis %>%
    filter(has_correct_urps_code == TRUE) %>%
    select(NPI, physician_name, abog_location,
           primary_taxonomy_code, secondary_code, tertiary_code)

  write_csv(urps_correct, "validation_results/urps_physicians_correct_taxonomy.csv")
  cat("✅ Saved", nrow(urps_correct), "physicians WITH correct code to: validation_results/urps_physicians_correct_taxonomy.csv\n")

  # 3. Those without correct code
  urps_incorrect <- urps_analysis %>%
    filter(has_correct_urps_code == FALSE) %>%
    select(NPI, physician_name, abog_location,
           primary_taxonomy_code, primary_taxonomy_category, secondary_code, tertiary_code)

  write_csv(urps_incorrect, "validation_results/urps_physicians_incorrect_taxonomy.csv")
  cat("✅ Saved", nrow(urps_incorrect), "physicians WITHOUT correct code to: validation_results/urps_physicians_incorrect_taxonomy.csv\n")

  # 4. Summary report
  summary_report <- tibble(
    metric = c("Total URPS Physicians in ABOG",
               "With NPPES Record",
               "With Correct URPS Code (207VG0400X)",
               "Correct Code as Primary",
               "Using General Otolaryngology Code Instead",
               "No NPPES Record Found",
               "Percentage With Correct Code"),
    value = c(summary_stats$total_urps_physicians,
              summary_stats$with_nppes_record,
              summary_stats$with_correct_code,
              summary_stats$correct_as_primary,
              summary_stats$general_otolaryngology_instead,
              summary_stats$no_nppes_record,
              paste0(summary_stats$correct_code_percentage, "%"))
  )

  write_csv(summary_report, "validation_results/urps_taxonomy_summary.csv")
  cat("\n✅ Saved summary to: validation_results/urps_taxonomy_summary.csv\n")

  # Show sample of incorrect ones
  cat("\n📋 Sample of URPS physicians WITHOUT correct taxonomy code:\n")
  sample_incorrect <- urps_incorrect %>%
    head(10) %>%
    select(physician_name, primary_taxonomy_code, primary_taxonomy_category)
  print(sample_incorrect)
}

DBI::dbDisconnect(con, shutdown = TRUE)

cat("\n🎯 Analysis complete! Check validation_results/ directory for CSV files.\n")
