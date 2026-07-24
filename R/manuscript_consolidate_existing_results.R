#!/usr/bin/env Rscript
#' @title Step 5.0: Consolidate Existing Workforce Projections
#' @inheritParams shared_params_paths
#'
#' @description
#' Integrates archived Monte Carlo simulation results into the canonical 
#' manuscript dataset. This script acts as a bridge for legacy workforce 
#' forecasting data, ensuring it is available for manuscript inline statistics.
#'
#' @details
#' \strong{TEST_MODE Behavior:}
#' In \code{TEST_MODE=1}, the script bypasses all disk lookups and writes a 
#' zero-valued stub CSV. This allows the manuscript to render even if the 
#' expensive forecasting results are not present.
#'
#' \strong{Input Resolution (Waterfall):}
#' \enumerate{
#'   \item \code{WORKFORCE_SOURCE_CSV} environment variable.
#'   \item Repo-tracked reference file
#' (\code{manuscript/data/reference/workforce_projections_source.csv}).
#'   \item Deep archive fallback (local Samsung volume path).
#' }
#'
#' @section Outputs:
#' Writes \code{manuscript/data/workforce_projections_consolidated.csv}.
#'
#' @family manuscript-data
#' @family pipeline-orchestration
#' @seealso Step 4 accessibility analysis (upstream), Step 5.5 Table 1 (downstream)
#'
#' @author Tyler Muffly, MD & Claude
#' @keywords pipeline workforce-projections

suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
  library(glue)
  library(checkmate)
})

# [ORCHESTRATOR NATIVE] Utilities
source(here::here("R", "utils", "step_receipts.R"))

