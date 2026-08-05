# tests/testthat/test-validation-refinement.R
# Guards for demand_lifecourse/09_validation.R (external-target harness) and the
# within-woman cesarean-correlation refinement in 02_birth_history.R.

library(testthat)
library(here)

source(here::here("demand_lifecourse/02_birth_history.R"))
source(here::here("demand_lifecourse/09_validation.R"))

# ---- Validation harness -----------------------------------------------------

test_that("validation targets load with the documented schema and cite every row", {
  tg <- load_validation_targets()
  expect_true(all(c("source", "metric", "value", "citation", "use_as") %in% names(tg)))
  expect_true(all(nzchar(trimws(tg$citation))))
  expect_true("prevalence_any_pfd" %in% tg$metric)          # Nygaard anchor present
  expect_true(any(grepl("SWAN", tg$source)))                # SWAN target present
})

test_that("validate_against_targets scores a prediction and flags agreement", {
  pred <- tibble::tibble(
    metric = c("prevalence_any_pfd", "incidence_ui_annual"),
    predicted_value = c(0.24, 0.11))               # both close to target
  res <- validate_against_targets(pred)
  expect_equal(nrow(res), 2)
  expect_true(all(res$agrees))                     # within tolerance of Nygaard/Waetjen
  expect_true(all(res$ratio > 0.9 & res$ratio < 1.1))
})

test_that("a far-off prediction fails agreement", {
  pred <- tibble::tibble(metric = "prevalence_any_pfd", predicted_value = 0.05)
  res <- validate_against_targets(pred)
  expect_false(res$agrees)
  expect_gt(res$abs_pct_diff, 50)
})

test_that("direction-only targets (NA value) are returned unscored, not errored", {
  pred <- tibble::tibble(metric = "parity_mode_direction", predicted_value = 1)
  res <- validate_against_targets(pred)
  expect_true(is.na(res$agrees))
  expect_true(is.na(res$target_value))
})

# ---- Within-woman cesarean correlation --------------------------------------

test_that("cesarean count never exceeds parity and is zero for nulliparas", {
  set.seed(1)
  k <- c(0L, 1L, 2L, 3L, 4L)
  cs <- cesarean_births_correlated(rep(k, each = 200))
  expect_true(all(cs >= 0))
  expect_true(all(cs <= rep(k, each = 200)))
  expect_true(all(cesarean_births_correlated(rep(0L, 50)) == 0))
})

test_that("correlated draw concentrates cesareans more than an independent binomial", {
  set.seed(42)
  n <- 20000L; parity <- 3L
  # correlated: primary 0.22, repeat 0.86
  corr <- cesarean_births_correlated(rep(parity, n))
  # independent binomial at the same marginal-ish total rate (0.32)
  indep <- stats::rbinom(n, parity, 0.32)
  # the correlated model puts MORE mass on the extremes (0 and 3 cesareans)
  extremes_corr  <- mean(corr == 0 | corr == parity)
  extremes_indep <- mean(indep == 0 | indep == parity)
  expect_gt(extremes_corr, extremes_indep)
})

test_that("with repeat_rate == primary_rate the draw reduces to independent", {
  set.seed(7)
  cs <- cesarean_births_correlated(rep(3L, 20000), primary_rate = 0.3, repeat_rate = 0.3)
  expect_equal(mean(cs), 3 * 0.3, tolerance = 0.03)   # ~ binomial mean
})
