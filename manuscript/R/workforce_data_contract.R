# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Workforce Cliff — Data Contract (Single Source of Truth)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose: One place that defines (a) the workforce-cliff analysis constants,
#          (b) the canonical data path, and (c) a FAIL-LOUD validator for the
#          consolidated workforce-projection table. Every consumer (the Rmd
#          loader `workforce_statistics.R`, the Word-table generator
#          `create_workforce_table.R`, and the generator
#          `R/manuscript_consolidate_existing_results.R`) sources this file so
#          the numbers, thresholds, and shape checks can never drift apart.
#
# Why this exists (2026-07-14): the manuscript silently rendered zeros because
#   `manuscript/data/workforce_projections_consolidated.csv` had been overwritten
#   by an all-zero 7-subspecialty scaffold (from a smoke-mode run) and NOTHING
#   rejected it on load. See CLAUDE.md #18/#19 (fail-closed provenance). This
#   module makes a zero / "Unknown" / wrong-shape table stop the render loudly
#   with a remediation message instead of publishing garbage.
#
# CANONICAL SOURCE: the workforce-cliff manuscript reports EXACTLY the three
#   gynecologic *surgical* subspecialties (URPS, GO, MIGS). Monte Carlo workforce
#   projections exist only for these three. The authoritative frozen table lives
#   at data/workforce_projections_consolidated.csv (matches the published
#   SGS deck). This is deliberately DIFFERENT from the 7-subspecialty cohort in
#   config/cohort_criteria.yml, which scopes the separate isochrone-access paper.
#
# Author: Tyler Muffly, MD / Claude Code
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(here)
})

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Analysis constants (NO magic numbers scattered in callers)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Projection horizon: 2025 -> 2029 is FOUR annual transitions. Every "over the
# next N years" statement and every `x * horizon` calculation MUST use this.
# Fellowship totals and retirement totals are BOTH reported over this same
# horizon (fellowship_total_4yr, total_retirements_4yr) so they are directly
# comparable. The prior separate 5-year fellowship-report horizon was removed
# on 2026-07-15 — mixing a 5-year fellowship count with 4-year retirements was
# an apples-to-oranges trap.
# Canonical definition lives in R/workforce_constants.R (single source of truth,
# shared with the projection engine so the two cannot drift).
source(here::here("R", "workforce_constants.R"), local = TRUE)

# Monte Carlo iteration count of the frozen archival projection simulation (no live re-run exists).
# Corrected 2026-07-25 from a stale 1000L to 10000L: the manuscript Methods and the supply-line
# figure caption both state the projection Monte Carlo used 10,000 iterations. The constant was a
# dead alias (only re-exported as N_MONTE_CARLO_ITERATIONS, never consumed), so this is a
# documentation correction with no behavioral effect; the manuscript now derives its stated count
# from this constant so the two cannot diverge again.
WORKFORCE_MONTE_CARLO_ITERATIONS <- 10000L

# Parametric 95% CI multiplier (mean +/- z * SD). Canonical definition now lives in
# R/workforce_constants.R (sourced above, line 47) so the manuscript, the supply figure,
# and the NRMP rebuild all share one z-multiplier and cannot drift. Re-exported here for
# consumers that source only the contract; not redefined.
stopifnot(exists("WORKFORCE_CI_Z95"))   # must arrive from workforce_constants.R

# Replacement-ratio labels are descriptive of HEADCOUNT replacement balance only
# (graduates / departures), NOT of adequacy relative to population demand. A ratio
# just above 1.0 means the pipeline replaces departing physicians one-for-one; it
# does not establish sufficient access, geographic coverage, or clinical capacity.
WORKFORCE_REPLACEMENT_ABOVE_MIN <- 1.05  # > 1.05      -> "Above replacement"
WORKFORCE_REPLACEMENT_AT_MIN    <- 0.95  # [0.95,1.05] -> "At replacement"; < 0.95 -> "Below replacement"
# The 1.20 value is retained ONLY as a 20% replacement-buffer sensitivity threshold,
# not as a clinical adequacy standard.
WORKFORCE_REPLACEMENT_BUFFER    <- 1.20

# The three surgical subspecialties this manuscript reports (order = display order).
WORKFORCE_SUBSPECIALTIES <- c("URPS", "GO", "MIGS")

