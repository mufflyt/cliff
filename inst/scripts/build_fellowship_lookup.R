#!/usr/bin/env Rscript
# =============================================================================
# Build the ACGME fellowship-programs lookup table
# =============================================================================
# Moved out of R/infer_fellowship_training.R, where it sat behind an
# `if (!interactive())` guard and therefore executed during R CMD INSTALL and
# pkgload::load_all() -- writing files as a side effect of installing the
# package. A script belongs in inst/scripts/.
#
# Run from the package root:  Rscript inst/scripts/build_fellowship_lookup.R
#
# Requires load_freida_programs(), which was never ported out of
# mufflyt/isochrones; see R/unported_helpers.R.
# =============================================================================
suppressPackageStartupMessages({library(cliff); library(here)})

cat("\n")
cat(strrep("=", 70), "\n")
cat("FELLOWSHIP TRAINING INFERENCE MODULE\n")
cat(strrep("=", 70), "\n\n")

# Create and save programs lookup
programs <- create_otolaryngology_fellowship_programs()

# Save lookup table
output_dir <- here("data", "fellowship_lookup")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

saveRDS(programs, file.path(output_dir, "acgme_otolaryngology_programs.rds"))
write.csv(programs, file.path(output_dir, "acgme_otolaryngology_programs.csv"), row.names = FALSE)

cat(sprintf("\nSaved programs lookup to: %s\n", output_dir))
cat("\nTo use in Table 1 pipeline, add:\n")
cat("  source(here('R', 'infer_fellowship_training.R'))\n")
cat("  physicians <- add_fellowship_to_table1(physicians)\n")
