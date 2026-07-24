#' @title Step 7: Create Table 1 - Physician Demographics for Manuscript
#' @description This script generates Table 1 showing demographic characteristics of
#' subspecialist physicians (FPMRS, Gynecologic Oncology, MIGS) in 2024.
#' It uses enriched physician data from a comprehensive Table 1 pipeline.
#' @author Tyler Muffly, MD / Claude Code
#' @date 2026-01-12
#' @return A Word document (\'table1_demographics.docx\') and a CSV file (\'table1_physicians.csv\')
#' containing the demographic data for Table 1.
#' @seealso \code{\link{00_RUN_ALL.R}}

#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 7: Create Table 1 - Physician Demographics for Manuscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose: Generate Table 1 showing demographic characteristics of subspecialist
#          physicians (FPMRS, Gynecologic Oncology, MIGS) in 2024
#
# Uses enriched physician data from full Table 1 pipeline, filtered to our
# three subspecialties of interest
#
# Author: Tyler Muffly, MD / Claude Code
# Date: 2026-01-12
#
# Usage:
#   Rscript cliff/code/07_create_table1.R
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# The \'suppressPackageStartupMessages\' function prevents package startup messages from being printed.
suppressPackageStartupMessages({
  # The \'tidyverse\' library is a collection of R packages designed for data science.
  # It includes ggplot2, dplyr, tidyr, readr, purrr, and tibble.
  library(tidyverse)
  # The \'here\' library helps to create reproducible paths to files.
  library(here)
  # The \'gtsummary\' library creates publication-ready analytical tables.
  library(gtsummary)
  # The \'flextable\' library creates editable tables for reporting.
  library(flextable)
})

