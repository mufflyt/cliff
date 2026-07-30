# SSOT guard: the reference / latest-available-data year 2024 (iter44) — the year cohort ages are reckoned
# as-of and the most recent Medicare panel year. It was authoritative in the engine (WC_REF_YEAR <- 2024L) but
# re-hardcoded as bare 2024 in the age-productivity script (`birth := 2024-age24`, panel end `:2024`). Now
# canonical in R/workforce_constants.R::WORKFORCE_REFERENCE_YEAR; the engine WC_REF_YEAR aliases it (like
# WC_OBS_END / WC_YEAR0) and the age-productivity script references it.
#
# INTENTIONALLY DISTINCT from the observation-confirmable end 2023 (WORKFORCE_OBSERVED_END_YEAR): latest data
# (2024) is one year past the last confirmable-departure year (2023). Also distinct from the module_bc Medicare
# TABLE/COLUMN identifiers (medicare_part_b_by_service_2024 / national_2024), which are schema names left literal.
library(testthat)
library(here)

wc <- new.env(); source(here::here("R", "workforce_constants.R"), local = wc)

test_that("canonical reference year is a well-formed 2024, ordered end < reference < baseline", {
  expect_type(wc$WORKFORCE_REFERENCE_YEAR, "integer")
  expect_length(wc$WORKFORCE_REFERENCE_YEAR, 1L)
  expect_identical(wc$WORKFORCE_REFERENCE_YEAR, 2024L)
  expect_gt(wc$WORKFORCE_REFERENCE_YEAR, wc$WORKFORCE_OBSERVED_END_YEAR)     # 2024 > 2023 observation end
  expect_lt(wc$WORKFORCE_REFERENCE_YEAR, wc$PROJECTION_BASELINE_YEAR)        # 2024 < 2025 baseline
  # the full year family is strictly increasing: start < end < reference < baseline
  yrs <- c(wc$WORKFORCE_OBSERVED_START_YEAR, wc$WORKFORCE_OBSERVED_END_YEAR,
           wc$WORKFORCE_REFERENCE_YEAR, wc$PROJECTION_BASELINE_YEAR)
  expect_true(all(diff(yrs) > 0))
})

test_that("[cross-lineage alias] the engine WC_REF_YEAR aliases the shared constant (== 2024)", {
  ee <- new.env()
  ok <- tryCatch({ suppressMessages(suppressWarnings(source(here::here("R", "workforce_cliff_engine.R"), local = ee))); TRUE },
                 error = function(e) FALSE)
  skip_if_not(ok, "engine could not be sourced")
  expect_identical(ee$WC_REF_YEAR, wc$WORKFORCE_REFERENCE_YEAR)
  expect_identical(ee$WC_REF_YEAR, 2024L)
  # the hazard window still has 3-yr follow-up headroom below the reference year (2021 < 2024)
  expect_lt(ee$WC_WIN[[2]], ee$WC_REF_YEAR)
})

test_that("[behavior-preserving] age reconstruction is unchanged under the alias", {
  ee <- new.env(); suppressWarnings(suppressMessages(source(here::here("R", "workforce_cliff_engine.R"), local = ee)))
  # age = REF_YEAR - cert_year + AGE_AT_CERT; a physician certified in the reference year is exactly age-at-cert.
  recon <- function(cy) ee$WC_REF_YEAR - cy + ee$WC_AGE_AT_CERT
  expect_identical(recon(ee$WC_REF_YEAR), ee$WC_AGE_AT_CERT)
  expect_identical(recon(2014L), 2024L - 2014L + ee$WC_AGE_AT_CERT)   # a decade before reference -> +10 years
})

test_that("[adversarial] engine + age-productivity reference the SSOT, not a bare 2024 year literal", {
  eng <- readLines(here::here("R", "workforce_cliff_engine.R"), warn = FALSE)
  ap  <- readLines(here::here("scripts", "urps_module_a_age_productivity_2026-07-23.R"), warn = FALSE)
  expect_true(any(grepl("WC_REF_YEAR\\s*<-\\s*WORKFORCE_REFERENCE_YEAR", eng)))
  expect_false(any(grepl("WC_REF_YEAR\\s*<-\\s*2024L", eng)))
  expect_true(any(grepl("birth := WORKFORCE_REFERENCE_YEAR-age24", ap)))
  expect_false(any(grepl("birth := 2024-age24", ap)))
  expect_true(any(grepl("WORKFORCE_OBSERVED_START_YEAR:WORKFORCE_REFERENCE_YEAR", ap)))
})

test_that("[intentional difference] the module_bc Medicare schema identifiers stay literal (not the constant)", {
  # medicare_part_b_by_service_2024 is a DuckDB TABLE NAME (schema), not the reference-year value; leave literal.
  mb <- readLines(here::here("scripts", "urps_demand_module_bc_2026-07-23.R"), warn = FALSE)
  expect_true(any(grepl("medicare_part_b_by_service_2024", mb)))          # schema identifier preserved
  expect_false(any(grepl("WORKFORCE_REFERENCE_YEAR", mb)))                 # the constant did NOT leak into SQL table names
})
