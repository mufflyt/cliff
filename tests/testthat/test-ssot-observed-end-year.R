# SSOT guard: the study observation-confirmable END year 2023 (iter43). It was authoritative in the engine
# (WC_OBS_END <- 2023L) but re-hardcoded in the truth-contract validator (year_max_allowed <- 2023L). Now
# canonical in R/workforce_constants.R::WORKFORCE_OBSERVED_END_YEAR; the engine WC_OBS_END aliases it (like
# WC_YEAR0 aliases PROJECTION_BASELINE_YEAR) and the validator references it.
#
# INTENTIONALLY DISTINCT from the reference / latest-data year 2024 (engine WC_REF_YEAR; the Medicare panel and
# observed supply series run to 2024). The confirmable-observation end (2023, 3-yr follow-up) and the latest-
# available-data year (2024) are separate concepts and must NOT be collapsed.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

wc <- new.env(); source(here::here("R", "workforce_constants.R"), local = wc)

test_that("canonical observation-end year is a well-formed 2023, ordered start < end < baseline", {
  expect_type(wc$WORKFORCE_OBSERVED_END_YEAR, "integer")
  expect_length(wc$WORKFORCE_OBSERVED_END_YEAR, 1L)
  expect_identical(wc$WORKFORCE_OBSERVED_END_YEAR, 2023L)
  expect_gt(wc$WORKFORCE_OBSERVED_END_YEAR, wc$WORKFORCE_OBSERVED_START_YEAR)   # end after start
  expect_lt(wc$WORKFORCE_OBSERVED_END_YEAR, wc$PROJECTION_BASELINE_YEAR)        # 2023 < 2025 baseline
})

test_that("[cross-lineage alias] the engine WC_OBS_END aliases the shared constant (== 2023)", {
  ee <- new.env()
  ok <- tryCatch({ suppressMessages(suppressWarnings(source(here::here("R", "workforce_cliff_engine.R"), local = ee))); TRUE },
                 error = function(e) FALSE)
  skip_if_not(ok, "engine could not be sourced")
  expect_identical(ee$WC_OBS_END, wc$WORKFORCE_OBSERVED_END_YEAR)
  expect_identical(ee$WC_OBS_END, 2023L)
  # the hazard window must still fit inside the observation window (WIN[2]=2021 <= 2023)
  expect_lte(ee$WC_WIN[[2]], ee$WC_OBS_END)
})

test_that("[adversarial] the engine + validator reference the SSOT, not a bare 2023 literal", {
  eng <- readLines(here::here("R", "workforce_cliff_engine.R"), warn = FALSE)
  val <- readLines(here::here("R", "validators", "validate_workforce_truth_contract.R"), warn = FALSE)
  expect_true(any(grepl("WC_OBS_END\\s*<-\\s*WORKFORCE_OBSERVED_END_YEAR", eng)))
  expect_false(any(grepl("WC_OBS_END\\s*<-\\s*2023L", eng)))
  expect_true(any(grepl("year_max_allowed <- WORKFORCE_OBSERVED_END_YEAR", val)))
  expect_false(any(grepl("year_max_allowed <- 2023L", val)))
})

test_that("[intentional difference] 2023 (observation end) is NOT collapsed into 2024 (latest-data year)", {
  eng <- readLines(here::here("R", "workforce_cliff_engine.R"), warn = FALSE)
  ap  <- readLines(here::here("scripts", "urps_module_a_age_productivity_2026-07-23.R"), warn = FALSE)
  expect_true(any(grepl("WC_REF_YEAR\\s*<-\\s*WORKFORCE_REFERENCE_YEAR", eng)))          # reference year aliases the shared constant (still 2024)
  expect_true(any(grepl("WORKFORCE_OBSERVED_START_YEAR:WORKFORCE_REFERENCE_YEAR", ap)))  # panel end = reference year (2024), not the 2023 end
  expect_false(any(grepl("WORKFORCE_OBSERVED_END_YEAR\\s*<-\\s*2024", eng)))    # the two ends never share a symbol
  expect_true(wc$WORKFORCE_OBSERVED_END_YEAR != 2024L)                          # 2023 != 2024, kept apart
  expect_true(wc$WORKFORCE_REFERENCE_YEAR == 2024L && wc$WORKFORCE_OBSERVED_END_YEAR == 2023L)  # the two concepts hold distinct values
})

test_that("[cross-config parity] config test_years ends at the canonical observation end", {
  cfg <- yaml::read_yaml(here::here("config", "expected_workforce_counts.yml"))
  ty <- as.integer(cfg$test_years)
  expect_identical(ty[[length(ty)]], wc$WORKFORCE_OBSERVED_END_YEAR)            # last test year == observation end
  expect_identical(ty[[1]], wc$WORKFORCE_OBSERVED_START_YEAR)                   # (and first == observed start, iter42)
})
