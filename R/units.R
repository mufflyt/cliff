# Canonical unit conversions — single source of truth.
#
# The Module-D geographic scripts convert great-circle distances between metres (what
# sf::st_distance returns on a geographic CRS) and statute miles (what the maps/metrics
# report). The conversion factor was previously copy-pasted as `MI <- 1609.344` per script.
# Pure constant + functions, no path/data dependencies — safe to source from any cwd.

# METERS_PER_MILE
#   Meaning : metres in one international/statute mile. 1 mile = 1609.344 m EXACTLY, by
#             definition (1959 international yard-and-pound agreement: 1 yd = 0.9144 m).
#   Units   : metres per mile.
#   Range   : exactly 1609.344.
#   Source  : NIST / 1959 international yard-and-pound agreement.
#   Consumers: scripts/urps_module_d_{differential_distance,geographic_access}.R
METERS_PER_MILE <- 1609.344
stopifnot(
  is.numeric(METERS_PER_MILE),
  length(METERS_PER_MILE) == 1L,
  !is.na(METERS_PER_MILE),
  METERS_PER_MILE == 1609.344,                              # exact by definition; guards a rounded copy (1609 / 1609.34)
  isTRUE(all.equal(METERS_PER_MILE, 5280 * 12 * 0.0254))    # = 5280 ft * 12 in * 0.0254 m/in -> it is THE statute mile
)

#' Convert metres to statute miles (vectorised; NA-preserving).
meters_to_miles <- function(m) m / METERS_PER_MILE

#' Convert statute miles to metres (vectorised; NA-preserving).
miles_to_meters <- function(mi) mi * METERS_PER_MILE

# RATE_PER_100K
#   Meaning : population-rate normalisation base. Counts are reported "per 100,000 population"
#             (rate = RATE_PER_100K * numerator / denominator), e.g. urogynecologists per 100,000 women 65+.
#   Units   : persons (the denominator scale).
#   Range   : exactly 1e5.
#   Source  : standard epidemiological per-100,000 rate convention.
#   Consumers: scripts/urps_{module_a_effective_supply,module_d_geographic_access,supply_demand_national}.R
#   NOT: the `guess_max = 1e5` row-count hint passed to read_csv/fread (the SAME literal, but a data-loading
#        parameter, not a rate base) -- those stay literal and are intentionally not this constant.
RATE_PER_100K <- 1e5
stopifnot(
  is.numeric(RATE_PER_100K), length(RATE_PER_100K) == 1L, !is.na(RATE_PER_100K),
  RATE_PER_100K == 1e5
)
