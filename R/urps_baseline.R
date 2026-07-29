# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# urps_baseline.R — cliff's SINGLE consumption seam for the national URPS baseline.
#
# CHARTER (2026-07-27): cliff CONSUMES the national URPS baseline; it does NOT
# redefine it. The one authoritative source is the mufflyaccess package, which
# serves counts validated from the immutable isochrones provider snapshot. cliff
# must never derive the national URPS count itself, read raw ABOG/ABU rosters to
# establish it, or hardcode the headline values (1031, 1339, 1295, 264, 308).
#
# Dependency direction (no reverse arrows):
#   ABOG/ABU sources -> isochrones (provider-level truth) -> hashed artifact
#     -> mufflyaccess (validated stable SSOT API) -> cliff (projections/scenarios)
#
# One-sentence rule: isochrones builds the roster, mufflyaccess certifies and
# serves the number, and cliff models what happens next.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' National URPS baseline count, obtained from the mufflyaccess SSOT
#'
#' The single accessor cliff uses for the national active URPS workforce count.
#' Delegates to [mufflyaccess::urps_count()], which serves the value validated
#' from the immutable isochrones provider snapshot. cliff transforms this baseline
#' into projections and scenarios but must never redefine it.
#'
#' @details Three distinct time attributes must never be collapsed into one
#'   ambiguous year: the MEASURE YEAR (the active-workforce year, default 2023),
#'   the source SNAPSHOT DATE (when isochrones froze the provider roster), and the
#'   MODEL BASELINE YEAR (the projection start, 2025). This accessor takes only the
#'   measure year; the snapshot date and provenance travel with the returned value
#'   via mufflyaccess.
#' @param year Measure year (integer; default `2023L`).
#' @param include_urology If `FALSE` (default), the ABOG-only URPS count (headline
#'   1,031 for 2023); if `TRUE`, the combined ABOG + ABU-net-new count (headline
#'   1,339 for 2023).
#' @return An integer count. Full provenance is available via
#'   [mufflyaccess::urps_provenance()].
#' @seealso [mufflyaccess::urps_count()], [mufflyaccess::urps_provenance()],
#'   [mufflyaccess::validate_urps_ssot()].
#' @examples
#' \dontrun{
#' urps_baseline(2023L, include_urology = FALSE)  # 1031 (ABOG-only)
#' urps_baseline(2023L, include_urology = TRUE)   # 1339 (ABOG + ABU)
#' }
urps_baseline <- function(year = 2023L, include_urology = FALSE) {
  have_api <- requireNamespace("mufflyaccess", quietly = TRUE) &&
    "urps_count" %in% getNamespaceExports("mufflyaccess")
  if (!have_api) {
    stop(
      "cliff requires a mufflyaccess release that provides urps_count(), but the ",
      "installed mufflyaccess does not export it. The isochrones -> mufflyaccess ",
      "SSOT chain must ship first (isochrones produces the hashed provider ",
      "artifact; mufflyaccess validates and serves urps_count()). Per the cliff ",
      "charter, cliff must NOT derive the national URPS baseline itself as a ",
      "fallback. See docs/CHARTER_cliff.md.",
      call. = FALSE
    )
  }
  mufflyaccess::urps_count(year = year, include_urology = include_urology)
}

#' Load the cliff workforce baseline from the mufflyaccess SSOT
#'
#' The interface cliff's models call to obtain the baseline. Delegates to
#' [urps_baseline()] (hence to `mufflyaccess::urps_count()`) and attaches the
#' provenance that keeps the three time attributes distinct.
#'
#' @param year Measure year (default `2023L`).
#' @param include_urology Whether to include the ABU net-new cohort.
#' @return A list with `n_providers` (the SSOT count), `source_package`
#'   (`"mufflyaccess"`), `measure_year`, and `model_start_year` — the projection
#'   baseline year, which is DELIBERATELY separate from the measure year.
#' @seealso [urps_baseline()], [project_urps_workforce()].
load_workforce_baseline <- function(year = 2023L, include_urology = FALSE) {
  n <- urps_baseline(year = year, include_urology = include_urology)
  list(
    n_providers      = n,
    source_package   = "mufflyaccess",
    measure_year     = as.integer(year),
    model_start_year = 2025L   # projection start; NEVER conflated with the measure year
  )
}

#' Project the URPS workforce forward from the SSOT baseline
#'
#' A minimal net-flow projection seeded from the mufflyaccess baseline: the value
#' at `baseline_year` equals the SSOT count, and each subsequent year adds the net
#' of `entrants` minus `retirements`. cliff transforms the baseline into a
#' trajectory; it never redefines the baseline.
#'
#' @param baseline_year Measure year of the baseline (default `2023L`).
#' @param include_urology Whether to include the ABU net-new cohort.
#' @param projection_years Integer vector of years to project; defaults to
#'   `baseline_year` through `baseline_year + 12`.
#' @param entrants,retirements Annual counts entering/leaving the workforce.
#' @return A data frame with `year` and `n_providers`, where the `baseline_year`
#'   row equals `urps_baseline(baseline_year, include_urology)`.
#' @seealso [load_workforce_baseline()], [urps_baseline()].
project_urps_workforce <- function(baseline_year = 2023L,
                                   include_urology = FALSE,
                                   projection_years = NULL,
                                   entrants = 0,
                                   retirements = 0) {
  base <- urps_baseline(year = baseline_year, include_urology = include_urology)
  if (is.null(projection_years)) {
    projection_years <- baseline_year:(baseline_year + 12L)
  }
  years <- as.integer(projection_years)
  net   <- entrants - retirements
  data.frame(
    year        = years,
    n_providers = as.numeric(base) + net * (years - as.integer(baseline_year))
  )
}
