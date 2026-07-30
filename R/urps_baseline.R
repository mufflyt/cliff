# urps_baseline.R   [APPLY IN: cliff, replacing any independent baseline derivation]
#
# The ONLY way cliff obtains the national URPS baseline. cliff depends on a
# PINNED release of mufflyaccess and uses these values purely as INPUTS to
# projections / scenarios. Never derive or hardcode the baseline here.
# (Per ARCHITECTURE.md: isochrones builds the roster, mufflyaccess serves the
#  number, cliff models what happens next.)
#
# CONTRACT v2.1.0: the baseline is a (measure, year, geography, pathway) cell.
# The canonical 2023 active count is 1332 (national) / 1329 (conus) WITH urology.
# 1339 is the 2025 roster_snapshot -- NOT the 2023 active baseline. Do not use it
# as the projection starting value.

#' National URPS baseline for cliff (sourced from mufflyaccess).
#' @param include_urology FALSE = ABOG-only; TRUE = ABOG + ABU net-new.
#' @param geography "national" (default) or "conus".
#' @param year measure year (default 2023).
#' @param measure "board_certified_active" (default; the active-workforce baseline)
#'   or "roster_snapshot".
#' @return integer active count (e.g. 2023/national/with-urology = 1332).
urps_baseline <- function(include_urology = FALSE, geography = "national",
                          year = 2023L, measure = "board_certified_active") {
  if (!requireNamespace("mufflyaccess", quietly = TRUE))
    stop('Package "mufflyaccess" is required. renv::install("mufflyt/mufflyaccess").',
         call. = FALSE)
  as.integer(mufflyaccess::urps_count(
    year = year, measure = measure, geography = geography,
    include_urology = include_urology, incomplete = "error"))
}

# Drop-in for the old get_baseline("URPS"): route it through mufflyaccess so the
# workforce_projections_consolidated.csv baseline is no longer a separate SSOT.
# Example replacement inside manuscript/R/workforce_statistics.R:
#   get_baseline <- function(sub) {
#     if (identical(sub, "URPS"))
#       return(urps_baseline(include_urology = TRUE, geography = "national"))  # 1332 (2023 active)
#     ... existing logic for other subspecialties ...
#   }
