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
  mutate(NPI = as.character(NPI))

cat("Found", nrow(abog_urps), "ABOG physicians with URPS/FPMRS subspecialty\n")

# Connect to NBER database
con <- DBI::dbConnect(duckdb::duckdb(), wc_duckdb_path(), read_only = TRUE)

# Get their NPPES taxonomy codes - ALL positions
if(nrow(abog_urps) > 0) {
  npi_list <- paste0("'", abog_urps$NPI, "'", collapse = ",")

  query <- sprintf("
    SELECT
      NPI,
      \"Healthcare Provider Taxonomy Code_1\" as taxonomy_code_1,
      \"Healthcare Provider Taxonomy Code_2\" as taxonomy_code_2,
      \"Healthcare Provider Taxonomy Code_3\" as taxonomy_code_3,
      \"Healthcare Provider Taxonomy Code_4\" as taxonomy_code_4,
      \"Healthcare Provider Taxonomy Code_5\" as taxonomy_code_5,
      \"Healthcare Provider Taxonomy Code_6\" as taxonomy_code_6,
      \"Healthcare Provider Taxonomy Code_7\" as taxonomy_code_7,
      \"Healthcare Provider Taxonomy Code_8\" as taxonomy_code_8,
      \"Healthcare Provider Taxonomy Code_9\" as taxonomy_code_9,
      \"Healthcare Provider Taxonomy Code_10\" as taxonomy_code_10,
      \"Healthcare Provider Taxonomy Code_11\" as taxonomy_code_11,
      \"Healthcare Provider Taxonomy Code_12\" as taxonomy_code_12,
      \"Healthcare Provider Taxonomy Code_13\" as taxonomy_code_13,
      \"Healthcare Provider Taxonomy Code_14\" as taxonomy_code_14,
      \"Healthcare Provider Taxonomy Code_15\" as taxonomy_code_15
    FROM npidata
    WHERE NPI IN (%s)
  ", npi_list)

  nppes_urps <- DBI::dbGetQuery(con, query) %>%
    mutate(NPI = as.character(NPI))

  # Join and analyze
  urps_analysis <- abog_urps %>%
    left_join(nppes_urps, by = "NPI") %>%
    mutate(
      # Check each position for URPS code
      has_urps_in_1 = (taxonomy_code_1 == "207VG0400X"),
      has_urps_in_2 = (taxonomy_code_2 == "207VG0400X"),
      has_urps_in_3 = (taxonomy_code_3 == "207VG0400X"),
      has_urps_in_4 = (taxonomy_code_4 == "207VG0400X"),
      has_urps_in_5 = (taxonomy_code_5 == "207VG0400X"),
      has_urps_in_6 = (taxonomy_code_6 == "207VG0400X"),
      has_urps_in_7 = (taxonomy_code_7 == "207VG0400X"),
      has_urps_in_8 = (taxonomy_code_8 == "207VG0400X"),
      has_urps_in_9 = (taxonomy_code_9 == "207VG0400X"),
      has_urps_in_10 = (taxonomy_code_10 == "207VG0400X"),
      has_urps_in_11 = (taxonomy_code_11 == "207VG0400X"),
      has_urps_in_12 = (taxonomy_code_12 == "207VG0400X"),
      has_urps_in_13 = (taxonomy_code_13 == "207VG0400X"),
      has_urps_in_14 = (taxonomy_code_14 == "207VG0400X"),
      has_urps_in_15 = (taxonomy_code_15 == "207VG0400X"),

      # Has URPS code in ANY position
      has_correct_code_anywhere = (has_urps_in_1 | has_urps_in_2 | has_urps_in_3 | has_urps_in_4 | has_urps_in_5 |
                                   has_urps_in_6 | has_urps_in_7 | has_urps_in_8 | has_urps_in_9 | has_urps_in_10 |
                                   has_urps_in_11 | has_urps_in_12 | has_urps_in_13 | has_urps_in_14 | has_urps_in_15),

      # Which position has the URPS code
      urps_position = case_when(
        has_urps_in_1 ~ "Position 1 (Primary)",
        has_urps_in_2 ~ "Position 2",
        has_urps_in_3 ~ "Position 3",
        has_urps_in_4 ~ "Position 4",
        has_urps_in_5 ~ "Position 5",
        has_urps_in_6 ~ "Position 6",
        has_urps_in_7 ~ "Position 7",
        has_urps_in_8 ~ "Position 8",
        has_urps_in_9 ~ "Position 9",
        has_urps_in_10 ~ "Position 10",
        has_urps_in_11 ~ "Position 11",
        has_urps_in_12 ~ "Position 12",
        has_urps_in_13 ~ "Position 13",
        has_urps_in_14 ~ "Position 14",
        has_urps_in_15 ~ "Position 15",
        is.na(taxonomy_code_1) ~ "No NPPES Record",
        TRUE ~ "No URPS Code in Any Position"
      )
    )

  # Summary by position
  cat("\n📊 URPS Code Position Analysis:\n")
  position_summary <- urps_analysis %>%
    count(urps_position, sort = TRUE) %>%
    mutate(percentage = round(100 * n / sum(n), 1))

  print(position_summary)

  # Overall statistics
  cat("\n📊 Overall URPS Taxonomy Statistics:\n")
  overall_stats <- urps_analysis %>%
    summarise(
      total_physicians = n(),
      with_nppes_record = sum(!is.na(taxonomy_code_1)),
      with_urps_code_anywhere = sum(has_correct_code_anywhere, na.rm = TRUE),
      percentage_with_urps = round(100 * sum(has_correct_code_anywhere, na.rm = TRUE) / n(), 1),
      urps_as_primary = sum(has_urps_in_1, na.rm = TRUE),
      urps_as_secondary = sum(has_urps_in_2, na.rm = TRUE),
      urps_in_other_positions = sum(has_correct_code_anywhere, na.rm = TRUE) -
                                sum(has_urps_in_1, na.rm = TRUE) -
                                sum(has_urps_in_2, na.rm = TRUE)
    )

  print(overall_stats)

  # Show examples where URPS is NOT in primary position
  cat("\n📋 Examples where URPS code is in secondary/tertiary positions:\n")
  non_primary_urps <- urps_analysis %>%
    filter(has_correct_code_anywhere == TRUE & has_urps_in_1 == FALSE) %>%
    select(physician_name, subspecialty_name, city, state, urps_position,
           taxonomy_code_1, taxonomy_code_2, taxonomy_code_3) %>%
    head(10)

  print(non_primary_urps)

  # Save detailed analysis
  detailed_output <- urps_analysis %>%
    select(NPI, physician_name, subspecialty_name, city, state,
           has_correct_code_anywhere, urps_position,
           taxonomy_code_1, taxonomy_code_2, taxonomy_code_3,
           taxonomy_code_4, taxonomy_code_5) %>%
    arrange(desc(has_correct_code_anywhere), urps_position)

  write_csv(detailed_output, "validation_results/urps_detailed_position_analysis.csv")
  cat("\n✅ Saved detailed analysis to: validation_results/urps_detailed_position_analysis.csv\n")

  # Create summary CSV
  summary_df <- tibble(
    Metric = c(
      "Total URPS Physicians",
      "With NPPES Record",
      "With URPS Code (207VG0400X) ANYWHERE",
      "Percentage with URPS Code",
      "URPS as Primary Taxonomy",
      "URPS as Secondary Taxonomy",
      "URPS in Other Positions (3-15)",
      "No NPPES Record",
      "No URPS Code in Any Position"
    ),
    Count = c(
      overall_stats$total_physicians,
      overall_stats$with_nppes_record,
      overall_stats$with_urps_code_anywhere,
      NA,
      overall_stats$urps_as_primary,
      overall_stats$urps_as_secondary,
      overall_stats$urps_in_other_positions,
      sum(is.na(urps_analysis$taxonomy_code_1)),
      sum(!urps_analysis$has_correct_code_anywhere & !is.na(urps_analysis$taxonomy_code_1))
    ),
    Percentage = c(
      100,
      round(100 * overall_stats$with_nppes_record / overall_stats$total_physicians, 1),
      overall_stats$percentage_with_urps,
      overall_stats$percentage_with_urps,
      round(100 * overall_stats$urps_as_primary / overall_stats$total_physicians, 1),
      round(100 * overall_stats$urps_as_secondary / overall_stats$total_physicians, 1),
      round(100 * overall_stats$urps_in_other_positions / overall_stats$total_physicians, 1),
      round(100 * sum(is.na(urps_analysis$taxonomy_code_1)) / overall_stats$total_physicians, 1),
      round(100 * sum(!urps_analysis$has_correct_code_anywhere & !is.na(urps_analysis$taxonomy_code_1)) / overall_stats$total_physicians, 1)
    )
  )

  write_csv(summary_df, "validation_results/urps_position_summary.csv")
  cat("✅ Saved position summary to: validation_results/urps_position_summary.csv\n")
}

DBI::dbDisconnect(con, shutdown = TRUE)

cat("\n🎯 Analysis complete! URPS code can appear in ANY of the 15 taxonomy positions.\n")
