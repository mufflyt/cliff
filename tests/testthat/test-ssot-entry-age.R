# SSOT guard: the fellowship-graduate ENTRY AGE (34), unified across lineages. iter 6 wired the engine-sourcing
# scripts to WC_ENTRY_AGE, but module_a (demand lineage) still hardcoded ENTRY_AGE <- 34L. Now both the engine's
# WC_ENTRY_AGE and module_a's ENTRY_AGE alias R/workforce_constants.R::WORKFORCE_ENTRY_AGE.
library(testthat)
library(here)

wc <- new.env(); source(here::here("R", "workforce_constants.R"), local = wc)

test_that("WORKFORCE_ENTRY_AGE is the pinned 34 (integer, plausible range)", {
  expect_type(wc$WORKFORCE_ENTRY_AGE, "integer")
  expect_identical(wc$WORKFORCE_ENTRY_AGE, 34L)
  expect_gte(wc$WORKFORCE_ENTRY_AGE, 25L); expect_lte(wc$WORKFORCE_ENTRY_AGE, 45L)
})

test_that("[cross-lineage] the engine WC_ENTRY_AGE aliases the shared constant", {
  ee <- new.env()
  ok <- tryCatch({ suppressMessages(suppressWarnings(source(here::here("R", "workforce_cliff_engine.R"), local = ee))); TRUE },
                 error = function(e) FALSE)
  skip_if_not(ok, "engine could not be sourced")
  expect_identical(ee$WC_ENTRY_AGE, wc$WORKFORCE_ENTRY_AGE)
  expect_gt(ee$WC_ENTRY_AGE, ee$WC_AGE_AT_CERT)   # graduates enter after certification
})

test_that("[adversarial] neither the engine nor module_a re-hardcodes 34 for the entry age", {
  eng <- readLines(here::here("R", "workforce_cliff_engine.R"), warn = FALSE)
  ma  <- readLines(here::here("scripts", "urps_module_a_effective_supply_2026-07-23.R"), warn = FALSE)
  expect_false(any(grepl("WC_ENTRY_AGE\\s*<-\\s*34L", eng)))
  expect_true(any(grepl("WC_ENTRY_AGE\\s*<-\\s*WORKFORCE_ENTRY_AGE", eng)))
  expect_false(any(grepl("ENTRY_AGE\\s*<-\\s*34L", ma)))
  expect_true(any(grepl("ENTRY_AGE\\s*<-\\s*WORKFORCE_ENTRY_AGE", ma)))
})
