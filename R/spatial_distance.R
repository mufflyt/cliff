# PORTED FROM THE ISOCHRONES MONOREPO (2026-08-14), commit ef8a0cdb6.
# R/infer_fellowship_training.R came across in the extraction; this file, which
# provides the five functions it calls, did not. Two EXPORTED functions were
# therefore calling undefined functions and would error on any call:
#   add_fellowship_to_table1  -> classify_us_region
#   infer_fellowship_training -> load_training_crosswalk, inference_output_columns,
#                                infer_from_abog_neighbors, validate_inference_qa
# R CMD check reported this as "no visible global function definition", inside a
# NOTE rather than a WARNING, which is why it survived this long.
#
# Changes on porting:
#   * file-scope library() calls removed; the package declares its imports in
#     NAMESPACE, and adding new attaches here would work against that
#   * source("R/utils/spatial_distance.R") dropped: R sources all of R/ , and
#     that file is now R/spatial_distance.R (R does not source R/ subdirectories)

#' @title Spatial Distance Utilities
#'
#' @description
#' Canonical implementations of spatial distance calculations. Consolidates
#' scattered \code{haversine_distance()} implementations and adds safety guards.
#'
#' @family geospatial-utils
#' @name spatial_distance_module
NULL

# ==============================================================================
# Spatial Distance Utilities
# ==============================================================================
# Purpose: Canonical implementations of spatial distance calculations
# Created: 2026-02-14
# Consolidates: haversine_distance() from 10+ files
# Hardened: 2026-03-05 (NaN/Inf/range validation, OOM guards)
# ==============================================================================

# ── Internal validators ──────────────────────────────────────────────────────

#' Validate a single latitude/longitude pair
#'
#' @param lat [numeric(1)]: Latitude in decimal degrees.
#' @param lon [numeric(1)]: Longitude in decimal degrees.
#' @keywords internal
.validate_lat_lon_scalar <- function(lat, lon) {
  if (!is.numeric(lat) || length(lat) != 1L) {
    stop("Latitude must be a numeric scalar.")
  }
  if (!is.numeric(lon) || length(lon) != 1L) {
    stop("Longitude must be a numeric scalar.")
  }
  if (is.na(lat) || is.na(lon)) {
    stop("Coordinates must not be NA.")
  }
  if (is.nan(lat) || is.nan(lon)) {
    stop("Coordinates must not be NaN.")
  }
  if (!is.finite(lat) || !is.finite(lon)) {
    stop("Coordinates must be finite (not Inf/-Inf).")
  }
  if (lat < -90 || lat > 90) {
    stop("Latitude must be between -90 and 90.")
  }
  if (lon < -180 || lon > 180) {
    stop("Longitude must be between -180 and 180.")
  }
  invisible(TRUE)
}

#' Validate vector lat/lon
#'
#' @param lat [numeric]: Latitudes in decimal degrees.
#' @param lon [numeric]: Longitudes in decimal degrees.
#' @keywords internal
.validate_lat_lon_vector <- function(lat, lon) {
  if (!is.numeric(lat) || !is.numeric(lon)) {
    stop("lat and lon must be numeric vectors.")
  }
  if (length(lat) != length(lon)) {
    stop("lat and lon must have the same length.")
  }
  if (any(is.na(lat)) || any(is.na(lon))) {
    stop("Coordinates must not contain NA.")
  }
  if (any(is.nan(lat)) || any(is.nan(lon))) {
    stop("Coordinates must not contain NaN.")
  }
  if (!all(is.finite(lat)) || !all(is.finite(lon))) {
    stop("Coordinates must be finite (not Inf/-Inf).")
  }
  if (any(lat < -90 | lat > 90)) {
    stop("Latitude must be between -90 and 90.")
  }
  if (any(lon < -180 | lon > 180)) {
    stop("Longitude must be between -180 and 180.")
  }
  invisible(TRUE)
}

