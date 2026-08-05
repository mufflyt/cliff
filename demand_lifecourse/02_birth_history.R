#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# demand_lifecourse/02_birth_history.R
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Level 2 (PRIMARY EXPOSURE) of the reproductive life-course demand model
# (DEMAND_LIFECOURSE_MODEL_SPEC.md): the cumulative VAGINAL-delivery exposure a
# birth cohort carries into later life. This is the model's central longitudinal
# exposure -- the thing the static age-only prevalence denominator omits.
#
# WHAT IT PRODUCES
#   Per birth cohort: mean total parity, the cohort's mean cesarean fraction, and
#   the derived mean number of VAGINAL and CESAREAN deliveries per woman. These
#   attach to the population cells from 01_population.R via birth_cohort.
#
# DERIVATION (and its documented limits)
#   Off-the-shelf US data do NOT publish a per-woman joint distribution of
#   vaginal vs cesarean deliveries by birth cohort (confirmed gap; would need a
#   custom NSFG microdata tabulation). We therefore DERIVE mean vaginal exposure
#   from two cited population series:
#
#     mean_vaginal_deliveries(cohort)
#         = mean_total_parity(cohort) * (1 - cohort_cesarean_fraction(cohort))
#
#   where cohort_cesarean_fraction is the average US total-cesarean rate over the
#   cohort's peak childbearing window (ages CHILDBEAR_AGE_LO..HI, i.e. calendar
#   years cohort+LO .. cohort+HI).
#
#   ASSUMPTIONS (flag before publication; refine with NSFG microdata):
#     (a) the period cesarean rate applies uniformly per birth (ignores
#         repeat-cesarean correlation -> once a cesarean, likely again);
#     (b) births are spread evenly across the childbearing window;
#     (c) completed parity is interpolated linearly between cited cohort anchors
#         and clamped outside their range.
#   These bias the split between vaginal and cesarean counts, NOT the total
#   parity, and are transparent levers for the "changing mode of delivery"
#   scenario. The parity-STRATUM shares (0/1/2/3+) are carried through from the
#   cited data where available and are the natural refinement target once an
#   NSFG vaginal/cesarean cross-tab is obtained.
#
# INPUTS (committed, cited):
#   data/us_cesarean_rate_by_year_2026-08-02.csv
#   data/us_completed_parity_by_cohort_2026-08-02.csv
#
# Author: Tyler Muffly, MD / Claude Code
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
  library(tibble)
})

# Peak childbearing window used to average the cohort's cesarean exposure.
CHILDBEAR_AGE_LO <- 20L
CHILDBEAR_AGE_HI <- 35L

#' Annual US total-cesarean rate, interpolated across cited anchor years
#'
#' @param years Integer vector of calendar years.
#' @param ces A data frame with numeric `year`, `cesarean_rate`. Defaults to the
#'   committed cited series.
#' @return Numeric cesarean fraction per requested year (clamped to the anchor
#'   range at the ends).
cesarean_rate_for_year <- function(years, ces = NULL) {
  if (is.null(ces)) {
    ces <- readr::read_csv(
      here::here("demand_lifecourse/data/us_cesarean_rate_by_year_2026-08-02.csv"),
      show_col_types = FALSE)
  }
  ces <- ces[order(ces$year), ]
  stats::approx(x = ces$year, y = ces$cesarean_rate, xout = years,
                rule = 2)$y                      # rule = 2 -> clamp at both ends
}

#' Mean completed parity by birth cohort, interpolated across cited anchors
#'
#' @param cohorts Integer vector of birth-cohort years.
#' @param par A data frame with `birth_cohort`, `mean_completed_parity`.
#'   Defaults to the committed cited series.
#' @return Numeric mean completed parity per cohort (clamped outside anchors).
completed_parity_for_cohort <- function(cohorts, par = NULL) {
  if (is.null(par)) {
    par <- readr::read_csv(
      here::here("demand_lifecourse/data/us_completed_parity_by_cohort_2026-08-02.csv"),
      show_col_types = FALSE)
  }
  par <- par[order(par$birth_cohort), ]
  stats::approx(x = par$birth_cohort, y = par$mean_completed_parity,
                xout = cohorts, rule = 2)$y
}