# Centralized headline constants (#9). The pinned expected values live ONCE here so a
# value change (e.g. after a rerun) touches one place instead of many test files.
# Raw SSOT values (display rounds ratios to 1 decimal in the manuscript).
WORKFORCE_HEADLINE_RATIO    <- c(URPS = 5.61,  GO = 7.11,  MIGS = 11.06)   # completion-to-departure
# -- URPS baseline: LEGACY FROZEN PROJECTION COHORT (not a mufflyaccess cell) --
# URPS = 1295 is the legacy reconciliation cohort (1031 ABOG + 264 model-included
# ABU net-new) that the frozen, published SGS-deck Monte Carlo projection was run
# on. It is a projection-cohort baseline, NOT an "active-workforce" count and NOT
# a mufflyaccess v2.1.0 canonical cell. It is intentionally preserved unchanged:
# re-baselining onto the current SSOT would require re-running that frozen
# projection (a separate, deliberate task -- do NOT do it in a plumbing migration).
# The current SSOT cohorts are different and are sourced via mufflyaccess::urps_count():
#   2023 board_certified_active / national / +urology = 1332 (ABU 301)  <- 2023 active
#   2025 roster_snapshot        / national / +urology = 1339 (ABU 308)  <- 2025 roster
# 1295 is a legacy projection cohort, not a current active-workforce count, and
# 1339 (the 2025 roster) is not the 2023 board-certified active count.
URPS_LEGACY_PROJECTION_BASELINE <- 1295L  # ssot-ok: legacy frozen SGS projection cohort
attr(URPS_LEGACY_PROJECTION_BASELINE, "metadata") <- list(
  measure         = "legacy_projection_cohort",
  cohort          = "1031 ABOG + 264 ABU net-new",
  purpose         = "reproduce frozen SGS projection",
  contract_status = "not a mufflyaccess v2.1.0 canonical cell")
WORKFORCE_HEADLINE_BASELINE <- c(URPS = 1295L, GO = 1052L, MIGS = 605L)    # ssot-ok: legacy frozen SGS projection cohort (URPS); see URPS_LEGACY_PROJECTION_BASELINE

# The only legal workforce-outlook labels (headcount replacement balance).
# "Unknown" is a red flag for a placeholder/zero scaffold and is rejected.
WORKFORCE_VALID_ASSESSMENTS <- c("Above replacement", "At replacement", "Below replacement")

# Numeric tolerances for the semantic (self-consistency) checks.
WORKFORCE_TOL_RATIO       <- 0.01   # replacement_ratio vs entrants/retirements
WORKFORCE_TOL_PROJECTION  <- 0.6    # projected vs baseline + horizon*(entrants-retirements)
WORKFORCE_TOL_PERCENT     <- 0.1    # percent_change vs 100*(proj-base)/base

