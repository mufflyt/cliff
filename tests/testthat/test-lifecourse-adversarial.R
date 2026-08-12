# tests/testthat/test-lifecourse-adversarial.R
# ADVERSARIAL tests: feed hostile / malformed inputs and confirm the code FAILS
# LOUDLY or degrades gracefully -- never silently returns a plausible-looking
# wrong number. Several of these are the reason guards were added to gini(),
# concentration_summary(), and service_volume_to_wrvu().

library(testthat)
library(here)

source(here::here("R/workforce_concentration_metrics.R"))
source(here::here("demand_lifecourse/demand-birth_history.R"))
source(here::here("demand_lifecourse/supply-staffing_conversion.R"))
source(here::here("demand_lifecourse/validation-targets.R"))

# ---- Concentration metrics ---------------------------------------------------

test_that("gini rejects negative and non-numeric input, and handles degenerate vectors", {
  expect_error(gini(c(-1, 2, 3)))
  expect_error(gini(c("a", "b")))                 # non-numeric -> clean error, not silent NA
  expect_true(is.na(gini(c(NA_real_, NA_real_)))) # all-NA -> NA
  expect_equal(gini(c(5)), 0)                     # single unit -> perfect equality
  expect_true(is.na(gini(numeric(0))))            # empty -> NA
})

test_that("herfindahl_index drops non-positive entries and returns NA on an empty total", {
  expect_true(is.na(herfindahl_index(c(0, 0, 0))))
  expect_equal(herfindahl_index(c(50, 50, -3)), 0.5)   # negative dropped
})

test_that("concentration_summary refuses a unit universe smaller than the occupied units", {
  expect_error(concentration_summary(c(10, 5, 3), n_units_total = 2))  # 3 occupied > 2 units
  s <- concentration_summary(c(0, 0, 0), n_units_total = 10)           # nobody anywhere
  expect_equal(s$n_occupied, 0)
  expect_true(is.na(s$gini))
})

# ---- Staffing conversion -----------------------------------------------------

test_that("service_volume_to_wrvu rejects unknown services and bad volumes", {
  expect_error(service_volume_to_wrvu(tibble::tibble(service = "teleporter", volume = 1)))
  expect_error(service_volume_to_wrvu(tibble::tibble(service = "cystoscopy", volume = -5)))
  expect_error(service_volume_to_wrvu(tibble::tibble(service = "cystoscopy", volume = NA_real_)))
  expect_error(service_volume_to_wrvu(tibble::tibble(service = "cystoscopy", volume = Inf)))
})

test_that("an empty volume table yields zero work RVUs, not an error", {
  z <- service_volume_to_wrvu(tibble::tibble(service = character(0), volume = numeric(0)))
  expect_equal(z$work_rvu, 0)
})

test_that("convert_workload_to_fte rejects a non-positive productivity or an indirect share >= 1", {
  v <- tibble::tibble(service = "sling_procedure", volume = 100)
  expect_error(convert_workload_to_fte(v, wrvu_per_fte = 0))
  expect_error(convert_workload_to_fte(v, wrvu_per_fte = -5000))
  expect_error(convert_workload_to_fte(v, wrvu_per_fte = 5000, indirect_share = 1))
  expect_error(convert_workload_to_fte(v, wrvu_per_fte = 5000, indirect_share = 1.5))
})

test_that("calibrate_wrvu_per_fte refuses a zero or negative base-year anchor", {
  expect_error(calibrate_wrvu_per_fte(5e6, 0))
  expect_error(calibrate_wrvu_per_fte(5e6, -100))
  expect_error(calibrate_wrvu_per_fte(0, 1339))
})

# ---- Cesarean correlation helper --------------------------------------------

test_that("cesarean_births_correlated rejects out-of-range rates and negative parity", {
  expect_error(cesarean_births_correlated(c(2L), primary_rate = 1.2))
  expect_error(cesarean_births_correlated(c(2L), repeat_rate = -0.1))
  expect_error(cesarean_births_correlated(c(-1L)))
})

test_that("cesarean_births_correlated degrades gracefully on NA and zero parity", {
  expect_equal(cesarean_births_correlated(c(0L, 0L)), c(0L, 0L))
  expect_equal(cesarean_births_correlated(NA_integer_), 0L)   # NA parity -> 0 (documented)
})

# ---- Cohort exposure functions ----------------------------------------------

test_that("cohort exposure handles empty input and clamps absurd cohorts to finite, bounded values", {
  expect_equal(nrow(cohort_vaginal_exposure(integer(0))), 0)   # empty -> 0-row, no crash
  ex <- cohort_vaginal_exposure(c(1800L, 3000L))               # far outside the anchor range
  expect_true(all(is.finite(ex$mean_total_parity)))
  expect_true(all(ex$cohort_cesarean_fraction >= 0 & ex$cohort_cesarean_fraction <= 1))
  expect_true(all(ex$mean_vaginal_deliveries >= 0))
})

test_that("an NA cohort fails loudly rather than producing a silent bogus row", {
  expect_error(cohort_vaginal_exposure(NA_integer_))
})

# ---- Validation harness ------------------------------------------------------

test_that("validate_against_targets errors on a missing metric column but not on an unknown metric", {
  expect_error(validate_against_targets(tibble::tibble(value = 0.2)))          # no 'metric'/'predicted_value'
  empty <- validate_against_targets(tibble::tibble(metric = "not_a_target",
                                                   predicted_value = 0.2))
  expect_equal(nrow(empty), 0)                                                 # unknown -> 0 rows, no error
})

# ---- Committed-data integrity (guards against a corrupt cited CSV) -----------

test_that("the cited cesarean series stays a valid probability and parity anchors stay plausible", {
  ces <- read.csv(here::here("demand_lifecourse/data/us_cesarean_rate_by_year_2026-08-02.csv"))
  expect_true(all(ces$cesarean_rate > 0 & ces$cesarean_rate < 1))
  par <- read.csv(here::here("demand_lifecourse/data/us_completed_parity_by_cohort_2026-08-02.csv"))
  expect_true(all(par$mean_completed_parity > 0 & par$mean_completed_parity < 5))
})

test_that("every non-NA dose-response effect size is positive (a protective OR here would be a data error)", {
  d <- read.csv(here::here("demand_lifecourse/params/parity_disease_dose_response.csv"))
  es <- suppressWarnings(as.numeric(d$effect_size))
  expect_true(all(es[!is.na(es)] > 0))
})
