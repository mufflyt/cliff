# SSOT guard: the URPS annual-entrant count (64) is a DERIVED value (mean of the ACGME
# graduate counts), not an independent literal. The supply-demand producer must derive it from
# GRAD_URPS so it cannot drift from the graduate-count source across the three lineages
# (engine WC_ENTRANTS, the frozen SSOT annual_entrants, and the supply-demand model).
library(testthat)
library(here)
suppressPackageStartupMessages(library(readr))

se <- new.env(); source(here::here("shiny_urps_scenarios", "urps_model_data.R"), local = se)
ee <- new.env(); suppressPackageStartupMessages(source(here::here("R", "workforce_cliff_engine.R"), local = ee))

test_that("URPS annual entrants == mean(GRAD_URPS) == 64, consistent across all three lineages", {
  entrants <- mean(se$GRAD_URPS)
  expect_equal(entrants, 64)
  expect_equal(entrants, ee$WC_ENTRANTS[["URPS"]])                 # engine derived mean
  s <- read_csv(here::here("data", "workforce_projections_consolidated.csv"), show_col_types = FALSE)
  expect_equal(s$annual_entrants[s$subspecialty_abbrev == "URPS"], entrants)  # frozen SSOT
})

test_that("the demand horizon in the supply-demand producer stays 25 (2025-2050), NOT collapsed to WC_HORIZON", {
  ls <- readLines(here::here("scripts", "urps_module_a_effective_supply_2026-07-23.R"), warn = FALSE)
  expect_true(any(grepl("HORIZON\\s*<-\\s*25L", ls)))             # intentional difference preserved
  expect_false(ee$WC_HORIZON == 25L)                             # sanity: the two horizons differ
})

test_that("[adversarial] the supply-demand producer derives ENTRANTS from GRAD_URPS, not a numeric literal", {
  ls <- readLines(here::here("scripts", "urps_module_a_effective_supply_2026-07-23.R"), warn = FALSE)
  expect_true(any(grepl("ENTRANTS\\s*<-\\s*mean\\(GRAD_URPS\\)", ls)))
  expect_false(any(grepl("ENTRANTS\\s*<-\\s*[0-9]", ls)))
})
