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

  tibble::tibble(
    birth_cohort            = cohorts,
    mean_total_parity       = round(parity, 3),
    cohort_cesarean_fraction = round(ces_frac, 4),
    mean_vaginal_deliveries = round(parity * (1 - ces_frac), 3),
    mean_cesarean_deliveries = round(parity * ces_frac, 3)
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
