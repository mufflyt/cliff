# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Workforce Statistics Helper Functions for Manuscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose: Provide inline statistics accessor functions for R Markdown manuscript
#          Enables dynamic text like `r get_baseline("URPS")` in Rmd
#
# Data Source: data/workforce_projections_consolidated.csv (SSOT via contract)
#
# Usage: source(here("manuscript/R/workforce_statistics.R"))
#
# Author: Tyler Muffly, MD / Claude Code
# Date: 2026-01-12
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(tidyverse)
  library(here)
})

# Data contract: constants, canonical path, and the fail-loud validator.
source(here::here("manuscript", "R", "workforce_data_contract.R"))

# Monte Carlo iteration count. As of the Tier-3 dynamic-model integration
# (2026-07-18) the SD/CI columns in the SSOT ARE a live re-runnable simulation:
# scripts/rebuild_ssot_dynamic_acgme.R runs a 1,000-iteration seeded microsimulation
# of the age-structured departure process and writes the 95% PREDICTION interval
# (ci95_lower/upper) and its SD into data/workforce_projections_consolidated.csv.
# The count lives once in workforce_data_contract.R; keep this alias for callers.
N_MONTE_CARLO_ITERATIONS <- WORKFORCE_MONTE_CARLO_ITERATIONS

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Load Data (canonical source + fail-loud validation)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# SSOT is data/workforce_projections_consolidated.csv (three surgical
# subspecialties). A zero / "Unknown" / wrong-shape table stops the render here
# with a remediation message instead of silently publishing zeros.

.workforce_data_path <- resolve_workforce_data_path()
.workforce_data <- load_workforce_data(.workforce_data_path)

# NRMP-positions-filled benchmark (retained comparison to the ACGME-graduate
# primary inflow). Optional: absent file yields NA-returning getters rather than
# a hard stop, so the manuscript still renders if only the benchmark is missing.
.workforce_benchmark_path <- here::here("data",
                                        "workforce_projection_benchmark_nrmp.csv")
.workforce_benchmark <- if (file.exists(.workforce_benchmark_path)) {
  readr::read_csv(.workforce_benchmark_path, show_col_types = FALSE)
} else NULL

.bench_val <- function(subspecialty, col) {
  if (is.null(.workforce_benchmark)) return(NA)
  pat <- toupper(trimws(subspecialty))
  row <- .workforce_benchmark[toupper(.workforce_benchmark$subspecialty_abbrev) == pat, ]
  if (nrow(row) != 1) return(NA)
  row[[col]]
}

#' Get the NRMP-positions-filled benchmark entrant count for a subspecialty.
#' @param subspecialty Abbreviation ("URPS", "GO", "MIGS").
#' @return Integer NRMP filled count (the retained benchmark inflow).
get_nrmp_entrants <- function(subspecialty) .bench_val(subspecialty, "nrmp_entrants")

#' Get the replacement ratio under the NRMP-filled benchmark inflow.
#' @param subspecialty Abbreviation.
#' @return Formatted string, one decimal (e.g., "3.4").
get_nrmp_ratio <- function(subspecialty) sprintf("%.1f", .bench_val(subspecialty, "replacement_ratio_nrmp"))

#' Get total NRMP-filled benchmark entrants across all three subspecialties.
#' @return Integer sum, or NA if the benchmark file is absent.
get_total_nrmp_entrants <- function() {
  if (is.null(.workforce_benchmark)) return(NA)
  sum(.workforce_benchmark$nrmp_entrants)
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Accessor Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Helper to filter by subspecialty (uses partial matching on full name or abbreviation)
#'  filter subspec
#'
#' Helper function used in manuscript workflows.
#' @param subspecialty_pattern Input for `subspecialty_pattern`.
#' @return Result from `.filter_subspec`.
#' @keywords internal
.filter_subspec <- function(subspecialty_pattern) {
  # BUG FIX (2026-07-14): match on the abbreviation column FIRST, exactly and
  # case-insensitively. The previous version ran `subspecialty_pattern` as a
  # regex against the full-name column, which is fragile: names contain regex
  # metacharacters (e.g. "&") and an abbreviation like "GO" could substring-match
  # an unrelated full name. Exact-abbrev-first is unambiguous.
  pat <- toupper(trimws(subspecialty_pattern))

  result <- .workforce_data[toupper(.workforce_data$subspecialty_abbrev) == pat, ]

  # Fall back to a FIXED (non-regex) case-insensitive substring on the full name.
  if (nrow(result) == 0) {
    result <- .workforce_data[str_detect(
      .workforce_data$subspecialty,
      fixed(subspecialty_pattern, ignore_case = TRUE)
    ), ]
  }

  if (nrow(result) == 0) {
    stop(sprintf("No subspecialty found matching pattern: '%s'", subspecialty_pattern))
  }

  if (nrow(result) > 1) {
    stop(sprintf("Pattern '%s' matched multiple subspecialties: %s\nUse a more specific pattern.",
                 subspecialty_pattern,
                 paste(result$subspecialty, collapse = ", ")))
  }

  result
}

#' Get baseline workforce count (2025)
#' @param subspecialty Partial name match (e.g., "URPS", "Gynecologic", "Minimally")
#' @return Formatted string with comma separator (e.g., "1,283")
get_baseline <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(baseline_2025) %>%
    format(big.mark = ",")
}

