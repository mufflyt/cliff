#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Consolidate Existing Workforce Projection Results for Manuscript (Step 5.0)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose: Integrate existing Monte Carlo simulation results from archived
#          analysis into clean dataset for manuscript inline statistics.
#
# Inputs:  - enhanced_comparison_table_20250928_030546.csv (archived results)
#          - Standard deviations from statistical summaries document
#
# Outputs: - manuscript/data/workforce_projections_consolidated.csv
#
# Author: Tyler Muffly, MD / Claude Code
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Attach only what this file actually uses. Every call below is namespace
# qualified except tribble(), so dplyr/readr/tibble are the whole surface;
# tidyverse and glue were attached but never called.
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(here)
})

# Bug 1: is_test_mode() must be sourced unconditionally at file scope so it is
# available before main() is entered (standalone Rscript and test harness paths).
source(here::here("R", "test_mode_contracts.R"))

# Shared data contract: constants + fail-loud validator.
#
# manuscript/ is excluded from the built package (.Rbuildignore), so this source()
# MUST NOT be unconditional: at install time the file is absent and lazy-loading
# the package fails with "unable to load R code in package 'cliff'". This file is
# a script (see the shebang) that runs from the source tree, where the contract is
# present; main() below is what needs the constants, and it is never called during
# installation. Guarded rather than moved because
# tests/testthat/test-step-5.0-workforce-saboteur-bugs.R reads this file at
# here::here("R", "manuscript_consolidate_existing_results.R").
.contract_path <- here::here("manuscript", "R", "workforce_data_contract.R")
if (file.exists(.contract_path)) source(.contract_path)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# main() — all processing is inside here; sourcing this file does NOT run it.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
main <- function() {

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # TEST_MODE stub — short-circuits real I/O for unit tests.
  # Uses doubles (not integers) for ci95 columns to match production column TYPES.
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  if (is_test_mode()) {
    message("[Step 5.0] TEST_MODE active \u2014 returning stub data.")
    stub <- tibble::tribble(
      ~subspecialty,                                       ~subspecialty_abbrev,
      ~baseline_2025, ~projected_2029, ~sd_2029,
      ~ci95_lower,    ~ci95_upper,     ~percent_change,
      ~annual_retirement_rate, ~avg_annual_retirements,  ~annual_entrants,
      ~replacement_ratio,
      ~fellowship_total_4yr,   ~total_retirements_4yr,   ~ci95_lower_clamped,

      # Source CSV row order: subspecialty_abbrev = c("FPMRS", "GO", "MIG", ...)
      "Female Pelvic Medicine & Reconstructive Surgery", "FPMRS",
      1283L, 1519.0, 15.2, 1489.0, 1549.0, 18.4,
      4.4, 55.6, 70L, 1.26, 280L, 222L, FALSE,

      "Gynecologic Oncology", "GO",
      1052L, 1309.8, 16.1, 1278.0, 1341.0, 24.5,
      1.0, 10.6, 75L, 7.11, 300L, 42L, FALSE,

      "Minimally Invasive Gynecologic Surgery", "MIG",
      605L, 776.0, 11.0, 754.0, 798.0, 28.3,
      0.7, 4.2, 47L, 11.06, 188L, 17L, FALSE
    ) %>%
      # replacement_assessment is a pure function of the ratio (SSOT: classify_replacement,
      # manuscript/R/workforce_data_contract.R). Derive it here so the fixture cannot silently
      # drift from its own ratios if a stub ratio is ever edited for a new test scenario, and
      # so the stub is classified by the SAME function the production path (line ~209) uses.
      dplyr::mutate(replacement_assessment = classify_replacement(replacement_ratio)) %>%
      dplyr::relocate(replacement_assessment, .after = replacement_ratio)
    return(invisible(stub))
  }

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # PROVENANCE WARNING
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  cat("\n", strrep("!", 74), "\n", sep = "")
  cat("PROVENANCE: input = historical_2025 scenario (entrants 47/60/51).\n")
  cat("This is NOT the published default scenario.\n")
  cat("SSOT for the paper is data/workforce_projections_consolidated.csv.\n")
  cat(strrep("!", 74), "\n\n", sep = "")

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Configuration — output path (Bug 2: support both DAG keys)
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  output_paths <- list(
    workforce_csv         = Sys.getenv("WORKFORCE_CONSOLIDATE_OUTPUT_CSV",
                                       unset = here::here("manuscript", "data",
                                                          "workforce_projections_consolidated.csv")),
    workforce_projections = Sys.getenv("WORKFORCE_CONSOLIDATE_OUTPUT_CSV",
                                       unset = here::here("manuscript", "data",
                                                          "workforce_projections_consolidated.csv"))
  )
  OUTPUT_CSV <- output_paths$workforce_csv %||% output_paths$workforce_projections

  INPUT_CSV <- Sys.getenv(
    "WORKFORCE_CONSOLIDATE_INPUT_CSV",
    unset = here::here(
      "docs/isochrones_deep_archive/2025-12-07",
      "legacy_matching_strategies_2025-12-05",
      "research_forecasting/comprehensive_forecasting",
      "enhanced_comparison_table_20250928_030546.csv"
    )
  )

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Standard deviations (inside main — NOT at file scope; Bug 9)
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  SD_VALUES <- tribble(
    ~subspecialty, ~sd_2029,
    "URPS",        15.2,
    "GO",          16.1,
    "MIGS",        11.0,
    "FPMRS",       15.2,
    "MIG",         11.0
  )

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Load input
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  cat(paste0("[", Sys.time(), "] Loading existing results from archived analysis\n"))

  if (!file.exists(INPUT_CSV)) {
    stop(sprintf("Input file not found: %s", INPUT_CSV), call. = FALSE)
  }

  enhanced_table <- readr::read_csv(INPUT_CSV, show_col_types = FALSE)
  cat(sprintf("  Loaded %d rows from %s\n", nrow(enhanced_table), basename(INPUT_CSV)))

  # Bug 4 — required source columns asserted up front with a clear stop().
  required_source_cols <- c("subspecialty", "baseline_workforce", "avg_retirement_rate",
                             "avg_annual_retirements", "annual_entrants")
  missing_source_cols <- setdiff(required_source_cols, names(enhanced_table))
  if (length(missing_source_cols) > 0) {
    stop(sprintf("Source workforce CSV is missing required column(s): %s  [file: %s]",
                 paste(missing_source_cols, collapse = ", "), basename(INPUT_CSV)),
         call. = FALSE)
  }

  for (.opt in c("projected_workforce", "percent_change", "replacement_ratio")) {
    if (!.opt %in% names(enhanced_table)) enhanced_table[[.opt]] <- NA_real_
  }

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Canonical abbreviation map
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  SUBSPECIALTY_FULL_NAMES <- c(
    URPS  = "Urogynecology and Reconstructive Pelvic Surgery",
    GO    = "Gynecologic Oncology",
    MIGS  = "Minimally Invasive Gynecologic Surgery",
    FPMRS = "Female Pelvic Medicine & Reconstructive Surgery",
    MIG   = "Minimally Invasive Gynecologic Surgery"
  )

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Processing
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  cat("\n[", as.character(Sys.time()), "] Processing data\n", sep = "")

  consolidated <- enhanced_table %>%
    dplyr::mutate(
      # Bug 5: normalize before join so 'FPMRS ' / 'fpmrs' all match.
      subspecialty = toupper(trimws(subspecialty))
    ) %>%
    dplyr::mutate(
      subspecialty_abbrev = subspecialty,
      subspecialty_full = dplyr::coalesce(
        unname(SUBSPECIALTY_FULL_NAMES[subspecialty]), subspecialty
      )
    ) %>%
    dplyr::left_join(SD_VALUES, by = c("subspecialty_abbrev" = "subspecialty")) %>%
    dplyr::mutate(
      replacement_ratio = dplyr::coalesce(
        replacement_ratio, annual_entrants / avg_annual_retirements
      ),
      projected_workforce = dplyr::coalesce(
        projected_workforce,
        baseline_workforce +
          WORKFORCE_PROJECTION_HORIZON_YEARS * (annual_entrants - avg_annual_retirements)
      ),
      # Bug 6: zero-guard baseline before division.
      percent_change = dplyr::if_else(
        baseline_workforce == 0, NA_real_,
        dplyr::coalesce(
          percent_change,
          100 * (projected_workforce - baseline_workforce) / baseline_workforce
        )
      )
    ) %>%
    dplyr::mutate(
      ci95_lower_raw = projected_workforce - WORKFORCE_CI_Z95 * sd_2029,
      ci95_upper     = projected_workforce + WORKFORCE_CI_Z95 * sd_2029,
      # Bug 12: surface clamped lower-CI rows.
      ci95_lower_clamped = !is.na(ci95_lower_raw) & ci95_lower_raw < 0,
      ci95_lower     = pmax(ci95_lower_raw, 0)
    )

  if (any(consolidated$ci95_lower_clamped, na.rm = TRUE)) {
    clamped_subs <- consolidated$subspecialty_abbrev[consolidated$ci95_lower_clamped]
    message(sprintf("[QA NOTE] ci95_lower clamped from negative to 0 for: %s",
                    paste(clamped_subs, collapse = ", ")))
  }

  consolidated <- consolidated %>%
    dplyr::transmute(
      subspecialty           = subspecialty_full,
      subspecialty_abbrev    = subspecialty_abbrev,
      baseline_2025          = baseline_workforce,
      projected_2029         = projected_workforce,
      sd_2029                = sd_2029,
      ci95_lower             = ci95_lower,
      ci95_upper             = ci95_upper,
      percent_change         = percent_change,
      annual_retirement_rate = avg_retirement_rate,
      avg_annual_retirements = avg_annual_retirements,
      annual_entrants        = annual_entrants,
      replacement_ratio      = replacement_ratio,
      replacement_assessment = classify_replacement(replacement_ratio),
      fellowship_total_4yr   = annual_entrants * WORKFORCE_PROJECTION_HORIZON_YEARS,
      total_retirements_4yr  = round(avg_annual_retirements * WORKFORCE_PROJECTION_HORIZON_YEARS),
      ci95_lower_clamped = ci95_lower_clamped
    )

  cat("\nConsolidated data:\n")
  print(consolidated, width = Inf)

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # QA Gates
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  cat("\n[", as.character(Sys.time()), "] Running QA gates\n", sep = "")

  # Gate 1: No NAs in critical columns.
  critical_cols <- c("baseline_2025", "projected_2029", "replacement_ratio")
  na_counts <- sapply(critical_cols, function(col) sum(is.na(consolidated[[col]])))
  if (any(na_counts > 0)) {
    cat("WARNING: NA values in critical columns:\n"); print(na_counts)
  } else {
    cat("  \u2713 Gate 1: No NAs in critical columns\n")
  }

  # Gate 2: Replacement ratios match computed values.
  ratio_diff <- abs(consolidated$annual_entrants / consolidated$avg_annual_retirements -
                    consolidated$replacement_ratio)
  if (max(ratio_diff, na.rm = TRUE) > 0.01) {
    cat("WARNING: Replacement ratio mismatch\n")
  } else {
    cat("  \u2713 Gate 2: Replacement ratios self-consistent\n")
  }

  # Gate 3: CI width reasonable (< 50% of mean).
  ci_check <- consolidated %>%
    dplyr::mutate(
      ci_width = ci95_upper - ci95_lower,
      # Bug 7: zero-guard projected_2029 before division.
      ci_percent = dplyr::if_else(
        projected_2029 == 0, NA_real_,
        100 * (ci95_upper - ci95_lower) / projected_2029
      )
    )
  if (any(ci_check$ci_percent > 50, na.rm = TRUE)) {
    cat("WARNING: Very wide confidence intervals\n"); print(ci_check[, c("subspecialty_abbrev","ci_percent")])
  } else {
    cat("  \u2713 Gate 3: CI widths reasonable\n")
  }

  # Gate 4: No negative projections — STOPS on failure (Bug 8).
  if (any(consolidated$projected_2029 < 0 | consolidated$ci95_lower < 0, na.rm = TRUE)) {
    cat("ERROR: Negative workforce projections detected!\n")
    print(dplyr::select(consolidated, subspecialty_abbrev, projected_2029, ci95_lower, ci95_upper))
    stop("Negative workforce projections detected in consolidated output.", call. = FALSE)
  } else {
    cat("  \u2713 Gate 4: All projections positive\n")
  }

  # Gate 5: Contract validation (fail-loud).
  validate_workforce_data(
    dplyr::select(consolidated, -ci95_lower_clamped),
    source_hint = "manuscript_consolidate_existing_results"
  )
  cat("  \u2713 Gate 5: Data contract passed\n")

  # Gate 6: CI width sanity — catches SD typos (Bug 11).
  width_ratio <- (consolidated$ci95_upper - consolidated$ci95_lower) / consolidated$projected_2029
  if (any(width_ratio > 2.0, na.rm = TRUE)) {
    bad <- consolidated$subspecialty_abbrev[width_ratio > 2.0]
    stop(sprintf("[Gate 6 CI width] CI spans >200%% of projection for: %s \u2014 check SD values.",
                 paste(bad, collapse = ", ")), call. = FALSE)
  } else {
    cat("  \u2713 Gate 6 CI width: all < 200%% of projection\n")
  }

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Write output (Bug 10: re-throw disk/IO errors)
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  dir.create(dirname(OUTPUT_CSV), recursive = TRUE, showWarnings = FALSE)

  tryCatch(
    readr::write_csv(dplyr::select(consolidated, -ci95_lower_clamped), OUTPUT_CSV),
    error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("no space left|disk full|read-only file system|permission denied",
                msg, ignore.case = TRUE)) {
        stop(sprintf("[Step 5.0] Disk/IO error writing %s: %s", OUTPUT_CSV, msg), call. = FALSE)
      }
      stop(e)
    }
  )

  # Write receipt (non-fatal if receipt write fails).
  receipt_path <- file.path(dirname(OUTPUT_CSV), "step5.0_receipt.json")
  tryCatch({
    jsonlite::write_json(
      list(written_at = format(Sys.time()), path = OUTPUT_CSV,
           rows = nrow(consolidated), sha256 = digest::digest(consolidated)),
      receipt_path
    )
  }, error = function(e) {
    msg <- conditionMessage(e)
    if (grepl("no space left|disk full|read-only file system|permission denied",
              msg, ignore.case = TRUE)) {
      warning(sprintf("[Step 5.0] Disk/IO error writing receipt %s: %s", receipt_path, msg))
    }
  })

  cat(sprintf("\n[%s] SUCCESS: %d rows written to:\n  %s\n", Sys.time(), nrow(consolidated), OUTPUT_CSV))
  invisible(consolidated)
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Auto-run when executed directly (not when sourced for testing).
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
if (!interactive() && identical(sys.nframe(), 0L)) main()