cat("\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("TABLE 1: PHYSICIAN DEMOGRAPHICS FOR WORKFORCE CLIFF MANUSCRIPT\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 1: Run Full Table 1 Pipeline
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("[", as.character(Sys.time()), "] Running comprehensive Table 1 pipeline...\n", sep = "")
cat("  This generates enriched physician data with all demographics\n\n")

# Run the comprehensive Table 1 script
# The 'system2' function executes a system command and captures its output.
pipeline_script <- here("manuscript", "R", "pipeline_table1_physician_characteristics_2024.R")
pipeline_output <- system2(
  "Rscript",
  args = pipeline_script,
  stdout = TRUE,
  stderr = TRUE
)

pipeline_status <- attr(pipeline_output, "status")
if (is.null(pipeline_status)) {
  pipeline_status <- 0
}

if (pipeline_status != 0) {
  message(paste(pipeline_output, collapse = "\n"))
  stop(
    "Table 1 pipeline failed. Check manuscript/R/pipeline_table1_physician_characteristics_2024.R for details."
  )
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 2: Load and Filter to Three Subspecialties
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("[", as.character(Sys.time()), "] Loading enriched physician data...\n", sep = "")

# Find most recent enriched data file
table1_dir <- here("data", "table1")
# The 'list.files' function lists the files in a directory.
enriched_files <- list.files(
  table1_dir,
  pattern = "physicians_for_table1_2024_\\d{8}_\\d{6}\\.csv$",
  full.names = TRUE
)

if (length(enriched_files) == 0) {
  stop("No enriched physician data found. Table 1 pipeline may have failed.")
}

# Use most recent
# The 'file.info' function returns information about files.
enriched_file <- enriched_files[order(file.info(enriched_files)$mtime, decreasing = TRUE)][1]
cat(sprintf("  Using: %s\n", basename(enriched_file)))

# The 'read_csv' function reads a comma-separated value (CSV) file into a tibble.
physicians_all <- readr::read_csv(
  enriched_file,
  col_types = readr::cols(
    .default = readr::col_guess(),
    npi_last_alt = readr::col_character()
  ),
  show_col_types = FALSE
)

parse_issues <- readr::problems(physicians_all)

if (nrow(parse_issues) > 0) {
  base::message(
    "[", Sys.time(), "] WARNING: readr parsing issues in enriched file: ",
    nrow(parse_issues), " rows"
  )
  print(utils::head(parse_issues, 5))
} else {
  base::message(
    "[", Sys.time(), "] No readr parsing issues after forcing column types."
  )
}


cat(sprintf("  Total physicians: %s\n", format(nrow(physicians_all), big.mark = ",")))

# Filter to our three subspecialties
# Match subspecialty names from ABOG data
cat("\n[", as.character(Sys.time()), "] Filtering to three target subspecialties...\n", sep = "")

physicians_filtered <- physicians_all %>%
  # The 'filter' function selects rows based on their values.
  filter(
    subspecialty_name %in% c(
      "Female Pelvic Medicine & Reconstructive Surgery",
      "Gynecologic Oncology",
      "MIG"  # MIGS sometimes abbreviated
    ) |
    # Also check other subspecialty fields
    sub1FullDescr %in% c(
      "Female Pelvic Medicine & Reconstructive Surgery",
      "Gynecologic Oncology",
      "MIG"
    )
  ) %>%
  # The 'mutate' function adds new variables to a tibble.
  # Create consistent subspecialty label
  mutate(
    subspecialty_clean = case_when(
      grepl("Female Pelvic|Reconstructive|FPMRS", subspecialty_name, ignore.case = TRUE) |
        grepl("Female Pelvic|Reconstructive|FPMRS", sub1FullDescr, ignore.case = TRUE) ~ "FPMRS",
      grepl("Gynecologic Oncology|GO", subspecialty_name, ignore.case = TRUE) |
        grepl("Gynecologic Oncology|GO", sub1FullDescr, ignore.case = TRUE) ~ "Gynecologic Oncology",
      grepl("MIG|Minimally Invasive", subspecialty_name, ignore.case = TRUE) |
        grepl("MIG|Minimally Invasive", sub1FullDescr, ignore.case = TRUE) ~ "MIGS",
      TRUE ~ "Other"
    )
  ) %>%
  filter(subspecialty_clean != "Other")

cat(sprintf("  Filtered physicians: %s\n", format(nrow(physicians_filtered), big.mark = ",")))

# The 'count' function counts the number of observations in each group.
# Count by subspecialty
subspec_counts <- physicians_filtered %>%
  count(subspecialty_clean, name = "n_physicians") %>%
  # The 'arrange' function reorders rows.
  arrange(desc(n_physicians))

cat("\n  Distribution by subspecialty:\n")
for (i in seq_len(nrow(subspec_counts))) {
  cat(sprintf("    %s: %s\n",
              subspec_counts$subspecialty_clean[i],
              format(subspec_counts$n_physicians[i], big.mark = ",")))
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 3: Prepare Table 1 Variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n[", as.character(Sys.time()), "] Preparing Table 1 variables...\n", sep = "")

table1_data <- physicians_filtered %>%
  # The 'transmute' function is similar to 'mutate', but it drops all other variables.
  transmute(
    # Grouping variable
    Subspecialty = factor(
      subspecialty_clean,
      levels = c("FPMRS", "Gynecologic Oncology", "MIGS"),
      labels = c("FPMRS (Urogynecology)", "Gynecologic Oncology", "MIGS")
    ),

    # Demographics
    Age = final_age,
    `Years in Practice` = years_in_practice,

    # Gender
    Gender = factor(
      case_when(
        tolower(gender_inferred) == "female" ~ "Female",
        tolower(gender_inferred) == "male" ~ "Male",
        TRUE ~ NA_character_
      ),
      levels = c("Female", "Male")
    ),

    # Geographic distribution
    `ACOG District` = factor(acog_district),

    # Practice characteristics
    `Practice Size` = factor(
      case_when(
        practice_size_category == "Solo (1)" ~ "Solo (1)",
        practice_size_category == "Small (2-5)" ~ "Small (2-5)",
        practice_size_category == "Medium (6-20)" ~ "Medium (6-20)",
        practice_size_category == "Large (21-100)" ~ "Large (21-100)",
        practice_size_category == "Very Large (>100)" ~ "Very Large (>100)",
        TRUE ~ "Unknown"
      ),
      levels = c("Solo (1)", "Small (2-5)", "Medium (6-20)",
                 "Large (21-100)", "Very Large (>100)", "Unknown")
    ),

    # Multi-location practice
    `Multi-Location Practice` = factor(
      case_when(
        multi_location_flag == 1 ~ "Yes",
        multi_location_flag == 0 ~ "No",
        TRUE ~ NA_character_
      ),
      levels = c("No", "Yes")
    ),

    # Practice type
    `Practice Type` = factor(
      case_when(
        practice_type == "Single Specialty" ~ "Single Specialty",
        practice_type == "OB/GYN Dedicated" ~ "OB/GYN Dedicated",
        practice_type == "Multi-Specialty" ~ "Multi-Specialty",
        TRUE ~ "Unknown"
      ),
      levels = c("Single Specialty", "OB/GYN Dedicated", "Multi-Specialty", "Unknown")
    ),

    # Medicare participation
    `Bills Medicare` = factor(
      case_when(
        bills_medicare == "Yes" ~ "Yes",
        bills_medicare == "No" ~ "No",
        bills_medicare == "Opted Out" ~ "Opted Out",
        TRUE ~ NA_character_
      ),
      levels = c("Yes", "No", "Opted Out")
    )
  )

# Remove rows with missing subspecialty
table1_data <- table1_data %>% filter(!is.na(Subspecialty))

cat(sprintf("  Final sample for Table 1: %s physicians\n",
            format(nrow(table1_data), big.mark = ",")))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 4: Generate Table 1 with gtsummary
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n[", as.character(Sys.time()), "] Creating Table 1...\n", sep = "")

# The 'tbl_summary' function creates a summary table of data.
table1 <- table1_data %>%
  gtsummary::tbl_summary(
    by = Subspecialty,
    statistic = list(
      gtsummary::all_continuous() ~ "{mean} ({sd})",
      gtsummary::all_categorical() ~ "{n} ({p}%)"
    ),
    digits = list(
      gtsummary::all_continuous() ~ c(1, 1),
      gtsummary::all_categorical() ~ c(0, 1)
    ),
    label = list(
      Age ~ "Age, years",
      `Years in Practice` ~ "Years in practice",
      Gender ~ "Gender",
      `ACOG District` ~ "ACOG District",
      `Practice Size` ~ "Practice size",
      `Multi-Location Practice` ~ "Multi-location practice",
      `Practice Type` ~ "Practice type",
      `Bills Medicare` ~ "Bills Medicare"
    ),
    missing = "no"
  ) %>%
  gtsummary::add_overall() %>%
  gtsummary::add_p(
    test = list(
      gtsummary::all_continuous() ~ "oneway.test",
      gtsummary::all_categorical() ~ "chisq.test"
    ),
    # use Monte Carlo p-values for all categorical tests
    test.args = list(
      gtsummary::all_categorical() ~ list(
        simulate.p.value = TRUE,
        B = 10000
      )
    ),
    # format everything with "<0.01" when appropriate
    pvalue_fun = function(x) {
      dplyr::case_when(
        is.na(x) ~ NA_character_,
        x < 0.01 ~ "<0.01",
        TRUE     ~ sprintf("%.2f", round(x, 2))
      )
    }
  ) %>%
  gtsummary::bold_p() %>%
  gtsummary::bold_labels() %>%
  gtsummary::modify_caption(
    "**Table 1. Demographic and Practice Characteristics of Gynecologic Surgical Subspecialists (2024)**"
  ) %>%
  gtsummary::modify_header(label ~ "**Characteristic**")



cat("  ✓ Table 1 created\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 5: Save Table 1
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n[", as.character(Sys.time()), "] Saving Table 1...\n", sep = "")

# Create output directory
table_dir <- here("manuscript/tables")
# The 'dir.create' function creates a directory.
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

# Save as Word document
table1_path <- file.path(table_dir, "table1_demographics.docx")

table1 %>%
  # The 'as_flex_table' function converts a gtsummary table to a flextable object.
  as_flex_table() %>%
  # The 'save_as_docx' function saves a flextable object to a Word document.
  flextable::save_as_docx(path = table1_path)

cat(sprintf("  ✓ Saved Word document: %s\n", table1_path))
cat(sprintf("    Size: %s\n",
            format(file.info(table1_path)$size, big.mark = ",")))

# Also save the filtered data
data_path <- here("data/table1_physicians.csv")
# The 'write_csv' function writes a tibble to a CSV file.
write_csv(table1_data, data_path)
cat(sprintf("  ✓ Saved filtered data: %s\n", data_path))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Summary
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("TABLE 1 GENERATION COMPLETE\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")
cat("Sample characteristics:\n")
cat(sprintf("  • Total physicians: %s\n", format(nrow(table1_data), big.mark = ",")))
for (i in seq_len(nrow(subspec_counts))) {
  cat(sprintf("  • %s: %s\n",
              subspec_counts$subspecialty_clean[i],
              format(subspec_counts$n_physicians[i], big.mark = ",")))
}
cat("\n")
cat("Variables included:\n")
cat("  • Age (years)\n")
cat("  • Years in practice\n")
cat("  • Gender\n")
cat("  • ACOG District (geographic region)\n")
cat("  • Practice size (solo/small/medium/large/very large)\n")
cat("  • Multi-location practice (yes/no)\n")
cat("  • Practice type (single specialty/OB/GYN dedicated/multi-specialty)\n")
cat("  • Bills Medicare (yes/no/opted out)\n")
cat("\n")
cat("Output files:\n")
cat(sprintf("  • Table 1 (Word): %s\n", table1_path))
cat(sprintf("  • Filtered data: %s\n", data_path))
cat("\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")

if (!interactive()) {
  cat("[", as.character(Sys.time()), "] Script completed successfully\n", sep = "")
}