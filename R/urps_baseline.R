# urps_baseline.R   [APPLY IN: cliff, replacing any independent baseline derivation]
#
# The ONLY way cliff obtains the national URPS baseline. cliff depends on a
# PINNED release of mufflyaccess and uses these values purely as INPUTS to
# projections / scenarios. Never derive or hardcode the baseline here.
# (Per ARCHITECTURE.md: isochrones builds the roster, mufflyaccess serves the
#  number, cliff models what happens next.)
#
# CONTRACT: the baseline is a (measure, year, geography, pathway) cell.
# The canonical 2023 active count is 1306 (national) / 1303 (conus) WITH urology,
# as served by mufflyaccess v3.0.0+ (package version >= 0.7.1; 0.10.0 installed).
# 1332 / 1329 are the RETIRED v2.1.0 primary-cert cells and must never be used.
# 1339 is the 2025 roster_snapshot -- NOT the 2023 active baseline. Do not use it
# as the projection starting value.
#
# These numbers are documentation only. urps_baseline() below asks mufflyaccess
# for the value and never hardcodes it, so the function stayed correct while this
# comment went stale after the v2.1.0 -> v3.0.0 migration.

#' National URPS baseline for cliff (sourced from mufflyaccess).
#' @param include_urology FALSE = ABOG-only; TRUE = ABOG + ABU net-new.
#' @param geography "national" (default) or "conus".
#' @param year measure year (default 2023).
#' @param measure "board_certified_active" (default; the active-workforce baseline)
#'   or "roster_snapshot".
#' @return integer active count (e.g. 2023/national/with-urology = 1306).
urps_baseline <- function(include_urology = FALSE, geography = "national",
                          year = 2023L, measure = "board_certified_active") {
  if (!requireNamespace("mufflyaccess", quietly = TRUE))
    stop('Package "mufflyaccess" is required. renv::install("mufflyt/mufflyaccess").',
         call. = FALSE)
  as.integer(mufflyaccess::urps_count(
    year = year, measure = measure, geography = geography,
    include_urology = include_urology, incomplete = "error"))
}

#' Load a qualified cliff workforce baseline from the mufflyaccess SSOT
#'
#' The interface cliff's models call to obtain a baseline count; delegates to
#' [urps_baseline()] and attaches provenance that keeps the measure year and the
#' model start year distinct.
#'
#' @inheritParams urps_baseline
#' @return A list with `n_providers`, `source_package` (`"mufflyaccess"`),
#'   `measure`, `geography`, `measure_year`, and `model_start_year` (the
#'   projection start, DELIBERATELY separate from the measure year).
#' @seealso [urps_baseline()], [project_urps_workforce()].
load_workforce_baseline <- function(include_urology = FALSE, geography = "national",
                                    year = 2023L, measure = "board_certified_active") {
  n <- urps_baseline(include_urology = include_urology, geography = geography,
                     year = year, measure = measure)
  list(
    n_providers      = n,
    source_package   = "mufflyaccess",
    measure          = measure,
    geography        = geography,
    measure_year     = as.integer(year),
    model_start_year = 2025L   # projection start; NEVER conflated with the measure year
  )
}

#' Project the URPS workforce forward from a qualified SSOT baseline
#'
#' Minimal net-flow projection seeded from the mufflyaccess baseline: the value at
#' `baseline_year` equals the SSOT count for the requested cell, and each
#' subsequent year adds the net of `entrants` minus `retirements`.
#'
#' @inheritParams urps_baseline
#' @param baseline_year Measure year of the baseline cell (default 2023).
#' @param projection_years Integer vector of years; defaults to `baseline_year`
#'   through `baseline_year + 12`.
#' @param entrants,retirements Annual counts entering/leaving the workforce.
#' @return A data frame with `year` and `n_providers`.
#' @seealso [load_workforce_baseline()], [urps_baseline()].
project_urps_workforce <- function(baseline_year = 2023L, include_urology = FALSE,
                                   geography = "national",
                                   measure = "board_certified_active",
                                   projection_years = NULL,
                                   entrants = 0, retirements = 0) {
  base <- urps_baseline(include_urology = include_urology, geography = geography,
                        year = baseline_year, measure = measure)
  if (is.null(projection_years)) projection_years <- baseline_year:(baseline_year + 12L)
  years <- as.integer(projection_years)
  net   <- entrants - retirements
  data.frame(year = years,
             n_providers = as.numeric(base) + net * (years - as.integer(baseline_year)))
}

# Drop-in for the old get_baseline("URPS"): route it through mufflyaccess so the
# workforce_projections_consolidated.csv baseline is no longer a separate SSOT.
# Example replacement inside manuscript/R/workforce_statistics.R:
#   get_baseline <- function(sub) {
#     if (identical(sub, "URPS"))
#       return(urps_baseline(include_urology = TRUE, geography = "national"))  # 1306 (2023 active)
#     ... existing logic for other subspecialties ...
#   }
