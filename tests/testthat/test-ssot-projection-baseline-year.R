# SSOT guard: the projection BASELINE year (2025), unified across lineages. It was hardcoded independently as
# the supply engine's WC_YEAR0 and the demand DEMAND_INDEX_BASE_YEAR. Now BOTH alias one canonical
# R/workforce_constants.R::PROJECTION_BASELINE_YEAR, so the two lineages cannot drift. (iter 22 added a guard
# that they were equal; iter 23 makes them the SAME source.)
library(testthat)
library(here)

wc <- new.env(); source(here::here("R", "workforce_constants.R"), local = wc)
de <- new.env(); source(here::here("R", "demand_denominator.R"),  local = de)

test_that("PROJECTION_BASELINE_YEAR is the pinned 2025 projection baseline (integer)", {
  expect_type(wc$PROJECTION_BASELINE_YEAR, "integer")
  expect_identical(wc$PROJECTION_BASELINE_YEAR, 2025L)
})

test_that("the DEMAND index base aliases the shared baseline (same source, not a parallel copy)", {
  expect_identical(de$DEMAND_INDEX_BASE_YEAR, wc$PROJECTION_BASELINE_YEAR)
  # demand_denominator pulled the shared constant into its own scope
  expect_true(exists("PROJECTION_BASELINE_YEAR", envir = de))
})

test_that("the SUPPLY engine WC_YEAR0 aliases the shared baseline (cross-lineage unification)", {
  ee <- new.env()
  ok <- tryCatch({ suppressMessages(suppressWarnings(source(here::here("R", "workforce_cliff_engine.R"), local = ee))); TRUE },
                 error = function(e) FALSE)
  skip_if_not(ok, "workforce_cliff_engine.R could not be sourced")
  expect_identical(ee$WC_YEAR0, wc$PROJECTION_BASELINE_YEAR)          # engine derives from the shared constant
  expect_identical(ee$WC_YEAR0, de$DEMAND_INDEX_BASE_YEAR)            # both lineages now equal BY CONSTRUCTION
})

test_that("[semantic] baseline + horizon fixes the published endpoint 2029", {
  expect_identical(wc$PROJECTION_BASELINE_YEAR + wc$WORKFORCE_PROJECTION_HORIZON_YEARS, 2029L)
})

test_that("[adversarial] neither lineage re-hardcodes 2025 for the baseline; both derive from the constant", {
  eng <- readLines(here::here("R", "workforce_cliff_engine.R"), warn = FALSE)
  dd  <- readLines(here::here("R", "demand_denominator.R"), warn = FALSE)
  expect_false(any(grepl("WC_YEAR0\\s*<-\\s*2025", eng)))                     # engine literal gone
  expect_true(any(grepl("WC_YEAR0\\s*<-\\s*PROJECTION_BASELINE_YEAR", eng)))  # engine aliases
  expect_false(any(grepl("DEMAND_INDEX_BASE_YEAR\\s*<-\\s*2025", dd)))        # demand literal gone
  expect_true(any(grepl("DEMAND_INDEX_BASE_YEAR\\s*<-\\s*PROJECTION_BASELINE_YEAR", dd)))
})
