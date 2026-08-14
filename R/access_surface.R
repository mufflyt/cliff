# =============================================================================
# Ingestion of the simulation repo's tract-level drive-time access surface
# =============================================================================
# The simulation repo's E2SFCA layer (run_geographic_access()$access), whose
# distance decay and wait response are fitted and geographically validated by the
# isochrone access-response pipeline, emits a per-tract drive-time access surface.
# cliff Module D consumes it as the drive-time refinement (v2) of its straight-
# line county access metric. These helpers are pure and base-R only (no
# tidyverse), so the aggregation is unit-testable in isolation. See
# SIMULATION_TO_CLIFF_INTEGRATION_PLAN.md Stage 4 and the simulation repo's
# R/geography-spatial_access_e2sfca.R + R/calibration-isochrone_access_response.R.

ACCESS_SURFACE_REQUIRED_COLS <- c("demand_id", "access", "population")

#' Normalise a Census GEOID that a CSV writer may have coerced to an integer
#'
#' Left-pads pure-digit strings shorter than `width` with zeros (so `1001`
#' becomes `01001`), leaving already-correct or non-numeric ids untouched. Pure.
#'
#' @param x character/numeric vector of GEOIDs.
#' @param width target width (11 for tracts, 5 for counties).
#' @return character vector.
.as_geoid <- function(x, width) {
  x <- trimws(as.character(x))
  # Pad by prepending zeros as STRINGS: an 11-digit tract GEOID exceeds the
  # 32-bit integer range, so as.integer() would overflow to NA on the very ids
  # this is meant to repair.
  needs <- grepl("^[0-9]+$", x) & nchar(x) < width
  x[needs] <- paste0(strrep("0", width - nchar(x[needs])), x[needs])
  x
}

#' Read the simulation drive-time access surface (tract level)
#'
#' Thin base-R I/O wrapper. Returns `NULL` when `path` is empty or missing, so
#' Module D cleanly falls back to the straight-line (v1) metric.
#'
#' @param path path to an `access_surface_v*.csv` (may be `""` / absent). Expected
#'   columns: `demand_id` (11-digit tract GEOID), `access`, `population`, and
#'   optionally `access_scaled`, `n_providers`, and provenance columns
#'   (`isochrone_run_id`, `sigma`, `wait_scale`, `calibration_status`).
#' @return `list(data = data.frame, provenance = named list)` or `NULL`.
read_access_surface <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) return(NULL)
  df <- utils::read.csv(path, stringsAsFactors = FALSE)
  miss <- setdiff(ACCESS_SURFACE_REQUIRED_COLS, names(df))
  if (length(miss))
    stop("read_access_surface(): missing column(s): ",
         paste(miss, collapse = ", "),
         ". Expected a simulation access surface (demand_id, access, population).",
         call. = FALSE)
  df$demand_id <- .as_geoid(df$demand_id, 11L)
  prov_cols <- intersect(
    c("isochrone_run_id", "sigma", "wait_scale", "calibration_status"),
    names(df))
  provenance <- if (length(prov_cols)) as.list(df[1L, prov_cols, drop = FALSE])
                else list()
  list(data = df, provenance = provenance)
}

#' Population-weighted county roll-up of the tract access surface
#'
#' Aggregates the tract-level drive-time access to counties by population-weighted
#' mean: county access `= sum(access_i * pop_i) / sum(pop_i)` over its tracts. The
#' county GEOID is the first five digits of the 11-digit tract GEOID. Higher
#' access is better (it is the E2SFCA accessibility, not a distance), so it is the
#' drive-time complement of Module D's straight-line `miles_to_nearest` (lower is
#' better).
#'
#' @param surface a [read_access_surface()] result, or its `$data` frame.
#' @param min_population drop tracts with population below this. Default `0`.
#' @return data.frame(`GEOID`, `drive_time_access`, `n_tracts`, `population`), one
#'   row per county, ordered by GEOID.
county_drive_time_access <- function(surface, min_population = 0) {
  df <- if (is.list(surface) && !is.data.frame(surface) && !is.null(surface$data))
    surface$data else surface
  if (!is.data.frame(df) || !all(ACCESS_SURFACE_REQUIRED_COLS %in% names(df)))
    stop("county_drive_time_access(): need an access-surface data frame with ",
         paste(ACCESS_SURFACE_REQUIRED_COLS, collapse = ", "), ".", call. = FALSE)

  demand_id <- .as_geoid(df$demand_id, 11L)
  access <- as.numeric(df$access)
  pop <- as.numeric(df$population)
  keep <- is.finite(access) & is.finite(pop) & pop >= min_population &
    nchar(demand_id) >= 5L
  if (!any(keep))
    stop("county_drive_time_access(): no tracts with finite access, ",
         "population >= ", min_population, ", and a >=5-char GEOID.", call. = FALSE)

  county <- substr(demand_id[keep], 1L, 5L)
  a <- access[keep]; p <- pop[keep]
  num <- tapply(a * p, county, sum)
  den <- tapply(p, county, sum)
  nt  <- tapply(rep(1L, sum(keep)), county, sum)
  geoids <- names(den)
  data.frame(
    GEOID = geoids,
    drive_time_access = ifelse(as.numeric(den[geoids]) > 0,
                               as.numeric(num[geoids]) / as.numeric(den[geoids]),
                               NA_real_),
    n_tracts = as.integer(nt[geoids]),
    population = as.numeric(den[geoids]),
    stringsAsFactors = FALSE, row.names = NULL
  )
}

#' Is an access surface usable (non-NULL with at least one tract)?
#' @param surface a [read_access_surface()] result (or `NULL`).
#' @return logical scalar.
access_surface_usable <- function(surface) {
  !is.null(surface) && is.data.frame(surface$data) && nrow(surface$data) > 0L
}
