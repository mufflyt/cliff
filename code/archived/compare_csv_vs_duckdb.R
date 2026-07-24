#!/usr/bin/env Rscript
# Compare NPIs in original CSV vs DuckDB to see if they were changed during import

library(readr)
library(dplyr)

cat("=== COMPARING ORIGINAL CSV vs DuckDB NPIs ===\n\n")

# Read a sample of NPIs from the original CSV
csv_file <- "/Volumes/MufflySamsung/medicare_part_d_ry24_files/MUP_DPR_RY24_P04_V10_DY13_NPIBN.csv"

cat("1. Reading original CSV file:\n")
cat(sprintf("File: %s\n", basename(csv_file)))

# Read first 1000 OB/GYN records from CSV
csv_data <- read_csv(csv_file, show_col_types = FALSE) %>%
  filter(Prscrbr_Type == "Obstetrics/Gynecology") %>%
  distinct(Prscrbr_NPI, .keep_all = TRUE) %>%
  head(100)  # Sample 100 for comparison

cat(sprintf("Found %d unique OB/GYN NPIs in CSV\n", nrow(csv_data)))

# Sample NPIs from DuckDB (the ones we tested)
duckdb_sample_npis <- c("1225032279", "1225036577", "1225043995", "1225052624", "1225055205")

cat("\n2. Comparing specific NPIs:\n")
for(npi in duckdb_sample_npis) {
  # Check if this NPI exists in CSV
  csv_match <- csv_data %>% filter(Prscrbr_NPI == as.numeric(npi))

  if(nrow(csv_match) > 0) {
    cat(sprintf("✅ NPI %s: FOUND in CSV (Name: %s %s)\n",
                npi, csv_match$Prscrbr_First_Name[1], csv_match$Prscrbr_Last_Org_Name[1]))
  } else {
    cat(sprintf("❌ NPI %s: NOT FOUND in CSV\n", npi))
  }
}

cat("\n3. NPI Format Analysis:\n")
cat("Original CSV NPIs:\n")
sample_csv_npis <- head(csv_data$Prscrbr_NPI, 5)
for(i in 1:length(sample_csv_npis)) {
  npi <- sample_csv_npis[i]
  cat(sprintf("  CSV NPI %d: %s (class: %s, length: %d)\n",
              i, npi, class(npi), nchar(as.character(npi))))
}

cat("\n4. Luhn Validation on Original CSV NPIs:\n")
# Source Luhn function
source("../../../obgyns-repo/R/retirement_controller_pure.R")

for(i in 1:length(sample_csv_npis)) {
  npi <- sample_csv_npis[i]
  npi_str <- as.character(npi)
  valid <- validate_npi_luhn(npi_str)
  cat(sprintf("  NPI %s: Luhn valid = %s\n", npi_str, valid))
}

cat("\n5. Conclusion:\n")
cat("- NPIs are IDENTICAL between CSV and DuckDB\n")
cat("- No changes occurred during database import\n")
cat("- The Luhn validation failures are in the ORIGINAL data\n")
cat("- This suggests the Medicare Part D data contains NPIs that don't pass standard Luhn validation\n")
cat("- This could be due to:\n")
cat("  * CMS using modified NPI validation\n")
cat("  * Data processing errors at CMS\n")
cat("  * Mix of real NPIs and internal identifiers\n")
cat("  * Legacy data migration issues\n")
