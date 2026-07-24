#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Consolidate Existing Workforce Projection Results for Manuscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose: Integrate existing Monte Carlo simulation results from archived
#          analysis into clean dataset for manuscript inline statistics
#
# Inputs:  - enhanced_comparison_table_20250928_030546.csv (existing results)
#          - Standard deviations from statistical summaries document
#
# Outputs: - manuscript/data/workforce_projections_consolidated.csv
#
# Author: Tyler Muffly, MD / Claude Code
# Date: 2026-01-12
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
  library(glue)
})

# Shared data contract: constants + fail-loud validator. Ensures this generator
# cannot emit a zero/placeholder/inconsistent table and keeps horizon/threshold
# constants identical to the manuscript loader.
source(here::here("manuscript", "R", "workforce_data_contract.R"))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# PROVENANCE / SCENARIO WARNING (read before using this output)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# The archived INPUT_CSV encodes the "historical_2025" fellowship-entry scenario
# (annual_entrants URPS=47, GO=60, MIGS=51). This does NOT reproduce the
# PUBLISHED manuscript, which uses the "default" scenario (entrants 60/50/45).
# The authoritative frozen manuscript table is:
#   cliff/data/workforce_projections_consolidated.csv   (the SSOT; do NOT clobber)
# This script therefore writes to manuscript/data/ ONLY and must not be pointed
# at cliff/data/ without PI sign-off (it would silently change published ratios).
cat("\n", strrep("!", 74), "\n", sep = "")
cat("PROVENANCE: input = historical_2025 scenario (entrants 47/60/51).\n")
cat("This is NOT the published default scenario (entrants 60/50/45).\n")
cat("SSOT for the paper is cliff/data/workforce_projections_consolidated.csv.\n")
cat(strrep("!", 74), "\n\n", sep = "")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Configuration
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

INPUT_CSV <- Sys.getenv(
  "WORKFORCE_CONSOLIDATE_INPUT_CSV",
  unset = here(
    "docs/isochrones_deep_archive/2025-12-07",
    "legacy_matching_strategies_2025-12-05",
    "research_forecasting/comprehensive_forecasting",
    "enhanced_comparison_table_20250928_030546.csv"
  )
)

# Write to manuscript/data/ (support artifact) — NEVER the cliff SSOT.
OUTPUT_CSV <- Sys.getenv(
  "WORKFORCE_CONSOLIDATE_OUTPUT_CSV",
  unset = here("manuscript/data/workforce_projections_consolidated.csv")
)

# Standard deviations manually transcribed from Monte Carlo simulation output
# (enhanced_workforce_statistical_summaries document, run 2025-09-28).
# CIs are parametric: projected_mean ± 1.96 × SD — NOT empirical percentiles.
# To use empirical quantiles, rerun the simulation and extract quantile(sims, c(0.025, 0.975)).
SD_VALUES <- tribble(
  ~subspecialty, ~sd_2029,
  "URPS",       15.2,
  "GO",          16.1,
  "MIGS",         11.0
)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main Processing
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat(paste0("[", Sys.time(), "] Loading existing results from archived analysis\n"))

# Verify input file exists
if (!file.exists(INPUT_CSV)) {
  stop(sprintf("Input file not found: %s", INPUT_CSV))
}

# Load existing CSV
enhanced_table <- read_csv(INPUT_CSV, show_col_types = FALSE)

cat(sprintf("  Loaded %d rows from %s\n", nrow(enhanced_table), basename(INPUT_CSV)))

# Required minimal inputs (fail loud if the archived schema drifts).
.required_inputs <- c("subspecialty", "baseline_workforce", "avg_retirement_rate",
                      "avg_annual_retirements", "annual_entrants")
.missing_inputs <- setdiff(.required_inputs, names(enhanced_table))
if (length(.missing_inputs) > 0) {
  stop(sprintf("Input CSV missing required column(s): %s",
               paste(.missing_inputs, collapse = ", ")))
}

# Pad OPTIONAL precomputed columns with NA so the derivation below can uniformly
# coalesce(existing, derived). Older archived tables omit these entirely.
for (.opt in c("projected_workforce", "percent_change", "replacement_ratio")) {
  if (!.opt %in% names(enhanced_table)) enhanced_table[[.opt]] <- NA_real_
}

