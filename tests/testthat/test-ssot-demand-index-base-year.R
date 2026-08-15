# SSOT guard: the reporting INDEX BASE year (projection baseline, 2025=100 / adequacy 2025=1.00). The
# `[YEAR==2025]` index-denominator filter was hardcoded across module_a (x2) and supply_demand_national (x2).
# Now canonical in R/demand_denominator.R::DEMAND_INDEX_BASE_YEAR. Distinct from DEMAND_REBASE_YEAR (2024,
# demographic growth) and from the 2050 horizon end. It EQUALS the supply engine's WC_YEAR0 (same projection
# baseline, separate lineage) -- guarded below so the two cannot silently diverge before unification.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

de <- new.env(); source(here::here("R", "demand_denominator.R"), local = de)
CONSUMERS <- c("urps_module_a_effective_supply_2026-07-23.R", "urps_supply_demand_national_2026-07-23.R")

test_that("DEMAND_INDEX_BASE_YEAR is the pinned projection baseline 2025 (integer)", {
  expect_type(de$DEMAND_INDEX_BASE_YEAR, "integer")
  expect_identical(de$DEMAND_INDEX_BASE_YEAR, 2025L)
  expect_gt(de$DEMAND_INDEX_BASE_YEAR, de$DEMAND_REBASE_YEAR)   # projection starts after the demographic base
  expect_false(de$DEMAND_INDEX_BASE_YEAR == 2050L)             # NOT the horizon end
})

test_that("[behavior-preserving] filtering YEAR==DEMAND_INDEX_BASE_YEAR selects the same row as ==2025", {
  yrs <- c(2024, 2025, 2050)
  expect_identical(yrs == de$DEMAND_INDEX_BASE_YEAR, yrs == 2025)
  expect_equal(which(yrs == de$DEMAND_INDEX_BASE_YEAR), 2L)
})

test_that("[adversarial] both consumers use the constant; no bare [YEAR==2025] index filter remains", {
  for (b in CONSUMERS) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    expect_false(any(grepl("YEAR==2025", ls)), info = b)                     # index-base literal gone
    expect_true(any(grepl("YEAR==DEMAND_INDEX_BASE_YEAR", ls)), info = b)    # uses the SSOT
    expect_true(any(grepl("demand_denominator\\.R", ls)), info = b)         # sources the module
    expect_true(any(grepl("YEAR==2050|YEAR==DEMAND_HORIZON_END_YEAR", ls)), info = b)   # horizon-end endpoint present, distinct from the index base (iter24 canonicalised module_a's literal)
  }
})

test_that("[cross-lineage guard] the supply engine's WC_YEAR0 equals DEMAND_INDEX_BASE_YEAR", {
  ee <- new.env()
  ok <- tryCatch({ suppressMessages(suppressWarnings(source(here::here("R", "workforce_cliff_engine.R"), local = ee))); TRUE },
                 error = function(e) FALSE)
  skip_if_not(ok, "workforce_cliff_engine.R could not be sourced in this environment")
  expect_identical(ee$WC_YEAR0, de$DEMAND_INDEX_BASE_YEAR)   # same 2025 projection baseline across lineages
})
