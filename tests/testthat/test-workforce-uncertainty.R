# Semantic + boundary-value tests for wc_uncertainty_summary() /
# wc_uncertainty_sentence() (R/workforce_uncertainty.R). The probabilities are
# exact functions of the draws, so we assert exact values on hand-built draw
# vectors, probe the threshold boundaries, and negative-control the validation.

suppressPackageStartupMessages({ library(here) })
source(here::here("R", "workforce_uncertainty.R"))

# ---- semantic: exact probabilities on known draws ----

test_that("decision probabilities are exact for a known draw set", {
  u <- wc_uncertainty_summary(final_draws = c(90, 100, 110),
                              ratio_draws = c(0.5, 1, 2), baseline = 100)
  expect_equal(u$median, 100)
  expect_equal(u$baseline, 100)
  # shortage_pct = 0 -> level 100 -> P(fd <= 100) = {90,100} = 2/3
  expect_equal(u$p_shortage_exceeds, 2 / 3)
  # improve_pct = 0 -> level 100 -> P(fd >= 100) = {100,110} = 2/3
  expect_equal(u$p_access_improves, 2 / 3)
  # ratio < 1 -> {0.5} = 1/3
  expect_equal(u$p_below_replacement, 1 / 3)
  expect_equal(u$n_draws, 3L)
})

test_that("shortage_pct and improve_pct move the thresholds as specified", {
  u <- wc_uncertainty_summary(c(90, 100, 110), baseline = 100,
                              shortage_pct = 10, improve_pct = 10)
  # shortage level = 90 -> P(fd <= 90) = {90} = 1/3
  expect_equal(u$p_shortage_exceeds, 1 / 3)
  # improve level = 110 -> P(fd >= 110) = {110} = 1/3
  expect_equal(u$p_access_improves, 1 / 3)
  expect_true(is.na(u$p_below_replacement))   # no ratio supplied
})

test_that("the prediction interval brackets the median and widens with level", {
  d <- as.numeric(1:100)
  u95 <- wc_uncertainty_summary(d, baseline = 50, interval = 0.95)
  u50 <- wc_uncertainty_summary(d, baseline = 50, interval = 0.50)
  expect_lt(u95$pi_lower, u95$median); expect_gt(u95$pi_upper, u95$median)
  expect_lt(u95$pi_lower, u50$pi_lower)   # wider interval reaches lower
  expect_gt(u95$pi_upper, u50$pi_upper)   # and higher
  expect_equal(u95$pi_level, 0.95)
})

test_that("non-finite draws are dropped", {
  u <- wc_uncertainty_summary(c(100, NA, Inf, -Inf, 110), baseline = 100)
  expect_equal(u$n_draws, 2L)             # only 100 and 110 count
  expect_equal(u$median, 105)
})

test_that("wc_uncertainty_sentence renders the key quantities", {
  u <- wc_uncertainty_summary(c(90, 100, 110), ratio_draws = c(0.5, 1, 2), baseline = 100)
  s <- wc_uncertainty_sentence(u, unit = "urogynecologists")
  expect_true(grepl("Median 100 urogynecologists", s))
  expect_true(grepl("PI", s))
  expect_true(grepl("below replacement", s))   # ratio present -> clause shown
})

# ---- boundary values ----

test_that("a single draw yields a degenerate interval at that value", {
  u <- wc_uncertainty_summary(c(100), baseline = 100)
  expect_equal(u$median, 100)
  expect_equal(u$pi_lower, 100); expect_equal(u$pi_upper, 100)
})

test_that("all draws exactly at baseline count as both shortage and improvement (boundary)", {
  u <- wc_uncertainty_summary(rep(100, 5), baseline = 100)  # fd == baseline
  expect_equal(u$p_shortage_exceeds, 1)   # <= baseline is TRUE at equality
  expect_equal(u$p_access_improves, 1)     # >= baseline is TRUE at equality
})

test_that("interval accepts values just inside (0,1) and rejects the endpoints", {
  expect_s3_class(wc_uncertainty_summary(1:10, baseline = 5, interval = 0.99), "data.frame")
  expect_error(wc_uncertainty_summary(1:10, baseline = 5, interval = 1),   "interval")
  expect_error(wc_uncertainty_summary(1:10, baseline = 5, interval = 0),   "interval")
})

# ---- negative controls (validation must STOP) ----

test_that("invalid inputs fail loud", {
  expect_error(wc_uncertainty_summary(numeric(0), baseline = 100), "non-empty")
  expect_error(wc_uncertainty_summary(c(1, 2), baseline = 0),      "positive")
  expect_error(wc_uncertainty_summary(c(1, 2), baseline = -5),     "positive")
  expect_error(wc_uncertainty_summary(c(1, 2), baseline = 100, shortage_pct = -1), "shortage_pct")
  expect_error(wc_uncertainty_summary(c(1, 2), baseline = 100, improve_pct = -1),  "improve_pct")
  expect_error(wc_uncertainty_summary(c(1, 2), ratio_draws = c(1), baseline = 100), "match")
  expect_error(wc_uncertainty_summary(c(NA, Inf), baseline = 100), "no finite")
})