#' Get projected workforce count (2029)
#' @param subspecialty Partial name match
#' @return Formatted string with comma separator
get_projected <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(projected_2029) %>%
    round() %>%
    format(big.mark = ",")
}

#' Get lower 95% confidence interval
#' @param subspecialty Partial name match
#' @return Formatted string with comma separator
get_ci_lower <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(ci95_lower) %>%
    format(big.mark = ",")
}

#' Get upper 95% confidence interval
#' @param subspecialty Partial name match
#' @return Formatted string with comma separator
get_ci_upper <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(ci95_upper) %>%
    format(big.mark = ",")
}

# BUG FIX #88 (2026-06-29): get_percent_change() called abs(), stripping the
# sign. A positive change (growth) returned "1.4", which prose then labelled
# "1.4% decline" — the contradiction was invisible because the sign was gone.
# Fix: return the signed value. Callers that want magnitude must call abs()
# themselves; callers that embed the number in directional prose must match
# the sign to the word they choose.
#' Get percent change with sign
#' @param subspecialty Partial name match
#' @return Formatted string with sign (e.g., "+1.4" or "-5.5")
get_percent_change <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(percent_change) %>%
    sprintf("%+.1f", .)
}

#' Get absolute percent change magnitude (no sign)
#' @param subspecialty Partial name match
#' @return Formatted string (e.g., "1.4")
get_percent_change_magnitude <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(percent_change) %>%
    abs() %>%
    sprintf("%.1f", .)
}

#' Get the direction word for a subspecialty ("growth" or "decline")
#' @param subspecialty Partial name match
#' @return "growth" or "decline"
get_direction <- function(subspecialty) {
  pct <- .filter_subspec(subspecialty) %>% pull(percent_change)
  if (pct >= 0) "growth" else "decline"
}

#' Get the present-participle direction verb for a subspecialty, driven by the
#' sign of percent_change so directional prose can never contradict the data
#' (guards against the BUG FIX #87 failure mode of a hardcoded "increasing"/
#' "declining" that drifts from the SSOT).
#' @param subspecialty Partial name match
#' @return "increasing" or "decreasing"
get_change_verb <- function(subspecialty) {
  pct <- .filter_subspec(subspecialty) %>% pull(percent_change)
  if (pct >= 0) "increasing" else "decreasing"
}

#' Get the noun / infinitive direction word ("increase" or "decrease") for a
#' subspecialty, driven by the sign of percent_change. Reads naturally both as a
#' noun ("a 6.0% decrease") and as an infinitive verb ("projected to decrease").
#' Use this instead of typing "increase"/"decrease" (or "growth"/"decline") so
#' the direction can never contradict the data — we have been burned by hardcoded
#' direction words before (BUG FIX #87).
#' @param subspecialty Partial name match
#' @return "increase" or "decrease"
get_change_noun <- function(subspecialty) {
  pct <- .filter_subspec(subspecialty) %>% pull(percent_change)
  if (pct >= 0) "increase" else "decrease"
}

#' Get projected net physician change over the 4-year window (signed integer)
#' @param subspecialty Partial name match
#' @return Formatted string with sign (e.g., "+18" or "-74")
get_net_change_4yr <- function(subspecialty) {
  row <- .filter_subspec(subspecialty)
  net <- round(row$projected_2029) - row$baseline_2025
  sprintf("%+d", as.integer(net))
}

#' Get percent change with sign
#' @param subspecialty Partial name match
#' @return Formatted string with sign (e.g., "-7.0" or "+8.4")
get_percent_change_signed <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(percent_change) %>%
    sprintf("%+.1f", .)
}