# Columns every consumer relies on.
WORKFORCE_REQUIRED_COLUMNS <- c(
  "subspecialty", "subspecialty_abbrev", "baseline_2025", "projected_2029",
  "sd_2029", "ci95_lower", "ci95_upper", "percent_change",
  "annual_retirement_rate", "avg_annual_retirements", "annual_entrants",
  "replacement_ratio", "replacement_assessment"
)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Canonical path resolution
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' Resolve the canonical workforce-projection CSV path.
#'
#' Order of precedence:
#'   1. `WORKFORCE_DATA_CSV` environment variable (tests / overrides).
#'   2. The frozen authoritative table at data/ (SSOT).
#'
#' @return Absolute path to the workforce-projection CSV (character scalar).
#' @keywords internal
resolve_workforce_data_path <- function() {
  env_path <- Sys.getenv("WORKFORCE_DATA_CSV", unset = "")
  if (nzchar(env_path)) {
    return(env_path)
  }
  here::here("data", "workforce_projections_consolidated.csv")
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Derived helpers
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' Classify a replacement ratio into a workforce-outlook label.
#'
#' @param ratio Numeric vector of replacement ratios (graduates / retirements).
#' @return Character vector of `WORKFORCE_VALID_ASSESSMENTS` labels.
classify_replacement <- function(ratio) {
  ifelse(
    ratio > WORKFORCE_REPLACEMENT_ABOVE_MIN, "Above replacement",
    ifelse(ratio >= WORKFORCE_REPLACEMENT_AT_MIN, "At replacement", "Below replacement")
  )
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Fail-loud validator
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' Validate a workforce-projection table against the data contract.
#'
#' Rejects (with an actionable `stop()`) any table that is structurally
#' incomplete, contains placeholder/degenerate values, or violates the
#' arithmetic that ties the columns together. This is the single guard that
#' turns the "silent zeros in the manuscript" failure into a loud error.
#'
#' @param df          A data frame / tibble read from the consolidated CSV.
#' @param expected    Character vector of expected `subspecialty_abbrev` values.
#'                    Defaults to `WORKFORCE_SUBSPECIALTIES`.
#' @param source_hint Optional string naming the data source, used in messages.
#' @return `df` invisibly, if every check passes.
validate_workforce_data <- function(df,
                                    expected = WORKFORCE_SUBSPECIALTIES,
                                    source_hint = NULL) {
  where <- if (is.null(source_hint)) "" else sprintf(" [source: %s]", source_hint)
  fail <- function(...) {
    stop(sprintf("[workforce contract]%s %s", where, sprintf(...)),
         call. = FALSE)
  }

  # --- structure -----------------------------------------------------------
  if (!is.data.frame(df)) fail("data is not a data frame (got %s)", class(df)[1])

  missing_cols <- setdiff(WORKFORCE_REQUIRED_COLUMNS, names(df))
  if (length(missing_cols) > 0) {
    fail("missing required column(s): %s", paste(missing_cols, collapse = ", "))
  }

  if (nrow(df) == 0L) fail("table has 0 rows")

  # --- subspecialty set (exact) --------------------------------------------
  if (anyDuplicated(df$subspecialty_abbrev) > 0L) {
    fail("duplicate subspecialty_abbrev value(s): %s",
         paste(df$subspecialty_abbrev[duplicated(df$subspecialty_abbrev)],
               collapse = ", "))
  }
  if (!setequal(df$subspecialty_abbrev, expected)) {
    fail(paste0(
      "subspecialty set mismatch.\n  expected exactly: %s\n  got:              %s\n",
      "  -> This usually means the CSV is a stale/zero scaffold. Restore the ",
      "frozen table at data/workforce_projections_consolidated.csv."),
      paste(expected, collapse = ", "),
      paste(df$subspecialty_abbrev, collapse = ", "))
  }

  # --- NA in critical numeric columns --------------------------------------
  num_cols <- c("baseline_2025", "projected_2029", "avg_annual_retirements",
                "annual_entrants", "replacement_ratio", "percent_change",
                "ci95_lower", "ci95_upper")
  for (col in num_cols) {
    if (any(is.na(df[[col]]))) fail("NA present in column '%s'", col)
  }

  # --- degenerate / placeholder values -------------------------------------
  if (any(df$baseline_2025 <= 0))          fail("baseline_2025 must be > 0 (zero scaffold?)")
  if (any(df$projected_2029 <= 0))         fail("projected_2029 must be > 0")
  if (any(df$avg_annual_retirements <= 0)) fail("avg_annual_retirements must be > 0")
  if (any(df$annual_entrants < 0))         fail("annual_entrants must be >= 0")
  if (any(df$ci95_lower > df$ci95_upper))  fail("ci95_lower exceeds ci95_upper")

  bad_assessment <- setdiff(unique(df$replacement_assessment), WORKFORCE_VALID_ASSESSMENTS)
  if (length(bad_assessment) > 0) {
    fail("invalid replacement_assessment value(s): %s (expected one of %s)",
         paste(bad_assessment, collapse = ", "),
         paste(WORKFORCE_VALID_ASSESSMENTS, collapse = "/"))
  }

  # --- semantic self-consistency (the columns must agree) ------------------
  ratio_calc <- df$annual_entrants / df$avg_annual_retirements
  ratio_bad  <- which(abs(ratio_calc - df$replacement_ratio) > WORKFORCE_TOL_RATIO)
  if (length(ratio_bad) > 0) {
    fail("replacement_ratio disagrees with annual_entrants/avg_annual_retirements for: %s",
         paste(df$subspecialty_abbrev[ratio_bad], collapse = ", "))
  }

  proj_calc <- df$baseline_2025 +
    WORKFORCE_PROJECTION_HORIZON_YEARS * (df$annual_entrants - df$avg_annual_retirements)
  proj_bad <- which(abs(proj_calc - df$projected_2029) > WORKFORCE_TOL_PROJECTION)
  if (length(proj_bad) > 0) {
    fail(paste0("projected_2029 disagrees with baseline + %d*(entrants-retirements) ",
                "for: %s"),
         WORKFORCE_PROJECTION_HORIZON_YEARS,
         paste(df$subspecialty_abbrev[proj_bad], collapse = ", "))
  }

  pct_calc <- 100 * (df$projected_2029 - df$baseline_2025) / df$baseline_2025
  pct_bad  <- which(abs(pct_calc - df$percent_change) > WORKFORCE_TOL_PERCENT)
  if (length(pct_bad) > 0) {
    fail("percent_change disagrees with 100*(projected-baseline)/baseline for: %s",
         paste(df$subspecialty_abbrev[pct_bad], collapse = ", "))
  }

  assess_calc <- classify_replacement(df$replacement_ratio)
  assess_bad  <- which(assess_calc != df$replacement_assessment)
  if (length(assess_bad) > 0) {
    fail("replacement_assessment disagrees with the ratio thresholds for: %s",
         paste(df$subspecialty_abbrev[assess_bad], collapse = ", "))
  }

  invisible(df)
}

#' Load and validate the canonical workforce-projection table.
#'
#' @param path        CSV path. Defaults to `resolve_workforce_data_path()`.
#' @param expected    Expected subspecialty set (see `validate_workforce_data`).
#' @return A validated tibble (fails loudly otherwise).
load_workforce_data <- function(path = resolve_workforce_data_path(),
                                expected = WORKFORCE_SUBSPECIALTIES) {
  if (!file.exists(path)) {
    stop(sprintf(paste0(
      "[workforce contract] data file not found: %s\n",
      "  Restore the frozen table at data/workforce_projections_consolidated.csv ",
      "or set WORKFORCE_DATA_CSV."), path), call. = FALSE)
  }
  df <- readr::read_csv(path, show_col_types = FALSE)
  validate_workforce_data(df, expected = expected, source_hint = basename(path))
  # Strip readr's non-deterministic pointer-valued 'problems' attribute so that
  # identical(load_workforce_data(), load_workforce_data()) holds.
  attr(df, "problems") <- NULL
  df
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Sensitivity-artifact contract (reviewer sensitivities S25-S31).
# The manuscript getters read these CSVs via .op_load(); a stale/missing one would
# otherwise render as a silent NA. This registry lets the render (and CI) fail loud
# instead. Extend the registry whenever a new sensitivity CSV reaches the manuscript.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
WORKFORCE_SENSITIVITY_ARTIFACTS <- list(
  "mortality_sensitivity.csv"                        = c("subspecialty_abbrev","ratio_primary","ratio_adj_all_missed","ratio_adj_half_missed","expected_mortality_per_yr"),
  "consistent_definition_baseline_sensitivity.csv"   = c("subspecialty_abbrev","baseline_primary","baseline_consistent","ratio_primary","ratio_consistent"),
  "inactivity_threshold_sensitivity.csv"             = c("subspecialty_abbrev","threshold_years","replacement_ratio"),
  "hierarchical_hazard_comparison.csv"               = c("subspecialty_abbrev","method","replacement_ratio","ci_lo","ci_hi"),
  "graduate_growth_scenarios.csv"                    = c("subspecialty_abbrev","scenario","replacement_ratio"),
  "baseline_lag_decomposition.csv"                   = c("subspecialty_abbrev","baseline_total","ratio_primary","ratio_lag_trimmed","directly_supported","carried_fwd_3plus","abu_net_new"),
  "temporal_backtest_ageband.csv"                    = c("subspecialty_abbrev","age_band","n_base","observed_active","predicted_active","pct_error")
)

#' Fail-closed validation that every registered sensitivity artifact exists with its
#' required columns. Called at manuscript setup so a stale/missing CSV stops the render
#' instead of rendering a silent NA.
#' @param data_dir directory holding the sensitivity CSVs (default cliff/data).
#' @param strict   TRUE (default) stops on any problem; FALSE warns. Env override:
#'   WORKFORCE_SENSITIVITY_CONTRACT=relaxed downgrades to a warning.
validate_sensitivity_artifacts <- function(data_dir = here::here("data"), strict = TRUE) {
  if (identical(Sys.getenv("WORKFORCE_SENSITIVITY_CONTRACT"), "relaxed")) strict <- FALSE
  problems <- character()
  for (f in names(WORKFORCE_SENSITIVITY_ARTIFACTS)) {
    p <- file.path(data_dir, f)
    if (!file.exists(p)) { problems <- c(problems, sprintf("MISSING: %s", f)); next }
    cols <- tryCatch(names(readr::read_csv(p, n_max = 0, show_col_types = FALSE)),
                     error = function(e) { problems <<- c(problems, sprintf("UNREADABLE: %s (%s)", f, conditionMessage(e))); character() })
    miss <- setdiff(WORKFORCE_SENSITIVITY_ARTIFACTS[[f]], cols)
    if (length(miss)) problems <- c(problems, sprintf("%s missing column(s): %s", f, paste(miss, collapse = ", ")))
  }
  if (length(problems)) {
    msg <- paste0("[workforce sensitivity contract] ", length(problems), " problem(s):\n  ",
                  paste(problems, collapse = "\n  "),
                  "\n  Regenerate via Rscript scripts/run_all_sensitivities.R")
    if (strict) stop(msg, call. = FALSE) else warning(msg, call. = FALSE)
  }
  invisible(TRUE)
}