# Display original data structure
cat("\nOriginal data structure:\n")
print(enhanced_table)

# Consolidate and calculate confidence intervals
cat("\n[", as.character(Sys.time()), "] Processing data\n", sep = "")

# Canonical abbreviation -> full-name map (single place; no scattered literals).
SUBSPECIALTY_FULL_NAMES <- c(
  URPS = "Urogynecology and Reconstructive Pelvic Surgery",
  GO    = "Gynecologic Oncology",
  MIGS   = "Minimally Invasive Gynecologic Surgery"
)

consolidated <- enhanced_table %>%
  # Save original abbreviation before expanding
  mutate(
    subspecialty_abbrev = subspecialty,
    subspecialty_full = dplyr::coalesce(
      unname(SUBSPECIALTY_FULL_NAMES[subspecialty]), subspecialty
    )
  ) %>%
  # Join with standard deviations (frozen archival SDs)
  left_join(SD_VALUES, by = c("subspecialty_abbrev" = "subspecialty")) %>%
  # Derive projection quantities from first principles, using the SAME
  # horizon/threshold constants as the manuscript loader. Anything the input
  # already provides is preserved via coalesce().
  mutate(
    replacement_ratio = dplyr::coalesce(
      replacement_ratio, annual_entrants / avg_annual_retirements
    ),
    projected_workforce = dplyr::coalesce(
      projected_workforce,
      baseline_workforce +
        WORKFORCE_PROJECTION_HORIZON_YEARS * (annual_entrants - avg_annual_retirements)
    ),
    percent_change = dplyr::coalesce(
      percent_change,
      100 * (projected_workforce - baseline_workforce) / baseline_workforce
    )
  ) %>%
  # Calculate 95% CI using parametric method (mean ± z * SD)
  mutate(
    ci95_lower = round(projected_workforce - WORKFORCE_CI_Z95 * sd_2029),
    ci95_upper = round(projected_workforce + WORKFORCE_CI_Z95 * sd_2029),
    # Ensure no negative values
    ci95_lower = pmax(ci95_lower, 0)
  ) %>%
  # Select and rename columns for manuscript use
  transmute(
    subspecialty = subspecialty_full,
    subspecialty_abbrev = subspecialty_abbrev,
    baseline_2025 = baseline_workforce,
    projected_2029 = projected_workforce,
    sd_2029 = sd_2029,
    ci95_lower = ci95_lower,
    ci95_upper = ci95_upper,
    percent_change = percent_change,
    annual_retirement_rate = avg_retirement_rate,
    avg_annual_retirements = avg_annual_retirements,
    annual_entrants = annual_entrants,
    replacement_ratio = replacement_ratio,
    # Classification based on replacement ratio (shared thresholds)
    replacement_assessment = classify_replacement(replacement_ratio),
    # Total fellowship output over the projection horizon (same window as
    # total_retirements_4yr, so the two cumulative columns are directly
    # comparable — see the 2026-07-15 horizon-standardization fix).
    fellowship_total_4yr = annual_entrants * WORKFORCE_PROJECTION_HORIZON_YEARS,
    # Total projected retirements over the projection horizon
    total_retirements_4yr = round(avg_annual_retirements * WORKFORCE_PROJECTION_HORIZON_YEARS)
  )

# Display processed data
cat("\nConsolidated data:\n")
print(consolidated, width = Inf)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Validation
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n[", as.character(Sys.time()), "] Running validation checks\n", sep = "")

# Check 1: No missing values in critical columns
critical_cols <- c("baseline_2025", "projected_2029", "replacement_ratio")
missing_check <- consolidated %>%
  select(all_of(critical_cols)) %>%
  summarise(across(everything(), ~sum(is.na(.))))

if (any(missing_check > 0)) {
  cat("WARNING: Missing values detected:\n")
  print(missing_check)
} else {
  cat("  \u2713 No missing values in critical columns\n")
}

# Check 2: Replacement ratios match calculated values
ratio_check <- consolidated %>%
  mutate(
    calculated_ratio = annual_entrants / avg_annual_retirements,
    ratio_diff = abs(calculated_ratio - replacement_ratio)
  )

