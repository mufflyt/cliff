#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# demand_lifecourse/01_population.R
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Level 1 of the reproductive life-course demand model (see
# DEMAND_LIFECOURSE_MODEL_SPEC.md): the female population base by single year of
# age and projection year. Every downstream cell (age x birth-cohort x
# vaginal-parity stratum) is seeded from this layer, so it is deliberately thin
# and depends only on the committed Census NPP file plus the existing
# demand-denominator SSOT (no external data, no research coefficients).
#
# birth_cohort is defined here as (year - age) so that 02_birth_history can join
# a cohort's completed vaginal-parity distribution onto the population.
#
# Source of truth reused:
#   R/demand_denominator.R  -> npp_total_female() (SEX==2, ORIGIN==0, RACE==0)
#   data/census/np2023_d1_<series>.csv  (single-year columns POP_0 .. POP_100)
#
# Author: Tyler Muffly, MD / Claude Code
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(here)
  library(data.table)
  library(dplyr)
  library(tidyr)
  library(tibble)
})

source(here::here("R", "demand_denominator.R"), local = TRUE)  # npp_total_female(), NPP_MAX_AGE

# PFD_MODEL_AGE_MIN
#   Meaning : youngest age carried in the demand model. Pelvic-floor disorders
#             are essentially absent below 20 (Nygaard 2008 prevalence = 0 for
#             age < 20), so the model starts at 20 to keep cells meaningful.
#   Units   : years.
PFD_MODEL_AGE_MIN <- 20L

#' Female population by single year of age and year, from a Census NPP series
#'
#' @param series One of "mid", "low", "hi" (Census 2023 NPP main / low / high
#'   immigration series). Default "mid".
#' @param age_min Youngest age to retain. Default \code{PFD_MODEL_AGE_MIN} (20).
#' @return A tibble with columns \code{year}, \code{age} (age_min..NPP_MAX_AGE),
#'   \code{birth_cohort} (= year - age), and \code{n_women} (female population),
#'   one row per age-year.
lifecourse_population <- function(series = c("mid", "low", "hi"),
                                  age_min = PFD_MODEL_AGE_MIN) {
  series <- match.arg(series)
  path <- here::here("data", "census", sprintf("np2023_d1_%s.csv", series))
  stopifnot(file.exists(path))

  dt <- data.table::fread(path)
  fem <- npp_total_female(dt)   # SSOT filter: female, all origins, all races

  age_cols <- sprintf("POP_%d", age_min:NPP_MAX_AGE)
  stopifnot(all(c("YEAR", age_cols) %in% names(fem)))

  long <- fem |>
    as.data.frame() |>
    dplyr::select(year = YEAR, dplyr::all_of(age_cols)) |>
    tidyr::pivot_longer(cols = dplyr::all_of(age_cols),
                        names_to = "age", values_to = "n_women") |>
    dplyr::mutate(
      age          = as.integer(sub("^POP_", "", age)),
      n_women      = as.numeric(n_women),
      birth_cohort = year - age
    ) |>
    dplyr::arrange(year, age) |>
    tibble::as_tibble()

  stopifnot(all(long$n_women >= 0), all(long$age >= age_min))
  long
}
