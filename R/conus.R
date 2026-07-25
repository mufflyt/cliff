# Canonical CONUS (contiguous United States) geographic scope — single source of truth.
#
# The Module-D geographic scripts restrict data to the contiguous 48 states + DC in two
# mechanisms, each of which was previously copy-pasted per script:
#   1) CONUS_EXCLUDE_FIPS + is_conus_fips()  — for administrative geographies (STATEFP / GEOID prefix)
#   2) CONUS_LON / CONUS_LAT + in_conus_bbox() — for raw lon/lat point coordinates
# Both are defined ONCE here and sourced by every consumer so they cannot drift.
#
# Pure constants + functions, no path/data dependencies — safe to source from any cwd.

# ── 1. Non-CONUS FIPS exclusion list ─────────────────────────────────────────
#   Meaning : 2-digit FIPS of the state/territory geographies NOT in the contiguous US —
#             02 Alaska, 15 Hawaii, 72 Puerto Rico, 60 American Samoa, 66 Guam,
#             69 Northern Mariana Islands, 78 US Virgin Islands.
#   Units   : character, zero-padded 2-digit FIPS.
#   Range   : exactly these 7 codes; must include the two non-contiguous states (02, 15).
#   Source  : US Census FIPS; study scope = contiguous US (project CONUS policy).
#   Consumers: scripts/urps_module_d_{differential_distance,differential_map,geographic_access,map}.R
CONUS_EXCLUDE_FIPS <- c("02", "15", "72", "60", "66", "69", "78")
stopifnot(
  is.character(CONUS_EXCLUDE_FIPS),
  length(CONUS_EXCLUDE_FIPS) == 7L,
  !anyNA(CONUS_EXCLUDE_FIPS),
  all(nchar(CONUS_EXCLUDE_FIPS) == 2L),
  all(grepl("^[0-9]{2}$", CONUS_EXCLUDE_FIPS)),
  all(c("02", "15") %in% CONUS_EXCLUDE_FIPS),   # AK + HI are the non-contiguous states
  anyDuplicated(CONUS_EXCLUDE_FIPS) == 0L
)

#' TRUE for a state FIPS (or the leading 2 chars of a GEOID) that IS in the contiguous US.
#' Vectorised; works for exact 2-digit STATEFP and for longer GEOIDs (county/tract).
is_conus_fips <- function(fips) {
  !(substr(as.character(fips), 1L, 2L) %in% CONUS_EXCLUDE_FIPS)
}

# ── 2. CONUS lon/lat bounding box ────────────────────────────────────────────
#   Meaning : coarse rectangle enclosing the contiguous US, for filtering RAW point
#             coordinates when only lon/lat is known (a fallback, NOT authoritative geography).
#   Units   : decimal degrees (WGS84). Open on all four sides (matches the prior `>`/`<` usage).
#   Range   : west < east, south < north, within a sane North-American window.
#   Source  : conventional CONUS extent shared across the Module-D scripts.
CONUS_LON <- c(-125, -66)   # (west, east)
CONUS_LAT <- c(  24,  50)   # (south, north)
stopifnot(
  length(CONUS_LON) == 2L, length(CONUS_LAT) == 2L,
  CONUS_LON[1] < CONUS_LON[2], CONUS_LAT[1] < CONUS_LAT[2],
  CONUS_LON[1] >= -130, CONUS_LON[2] <= -60,
  CONUS_LAT[1] >= 20,   CONUS_LAT[2] <= 55
)

#' TRUE for a point strictly inside the CONUS bounding box. Preserves 3-valued logic:
#' an NA lon/lat yields NA (never silently kept/dropped), so callers keep their own
#' is.na() handling exactly as before. De Morgan holds, so `!in_conus_bbox(...)` is the
#' exact prior "outside the box" test.
in_conus_bbox <- function(lon, lat) {
  lon > CONUS_LON[1] & lon < CONUS_LON[2] & lat > CONUS_LAT[1] & lat < CONUS_LAT[2]
}

# ── 3. Census geography vintage year ─────────────────────────────────────────
# CENSUS_VINTAGE_YEAR
#   Meaning : the Census vintage year used for BOTH the ACS 5-year data pull
#             (tidycensus::get_acs(year=)) AND the TIGER/Line boundary pull (tigris::counties/states(year=)).
#             The two MUST be the same year: the geographic-access step merges ACS county estimates onto the
#             tigris county polygons BY GEOID, so a boundary-vs-data vintage mismatch silently breaks the join
#             (e.g. the 2022+ Connecticut planning-region GEOIDs vs 2020 county GEOIDs). Boundary vintage is
#             keyed off the ACS year here, never a separate literal.
#   Units   : calendar year (integer).
#   Range   : a 4-digit ACS/TIGER release year.
#   Source  : study design (the 2019-2023 ACS 5-year vintage; 2020-based boundaries).
#   Consumers: scripts/urps_module_d_{differential_distance,differential_map,geographic_access,map}.R
CENSUS_VINTAGE_YEAR <- 2023L
stopifnot(
  is.integer(CENSUS_VINTAGE_YEAR), length(CENSUS_VINTAGE_YEAR) == 1L, !is.na(CENSUS_VINTAGE_YEAR),
  CENSUS_VINTAGE_YEAR >= 2009L, CENSUS_VINTAGE_YEAR <= 2100L,
  CENSUS_VINTAGE_YEAR == 2023L   # pin the published vintage; a change moves ACS + boundaries together, deliberately
)

# CENSUS_CB_RESOLUTION
#   Meaning : the tigris cartographic-boundary generalization used for EVERY module-D county/state pull
#             (tigris::counties/states(cb=TRUE, resolution=)). It MUST be the same across the scripts: the
#             differential-distance and geographic-access steps both compute county-CENTROID-to-provider
#             distances, and a different boundary generalization shifts the centroids -> different distances
#             for the same county. Kept alongside CENSUS_VINTAGE_YEAR so the geometry inputs match.
#   Units   : tigris resolution string ("20m" = 1:20,000,000; also valid: "5m", "500k").
#   Range   : one of tigris's cartographic-boundary resolutions.
#   Source  : study design (national-scale choropleth generalization).
#   Consumers: scripts/urps_module_d_{differential_distance,differential_map,geographic_access,map}.R
CENSUS_CB_RESOLUTION <- "20m"
stopifnot(
  is.character(CENSUS_CB_RESOLUTION), length(CENSUS_CB_RESOLUTION) == 1L, !is.na(CENSUS_CB_RESOLUTION),
  CENSUS_CB_RESOLUTION %in% c("20m", "5m", "500k")   # valid tigris cb resolutions
)