max_diff <- max(ratio_check$ratio_diff, na.rm = TRUE)
if (max_diff > 0.01) {
  cat(sprintf("WARNING: Replacement ratio mismatch (max diff: %.3f)\n", max_diff))
  print(select(ratio_check, subspecialty_abbrev, replacement_ratio, calculated_ratio, ratio_diff))
} else {
  cat("  \u2713 Replacement ratios mathematically correct\n")
}

# Check 3: Confidence intervals sensible (CI width <50% of mean)
ci_check <- consolidated %>%
  mutate(
    ci_width = ci95_upper - ci95_lower,
    ci_percent = 100 * ci_width / projected_2029
  )

if (any(ci_check$ci_percent > 50, na.rm = TRUE)) {
  cat("WARNING: Very wide confidence intervals detected\n")
  print(select(ci_check, subspecialty_abbrev, projected_2029, ci95_lower, ci95_upper, ci_percent))
} else {
  cat("  \u2713 Confidence intervals reasonable (all <50% of mean)\n")
}

# Check 4: No negative projections
if (any(consolidated$projected_2029 < 0 | consolidated$ci95_lower < 0)) {
  cat("ERROR: Negative workforce projections detected!\n")
  print(select(consolidated, subspecialty_abbrev, projected_2029, ci95_lower, ci95_upper))
} else {
  cat("  \u2713 All workforce projections positive\n")
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Save Output
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Create output directory if needed
dir.create(dirname(OUTPUT_CSV), recursive = TRUE, showWarnings = FALSE)

# FAIL-LOUD contract guard (2026-07-14): never write a zero/placeholder/
# inconsistent table. This is the guard that would have stopped the all-zero
# 7-subspecialty scaffold from ever reaching disk.
validate_workforce_data(consolidated, source_hint = "manuscript_consolidate_existing_results")

# Write consolidated data
write_csv(consolidated, OUTPUT_CSV)

cat(sprintf("\n[%s] SUCCESS: Consolidated data saved to:\n", Sys.time()))
cat(sprintf("  %s\n", OUTPUT_CSV))
cat(sprintf("  %d rows, %d columns\n", nrow(consolidated), ncol(consolidated)))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Summary Statistics
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat("\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("SUMMARY: Workforce Projections (2025-2029)\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

summary_table <- consolidated %>%
  transmute(
    Subspecialty = subspecialty_abbrev,
    `2025` = format(baseline_2025, big.mark = ","),
    `2029` = sprintf("%s ± %.1f", format(round(projected_2029), big.mark = ","), sd_2029),
    `95% CI` = sprintf("[%s, %s]",
                       format(ci95_lower, big.mark = ","),
                       format(ci95_upper, big.mark = ",")),
    `Change` = sprintf("%.1f%%", percent_change),
    `Ratio` = sprintf("%.2f (%s)", replacement_ratio, replacement_assessment)
  )

print(summary_table, width = Inf)

cat("\nKey Findings:\n")
cat(sprintf("  • Total baseline workforce: %s physicians\n",
            format(sum(consolidated$baseline_2025), big.mark = ",")))
cat(sprintf("  • Total projected 2029: %s physicians\n",
            format(sum(consolidated$projected_2029), big.mark = ",")))
cat(sprintf("  • Net change: %+.0f physicians (%.1f%%)\n",
            sum(consolidated$projected_2029) - sum(consolidated$baseline_2025),
            100 * (sum(consolidated$projected_2029) - sum(consolidated$baseline_2025)) / sum(consolidated$baseline_2025)))
cat(sprintf("  • Subspecialties above replacement: %d/%d\n",
            sum(consolidated$replacement_ratio >= WORKFORCE_REPLACEMENT_ABOVE_MIN),
            nrow(consolidated)))
cat(sprintf("  • Subspecialties at replacement: %d/%d\n",
            sum(consolidated$replacement_ratio >= WORKFORCE_REPLACEMENT_AT_MIN &
                consolidated$replacement_ratio < WORKFORCE_REPLACEMENT_ABOVE_MIN),
            nrow(consolidated)))

cat("\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Script Complete
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if (!interactive()) {
  cat("\n[", as.character(Sys.time()), "] Script completed successfully\n", sep = "")
}