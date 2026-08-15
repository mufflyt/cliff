# SSOT guard: the study observed-window START year 2013 (iter42). It was a bare literal in three code sites —
# the age-productivity panel (`yrs <- 2013:2024`), the FPMRS supply figure (`OBS_START <- 2013L`), and the
# truth-contract validator (`year_min_allowed <- 2013L`) — plus the config test_years list. Now canonical in
# R/workforce_constants.R::WORKFORCE_OBSERVED_START_YEAR.
#
# INTENTIONALLY NOT collapsed: the window END differs by context and stays literal — the truth-contract study
# scope ends 2023, while the Medicare panel / observed supply series run to 2024. Only the START is unified.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

wc <- new.env(); source(here::here("R", "workforce_constants.R"), local = wc)

test_that("canonical observed-start year is a well-formed 2013 that precedes the projection baseline", {
  expect_type(wc$WORKFORCE_OBSERVED_START_YEAR, "integer")
  expect_length(wc$WORKFORCE_OBSERVED_START_YEAR, 1L)
  expect_identical(wc$WORKFORCE_OBSERVED_START_YEAR, 2013L)
  expect_lt(wc$WORKFORCE_OBSERVED_START_YEAR, wc$PROJECTION_BASELINE_YEAR)   # observation precedes projection
})

test_that("[adversarial] the three code consumers reference the SSOT, not a bare 2013 literal", {
  ap  <- readLines(here::here("scripts", "urps_module_a_age_productivity_2026-07-23.R"), warn = FALSE)
  fig <- readLines(here::here("scripts", "fig_fpmrs_supply_line.R"), warn = FALSE)
  val <- readLines(here::here("R", "validators", "validate_workforce_truth_contract.R"), warn = FALSE)
  expect_true(any(grepl("yrs <- WORKFORCE_OBSERVED_START_YEAR:WORKFORCE_REFERENCE_YEAR", ap)))
  expect_false(any(grepl("yrs <- 2013:2024", ap)))
  expect_true(any(grepl("OBS_START\\s*<-\\s*WORKFORCE_OBSERVED_START_YEAR", fig)))
  expect_false(any(grepl("OBS_START\\s*<-\\s*2013L", fig)))
  expect_true(any(grepl("year_min_allowed <- WORKFORCE_OBSERVED_START_YEAR", val)))
  expect_false(any(grepl("year_min_allowed <- 2013L", val)))
})

test_that("[intentional difference] the window END years stay distinct and are NOT folded into the constant", {
  # the validator's study-scope end is its OWN end constant (2023, iter43), NOT the start; the age-productivity
  # panel + fig keep 2024 (latest Medicare), also distinct from the start.
  val <- readLines(here::here("R", "validators", "validate_workforce_truth_contract.R"), warn = FALSE)
  ap  <- readLines(here::here("scripts", "urps_module_a_age_productivity_2026-07-23.R"), warn = FALSE)
  expect_true(any(grepl("year_max_allowed <- WORKFORCE_OBSERVED_END_YEAR", val)))        # end has its own constant
  expect_false(any(grepl("year_max_allowed <- WORKFORCE_OBSERVED_START_YEAR", val)))     # end NOT folded into the start
  expect_true(any(grepl("WORKFORCE_OBSERVED_START_YEAR:WORKFORCE_REFERENCE_YEAR", ap)))   # panel end = reference year (2024), distinct from start
  expect_false(any(grepl("WORKFORCE_OBSERVED_START_YEAR:2023", ap)))                      # start not miswired to the 2023 end
})

test_that("[cross-config parity] config test_years begins at the canonical start year", {
  cfg <- yaml::read_yaml(here::here("config", "expected_workforce_counts.yml"))
  ty <- cfg$test_years
  expect_true(length(ty) > 0)
  expect_identical(as.integer(ty[[1]]), wc$WORKFORCE_OBSERVED_START_YEAR)         # first test year == observed start
  expect_true(all(diff(as.integer(ty)) == 1L))                                    # contiguous run
})

test_that("[behavior-preserving] the wired sequences equal the prior literals", {
  # yrs 2013:2024 and OBS_START:OBS_END(=2024) reproduce exactly under the constant.
  expect_identical(wc$WORKFORCE_OBSERVED_START_YEAR:2024L, 2013L:2024L)
})
