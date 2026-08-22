#' @title Master Pipeline: Run All Workforce Analysis Scripts
#' @description This script executes the complete workforce analysis pipeline in the correct order.
#' It consolidates data, creates figures, renders the manuscript, and archives the outputs.
#' @author Tyler Muffly, MD / Claude Code
#' @date 2026-01-12
#' @param scenario_name The name of the fellowship scenario to use (e.g., "default", "optimistic"). Defaults to "default".
#' @usage Rscript code/00_RUN_ALL.R [scenario]
#' @example Rscript code/00_RUN_ALL.R optimistic
#' @seealso \code{\link{01_consolidate_workforce_data.R}}, \code{\link{02_create_figures.R}}, \code{\link{03_create_abstract_figure.R}}, \code{\link{save_run_metadata.R}}

#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Master Pipeline: Run All Workforce Analysis Scripts
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose: Execute complete workforce analysis pipeline in correct order
#
# Author: Tyler Muffly, MD / Claude Code
# Date: 2026-01-12
#
# Usage:
#   From command line:
#     cd /Users/tmuffly/cliff
#     Rscript code/00_RUN_ALL.R [scenario]
#
#   Examples:
#     Rscript code/00_RUN_ALL.R               # Uses 'default' scenario
#     Rscript code/00_RUN_ALL.R optimistic    # Uses 'optimistic' scenario
#     Rscript code/00_RUN_ALL.R pessimistic   # Uses 'pessimistic' scenario
#
#   From RStudio:
#     setwd("/Users/tmuffly/isochrones")
#     source("cliff/code/00_RUN_ALL.R")
#
# Runtime: ~3 seconds
#
# Outputs:
#   - data/workforce_projections_consolidated.csv
#   - cliff/figures/ (4 files: PNG and TIFF for 2 figures)
#   - cliff/manuscript/manuscript_WORKFORCE_CLIFF.html
#   - cliff/manuscript/manuscript_WORKFORCE_CLIFF.docx
#
# IMPORTANT: This script MUST be run from the isochrones project directory.
#            The script will check and provide helpful errors if run from wrong location.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# The 'here' library helps to create reproducible paths to files.
library(here)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Parse Command Line Arguments
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# The 'commandArgs' function retrieves command-line arguments passed to the script.
args <- commandArgs(trailingOnly = TRUE)
scenario_name <- if (length(args) > 0) args[1] else "default"

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Verify Project Structure
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Check that we can find the required files before proceeding.
# This script requires being run from the isochrones project directory.

required_file <- here::here("code/01_consolidate_workforce_data.R")

if (!file.exists(required_file)) {
  cat("\n")
  cat("❌ ERROR: Cannot find required script!\n")
  cat(sprintf("   Looking for: %s\n", required_file))
  cat(sprintf("   Current here() root: %s\n", here::here()))
  cat(sprintf("   Current working directory: %s\n", getwd()))
  cat("\n")
  cat("SOLUTION:\n")
  cat("   This script must be run from the isochrones project directory.\n")
  cat("   Either:\n")
  cat("   1. Change directory first:\n")
  cat("      setwd('/Users/tmuffly/cliff')\n")
  cat("      source('cliff/code/00_RUN_ALL.R')\n")
  cat("\n")
  cat("   2. Or run from command line:\n")
  cat("      cd /Users/tmuffly/cliff\n")
  cat("      Rscript code/00_RUN_ALL.R\n")
  cat("\n")
  stop("Script cannot proceed without correct project structure")
}

start_time <- Sys.time()