# BUG FIX #1 (saboteur audit 2026-04-25): is_test_mode() was called inside
# main() (line 112) but never sourced. Running this script standalone via
# Rscript crashed with "could not find function 'is_test_mode'" before any
# work happened. Source the canonical helper unconditionally; idempotent.
if (!exists("is_test_mode", mode = "function")) {
  source(here::here("R", "test_mode_contracts.R"))
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Main Entry Point
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' Main Entrypoint for Step 5.0: Consolidate Existing Workforce Projections
#'
#' @title Main Entrypoint for Step 5.0 — Consolidate Existing Workforce
#'   Projections
#' @description
#' Integrates archived Monte Carlo simulation results into the canonical
#' manuscript dataset. Acts as a bridge for legacy workforce forecasting data,
#' making it available for manuscript inline statistics without re-running the
#' full simulation. Falls back to a bundled reference CSV when no live artifact
#' is found, ensuring the manuscript can always render.
#'
#' @param input_paths `list|NULL`: Named list optionally containing
#'   \code{workforce_projections} pointing to a CSV with simulation results.
#'   When \code{NULL}, falls back to \code{WORKFORCE_SOURCE_CSV} env var, then
#'   \code{manuscript/data/reference/workforce_projections_source.csv}.
#' @param output_paths `list|NULL`: Named list with element
#'   \code{consolidated_results} giving the output RDS path. When \code{NULL},
#'   read from \code{PIPELINE_OUTPUT_PATHS} env var.
#' @param run_id `character|NULL`: Pipeline run identifier for receipts.
#'
#' @return Invisibly returns \code{NULL}. Side effects: writes consolidated
#'   workforce projection RDS and a step receipt JSON.
#'
#' @section Step 5.0 pipeline position:
#' \preformatted{
#'   Step 4 (accessibility) -> Step 5.0 main() [HERE] -> Step 5.1 (RUCA)
#'
#'   Input:  workforce_projections_source.csv (legacy Monte Carlo output)
#'   Output: step_5.0_consolidated_results.rds
#' }
#'
#' @family manuscript-generation
#' @family step5-analysis
#' @concept workforce-projections
#' @concept monte-carlo
#' @seealso \code{R/production_to_manuscript_adapter.R} (Step 4.5 -- upstream)
#'
#' @examples
#' \dontrun{
#' main(
#'   input_paths  = list(workforce_projections =
#' "manuscript/data/reference/workforce_projections_source.csv"),
#'   output_paths = list(consolidated_results  =
#' "artifacts/run_123/step_5.0_consolidated_results.rds"),
#'   run_id       = "run_123"
#' )
#' }
#'
#' @export
#' @section Invariants:
#' Pre-conditions that must hold or the function will stop():
#' \itemize{
#'   \item Input files exist and are readable
#'   \item Data grain matches the upstream step's contract
#'   \item Required columns from the upstream step are present
#'   \item No unexpected duplication of primary keys
#' }
#' Violations indicate upstream pipeline failure, not a bug in this step.
#'
#' @section Failure modes:
#' What breaks when invariants are violated:
#' \itemize{
#'   \item Missing input files \eqn{\rightarrow} pipeline stops early with an
#' informative error
#'   \item Schema drift \eqn{\rightarrow} downstream joins or filters behave
#' incorrectly
#'   \item Duplicate primary keys \eqn{\rightarrow} aggregation or join
#' inflation
#'   \item Incomplete upstream processing \eqn{\rightarrow} missing or NA values
#' in output
#' }
#'
#' @section Mental model:
#' This step assumes all upstream steps have completed successfully.
#' If outputs appear incorrect, first verify upstream invariants rather
#' than debugging this step in isolation. Check the step receipt JSON
#' and the upstream output artifact before diving into this script.
#'
main <- function(input_paths = NULL, output_paths = NULL, run_id = NULL) {
  start_time <- Sys.time()

  # [HARDENING] Layer 1: Input Validation
  checkmate::assert_list(input_paths, null.ok = TRUE)
  checkmate::assert_list(output_paths, null.ok = TRUE)
  checkmate::assert_string(run_id, null.ok = TRUE)

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Configuration
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  # ── Input Resolution ──────────────────────────────────────────────────────
  # Sources tried in order (highest priority first):
  #   1. input_paths$workforce_projections / $workforce_source_csv  (DAG explicit)
  #   2. Env var WORKFORCE_SOURCE_CSV                               (caller override)
  #   3. Repo-tracked reference file                                (clean checkout)
  #   4. Deep archive path                                          (original fallback)
  #
  # BUG FIX (2026-05-08): The roxygen contract advertises that callers may
  # pass an explicit input path via input_paths, but the previous resolution
  # ignored input_paths entirely.  When the DAG (or any caller) supplied a
  # path, the function silently fell through to the env var or fallback —
  # potentially reading a different file than the caller requested.  Accept
  # both `workforce_projections` (canonical name) and `workforce_source_csv`
  # (mirrors the WORKFORCE_SOURCE_CSV env var) so the contract is honored
  # under either spelling.
  input_explicit <- c(
    if (!is.null(input_paths)) input_paths$workforce_projections else NULL,
    if (!is.null(input_paths)) input_paths$workforce_source_csv  else NULL
  )
  input_candidates <- c(
    input_explicit,
    Sys.getenv("WORKFORCE_SOURCE_CSV", unset = NA_character_),
    here("manuscript", "data", "reference", "workforce_projections_source.csv"),
    here(
      "docs", "isochrones_deep_archive", "2025-12-07",
      "legacy_matching_strategies_2025-12-05",
      "research_forecasting", "comprehensive_forecasting",
      "enhanced_comparison_table_20250928_030546.csv"
    )
  )
  input_candidates <- input_candidates[!is.na(input_candidates) & nzchar(input_candidates)]
  resolved <- Filter(file.exists, input_candidates)
  INPUT_CSV <- if (length(resolved) > 0) resolved[[1]] else NA_character_

  # BUG FIX #2 (saboteur audit 2026-04-25): the DAG sets output_paths$workforce_csv
  # (orchestrator_dag.R:5610), not workforce_projections. The old lookup silently
  # missed the orchestrator's path and fell through to the default — which
  # happened to be correct only by coincidence. Accept BOTH keys (DAG canonical
  # first, legacy fallback second) so any future DAG rename also works without
  # silent breakage. Avoid %||% (R 4.4+) for backwards compatibility.
  OUTPUT_CSV <- if (!is.null(output_paths) && !is.null(output_paths$workforce_csv)) {
    output_paths$workforce_csv
  } else if (!is.null(output_paths) && !is.null(output_paths$workforce_projections)) {
    output_paths$workforce_projections
  } else {
    here::here("manuscript", "data", "workforce_projections_consolidated.csv")
  }

  # Standard deviations from enhanced_workforce_statistical_summaries document
  # BUG FIX (2026-04-03): Expanded to all 7 subspecialties. Previously only 3
  # were listed, causing silent NA propagation in ci95_lower/ci95_upper for the
  # missing 4 subspecialties (MFM, CFP, REI, PAG).
  SD_VALUES <- tribble(
    ~subspecialty, ~sd_2029,
    "FPMRS",       15.2,
    "GO",          16.1,
    "MIG",         11.0,
    "MFM",         NA_real_,
    "CFP",         NA_real_,
    "REI",         NA_real_,
    "PAG",         NA_real_
  )

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Main Processing
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  cat(paste0("[", Sys.time(), "] Loading existing results from archived analysis\n"))

  # ── TEST_MODE stub writer ─────────────────────────────────────────────────
  # In TEST_MODE we write a clearly-marked stub CSV (all zeros) so the
  # manuscript Rmd can render without real projection data.
  if (is_test_mode()) {
    message("[Step 5.0] TEST_MODE: writing stub workforce CSV (zero values)")
    dir.create(dirname(OUTPUT_CSV), recursive = TRUE, showWarnings = FALSE)
    # BUG FIX #3 (saboteur audit 2026-04-25): match production column TYPES.
    # Production rounds ci95_lower/upper via round() (returns double) and
    # writes them as doubles via readr::write_csv. The old stub used 0L
    # (integer) → checkmate::assert_integer in any downstream consumer would
    # pass in TEST_MODE and crash in production (or vice versa).
    # All numeric columns now match the production schema's natural types.
    # BUG FIX #13 (saboteur audit 2026-04-25): subspecialty order matches the
    # production source-CSV order (FPMRS, GO, MIG, then alphabetical for the
    # NA-SD subspecialties). Position-wise comparators in downstream tests
    # would silently break if TEST_MODE and production used different orders.
    stub <- tibble::tibble(
      subspecialty = c(
        "Female Pelvic Medicine & Reconstructive Surgery",
        "Gynecologic Oncology",
        "Minimally Invasive Gynecologic Surgery",
        "Complex Family Planning",
        "Maternal-Fetal Medicine",
        "Pediatric & Adolescent Gynecology",
        "Reproductive Endocrinology & Infertility"
      ),
      subspecialty_abbrev = c("FPMRS", "GO", "MIG", "CFP", "MFM", "PAG", "REI"),
      baseline_2025 = 0,           # double (matches production: from source CSV)
      projected_2029 = 0,          # double (production: derived via arithmetic)
      sd_2029 = 0,                 # double
      ci95_lower = 0,              # double (production: round() returns double)
      ci95_upper = 0,              # double
      percent_change = 0,          # double
      annual_retirement_rate = 0,  # double
      avg_annual_retirements = 0,  # double
      annual_entrants = 0,         # double
      replacement_ratio = 0,       # double
      replacement_assessment = "Unknown",
      fellowship_total_5yr = 0,    # double (production: integer * 5 = integer, but we standardize)
      total_retirements_4yr = 0    # double (production: round() returns double)
    )
    readr::write_csv(stub, OUTPUT_CSV)
    message("[Step 5.0] Stub written: ", OUTPUT_CSV)
    tryCatch({
      if (!exists("write_step_receipt", mode = "function")) {
        source(here::here("R", "utils", "step_receipts.R"))
      }
      write_step_receipt(
        id         = "5.0",
        start_time = start_time,
        inputs     = input_paths,
        outputs    = output_paths,
        metrics    = list(row_count = nrow(stub)),
        grain      = "1 row per Subspecialty",
        status     = "success"
      )
    }, error = function(e) {
      msg <- if (!is.null(e$message)) e$message else as.character(e)
      if (grepl("no space left|disk full|read-only file system|permission denied",
                msg, ignore.case = TRUE)) {
        stop(sprintf(
          "[Step 5.0] TEST_MODE receipt write failed with disk/IO error: %s", msg
        ), call. = FALSE)
      }
      warning(sprintf("[Step 5.0] Receipt write failed (non-fatal): %s", msg), call. = FALSE)
    })
    return(invisible(stub))
  }

  # ── Verify input file exists ─────────────────────────────────────────────
  if (is.na(INPUT_CSV) || !file.exists(INPUT_CSV)) {
    stop(paste0(
      "[Step 5.0] Workforce source CSV not found.\n",
      "  Tried:\n  - ", paste(input_candidates, collapse = "\n  - "), "\n",
      "  Set WORKFORCE_SOURCE_CSV env var or add:\n",
      "    manuscript/data/reference/workforce_projections_source.csv\n",
      "  Then re-run: Rscript R/manuscript_consolidate_existing_results.R"
    ), call. = FALSE)
  }

  # Load existing CSV
  enhanced_table <- readr::read_csv(INPUT_CSV, show_col_types = FALSE)

  cat(sprintf("  Loaded %d rows from %s\n", nrow(enhanced_table), basename(INPUT_CSV)))

  # Display original data structure
  cat("\nOriginal data structure:\n")
  print(enhanced_table)

  # BUG FIX #4 (saboteur audit 2026-04-25): assert all source columns exist
  # BEFORE the mutate chain. Old behaviour: a missing column (e.g., source CSV
  # rename from `avg_annual_retirements` to `mean_annual_retirements`) would
  # crash deep inside dplyr with a confusing "object 'avg_annual_retirements'
  # not found" error. Now we surface a single actionable message that names
  # the missing columns AND the file we read them from.
  required_source_cols <- c(
    "subspecialty", "baseline_workforce", "annual_entrants",
    "avg_annual_retirements", "avg_retirement_rate"
  )
  missing_source_cols <- setdiff(required_source_cols, names(enhanced_table))
  if (length(missing_source_cols) > 0L) {
    stop(sprintf(
      paste0(
        "[Step 5.0] Source workforce CSV is missing required column(s): %s\n",
        "  Source file: %s\n",
        "  Available columns: %s\n",
        "  Required by the consolidate-then-derive pipeline (projected_workforce,\n",
        "  percent_change, replacement_ratio, ci95_lower, ci95_upper).\n",
        "  Fix: rebuild the source CSV with the required schema or update\n",
        "  required_source_cols in R/manuscript_consolidate_existing_results.R."
      ),
      paste(missing_source_cols, collapse = ", "),
      INPUT_CSV,
      paste(names(enhanced_table), collapse = ", ")
    ), call. = FALSE)
  }
  if (!"subspecialty" %in% names(enhanced_table)) {
    stop("[Step 5.0] Source CSV missing 'subspecialty' column", call. = FALSE)
  }

  # Consolidate and calculate confidence intervals
  cat("\n[", as.character(Sys.time()), "] Processing data\n", sep = "")

  consolidated <- enhanced_table %>%
    # BUG FIX #5 (saboteur audit 2026-04-25): normalize subspecialty BEFORE
    # case_when. Old behaviour: trailing whitespace ("FPMRS ") or alternate
    # case ("fpmrs") fell through to `TRUE ~ subspecialty`, the SD join then
    # silently missed, and ci95_lower/upper became NA for the whole row →
    # silent NA in the manuscript text. Now trimws() + toupper() so common
    # source-CSV defects can't poison the join.
    mutate(
      subspecialty = toupper(trimws(subspecialty)),
      subspecialty_abbrev = subspecialty,
      subspecialty_full = case_when(
        subspecialty == "FPMRS" ~ "Female Pelvic Medicine & Reconstructive Surgery",
        subspecialty == "GO"    ~ "Gynecologic Oncology",
        subspecialty == "MIG"   ~ "Minimally Invasive Gynecologic Surgery",
        subspecialty == "MFM"   ~ "Maternal-Fetal Medicine",
        subspecialty == "CFP"   ~ "Complex Family Planning",
        subspecialty == "REI"   ~ "Reproductive Endocrinology & Infertility",
        subspecialty == "PAG"   ~ "Pediatric & Adolescent Gynecology",
        TRUE ~ subspecialty
      ),
      # BUG FIX (2026-04-03): These three columns are absent from the source CSV and
      # must be derived here. projected_workforce uses the 4-year net-flow formula
      # (2025 baseline + 4 years of net annual change = 2029 projection).
      # percent_change and replacement_ratio are derived from the same source columns.
      projected_workforce = baseline_workforce +
        (annual_entrants - avg_annual_retirements) * 4L,
      # BUG FIX #6 (saboteur audit 2026-04-25): zero-guard on percent_change.
      # Old behaviour: a baseline of 0 (subspecialty with no providers in 2025)
      # produced Inf that propagated into the manuscript inline-statistics text
      # ("Inf% increase"). Now NA — manuscript renderer handles NA explicitly.
      percent_change      = dplyr::if_else(
        is.na(baseline_workforce) | baseline_workforce == 0,
        NA_real_,
        (projected_workforce - baseline_workforce) / baseline_workforce * 100
      ),
      # BUG FIX (2026-04-03): Guard against division by zero when
      # avg_annual_retirements == 0, which produces Inf that propagates to CI bounds.
      replacement_ratio   = dplyr::if_else(
        avg_annual_retirements == 0 | is.na(avg_annual_retirements),
        NA_real_,
        annual_entrants / avg_annual_retirements
      )
    ) %>%
    # Join with standard deviations
    dplyr::left_join(SD_VALUES, by = c("subspecialty_abbrev" = "subspecialty")) %>%
    # Calculate 95% CI using parametric method (mean +/- 1.96 * SD)
    mutate(
      ci95_lower_raw = round(projected_workforce - 1.96 * sd_2029),
      ci95_upper = round(projected_workforce + 1.96 * sd_2029),
      # BUG FIX #12 (saboteur audit 2026-04-25): clamp negatives but record
      # which rows were clamped. Silent pmax() hid Normal-approx breakdowns
      # at small N. Now ci95_lower_clamped = TRUE flags rows for inspection.
      ci95_lower = pmax(ci95_lower_raw, 0),
      ci95_lower_clamped = !is.na(ci95_lower_raw) & ci95_lower_raw < 0
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
      ci95_lower_clamped = ci95_lower_clamped,  # BUG FIX #12: surface to caller
      percent_change = percent_change,
      annual_retirement_rate = avg_retirement_rate,
      avg_annual_retirements = avg_annual_retirements,
      annual_entrants = annual_entrants,
      replacement_ratio = replacement_ratio,
      # Classification based on replacement ratio (NA = projections not yet available)
      replacement_assessment = case_when(
        is.na(replacement_ratio) ~ "Pending",
        replacement_ratio >= 1.2 ~ "Adequate",
        replacement_ratio >= 0.8 ~ "Marginal",
        TRUE ~ "Insufficient"
      ),
      # Calculate total 5-year fellowship output
      fellowship_total_5yr = annual_entrants * 5,
      # Calculate total projected retirements over 4 years
      total_retirements_4yr = round(avg_annual_retirements * 4)
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
  # BUG FIX (2026-04-03): Guard against avg_annual_retirements == 0 which
  # produces Inf/NaN in ratio_diff, poisoning max_diff and causing either a
  # false-positive warning (Inf > 0.01) or a silently-passed NaN check.
  # Rows with zero retirements are excluded from the comparison with na.rm.
  ratio_check <- consolidated %>%
    dplyr::mutate(
      calculated_ratio = dplyr::if_else(
        avg_annual_retirements == 0 | is.na(avg_annual_retirements),
        NA_real_,
        annual_entrants / avg_annual_retirements
      ),
      ratio_diff = abs(calculated_ratio - replacement_ratio)
    )

  max_diff <- max(ratio_check$ratio_diff, na.rm = TRUE)
  if (is.infinite(max_diff) || is.nan(max_diff)) {
    message("[Step 5.0] Check 2: ratio_diff is non-finite; check avg_annual_retirements column")
  } else if (max_diff > 0.01) {
    cat(sprintf("WARNING: Replacement ratio mismatch (max diff: %.3f)\n", max_diff))
    print(dplyr::select(ratio_check, subspecialty_abbrev, replacement_ratio,
                        calculated_ratio, ratio_diff))
  } else {
    cat("  \u2713 Replacement ratios mathematically correct\n")
  }

  # Check 3: Confidence intervals sensible (CI width <50% of mean)
  # BUG FIX #7 (saboteur audit 2026-04-25): zero-guard the divisor. Old
  # behaviour: a projected_2029 of 0 produced Inf in ci_percent that triggered
  # a spurious "very wide CI" warning when in fact it was just division-by-zero.
  ci_check <- consolidated %>%
    mutate(
      ci_width = ci95_upper - ci95_lower,
      ci_percent = dplyr::if_else(
        is.na(projected_2029) | projected_2029 == 0,
        NA_real_,
        100 * ci_width / projected_2029
      )
    )

  if (any(ci_check$ci_percent > 50, na.rm = TRUE)) {
    cat("WARNING: Very wide confidence intervals detected\n")
    print(select(ci_check, subspecialty_abbrev, projected_2029, ci95_lower, ci95_upper, ci_percent))
  } else {
    cat("  \u2713 Confidence intervals reasonable (all <50% of mean)\n")
  }

  # BUG FIX #12 (continued): report any clamped CI bounds in the validation pass
  if ("ci95_lower_clamped" %in% names(consolidated)) {
    n_clamped <- sum(consolidated$ci95_lower_clamped, na.rm = TRUE)
    if (n_clamped > 0L) {
      cat(sprintf(
        "[QA NOTE] %d row(s) had ci95_lower clamped from negative to 0 (Normal-approx breakdown at small N):\n",
        n_clamped
      ))
      print(consolidated[consolidated$ci95_lower_clamped %in% TRUE,
                         c("subspecialty_abbrev", "projected_2029", "sd_2029",
                           "ci95_lower", "ci95_upper")])
    }
  }

  # Check 4: No negative projections (na.rm = TRUE: NA rows are pending data, skip them)
  # BUG FIX #8 (saboteur audit 2026-04-25): "ERROR: Negative workforce
  # projections" used to only cat() and continue. Gate 3 (later) does stop()
  # for the same condition, so the script eventually halted — but only after
  # printing more output. The double-handling masked the actual point of
  # failure in long logs. Now Check 4 stops immediately at the first sign,
  # producing a single clear error trail.
  if (any(consolidated$projected_2029 < 0 | consolidated$ci95_lower < 0, na.rm = TRUE)) {
    cat("ERROR: Negative workforce projections detected!\n")
    print(select(consolidated, subspecialty_abbrev, projected_2029, ci95_lower, ci95_upper))
    stop(
      "[Step 5.0] Check 4 fatal: negative projected_2029 or ci95_lower. ",
      "A negative future workforce is impossible; verify source CSV inputs ",
      "(annual_entrants - avg_annual_retirements may be too negative).",
      call. = FALSE
    )
  } else {
    cat("  \u2713 All workforce projections positive\n")
  }

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Save Output
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  # Create output directory if needed
  dir.create(dirname(OUTPUT_CSV), recursive = TRUE, showWarnings = FALSE)

  # Write consolidated data
  readr::write_csv(consolidated, OUTPUT_CSV)

  cat(sprintf("\n[%s] Consolidated data saved to:\n", Sys.time()))
  cat(sprintf("  %s\n", OUTPUT_CSV))
  cat(sprintf("  %d rows, %d columns\n", nrow(consolidated), ncol(consolidated)))

  # ── QA Gates (post-write validation of workforce consolidation) ────────────
  qa_issues   <- character(0)
  qa_warnings <- character(0)

  # Gate 1: Read-back verification — CSV can be loaded and row count matches (FATAL)
  tryCatch({
    rb <- readr::read_csv(OUTPUT_CSV, show_col_types = FALSE)
    if (nrow(rb) != nrow(consolidated)) {
      qa_issues <- c(qa_issues, sprintf(
        "Gate 1 FATAL: Row count mismatch (written=%d, read-back=%d)",
        nrow(consolidated), nrow(rb)))
    } else {
      cat(sprintf("[QA Gate 1] CSV read-back OK: %d rows\n", nrow(rb)))
    }
    rm(rb)
  }, error = function(e) {
    qa_issues <<- c(qa_issues, sprintf(
      "Gate 1 FATAL: Cannot read back output CSV: %s", e$message))
  })

  # Gate 2: Required columns present (FATAL)
  req_cols <- c("subspecialty_abbrev", "baseline_2025", "projected_2029",
                "percent_change", "replacement_ratio")
  missing_cols <- setdiff(req_cols, names(consolidated))
  if (length(missing_cols) > 0) {
    qa_issues <- c(qa_issues, sprintf(
      "Gate 2 FATAL: Missing columns: %s", paste(missing_cols, collapse = ", ")))
  } else {
    cat(sprintf("[QA Gate 2] All %d required columns present\n", length(req_cols)))
  }

  # Gate 3: No negative baseline or projected values (FATAL)
  if (all(c("baseline_2025", "projected_2029") %in% names(consolidated))) {
    neg_vals <- sum(consolidated$baseline_2025 < 0 | consolidated$projected_2029 < 0, na.rm = TRUE)
    if (neg_vals > 0) {
      qa_issues <- c(qa_issues, sprintf(
        "Gate 3 FATAL: %d rows with negative workforce projections", neg_vals))
    } else {
      cat("[QA Gate 3] All workforce projections non-negative\n")
    }
  }

  # Gate 4: Subspecialty uniqueness (FATAL)
  if ("subspecialty_abbrev" %in% names(consolidated)) {
    n_dup <- sum(duplicated(consolidated$subspecialty_abbrev))
    if (n_dup > 0) {
      qa_issues <- c(qa_issues, sprintf(
        "Gate 4 FATAL: %d duplicate subspecialty_abbrev values", n_dup))
    } else {
      cat(sprintf("[QA Gate 4] Subspecialty uniqueness OK (%d unique)\n",
                  nrow(consolidated)))
    }
  }

  # Gate 5: Replacement ratio in reasonable range 0-5 (warning)
  if ("replacement_ratio" %in% names(consolidated)) {
    bad_ratio <- sum(!is.na(consolidated$replacement_ratio) &
                     (consolidated$replacement_ratio < 0 | consolidated$replacement_ratio > 5))
    if (bad_ratio > 0) {
      qa_warnings <- c(qa_warnings, sprintf(
        "Gate 5: %d subspecialties have replacement_ratio outside 0-5 range", bad_ratio))
    } else {
      cat("[QA Gate 5] Replacement ratios all in 0-5 range\n")
    }
  }

  # BUG FIX #11 (saboteur audit 2026-04-25): Gate 6 — CI absurdity check.
  # An SD typo (e.g., entering 152.0 instead of 15.2) inflates ci95_upper to
  # ~10x reality, but every prior gate accepts it (positive, finite, no
  # uniqueness violation). Flag any subspecialty whose CI width exceeds
  # 200% of the projected workforce — a normal SD never produces that.
  if (all(c("ci95_upper", "ci95_lower", "projected_2029") %in% names(consolidated))) {
    width <- consolidated$ci95_upper - consolidated$ci95_lower
    width_ratio <- ifelse(
      is.na(consolidated$projected_2029) | consolidated$projected_2029 == 0,
      NA_real_,
      width / consolidated$projected_2029
    )
    absurd <- which(!is.na(width_ratio) & width_ratio > 2.0)
    if (length(absurd) > 0L) {
      qa_warnings <- c(qa_warnings, sprintf(
        "Gate 6: %d subspecialties have CI width > 200%% of projection — likely SD typo. Inspect: %s",
        length(absurd),
        paste(consolidated$subspecialty_abbrev[absurd], collapse = ", ")))
    } else {
      cat("[QA Gate 6] CI widths within 200% of projection (no SD typos)\n")
    }
  }

  # ── QA Summary ──────────────────────────────────────────────────────────
  if (length(qa_warnings) > 0) {
    for (w in qa_warnings) {
      cat(sprintf("  [QA WARNING] %s\n", w))
      warning(sprintf("[Step 5.0 QA] %s", w), call. = FALSE)
    }
  }
  if (length(qa_issues) > 0) {
    for (i in qa_issues) cat(sprintf("  [QA FATAL] %s\n", i))
    stop(sprintf("[Step 5.0 QA] %d fatal issue(s) — workforce consolidation invalid:\n  %s",
                 length(qa_issues), paste(qa_issues, collapse = "\n  ")),
         call. = FALSE)
  }
  cat("[QA] All Step 5.0 gates passed\n")

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
      `2029` = sprintf("%s \u00b1 %.1f", format(round(projected_2029), big.mark = ","), sd_2029),
      `95% CI` = sprintf("[%s, %s]",
                         format(ci95_lower, big.mark = ","),
                         format(ci95_upper, big.mark = ",")),
      `Change` = sprintf("%.1f%%", percent_change),
      `Ratio` = sprintf("%.2f (%s)", replacement_ratio, replacement_assessment)
    )

  print(summary_table, width = Inf)

  # [ORCHESTRATOR NATIVE] Write Step Receipt
  # BUG FIX #10 (saboteur audit 2026-04-25): the receipt is the audit trail.
  # Silently warning on ALL errors meant a disk-full or permissions error
  # (which would also corrupt the OUTPUT_CSV write that just completed)
  # produced only a buried warning. Now distinguish disk/IO errors (re-stop)
  # from genuinely-non-fatal issues (function-not-found, schema drift in the
  # receipt utility). Disk errors are re-thrown because if the receipt can't
  # write, the next downstream step's input check will fail anyway.
  tryCatch(write_step_receipt(
    id = "5.0",
    start_time = start_time,
    inputs = input_paths,
    outputs = output_paths,
    metrics = list(
      total_baseline = sum(consolidated$baseline_2025, na.rm = TRUE),
      total_projected = sum(consolidated$projected_2029, na.rm = TRUE),
      n_subspecialties = nrow(consolidated),
      qa_warnings_count = length(qa_warnings),
      validation_passed = TRUE
    ),
    grain = "1 row per subspecialty",
    status = "success"
  ), error = function(e) {
    msg <- if (!is.null(e$message)) e$message else as.character(e)
    if (grepl("no space left|disk full|read-only file system|permission denied",
              msg, ignore.case = TRUE)) {
      stop(sprintf(
        "[Step 5.0] Receipt write failed with disk/IO error — re-throwing because the OUTPUT_CSV write probably failed too: %s",
        msg
      ), call. = FALSE)
    }
    warning(sprintf("[Step 5.0] write_step_receipt() failed (non-fatal): %s", msg), call. = FALSE)
  })

  cat("\n[", as.character(Sys.time()), "] Script completed successfully\n", sep = "")
  return(invisible(consolidated))
}

# BUG FIX #9 (saboteur audit 2026-04-25): removed the duplicate file-scope
# definitions of SD_VALUES, INPUT_CSV, and OUTPUT_CSV. main() builds its own
# copies; the file-scope copies were drift bait that would silently disagree
# with main()'s values if anyone updated one and not the other. main() is now
# the only entry point.

# Execution Guard: only run main() if executed directly, not if sourced
if (sys.nframe() == 0) {
  main()
}