#' Guard against OOM from distm() on large point sets
#'
#' @inheritParams shared_params_coordinates
#' @param n_points Integer number of points.
#' @param block_label Character label for error messages.
#' @keywords internal
.guard_distm_size <- function(n_points, block_label = "global") {
  if (!is.numeric(n_points) || length(n_points) != 1L) {
    stop("n_points must be a numeric scalar.")
  }
  est_gb <- (n_points^2 * 8) / (1024^3)

  if (n_points > 15000) {
    warning(
      "Block '", block_label, "' has ", n_points,
      " points; distance matrix will use ~",
      format(round(est_gb, 1), trim = TRUE), " GB RAM."
    )
  }

  if (n_points > 50000) {
    stop(
      "Block '", block_label, "' has ", n_points,
      " points; distm() would allocate ~",
      format(round(est_gb, 1), trim = TRUE),
      " GB RAM. Reduce input size or enable blocking."
    )
  }

  invisible(TRUE)
}

# ── Public functions ─────────────────────────────────────────────────────────

#' Calculate Haversine Distance Between Two Points
#'
#' Computes the great-circle distance between two geographic coordinates
#' using the Haversine formula via the geosphere package.
#'
#' @param lat1 `numeric`: - latitude of first point (degrees)
#' @param lon1 `numeric`: - longitude of first point (degrees)
#' @param lat2 `numeric`: - latitude of second point (degrees)
#' @param lon2 `numeric`: - longitude of second point (degrees)
#'
#' @return Numeric - distance in kilometers
#'
#' @details
#' Uses geosphere::distHaversine for consistency. The function expects
#' single coordinate values (not vectors). For vectorized operations,
#' see haversine_distance_vectorized().
#'
#' @family spatial-distance
#' @keywords spatial distance haversine
#' @seealso \code{\link{haversine_distance_m}} for meters,
#'   \code{\link{haversine_distance_vectorized}} for vectors
#' @export
#'
#' @examples
#' # Distance from Denver to Boulder (approx 40 km)
#' haversine_distance(39.7392, -104.9903, 40.0150, -105.2705)
#'
#' # Distance from NYC to LA (approx 3936 km)
#' haversine_distance(40.7128, -74.0060, 34.0522, -118.2437)
haversine_distance <- function(lat1, lon1, lat2, lon2) {
  .validate_lat_lon_scalar(lat1, lon1)
  .validate_lat_lon_scalar(lat2, lon2)

  # Calculate distance (geosphere expects lon, lat order)
  if (!requireNamespace("geosphere", quietly = TRUE))
    stop("Package 'geosphere' is required for haversine distances. ",
         "install.packages(\"geosphere\")", call. = FALSE)
  distance_m <- geosphere::distHaversine(
    c(lon1, lat1),
    c(lon2, lat2)
  )

  # Convert meters to kilometers
  return(distance_m / 1000)
}

#' Calculate Haversine Distance in Meters
#'
#' Same as haversine_distance() but returns meters instead of kilometers.
#' Useful for clustering algorithms that expect meter-scale distances.
#'
#' @param lat1 `numeric`: - latitude of first point (degrees)
#' @param lon1 `numeric`: - longitude of first point (degrees)
#' @param lat2 `numeric`: - latitude of second point (degrees)
#' @param lon2 `numeric`: - longitude of second point (degrees)
#'
#' @return Numeric - distance in meters
#'
#' @family spatial-distance
#' @keywords spatial distance haversine
#' @seealso \code{\link{haversine_distance}} for kilometers,
#'   \code{\link{haversine_distance_vectorized}} for vectors
#' @export
#'
#' @examples
#' # Distance in meters (for clustering thresholds)
#' haversine_distance_m(39.7392, -104.9903, 40.0150, -105.2705)
haversine_distance_m <- function(lat1, lon1, lat2, lon2) {
  .validate_lat_lon_scalar(lat1, lon1)
  .validate_lat_lon_scalar(lat2, lon2)

  # Calculate distance (geosphere expects lon, lat order)
  if (!requireNamespace("geosphere", quietly = TRUE))
    stop("Package 'geosphere' is required for haversine distances. ",
         "install.packages(\"geosphere\")", call. = FALSE)
  distance_m <- geosphere::distHaversine(
    c(lon1, lat1),
    c(lon2, lat2)
  )

  return(distance_m)
}

