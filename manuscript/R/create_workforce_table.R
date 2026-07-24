#!/usr/bin/env Rscript
#' @title Create Manuscript Table for Workforce Statistics
#'
#' @description
#' Script to format workforce projection data (from Monte Carlo simulation)
#' into a publication-ready table and export to Word document format.
#' Data is hardcoded from simulation output captured 2026-01-12.
#'
#' @details
#' This is a standalone script (not a function). Run it directly:
#' \preformatted{
#'   Rscript manuscript/R/create_workforce_table.R
#' }
#'
#' Input:
#' \itemize{
#'   \item Consolidated workforce projection data (hardcoded in script from
#'     Monte Carlo simulation output)
#' }
#'
#' Output:
#' \itemize{
#'   \item \code{manuscript/tables/workforce_projections_table.docx}
#' }
#'
#' @family tables
#'
#' @importFrom tidyverse tribble transmute
#' @importFrom here here
#' @importFrom officer read_docx body_add_par body_add_flextable fp_border
#' @importFrom flextable flextable font fontsize bold align width
#'   border_outer border_inner_h border_inner_v bg padding
#'
#' @return Writes a DOCX file to
#'   \code{manuscript/tables/workforce_projections_table.docx}.
#'   No return value (script exits on completion).
#'
#' @examples
#' \dontrun{
#' # Run from command line:
#' #   Rscript manuscript/R/create_workforce_table.R
#' #
#' # Or source in R:
#' source(here::here("manuscript", "R", "create_workforce_table.R"))
#' }
#'
#' @author Tyler Muffly, MD / Claude Code
#'
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Create Manuscript Table for Workforce Statistics
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
  library(officer)
  library(flextable)
  library(checkmate)
})
# [ORCHESTRATOR NATIVE] Utilities
source(here::here("R", "safe_divide.R"))
#' Main entry point for Workforce Table
#'
#' @param input_paths [list] Named list of input file paths.
#' @param output_paths [list] Named list of output file paths.
#' @param run_id [character] Pipeline run identifier.
#'
#' @export
main <- function(input_paths = NULL, output_paths = NULL, run_id = NULL) {
  # [HARDENING] Layer 1: Input Validation
  checkmate::assert_list(input_paths, null.ok = TRUE)
  checkmate::assert_list(output_paths, null.ok = TRUE)
  checkmate::assert_string(run_id, null.ok = TRUE)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Configuration
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# BUG FIX (2026-04-18): Use orchestrator-injected output path if available,
# fall back to here() for standalone execution.
OUTPUT_DOCX <- if (!is.null(output_paths$workforce_docx)) {
  output_paths$workforce_docx
} else {
  here("manuscript/tables/workforce_projections_table.docx")
}
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Data Preparation
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Create the data (from your R output)
workforce_data <- tribble(
  ~subspecialty, ~subspecialty_abbrev, ~baseline_2025, ~projected_2029, ~sd_2029, ~ci95_lower, ~ci95_upper, ~percent_change, ~annual_retirement_rate, ~avg_annual_retirements, ~annual_entrants, ~replacement_ratio, ~replacement_assessment, ~fellowship_total_5yr, ~total_retirements_4yr,
  "Female Pelvic Medicine & Reconstructive Surgery", "FPMRS", 1283, 1301, 15.2, 1271, 1330, 1.37, 4.4, 55.6, 60, 1.08, "Marginal", 300, 222,
  "Gynecologic Oncology", "GO", 1352, 1278, 16.1, 1246, 1310, -5.47, 5.2, 68.5, 50, 0.730, "Insufficient", 250, 274,
  "Minimally Invasive Gynecologic Surgery", "MIG", 767, 835, 11.0, 814, 857, 8.92, 3.4, 27.9, 45, 1.61, "Adequate", 225, 112
)
# ── Hardcoded data validation ─────────────────────────────────────────────
# RETRACTION GUARD: workforce_data is hardcoded from Monte Carlo simulation output
# (captured 2026-01-12). Update tribble() whenever the simulation is re-run.
# Validate structure and plausible value ranges before producing the table.
{
  required_wf_cols <- c("subspecialty", "baseline_2025", "projected_2029",
                        "percent_change", "replacement_ratio", "replacement_assessment")
  missing_wf_cols <- setdiff(required_wf_cols, names(workforce_data))
  if (length(missing_wf_cols) > 0) {
    stop("[create_workforce_table] RETRACTION GUARD: workforce_data missing required columns: ",
         paste(missing_wf_cols, collapse = ", "), call. = FALSE)
  }
  if (nrow(workforce_data) == 0) {
    stop("[create_workforce_table] RETRACTION GUARD: workforce_data has 0 rows", call. = FALSE)
  }
  # RETRACTION GUARD (2026-05-08): subspecialty completeness. The manuscript
  # reports on the canonical OB/GYN subspecialty set defined in
  # config/cohort_criteria.yml. A workforce table that silently omits any of
  # them publishes an incomplete picture under the same caption — exactly
  # the failure mode that bit prior runs (only 3 of 7 subspecialties shown).
  .canonical_subspec_path <- here("config", "cohort_criteria.yml")
  if (file.exists(.canonical_subspec_path)) {
    .canonical_subspec <- yaml::read_yaml(.canonical_subspec_path)$subspecialties
    if (length(.canonical_subspec) > 0L && nrow(workforce_data) < length(.canonical_subspec)) {
      stop(sprintf(
        paste0(
          "[create_workforce_table] RETRACTION GUARD: workforce_data has %d ",
          "row(s) but config/cohort_criteria.yml declares %d canonical ",
          "subspecialties (%s). The hardcoded tribble() must be regenerated ",
          "from the simulation to cover every subspecialty.\n",
          "  Present: %s"
        ),
        nrow(workforce_data),
        length(.canonical_subspec),
        paste(.canonical_subspec, collapse = ", "),
        paste(workforce_data$subspecialty_abbrev %||% workforce_data$subspecialty,
              collapse = ", ")
      ), call. = FALSE)
    }
  }
  # Plausible range guards
  if (any(workforce_data$baseline_2025 < 100 | workforce_data$baseline_2025 > 10000, na.rm = TRUE)) {
    stop("[create_workforce_table] RETRACTION GUARD: baseline_2025 outside plausible range [100, 10000]. ",
         "Check hardcoded data.", call. = FALSE)
  }
  if (any(abs(workforce_data$percent_change) > 50, na.rm = TRUE)) {
    stop("[create_workforce_table] RETRACTION GUARD: percent_change outside [-50%, +50%]. ",
         "Verify simulation output.", call. = FALSE)
  }
  if (any(workforce_data$replacement_ratio < 0 | workforce_data$replacement_ratio > 5, na.rm = TRUE)) {
    stop("[create_workforce_table] RETRACTION GUARD: replacement_ratio outside [0, 5]. ",
         "Verify simulation output.", call. = FALSE)
  }
  # RETRACTION GUARD [Workforce Table]: annual_retirement_rate must be in [0, 100]
  .bad_ret_rate <- sum(workforce_data$annual_retirement_rate < 0 |
                         workforce_data$annual_retirement_rate > 100, na.rm = TRUE)
  if (.bad_ret_rate > 0)
    stop(sprintf("[create_workforce_table] RETRACTION GUARD [Workforce Table]: %d values of annual_retirement_rate outside [0, 100]",
                 .bad_ret_rate), call. = FALSE)
  valid_outlook <- c("Adequate", "Marginal", "Insufficient")
  bad_outlook <- setdiff(unique(workforce_data$replacement_assessment), valid_outlook)
  if (length(bad_outlook) > 0) {
    stop("[create_workforce_table] RETRACTION GUARD: unexpected replacement_assessment values: ",
         paste(bad_outlook, collapse = ", "), ". Expected: ", paste(valid_outlook, collapse = "/"),
         call. = FALSE)
  }
  # RETRACTION GUARD: NA in CI bounds → sprintf produces "NA-NA" in table
  n_na_ci <- sum(is.na(workforce_data$ci95_lower) | is.na(workforce_data$ci95_upper))
  if (n_na_ci > 0) {
    stop(sprintf(
      "[create_workforce_table] RETRACTION GUARD: %d row(s) have NA ci95_lower or ci95_upper — sprintf would produce 'NA-NA' in the 95%% CI column.",
      n_na_ci
    ), call. = FALSE)
  }
  # RETRACTION GUARD: NA annual_entrants → as.character produces "NA" in table
  n_na_ent <- sum(is.na(workforce_data$annual_entrants))
  if (n_na_ent > 0) {
    stop(sprintf(
      "[create_workforce_table] RETRACTION GUARD: %d row(s) have NA annual_entrants — as.character() would produce 'NA' in the Annual Entrants column.",
      n_na_ent
    ), call. = FALSE)
  }
  cat(sprintf("[create_workforce_table] Input validation passed (%d subspecialties)\n",
              nrow(workforce_data)))
}
# FIX 2026-05-22 (Round 47 R5): four cat() log lines (here, L215, L266,
# L319) use bare Sys.time() in log output. Under strict reproducibility
# mode, the rendered log is non-deterministic. Define a helper that
# pins to default_reference_year()-anchored "YYYY-01-01 00:00:00 UTC"
# under strict, else returns wall-clock Sys.time(). Defines once at the
# top of the script; reused at all 4 sites.
#' @title Internal Helper: .repro_now
#' @keywords internal
.repro_now <- function() {
  if (identical(Sys.getenv("REPRODUCIBILITY_MODE", "relaxed"), "strict")) {
    if (!exists("default_reference_year", mode = "function", inherits = TRUE)) {
      source(here::here("R", "utils", "default_reference_year.R"))
    }
    sprintf("%d-01-01 00:00:00 UTC", default_reference_year())
  } else {
    as.character(Sys.time())
  }
}
cat(paste0("[", .repro_now(), "] Formatting workforce data for manuscript\n"))
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Format Table for Manuscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Create formatted table
manuscript_table <- workforce_data %>%
  transmute(
    `Subspecialty` = subspecialty,
    `Baseline\n2025` = format(baseline_2025, big.mark = ","),
    `Projected\n2029` = format(round(projected_2029), big.mark = ","),
    `95% CI` = sprintf("%s-%s",
                      format(ci95_lower, big.mark = ","),
                      format(ci95_upper, big.mark = ",")),
    `Change\n(%)` = sprintf("%.1f%%", percent_change),
    `Annual\nRetirement\nRate (%)` = sprintf("%.1f%%", annual_retirement_rate),
    `Annual\nEntrants` = as.character(annual_entrants),
    `Replacement\nRatio` = sprintf("%.2f", replacement_ratio),
    `Workforce\nOutlook` = replacement_assessment
  )
cat(sprintf("  Formatted %d rows for publication\n", nrow(manuscript_table)))
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Create Flextable
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
cat(paste0("[", .repro_now(), "] Creating formatted table\n"))
# Create flextable object
ft <- flextable(manuscript_table)
# Apply formatting
ft <- ft %>%
  # Set fonts
  font(fontname = "Times New Roman", part = "all") %>%
  fontsize(size = 10, part = "body") %>%
  fontsize(size = 10, part = "header") %>%
  # Format header
  bold(part = "header") %>%
  align(align = "center", part = "header") %>%
  # Format body
  align(j = 1, align = "left", part = "body") %>%   # Subspecialty names left-aligned
  align(j = 2:9, align = "center", part = "body") %>%  # Numbers centered
  # Set column widths (in inches)
  width(j = 1, width = 2.5) %>%   # Subspecialty
  width(j = 2:4, width = 0.8) %>% # Numeric columns
  width(j = 5, width = 0.7) %>%   # Change %
  width(j = 6, width = 0.8) %>%   # Retirement rate
  width(j = 7, width = 0.7) %>%   # Annual entrants
  width(j = 8, width = 0.8) %>%   # Replacement ratio
  width(j = 9, width = 1.0) %>%   # Outlook
  # Add borders
  border_outer(border = fp_border(width = 2), part = "all") %>%
  border_inner_h(border = fp_border(width = 1), part = "all") %>%
  border_inner_v(border = fp_border(width = 1), part = "all") %>%
  # Color code the Workforce Outlook column
  bg(j = 9, i = ~ `Workforce\nOutlook` == "Adequate",
     bg = "#d4edda", part = "body") %>%
  bg(j = 9, i = ~ `Workforce\nOutlook` == "Marginal",
     bg = "#fff3cd", part = "body") %>%
  bg(j = 9, i = ~ `Workforce\nOutlook` == "Insufficient",
     bg = "#f8d7da", part = "body") %>%
  # Add padding
  padding(padding = 3, part = "all")
cat("  Applied formatting and styling\n")
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Create Word Document
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
cat(paste0("[", .repro_now(), "] Creating Word document\n"))
# Create output directory
dir.create(dirname(OUTPUT_DOCX), recursive = TRUE, showWarnings = FALSE)
# Create Word document
doc <- read_docx()
# Add title
doc <- doc %>%
  body_add_par("Table 1. Workforce Projections for Gynecologic Subspecialties (2025-2029)",
               style = "heading 1") %>%
  body_add_par("", style = "Normal")  # Blank line
# Add the table
doc <- doc %>%
  body_add_flextable(ft)
# Add table footnote
doc <- doc %>%
  body_add_par("", style = "Normal") %>%  # Blank line
  body_add_par(paste0(
    "Note: Projections based on Monte Carlo simulation (n=10,000 iterations). ",
    "95% CI = 95% confidence interval. ",
    "Replacement ratio = annual fellowship graduates / average annual retirements. ",
    "Workforce outlook categories: Adequate (≥1.2), Marginal (0.8-1.19), Insufficient (<0.8)."
  ), style = "Normal")
# Save document
print(doc, target = OUTPUT_DOCX)
# ── Post-write guard ──────────────────────────────────────────────────────
if (!file.exists(OUTPUT_DOCX)) {
  stop("[create_workforce_table] RETRACTION GUARD: Output DOCX not created: ", OUTPUT_DOCX,
       call. = FALSE)
}
docx_size <- file.info(OUTPUT_DOCX)$size
# RETRACTION GUARD (2026-03-08): file.info()$size returns NA on filesystem failure.
# NA < 5000L evaluates to NA (not TRUE), silently bypassing this guard — the script
# would report "SUCCESS" even though the file size is unknown.
if (is.na(docx_size)) {
  stop("[create_workforce_table] RETRACTION GUARD: Cannot determine size of output DOCX. ",
       "file.info() returned NA — check filesystem permissions and disk space. File: ",
       OUTPUT_DOCX, call. = FALSE)
}
if (docx_size < 5000L) {
  stop(sprintf(
    "[create_workforce_table] RETRACTION GUARD: Output DOCX is suspiciously small (%d bytes) — flextable may have failed silently. Check: %s",
    docx_size, OUTPUT_DOCX
  ), call. = FALSE)
}
cat(sprintf("[create_workforce_table] Post-write guard passed (%.1f KB)\n", docx_size / 1024))
cat(sprintf("\n[%s] SUCCESS: Manuscript table saved to:\n", .repro_now()))
cat(sprintf("  %s\n", OUTPUT_DOCX))
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Summary
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
cat("\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat("Table Summary\n")
cat(paste0(rep("=", 70), collapse = ""), "\n")
cat(sprintf("  Subspecialties: %d\n", nrow(manuscript_table)))
cat(sprintf("  Columns: %d\n", ncol(manuscript_table)))
cat(sprintf("  Output format: Microsoft Word (.docx)\n"))
.wf_final_sz <- file.info(OUTPUT_DOCX)$size
if (is.na(.wf_final_sz))
  stop(sprintf("[create_workforce_table] RETRACTION GUARD: file.info()$size=NA (stat failed) for: %s", OUTPUT_DOCX), call. = FALSE)
cat(sprintf("  File size: %.1f KB\n", .wf_final_sz / 1024))
cat(paste0(rep("=", 70), collapse = ""), "\n")
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Script Complete
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
if (!interactive()) {
  cat("\n[", as.character(Sys.time()), "] Script completed successfully\n", sep = "")
}
} # end main()
# Execution guard
if (sys.nframe() == 0) {
  main()
}
