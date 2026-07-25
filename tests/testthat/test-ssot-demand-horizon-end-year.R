# SSOT guard: the demand/supply projection HORIZON END year (2050). Previously hardcoded as spans (2025:2050),
# the HORIZON length (25L), YEAR==2050 endpoint filters, gf(2050), and milestone sets across 4 demand scripts.
# Now canonical in R/demand_denominator.R::DEMAND_HORIZON_END_YEAR; the HORIZON length is DERIVED from it.
# INTENTIONALLY NOT collapsed: the Wu-2011 / Kirby literature projection anchor years (fixed by source data)
# and the *_2050 data-column identifiers.
library(testthat)
library(here)

de <- new.env(); source(here::here("R", "demand_denominator.R"), local = de)

test_that("DEMAND_HORIZON_END_YEAR is the pinned 2050 horizon end (integer, after the index base)", {
  expect_type(de$DEMAND_HORIZON_END_YEAR, "integer")
  expect_identical(de$DEMAND_HORIZON_END_YEAR, 2050L)
  expect_gt(de$DEMAND_HORIZON_END_YEAR, de$DEMAND_INDEX_BASE_YEAR)
})

test_that("[behavior-preserving] the horizon length + span + milestones derive to the prior literals", {
  expect_identical(de$DEMAND_HORIZON_END_YEAR - de$PROJECTION_BASELINE_YEAR, 25L)                 # HORIZON <- 25L
  expect_identical(de$PROJECTION_BASELINE_YEAR:de$DEMAND_HORIZON_END_YEAR, 2025:2050)             # yrs span
  expect_identical(seq(de$PROJECTION_BASELINE_YEAR, de$DEMAND_HORIZON_END_YEAR, 5L),
                   as.integer(c(2025,2030,2035,2040,2045,2050)))                                   # milestone set
})

test_that("[adversarial] the demand consumers derive the horizon end; no bare literal remains", {
  ma <- readLines(here::here("scripts", "urps_module_a_effective_supply_2026-07-23.R"), warn = FALSE)
  bc <- readLines(here::here("scripts", "urps_demand_module_bc_2026-07-23.R"), warn = FALSE)
  cr <- readLines(here::here("scripts", "urps_module_bc_corrected_2026-07-23.R"), warn = FALSE)
  se <- readLines(here::here("scripts", "urps_demand_denominators_sensitivity.R"), warn = FALSE)
  # no bare horizon-end literals
  expect_false(any(grepl("HORIZON\\s*<-\\s*25L", ma)))          # length now derived
  expect_false(any(grepl("YEAR==2050", ma)))                    # filters canonicalised
  expect_false(any(grepl("YEAR==2050", bc)))
  expect_false(any(grepl("yrs\\s*<-\\s*2025:2050", bc)))        # span canonicalised
  # all four reference the SSOT
  for (nm in list(list(ma,"module_a"), list(bc,"module_bc"), list(cr,"module_bc_corrected"), list(se,"sensitivity")))
    expect_true(any(grepl("DEMAND_HORIZON_END_YEAR", nm[[1]])), info = nm[[2]])
  expect_true(any(grepl("HORIZON <- DEMAND_HORIZON_END_YEAR - PROJECTION_BASELINE_YEAR", ma)))  # derived length
})

test_that("[intentional differences preserved] literature anchors + data-column identifiers stay literal", {
  se <- readLines(here::here("scripts", "urps_demand_denominators_sensitivity.R"), warn = FALSE)
  cr <- readLines(here::here("scripts", "urps_module_bc_corrected_2026-07-23.R"), warn = FALSE)
  # Wu-2011 literature projection anchor: 2050 stays literal, NOT the study-horizon constant
  expect_true(any(grepl("anchor_index\\(d\\$YEAR, 2010, WU2011_SURG_2010, 2050, WU2011_SURG_2050\\)", se)))
  # data-column schema identifiers keep their _2050 names (not the horizon value)
  expect_true(any(grepl("vol_2050|req_fte_confirmed_2050|req_fte_mid_2050", cr)))
})