#' Get annual retirement rate
#' @param subspecialty Partial name match
#' @return Formatted string (e.g., "4.4")
get_annual_rate <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(annual_retirement_rate) %>%
    sprintf("%.1f", .)
}

#' Get replacement ratio
#' @param subspecialty Partial name match
#' @return Formatted string, one decimal (e.g., "0.9")
get_replacement_ratio <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(replacement_ratio) %>%
    sprintf("%.1f", .)
}

#' Get replacement assessment classification
#' @param subspecialty Partial name match
#' @return String: "Adequate", "Marginal", or "Insufficient"
get_replacement_assessment <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(replacement_assessment)
}

#' Get total fellowship graduates over the four-year projection horizon
#' Reads the SSOT fellowship_total_4yr column (annual_entrants x horizon), which
#' shares the same 2025-2029 window as total_retirements_4yr so the two are
#' directly comparable. (Horizon standardized to 4 years on 2026-07-15; the
#' prior five-year column was removed.)
#' @param subspecialty Partial name match
#' @return Formatted string with comma separator
get_fellowship_total <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(fellowship_total_4yr) %>%
    format(big.mark = ",")
}

#' Get total fellowship graduates over the four-year projection horizon
#' Computes annual_entrants x WORKFORCE_PROJECTION_HORIZON_YEARS directly; agrees
#' with get_fellowship_total() (which reads the equivalent SSOT column).
#' @param subspecialty Partial name match
#' @return Formatted string with comma separator
get_fellowship_total_4yr <- function(subspecialty) {
  entrants <- .filter_subspec(subspecialty) %>%
    pull(annual_entrants)
  format(entrants * WORKFORCE_PROJECTION_HORIZON_YEARS, big.mark = ",")
}

#' Get total annual fellowship graduates across all subspecialties
#' (sum of annual_entrants). Distinct from get_total_baseline(), which is the
#' active workforce. Fixes a bug where the manuscript reported the total
#' workforce as the annual graduate count.
#' @return Formatted string with comma separator
get_total_annual_entrants <- function() {
  sum(.workforce_data$annual_entrants) %>%
    format(big.mark = ",")
}

#' Get annual fellowship entrants
#' @param subspecialty Partial name match
#' @return Numeric value
get_annual_entrants <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(annual_entrants)
}

#' Get average annual retirements
#' @param subspecialty Partial name match
#' @return Formatted string (e.g., "55.6")
get_avg_retirements <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(avg_annual_retirements) %>%
    sprintf("%.1f", .)
}

#' Get the annual fellowship graduates required to reach the 20% replacement
#' buffer (ratio >= WORKFORCE_REPLACEMENT_BUFFER) for a subspecialty.
#' @param subspecialty Partial name match
#' @return Integer count of annual graduates needed for the buffer
get_positions_for_adequate <- function(subspecialty) {
  avg_ret <- .filter_subspec(subspecialty) %>% pull(avg_annual_retirements)
  as.integer(ceiling(avg_ret * WORKFORCE_REPLACEMENT_BUFFER))
}

#' Get the 20% replacement-buffer sensitivity threshold as a display string
#' (e.g., "1.2"). This is a buffer, NOT a clinical adequacy standard.
#' @return Formatted string
get_adequate_threshold <- function() {
  sprintf("%.1f", WORKFORCE_REPLACEMENT_BUFFER)
}

