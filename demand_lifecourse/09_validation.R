#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# demand_lifecourse/09_validation.R
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Level 9 (VALIDATION) of the reproductive life-course demand model
# (DEMAND_LIFECOURSE_MODEL_SPEC.md): compare the model's predicted pelvic-floor
# prevalence / incidence against EXTERNAL published targets.
#
# WHAT THIS IS (and is NOT)
#   A general comparison HARNESS plus a committed, cited TARGETS table
#   (params/validation_targets.csv). It back-casts a predicted series against
#   cross-sectional (Nygaard 2008) and longitudinal (SWAN / Waetjen 2007)
#   anchors. It does NOT ship the restricted SWAN microdata: the full
#   participant-level validation lives in the simulation package's legacy DPPM
#   SWAN framework (inst/legacy/), which requires the application-gated ICPSR
#   SWAN dataset. This harness validates against the PUBLISHED SWAN estimates,
#   which are open.
#
# TARGETS (cited; see params/validation_targets.csv)
#   - Nygaard 2008 (JAMA, NHANES 2005-06): any-PFD 23.7%, UI 15.7%, POP 2.9%,
#     FI 9.0% -- cross-sectional prevalence anchors.
#   - SWAN / Waetjen 2007 (Am J Epidemiol): midlife UI prevalence 46.7% (mean age
#     45.8), annual UI incidence 11.1% -- longitudinal targets.
#   - SWAN 2025 (Sci Rep): parity/mode DIRECTION check (no significant UI
#     difference vs nulliparous; vaginal vs cesarean -> higher stress UI).
#
# NOTE: all target values were verified against published abstracts/reports via
# search (publisher/PubMed PDFs were network-blocked); confirm one read through
# institutional access before locking a published number.
#
# Author: Tyler Muffly, MD / Claude Code
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
  library(tibble)
})

#' Load the cited external validation targets
#' @return Tibble from params/validation_targets.csv.
#' @export
load_validation_targets <- function() {
  readr::read_csv(
    here::here("demand_lifecourse/params/validation_targets.csv"),
    show_col_types = FALSE)
}

#' Compare model-predicted values against the cited targets
#'
#' @param predicted Tibble with `metric` (matching a target `metric`) and
#'   `predicted_value`.
#' @param targets Targets table (default: the cited set). Only numeric-valued
#'   targets are scored; DIRECTION-only rows (value NA) are returned unscored.
#' @param tol Relative tolerance for the `agrees` flag when a target has no CI.
#'   Default 0.20 (within +/-20%).
#' @return Tibble: metric, predicted_value, target_value, ci_low, ci_high,
#'   ratio, abs_pct_diff, agrees, source, citation, confidence.
#' @export
validate_against_targets <- function(predicted,
                                     targets = load_validation_targets(),
                                     tol = 0.20) {
  stopifnot(all(c("metric", "predicted_value") %in% names(predicted)))
  j <- dplyr::inner_join(predicted, targets, by = "metric")
  j <- dplyr::mutate(
    j,
    target_value = suppressWarnings(as.numeric(.data$value)),
    ratio        = ifelse(!is.na(.data$target_value) & .data$target_value != 0,
                          .data$predicted_value / .data$target_value, NA_real_),
    abs_pct_diff = ifelse(!is.na(.data$ratio), abs(.data$ratio - 1) * 100, NA_real_),
    agrees = dplyr::case_when(
      is.na(.data$target_value)                       ~ NA,               # direction-only
      !is.na(.data$ci_low) & !is.na(.data$ci_high)    ~ .data$predicted_value >= .data$ci_low &
                                                        .data$predicted_value <= .data$ci_high,
      TRUE                                            ~ .data$abs_pct_diff <= tol * 100
    )
  )
  dplyr::select(j, "metric", "predicted_value", "target_value", "ci_low", "ci_high",
                "ratio", "abs_pct_diff", "agrees", "source", "citation", "confidence")
}
