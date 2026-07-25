# Canonical demand-denominator age definition — single source of truth.
#
# The temporal demand driver is the projected population of older US women (in whom pelvic
# floor disorders concentrate), taken from the Census 2023 National Population Projections
# single-year-of-age file (np2023_d1_mid.csv, columns POP_0 .. POP_100). "Women 65+" is the
# sum of the female single-year columns POP_65 .. POP_100. That age range was previously
# hardcoded as `sprintf("POP_%d", 65:100)` in each demand module.
#
# NOTE — intentional separate construction: the SPATIAL access map (geographic_access) uses
# ACS 5-year Table B01001 female bands 044:049 for a CROSS-SECTIONAL county count, NOT this
# temporal NPP driver. The two are deliberately different sources and are NOT unified here.
#
# Constants + function. Sources R/workforce_constants.R for the SHARED projection baseline year (so the
# demand index base and the supply engine's WC_YEAR0 cannot drift); otherwise no path/data dependencies.
source(here::here("R", "workforce_constants.R"), local = TRUE)   # canonical PROJECTION_BASELINE_YEAR

# DEMAND_AGE_MIN
#   Meaning : inclusive lower age bound of the "older women" demand denominator (women 65+).
#   Units   : years.
#   Range   : a single non-negative integer < NPP_MAX_AGE.
#   Source  : study design (pelvic-floor-disorder demand concentrates at 65+; matches the
#             Census NPP single-year age buckets and the manuscript "women aged 65 years or older").
DEMAND_AGE_MIN <- 65L

# NPP_MAX_AGE
#   Meaning : top single-year age bucket in the Census NPP file (ages are 0..100, 100 = "100+").
#   Units   : years.
#   Source  : Census 2023 National Population Projections file schema (POP_0 .. POP_100).
NPP_MAX_AGE <- 100L

stopifnot(
  is.integer(DEMAND_AGE_MIN), length(DEMAND_AGE_MIN) == 1L, !is.na(DEMAND_AGE_MIN),
  DEMAND_AGE_MIN >= 0L,
  is.integer(NPP_MAX_AGE), length(NPP_MAX_AGE) == 1L, !is.na(NPP_MAX_AGE),
  DEMAND_AGE_MIN < NPP_MAX_AGE,
  DEMAND_AGE_MIN == 65L, NPP_MAX_AGE == 100L   # pin the published definition; a drift must be deliberate
)

#' Census-NPP single-year-of-age column names that sum to the women-65+ demand denominator.
#' Returns c("POP_65", ..., "POP_100"). The female-row filter (SEX==2) is the caller's job.
npp_women_65plus_cols <- function() sprintf("POP_%d", DEMAND_AGE_MIN:NPP_MAX_AGE)

# DEMAND_REBASE_YEAR
#   Meaning : the year to which the projected older-women population is REBASED so the demographic
#             growth factor equals 1 (g(base)=1). Every demand module divides its women-65+ series by
#             the women-65+ count in this year to get the growth index that scales projected volume/FTE.
#   Units   : calendar year (integer).
#   Range   : a single 4-digit year within the NPP projection window.
#   Source  : study design (last observed base year of the demographic projection).
#   Consumers: scripts/urps_demand_module_bc_2026-07-23.R, scripts/urps_module_bc_corrected_2026-07-23.R.
#   NOT: the Medicare-claims data vintage (the table medicare_part_b_by_service_2024 / national_2024 is a
#        DATA year, also 2024, but a different concept) NOR the supply-side index base 2025 (module_a /
#        supply_demand_national rebase reporting indices to the 2025 projection baseline). Do not conflate.
DEMAND_REBASE_YEAR <- 2024L
stopifnot(
  is.integer(DEMAND_REBASE_YEAR), length(DEMAND_REBASE_YEAR) == 1L, !is.na(DEMAND_REBASE_YEAR),
  DEMAND_REBASE_YEAR >= 2000L, DEMAND_REBASE_YEAR <= 2100L,
  DEMAND_REBASE_YEAR == 2024L   # pin the published demographic base; a change must be deliberate
)

# DEMAND_INDEX_BASE_YEAR
#   Meaning : the projection BASELINE year to which the supply/demand REPORTING indices are rebased
#             (index(base)=100, adequacy(base)=1.00) and against which baseline endpoint values are reported.
#             Distinct from DEMAND_REBASE_YEAR (2024, the demographic-growth denominator): 2025 is the
#             projection start; the reporting indices are all expressed relative to it.
#   Units   : calendar year (integer).
#   Range   : a single 4-digit year; must be > DEMAND_REBASE_YEAR (the projection starts after the demographic base).
#   Source  : study design (projection baseline / first projected year).
#   Consumers: scripts/urps_module_a_effective_supply_*.R, scripts/urps_supply_demand_national_*.R.
#   RELATIONSHIP: this equals the supply-engine's WC_YEAR0 (workforce_cliff_engine.R) — the SAME 2025
#     projection baseline — but the demand modules are a separate lineage that does not source the engine.
#     Formalising the demand copies here (4 sites -> 1) does not create a new SSOT; the residual cross-lineage
#     duplication (WC_YEAR0 vs this) is the documented next step: a shared PROJECTION_BASELINE_YEAR in
#     workforce_constants.R that BOTH alias. Do NOT conflate with the 2050 demand horizon end (a separate value).
DEMAND_INDEX_BASE_YEAR <- PROJECTION_BASELINE_YEAR   # SSOT: shared with the supply engine (workforce_constants.R)
stopifnot(
  is.integer(DEMAND_INDEX_BASE_YEAR), length(DEMAND_INDEX_BASE_YEAR) == 1L, !is.na(DEMAND_INDEX_BASE_YEAR),
  DEMAND_INDEX_BASE_YEAR > DEMAND_REBASE_YEAR,
  DEMAND_INDEX_BASE_YEAR == 2025L,                       # pin the projection baseline; a change must be deliberate
  identical(DEMAND_INDEX_BASE_YEAR, PROJECTION_BASELINE_YEAR)   # it IS the shared baseline, not a parallel copy
)

# DEMAND_HORIZON_END_YEAR
#   Meaning : the final year of the demand/supply projection horizon (indices run PROJECTION_BASELINE_YEAR
#             .. this year). The horizon LENGTH is DEMAND_HORIZON_END_YEAR - PROJECTION_BASELINE_YEAR (= 25).
#   Units   : calendar year (integer).
#   Range   : a single 4-digit year > DEMAND_INDEX_BASE_YEAR.
#   Source  : study design (long-horizon demographic-demand projection endpoint, 2050).
#   Consumers: scripts/urps_{module_a_effective_supply,demand_module_bc,module_bc_corrected,demand_denominators_sensitivity}.R
#   NOT: the literature projection target years used as extrapolation anchors -- Wu-2011 projects surgery to
#        2050 and Kirby to 2030; those `anchor_index(..., 2050/2030, ...)` years are fixed by the SOURCE data
#        (they coincide numerically but are a different concept) and stay literal. Do not conflate.
DEMAND_HORIZON_END_YEAR <- 2050L
stopifnot(
  is.integer(DEMAND_HORIZON_END_YEAR), length(DEMAND_HORIZON_END_YEAR) == 1L, !is.na(DEMAND_HORIZON_END_YEAR),
  DEMAND_HORIZON_END_YEAR > DEMAND_INDEX_BASE_YEAR,
  DEMAND_HORIZON_END_YEAR == 2050L   # pin the published horizon end; a change must be deliberate
)