#' Get standard deviation for 2029 projection
#' @param subspecialty Partial name match
#' @return Formatted string (e.g., "15.2")
get_sd <- function(subspecialty) {
  .filter_subspec(subspecialty) %>%
    pull(sd_2029) %>%
    sprintf("%.1f", .)
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Summary Statistics (Aggregate)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' Get total baseline workforce across all subspecialties
#' @return Formatted string with comma separator
get_total_baseline <- function() {
  sum(.workforce_data$baseline_2025) %>%
    format(big.mark = ",")
}

#' Get total projected workforce across all subspecialties
#' @return Formatted string with comma separator
get_total_projected <- function() {
  sum(.workforce_data$projected_2029) %>%
    round() %>%
    format(big.mark = ",")
}

#' Get net change across all subspecialties
#' @return Formatted string with sign and comma separator
get_total_net_change <- function() {
  net_change <- sum(.workforce_data$projected_2029) - sum(.workforce_data$baseline_2025)
  sprintf("%s%s",
          ifelse(net_change >= 0, "+", ""),
          format(round(net_change), big.mark = ","))
}

#' Get total percent change across all subspecialties
#' @return Formatted string with sign (e.g., "-3.8")
get_total_percent_change <- function() {
  # BUG FIX CC1 (2026-01-29): Guard against division by zero.
  # If baseline is 0 (no physicians), returns Inf which breaks sprintf output.
  baseline_sum <- sum(.workforce_data$baseline_2025)
  if (baseline_sum <= 0) {
    return("N/A")
  }
  pct_change <- 100 * (sum(.workforce_data$projected_2029) - baseline_sum) / baseline_sum
  sprintf("%+.1f", pct_change)
}

#' Count subspecialties by replacement assessment
#' @param assessment "Adequate", "Marginal", or "Insufficient"
#' @return Integer count
count_by_assessment <- function(assessment) {
  sum(.workforce_data$replacement_assessment == assessment)
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# EXPLORATORY: claims-defined operative-workforce analysis (GO and URPS)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Medicare-provisional exploratory analysis, reported chiefly as a VALIDITY
# finding (see supplement). The measured event is "sustained cessation of
# Medicare-observed qualifying surgery"; only 7-18% of such events are
# corroborated by total-billing-stop or NPPES deactivation, so the endpoint
# cannot be equated with true operative retirement and the (corrected, above-one)
# replacement estimates are NOT interpreted. Getters read the producer CSVs from
# scripts/operative_capacity_and_validation.R; absent files yield NA getters.

.op_load <- function(name) {
  p <- here::here("data", name)
  if (file.exists(p)) readr::read_csv(p, show_col_types = FALSE) else NULL
}
.operative_data <- .op_load("operative_workforce.csv")
.operative_cap  <- .op_load("operative_capacity.csv")
.operative_adj  <- .op_load("operative_adjudication.csv")
.operative_tte  <- .op_load("operative_tte.csv")

.op_get <- function(tbl, subspecialty, col) {
  if (is.null(tbl)) return(NA)
  pat <- toupper(trimws(subspecialty))
  row <- tbl[toupper(tbl$subspecialty_abbrev) == pat, ]
  if (nrow(row) != 1) return(NA)
  row[[col]]
}
.op_val <- function(subspecialty, col) .op_get(.operative_data, subspecialty, col)

#' Sustained-cessation rate (% per year) among Medicare-visible established
#' operators. GO or URPS only.
get_op_cessation_rate <- function(subspecialty) sprintf("%.1f", .op_val(subspecialty, "operative_cessation_rate_pct"))

#' Percent of physicians still billing clinically after their last observed operation.
get_op_still_billing <- function(subspecialty) as.integer(.op_val(subspecialty, "pct_still_billing_after"))

#' Count of Medicare-visible established operators in the active cohort.
get_op_operators <- function(subspecialty) as.integer(.op_val(subspecialty, "medicare_visible_operators"))

#' Percent of the ACTIVE board-certified cohort visible as established Medicare
#' operators (corrected denominator = active workforce, not the total incl. retirees).
get_op_visible_pct <- function(subspecialty) sprintf("%.0f", .op_val(subspecialty, "pct_of_active_visible"))

#' Percent of apparent operative cessations CORROBORATED as true exits by an
#' independent signal (total Medicare billing stopped or NPPES deactivation).
#' This is the key validity number. GO or URPS.
get_op_corroborated <- function(subspecialty) as.integer(.op_get(.operative_adj, subspecialty, "pct_corroborated_true_exit"))

#' Cumulative probability a graduate becomes an established Medicare operator by
#' 8 years post-certification (time-to-event; supersedes the fixed-ramp estimate).
get_op_conversion_8yr <- function(subspecialty) sprintf("%.0f", 100 * .op_get(.operative_tte, subspecialty, "ci_operator_by8yr"))

#' Volume-weighted operative-workforce capacity ratio (above one; reported in the
#' supplement, NOT interpreted in the main text because of the endpoint's poor validity).
get_op_capacity_ratio <- function(subspecialty) sprintf("%.1f", .op_get(.operative_cap, subspecialty, "operative_workforce_capacity_ratio"))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Multidimensional sensitivity grid (review point #1)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Honest reporting of the fully-crossed grid (window x rate-multiplier x
# conversion): one-way sensitivities stay above replacement, below-replacement
# cells arise only when several adverse assumptions combine. Getters read
# data/sensitivity_grid_summary.csv (producer: scripts/sensitivity_grid.R).

.grid_summary <- .op_load("sensitivity_grid_summary.csv")
.grid_get <- function(subspecialty, col) .op_get(.grid_summary, subspecialty, col)

#' Total cells in the multidimensional sensitivity grid (e.g., 27).
get_grid_total <- function(subspecialty) as.integer(.grid_get(subspecialty, "n_cells"))
#' Cells above replacement (ratio > 1.05).
get_grid_above <- function(subspecialty) as.integer(.grid_get(subspecialty, "n_above"))
#' Cells at replacement (0.95 to 1.05).
get_grid_at <- function(subspecialty) as.integer(.grid_get(subspecialty, "n_at"))
#' Cells below replacement (ratio < 0.95).
get_grid_below <- function(subspecialty) as.integer(.grid_get(subspecialty, "n_below"))
#' Worst (minimum) replacement ratio anywhere in the grid.
get_grid_worst <- function(subspecialty) sprintf("%.2f", .grid_get(subspecialty, "worst_ratio"))
#' Minimum ratio across ONE-WAY (single-lever) sensitivities (stays above replacement).
get_grid_oneway_min <- function(subspecialty) sprintf("%.2f", .grid_get(subspecialty, "oneway_min"))

# Break-even ranges across the two BOARD-CERTIFIED cohorts (GO, URPS), drift-proof
# so they cannot go stale as the SSOT changes (MIGS is reported separately).
.breakeven <- .op_load("breakeven_thresholds.csv")
.bkv <- function() {
  if (is.null(.breakeven)) return(NULL)
  .breakeven[.breakeven$subspecialty_abbrev %in% c("GO", "URPS"), ]
}
#' Departure-rate multiple needed to reach replacement, GO-URPS range (e.g., "4.5 to 5.8").
get_breakeven_rate_range <- function() {
  b <- .bkv(); if (is.null(b)) return("NA")
  sprintf("%.1f- to %.1f-fold", min(b$breakeven_rate_multiple), max(b$breakeven_rate_multiple))
}
#' Graduate-output drop needed to reach replacement, GO-URPS range (e.g., "78% to 83%").
get_breakeven_drop_range <- function() {
  b <- .bkv(); if (is.null(b)) return("NA")
  sprintf("%d%% to %d%%", min(b$graduate_drop_pct), max(b$graduate_drop_pct))
}

#' Classifier false-negative tipping point: the fraction of true departures that
#' would have to be MISSED for replacement to fail, at a given graduate-to-practice
#' conversion factor (1.0 = all completers enter). GO-URPS range, drift-proof.
get_tipping_missed_range <- function(conv = 1.0) {
  go_e <- as.numeric(.filter_subspec("GO")$annual_entrants) * conv
  go_d <- as.numeric(.filter_subspec("GO")$avg_annual_retirements)
  ur_e <- as.numeric(.filter_subspec("URPS")$annual_entrants) * conv
  ur_d <- as.numeric(.filter_subspec("URPS")$avg_annual_retirements)
  m <- c((go_e - go_d)/go_e, (ur_e - ur_d)/ur_e) * 100
  sprintf("%.0f%% to %.0f%%", min(m), max(m))
}

# Automated departure-classifier corroboration proxy (review point #3). A
# provisional PPV proxy only; true PPV requires the chart adjudication.
.corr_data <- .op_load("classifier_corroboration.csv")
#' Percent of classified departures with an independent corroborating signal.
get_ppv_proxy <- function(subspecialty) as.integer(.op_get(.corr_data, subspecialty, "ppv_proxy_corroborated"))

# Open Payments construct-validity sensitivity (reviewer #2). Departure rate and
# replacement ratio under alternative source-inclusion rules.
.op_sens <- .op_load("open_payments_sensitivity.csv")
.opsg <- function(rule, subspecialty, col) {
  if (is.null(.op_sens)) return(NA)
  r <- .op_sens[.op_sens$rule == rule &
                toupper(.op_sens$subspecialty_abbrev) == toupper(trimws(subspecialty)), ]
  if (nrow(r) != 1) return(NA)
  r[[col]]
}
#' Departure rate (%) under an Open Payments source-inclusion rule.
get_opsens_rate <- function(rule, subspecialty) sprintf("%.1f", .opsg(rule, subspecialty, "departure_rate_pct"))
#' Replacement ratio under an Open Payments source-inclusion rule (one decimal).
get_opsens_ratio <- function(rule, subspecialty) sprintf("%.1f", .opsg(rule, subspecialty, "replacement_ratio"))

# Graduation -> active-practice transition function (review point #3).
.trans_data <- .op_load("graduation_active_transition.csv")
.trans_proj <- .op_load("graduation_active_transition_projection.csv")
#' Cumulative fraction of a certification cohort active by k years (as percent).
get_transition_kyr <- function(subspecialty, k) {
  if (is.null(.trans_data)) return(NA)
  pat <- toupper(trimws(subspecialty))
  row <- .trans_data[toupper(.trans_data$subspecialty_abbrev) == pat & .trans_data$k == k, ]
  if (nrow(row) != 1) return(NA)
  as.integer(round(100 * row$cum_active_fraction))
}
#' Ever-Medicare-billed ceiling (visibility, not entry), as percent.
get_transition_ceiling <- function(subspecialty) {
  if (is.null(.trans_data)) return(NA)
  pat <- toupper(trimws(subspecialty))
  row <- .trans_data[toupper(.trans_data$subspecialty_abbrev) == pat & .trans_data$k == 0, ]
  if (nrow(row) != 1) return(NA)
  as.integer(round(100 * row$ever_billed_ceiling))
}
#' Percent of the projected four-year growth deferred beyond 2029 by the entry ramp.
get_transition_deferred <- function(subspecialty) as.integer(.op_get(.trans_proj, subspecialty, "pct_of_growth_deferred"))
#' Transition-adjusted (ramped) projected 2029 count.
get_transition_ramped_2029 <- function(subspecialty) format(as.integer(.op_get(.trans_proj, subspecialty, "projected_2029_ramped")), big.mark = ",")

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Reviewer sensitivities (scripts/build_reviewer_sensitivities.R)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# #2 age-specific mortality (SSA Period Life Table 2020) layered onto the departure numerator.
.mortality_sens <- .op_load("mortality_sensitivity.csv")
#' Completion-to-departure ratio after adding ALL expected age-specific deaths (upper bound).
get_mortality_ratio_all  <- function(subspecialty) sprintf("%.1f", .op_get(.mortality_sens, subspecialty, "ratio_adj_all_missed"))
#' Completion-to-departure ratio adding half the expected deaths (realistic partial under-ascertainment).
get_mortality_ratio_half <- function(subspecialty) sprintf("%.1f", .op_get(.mortality_sens, subspecialty, "ratio_adj_half_missed"))
#' Expected age-specific deaths per year in the active stock.
get_mortality_deaths     <- function(subspecialty) sprintf("%.0f", .op_get(.mortality_sens, subspecialty, "expected_mortality_per_yr"))
#' Departure rate (%) after adding all expected deaths.
get_mortality_rate_adj   <- function(subspecialty) sprintf("%.1f", .op_get(.mortality_sens, subspecialty, "rate_adj_all_pct"))

# #10 age-band-stratified temporal back-test.
.backtest_band <- .op_load("temporal_backtest_ageband.csv")
#' Max absolute percent back-test error among well-populated age bands (n_base >= min_n).
get_backtest_band_maxerr <- function(min_n = 50) {
  if (is.null(.backtest_band)) return(NA)
  e <- abs(.backtest_band$pct_error[.backtest_band$n_base >= min_n])
  sprintf("%.0f", max(e, na.rm = TRUE))
}

# #5 estimated-baseline lag decomposition.
.baseline_lag <- .op_load("baseline_lag_decomposition.csv")
.blrow <- function(subspecialty) {
  if (is.null(.baseline_lag)) return(NULL)
  r <- .baseline_lag[toupper(.baseline_lag$subspecialty_abbrev) == toupper(trimws(subspecialty)), ]
  if (nrow(r) != 1) return(NULL); r
}
#' Percent of the Part B-observable (ABOG-pathway) active stock directly supported in the latest admin year.
get_baseline_directly_pct <- function(subspecialty) {
  r <- .blrow(subspecialty); if (is.null(r)) return(NA)
  sprintf("%.0f", 100 * r$directly_supported / (r$baseline_total - r$abu_net_new))
}
#' Count resting on a three-year-or-longer administrative carry-forward.
get_baseline_carried3 <- function(subspecialty) { r <- .blrow(subspecialty); if (is.null(r)) return(NA); as.integer(r$carried_fwd_3plus) }
#' Completion-to-departure ratio after removing the long-lag carried-forward stock (adverse baseline-lag bound).
get_baseline_lag_ratio <- function(subspecialty) { r <- .blrow(subspecialty); if (is.null(r)) return(NA); sprintf("%.1f", r$ratio_lag_trimmed) }

# #8 graduate-supply growth scenarios.
.grad_scen <- .op_load("graduate_growth_scenarios.csv")
#' Completion-to-departure ratio under a graduate-supply scenario.
get_grad_scenario_ratio <- function(scenario, subspecialty) {
  if (is.null(.grad_scen)) return(NA)
  r <- .grad_scen[.grad_scen$scenario == scenario &
                   toupper(.grad_scen$subspecialty_abbrev) == toupper(trimws(subspecialty)), ]
  if (nrow(r) != 1) return(NA)
  sprintf("%.1f", r$replacement_ratio)
}

# #9 inactivity-threshold (2/3/4-year) sensitivity, from Medicare Part B activity.
.inactivity_sens <- .op_load("inactivity_threshold_sensitivity.csv")
#' Completion-to-departure ratio at a required inactivity threshold (years).
get_inactivity_ratio <- function(threshold, subspecialty) {
  if (is.null(.inactivity_sens)) return(NA)
  r <- .inactivity_sens[.inactivity_sens$threshold_years == threshold &
                          toupper(.inactivity_sens$subspecialty_abbrev) == toupper(trimws(subspecialty)), ]
  if (nrow(r) != 1) return(NA)
  sprintf("%.1f", r$replacement_ratio)
}

# #4 hierarchical partial-pooling hazard comparison (unpooled / pooled / partial_pooled).
.hier_hz <- .op_load("hierarchical_hazard_comparison.csv")
.hier_row <- function(method, subspecialty) {
  if (is.null(.hier_hz)) return(NULL)
  r <- .hier_hz[.hier_hz$method == method &
                 toupper(.hier_hz$subspecialty_abbrev) == toupper(trimws(subspecialty)), ]
  if (nrow(r) != 1) return(NULL)
  r
}
#' Completion-to-departure ratio under a pooling method (unpooled/pooled/partial_pooled).
get_hier_ratio <- function(method, subspecialty) {
  r <- .hier_row(method, subspecialty); if (is.null(r)) return(NA); sprintf("%.1f", r$replacement_ratio)
}
#' 95% interval (lo to hi) for a pooling method's ratio.
get_hier_ci <- function(method, subspecialty) {
  r <- .hier_row(method, subspecialty); if (is.null(r) || is.na(r$ci_lo)) return(NA)
  sprintf("%.1f to %.1f", r$ci_lo, r$ci_hi)
}

# ---- Primary age-band hazard method: single source of truth -----------------
# The headline fellowship-completion-to-departure ratios (Table 2, abstract,
# Discussion, Conclusion) come from the dynamic model driven by ONE hazard
# method. That method is named here, once. Every place the manuscript names the
# primary hazard reads its LABEL from primary_hazard_adjective() and its NUMBERS
# from get_primary_ratio()/get_primary_ci(), so the word and the value can never
# disagree. The load-time guard below stops the render if the headline table and
# the named primary method's hierarchical row ever diverge. To change the primary
# estimator, flip this one constant AND regenerate the workforce table on that
# hazard; the guard enforces that both moved together.
WORKFORCE_PRIMARY_HAZARD_METHOD <- "pooled"

#' Human-readable adjective for the primary hazard method (matches the number).
primary_hazard_adjective <- function(method = WORKFORCE_PRIMARY_HAZARD_METHOD) {
  switch(method,
    pooled         = "pooled",
    partial_pooled = "hierarchical partial-pooled",
    unpooled       = "fully unpooled",
    stop("unknown WORKFORCE_PRIMARY_HAZARD_METHOD: ", method))
}

#' Headline completion-to-departure ratio via the declared primary hazard method.
get_primary_ratio <- function(subspecialty) get_hier_ratio(WORKFORCE_PRIMARY_HAZARD_METHOD, subspecialty)
#' 95% interval for the declared primary hazard method's ratio.
get_primary_ci    <- function(subspecialty) get_hier_ci(WORKFORCE_PRIMARY_HAZARD_METHOD, subspecialty)

# ABU-pathway (separate deterministic) hazard-scaling range, Appendix S11.5 /
# Appendix Table S16 (data/abu_pathway_sensitivity.csv). Distinct from the
# hierarchical ABU-scaling in Appendix Table S28; read live so the main-text
# range can never drift from the supplement table.
.abu_pathway <- tryCatch(
  readr::read_csv(here::here("data", "abu_pathway_sensitivity.csv"), show_col_types = FALSE),
  error = function(e) NULL)
#' "lo to hi" completion-to-departure range over the scaled ABU scenarios (x0.5, x2.0).
get_abu_pathway_range <- function() {
  if (is.null(.abu_pathway)) return(NA_character_)
  scaled <- .abu_pathway[grepl("hazard x", .abu_pathway$scenario, ignore.case = TRUE), ]
  if (nrow(scaled) < 2) return(NA_character_)
  sprintf("%.1f to %.1f", min(scaled$replacement_ratio), max(scaled$replacement_ratio))
}

# Fail-closed SSOT guard: the headline replacement_ratio (dynamic model, Table 2,
# get_replacement_ratio) MUST equal the primary hazard method's hierarchical row,
# so the reported headline and the word "primary" can never contradict.
local({
  for (ab in c("GO", "URPS")) {
    head_r <- suppressWarnings(as.numeric(get_replacement_ratio(ab)))
    prim_r <- suppressWarnings(as.numeric(get_primary_ratio(ab)))
    if (is.na(head_r) || is.na(prim_r) || abs(head_r - prim_r) > 0.05) {
      stop(sprintf(
        paste0("SSOT guard: headline ratio (%s) != primary '%s' hazard ratio (%s) for %s. ",
               "The manuscript's primary hazard label and its number have drifted. ",
               "Reconcile the workforce table with WORKFORCE_PRIMARY_HAZARD_METHOD."),
        head_r, WORKFORCE_PRIMARY_HAZARD_METHOD, prim_r, ab))
    }
  }
})

# Raw departure-event count in the primary 2016-2021 hazard window, read from the
# frozen band table so the manuscript count can never drift from the hazard data.
# subspecialty = NULL returns the pooled GO+URPS total.
.dep_band <- tryCatch(
  readr::read_csv(here::here("data", "hazard_by_band_pooled_vs_unpooled.csv"), show_col_types = FALSE),
  error = function(e) NULL)
#' Departure events over 2016-2021: get_departure_events("GO") = 36, ("URPS") = 35, NULL = 71.
get_departure_events <- function(subspecialty = NULL) {
  if (is.null(.dep_band)) return(NA_integer_)
  if (is.null(subspecialty)) return(as.integer(sum(.dep_band$pooled_events)))
  col <- paste0(tolower(trimws(subspecialty)), "_events")
  if (!col %in% names(.dep_band)) return(NA_integer_)
  as.integer(sum(.dep_band[[col]]))
}
#' Person-years over 2016-2021 (formatted with a thousands comma): ("GO"), ("URPS"), or NULL = pooled.
get_person_years <- function(subspecialty = NULL) {
  if (is.null(.dep_band)) return(NA_character_)
  py <- if (is.null(subspecialty)) sum(.dep_band$pooled_py) else {
    col <- paste0(tolower(trimws(subspecialty)), "_py"); if (!col %in% names(.dep_band)) return(NA_character_); sum(.dep_band[[col]])
  }
  format(as.integer(round(py)), big.mark = ",")
}

# #3 consistent-definition (anchored) 2025 baseline.
.consistent_base <- .op_load("consistent_definition_baseline_sensitivity.csv")
#' Anchored-definition 2025 active baseline count.
get_consistent_baseline <- function(subspecialty) format(as.integer(.op_get(.consistent_base, subspecialty, "baseline_consistent")), big.mark = ",")
#' Completion-to-departure ratio under the anchored-definition baseline.
get_consistent_ratio    <- function(subspecialty) sprintf("%.1f", .op_get(.consistent_base, subspecialty, "ratio_consistent"))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Validation
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Fail loud at source time if any registered sensitivity artifact (S25-S31) is
# missing or malformed, instead of letting a getter render a silent NA.
if (exists("validate_sensitivity_artifacts")) validate_sensitivity_artifacts(strict = TRUE)

# Verify all expected subspecialties present
expected_subspecs <- c("Urogynecology", "Gynecologic Oncology", "Minimally Invasive")

for (subspec in expected_subspecs) {
  tryCatch({
    result <- .filter_subspec(subspec)
    if (nrow(result) == 0) {
      warning(sprintf("Expected subspecialty pattern '%s' not found in data", subspec))
    }
  }, error = function(e) {
    warning(sprintf("Error validating subspecialty pattern '%s': %s", subspec, e$message))
  })
}

# Success message
if (interactive()) {
  cat("✓ Workforce statistics functions loaded successfully\n")
  cat(sprintf("  Data source: %s\n", basename(.workforce_data_path)))
  cat(sprintf("  Subspecialties: %d\n", nrow(.workforce_data)))
  cat(sprintf("  Total baseline: %s physicians\n", get_total_baseline()))
}