#' Calculate Haversine Distance (Alternative Name)
#'
#' Alias for haversine_distance_m() to match naming conventions
#' in some geocoding scripts.
#'
#' @param lat1 `numeric`: - latitude of first point
#' @param lng1 `numeric`: - longitude of first point (note: lng vs lon)
#' @param lat2 `numeric`: - latitude of second point
#' @param lng2 `numeric`: - longitude of second point
#'
#' @return Numeric - distance in meters
#'
#' @keywords spatial distance haversine
#' @seealso \code{\link{haversine_distance_m}}
#' @export
#' @family spatial-distance
calculate_haversine_distance <- function(lat1, lng1, lat2, lng2) {
  haversine_distance_m(lat1, lng1, lat2, lng2)
}

#' Vectorized Haversine Distance Calculation
#'
#' Calculates distances between pairs of coordinates (vectorized).
#' Uses geosphere::distHaversine which handles vectors efficiently.
#'
#' @param lat1 `numeric vector`: - latitudes of first points
#' @param lon1 `numeric vector`: - longitudes of first points
#' @param lat2 `numeric vector`: - latitudes of second points
#' @param lon2 `numeric vector`: - longitudes of second points
#' @param units `character`: - "km" (default) or "m" for kilometers or meters
#'
#' @return Numeric vector - distances in specified units
#'
#' @family spatial-distance
#' @keywords spatial distance haversine
#' @seealso \code{\link{haversine_distance}} for single-point
#'   calculations
#' @export
#'
#' @examples
#' # Calculate multiple distances at once
#' lats1 <- c(39.7392, 40.7128)
#' lons1 <- c(-104.9903, -74.0060)
#' lats2 <- c(40.0150, 34.0522)
#' lons2 <- c(-105.2705, -118.2437)
#' haversine_distance_vectorized(lats1, lons1, lats2, lons2)
haversine_distance_vectorized <- function(lat1, lon1, lat2, lon2, units = "km") {
  .validate_lat_lon_vector(lat1, lon1)
  .validate_lat_lon_vector(lat2, lon2)

  if (length(lat1) != length(lat2)) {
    stop("All coordinate vectors must have the same length")
  }

  # Calculate distances using geosphere
  if (!requireNamespace("geosphere", quietly = TRUE))
    stop("Package 'geosphere' is required for haversine distances. ",
         "install.packages(\"geosphere\")", call. = FALSE)
  distances_m <- geosphere::distHaversine(
    cbind(lon1, lat1),
    cbind(lon2, lat2)
  )

  # Convert units if needed
  if (units == "km") {
    return(distances_m / 1000)
  } else if (units == "m") {
    return(distances_m)
  } else {
    stop("units must be 'km' or 'm'")
  }
}

#' Vectorized Pure-R Haversine Distance in Kilometers (mean-radius family)
#'
#' Canonical home for the pure-R, vectorized, mean-Earth-radius haversine that
#' was copy-pasted across the pipeline (`.vbo_hav_km`, `.vps_haversine_km`,
#' `haversine_km`, `.haversine_km`, ...). Uses the IUGG mean radius
#' R = 6371.0088 km and an inline great-circle formula with a `pmin(1, .)`
#' clamp for near-antipodal float safety. Fully vectorized over its inputs.
#'
#' \strong{NOT interchangeable with} \code{\link{haversine_distance}} /
#' \code{\link{haversine_distance_vectorized}}: those call
#' \code{geosphere::distHaversine}, which uses the WGS84 equatorial radius
#' (6378137 m) and so returns values ~0.11\% LARGER. Migrating a pure-R caller
#' to the geosphere family (or vice-versa) silently shifts distances that feed
#' the 5 km clustering threshold (CLAUDE.md #17) and the 100-mile secondary
#' filter. Pick deliberately; do not cross families in a "cleanup".
#'
#' @param lat1,lon1 `numeric`: latitude/longitude of point 1 (degrees).
#' @param lat2,lon2 `numeric`: latitude/longitude of point 2 (degrees).
#' @return Numeric vector of great-circle distances in kilometers.
#' @family geospatial-utils
#' @seealso \code{\link{haversine_distance}} (geosphere/WGS84 scalar, km)
#' @export
haversine_km_vec <- function(lat1, lon1, lat2, lon2) {
  R <- 6371.0088
  d_lat <- (lat2 - lat1) * pi / 180
  d_lon <- (lon2 - lon1) * pi / 180
  a <- sin(d_lat / 2)^2 + cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
       sin(d_lon / 2)^2
  2 * R * asin(pmin(1, sqrt(a)))
}