#' Cohort vaginal-delivery exposure table
#'
#' Derives mean vaginal and cesarean deliveries per woman for each birth cohort.
#'
#' @param cohorts Integer vector of birth cohorts to evaluate (e.g. 1930:1990).
#' @return A tibble: birth_cohort, mean_total_parity, cohort_cesarean_fraction,
#'   mean_vaginal_deliveries, mean_cesarean_deliveries.
cohort_vaginal_exposure <- function(cohorts) {
  cohorts <- as.integer(cohorts)
  ces <- readr::read_csv(
    here::here("demand_lifecourse/data/us_cesarean_rate_by_year_2026-08-02.csv"),
    show_col_types = FALSE)

  # mean cesarean fraction over each cohort's childbearing window
  ces_frac <- vapply(cohorts, function(c0) {
    yrs <- (c0 + CHILDBEAR_AGE_LO):(c0 + CHILDBEAR_AGE_HI)
    mean(cesarean_rate_for_year(yrs, ces = ces))
  }, numeric(1))

  parity <- completed_parity_for_cohort(cohorts)

  # Round total and vaginal, then derive cesarean as (total - vaginal) so the
  # additive identity vaginal + cesarean == total holds EXACTLY (rounding each of
  # the three independently broke it by up to 0.001 -- caught by a semantic test).
  mtp <- round(parity, 3)
  mvd <- round(parity * (1 - ces_frac), 3)
  tibble::tibble(
    birth_cohort            = cohorts,
    mean_total_parity       = mtp,
    cohort_cesarean_fraction = round(ces_frac, 4),
    mean_vaginal_deliveries = mvd,
    mean_cesarean_deliveries = mtp - mvd
  )
}

#' Attach cohort vaginal exposure onto population cells from 01_population.R
#'
#' @param population A tibble from `lifecourse_population()` (has birth_cohort).
#' @return `population` with mean_total_parity, cohort_cesarean_fraction,
#'   mean_vaginal_deliveries, mean_cesarean_deliveries joined by birth_cohort.
attach_birth_history <- function(population) {
  stopifnot("birth_cohort" %in% names(population))
  exposure <- cohort_vaginal_exposure(sort(unique(population$birth_cohort)))
  dplyr::left_join(population, exposure, by = "birth_cohort")
}

# ---- Within-woman cesarean correlation (per-woman stratum refinement) --------
# The cohort-MEAN vaginal exposure above is unbiased regardless of how cesareans
# are distributed within a woman (expectation is linear). But the DISTRIBUTION of
# vaginal-parity strata (0/1/2/3+ vaginal births) depends on the strong
# within-woman correlation of cesarean delivery that an independent-per-birth
# draw omits: among US women with a prior cesarean, ~85-87% of the next births
# are repeat cesareans (NCHS Data Brief No. 359; VSRR No. 21), versus a ~22%
# primary (first-birth) rate -- a ~4x within-woman elevation. This helper draws a
# per-woman cesarean count with a first-order sequence model, for a per-woman
# microsimulation (the cohort-cell model uses the mean and does not need it).
#
# The exact per-woman joint distribution of vaginal vs cesarean births is NOT
# published and requires a custom NSFG Female Pregnancy File tabulation
# (see PARAMETERS_EVIDENCE.md). This is a documented approximation, not that.

#' Draw per-woman cesarean-birth counts with within-woman correlation
#'
#' First birth is cesarean with probability `primary_rate`; each subsequent birth
#' is cesarean with `repeat_rate` if the woman has already had a cesarean, else
#' `primary_rate`. Reduces to an independent binomial only when
#' `repeat_rate == primary_rate`.
#'
#' @param parity Integer vector of total births per woman.
#' @param primary_rate First-birth (primary) cesarean probability. Default 0.22.
#' @param repeat_rate Cesarean probability given a prior cesarean. Default 0.86.
#' @return Integer vector of cesarean births per woman (0..parity).
cesarean_births_correlated <- function(parity, primary_rate = 0.22, repeat_rate = 0.86) {
  parity <- as.integer(parity)
  stopifnot(all(parity >= 0, na.rm = TRUE),
            primary_rate >= 0, primary_rate <= 1, repeat_rate >= 0, repeat_rate <= 1)
  vapply(parity, function(k) {
    if (is.na(k) || k <= 0) return(0L)
    had_cs <- FALSE; n_cs <- 0L
    for (b in seq_len(k)) {
      p <- if (had_cs) repeat_rate else primary_rate
      if (stats::runif(1) < p) { n_cs <- n_cs + 1L; had_cs <- TRUE }
    }
    n_cs
  }, integer(1))
}