cat("\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("WORKFORCE CLIFF ANALYSIS - MASTER PIPELINE\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")
cat(sprintf("Started: %s\n", format(start_time, "%Y-%m-%d %H:%M:%S")))
cat(sprintf("Project root: %s\n", here::here()))
cat(sprintf("Fellowship scenario: %s\n", scenario_name))
cat("\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 1: Consolidate Workforce Data
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("STEP 1: Consolidating Workforce Data with Updated Fellowship Assumptions\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")

consolidated_csv <- here("data/workforce_projections_consolidated.csv")
force_rebuild    <- identical(Sys.getenv("CLIFF_FORCE_REBUILD"), "1")

if (file.exists(consolidated_csv) && !force_rebuild) {
  cat("✓ Seed data found — skipping Step 1 (set CLIFF_FORCE_REBUILD=1 to override)\n\n")
} else {
  step1_start <- Sys.time()
  step1_cmd <- sprintf("Rscript %s %s",
                       here("code/01_consolidate_workforce_data.R"),
                       scenario_name)
  step1_status <- system(step1_cmd)
  if (step1_status != 0) {
    stop("Step 1 failed with exit code ", step1_status)
  }
  step1_duration <- as.numeric(difftime(Sys.time(), step1_start, units = "secs"))
  cat(sprintf("\n✓ Step 1 completed in %.1f seconds\n\n", step1_duration))
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 2: Create Figures
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("STEP 2: Creating Figures\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")

step2_start <- Sys.time()
# The 'source' function executes an R script.
source(here("code/02_create_figures.R"))
step2_duration <- as.numeric(difftime(Sys.time(), step2_start, units = "secs"))

cat(sprintf("\n✓ Step 2 completed in %.1f seconds\n\n", step2_duration))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 3: Create Abstract Figure (SGS Style)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("STEP 3: Creating Abstract Figure (SGS Style)\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")

step3_start <- Sys.time()
# The 'source' function executes an R script.
source(here("code/03_create_abstract_figure.R"))
step3_duration <- as.numeric(difftime(Sys.time(), step3_start, units = "secs"))

cat(sprintf("\n✓ Step 3 completed in %.1f seconds\n\n", step3_duration))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 4: Render Manuscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("STEP 4: Rendering Manuscript\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")

step4_start <- Sys.time()

# The 'rmarkdown::render' function renders an R Markdown file to a specified format.
# Render to HTML
cat("Rendering HTML version...\n")
rmarkdown::render(
  here("manuscript/manuscript_WORKFORCE_CLIFF.Rmd"),
  output_format = "html_document",
  quiet = TRUE
)
cat("  ✓ HTML: cliff/manuscript/manuscript_WORKFORCE_CLIFF.html\n")

# Render to Word
cat("Rendering Word version...\n")
rmarkdown::render(
  here("manuscript/manuscript_WORKFORCE_CLIFF.Rmd"),
  output_format = "word_document",
  quiet = TRUE
)
cat("  ✓ Word: cliff/manuscript/manuscript_WORKFORCE_CLIFF.docx\n")

step4_duration <- as.numeric(difftime(Sys.time(), step4_start, units = "secs"))

cat(sprintf("\n✓ Step 4 completed in %.1f seconds\n\n", step4_duration))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Step 5: Geographic Concentration & Equity Metrics
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Supplementary distribution/equity analysis (Gini, HHI, Lorenz, demographic
# and access composition) computed from the committed enriched URPS rosters.
# Additive and non-fatal: a failure here never blocks the core manuscript
# outputs above. Skips cleanly if the enriched rosters are absent.

cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("STEP 5: Geographic Concentration & Equity Metrics\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")

step5_start          <- Sys.time()
concentration_script <- here("scripts/urps_concentration_equity_2026-08-01.R")
roster_inputs        <- c(
  here("data/abog_all_urps_ENRICHED_2026-07-22.csv"),
  here("data/abu_all_urps_ENRICHED_2026-07-22.csv")
)

if (!all(file.exists(roster_inputs))) {
  cat("⚠ Skipping Step 5 — enriched URPS rosters not found:\n")
  cat(sprintf("    %s\n", roster_inputs[!file.exists(roster_inputs)]))
  cat("\n")
} else {
  step5_status <- system(sprintf("Rscript %s", concentration_script))
  if (step5_status != 0) {
    warning("Step 5 (concentration & equity) failed with exit code ", step5_status,
            " — continuing; core manuscript outputs are unaffected.")
  } else {
    step5_duration <- as.numeric(difftime(Sys.time(), step5_start, units = "secs"))
    cat(sprintf("\n✓ Step 5 completed in %.1f seconds\n\n", step5_duration))
  }
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Final Summary
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

total_duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

cat("\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("PIPELINE COMPLETE\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")
cat(sprintf("Total runtime: %.1f seconds\n", total_duration))
cat("\n")
cat("Outputs created:\n")
cat("  ✓ Data: data/workforce_projections_consolidated.csv\n")
cat("  ✓ Figures: cliff/figures/ (6 files)\n")
cat("    - figure1_workforce_trajectories.png/tiff\n")
cat("    - figure2_replacement_gap.png/tiff\n")
cat("    - workforce_crisis_abstract.png/tiff (SGS style)\n")
cat("  ✓ Manuscript HTML: cliff/manuscript/manuscript_WORKFORCE_CLIFF.html\n")
cat("  ✓ Manuscript Word: cliff/manuscript/manuscript_WORKFORCE_CLIFF.docx\n")
cat("  ✓ Concentration & equity: data/urps_concentration_by_geography_2026-08-01.csv,\n")
cat("      urps_equity_demographics_*, urps_lorenz_states_*, urps_provider_rate_dispersion_*\n")
cat("      figures/urps_concentration_lorenz_2026-08-01.png/tiff\n")
cat("\n")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Archive Run Outputs with Metadata
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("ARCHIVING RUN OUTPUTS\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")

# The 'source' function executes an R script.
source(here("code/utils/save_run_metadata.R"))
# The 'save_run_metadata' function saves metadata about the current run to a file.
save_run_metadata(
  scenario_name = scenario_name,
  runtime_seconds = total_duration
)

cat("\n")
cat("To view results:\n")
cat("  open cliff/manuscript/manuscript_WORKFORCE_CLIFF.html\n")
cat("  open cliff/figures/workforce_crisis_abstract.png\n")
cat("\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("\n")
