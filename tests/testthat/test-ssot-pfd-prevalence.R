# SSOT guard: age-specific PFD prevalence (R/pfd_prevalence.R). It weights population projections
# into women_with_pfd, the demand denominator; a typo here would silently move every per-100k /
# adequacy number. Guards behavior-preservation vs the original inline formula, the Nygaard values,
# range/monotonicity, and that the producer references the canonical.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

ee <- new.env(); source(here::here("R", "pfd_prevalence.R"), local = ee)

# The exact inline formula this canonical replaced, as a behavior-preservation oracle.
orig <- function(age) ifelse(age < 20, 0, ifelse(age < 40, 0.097, ifelse(age < 60, 0.265, ifelse(age < 80, 0.368, 0.497))))

test_that("canonical PFD prevalence reproduces the original age formula for all ages 0-120", {
  ages <- 0:120
  expect_equal(ee$pfd_prevalence_by_age(ages), orig(ages))
})

test_that("PFD prevalence pins at the Nygaard age-group boundaries", {
  f <- ee$pfd_prevalence_by_age
  expect_equal(f(19), 0);     expect_equal(f(20), 0.097)
  expect_equal(f(39), 0.097); expect_equal(f(40), 0.265)
  expect_equal(f(59), 0.265); expect_equal(f(60), 0.368)
  expect_equal(f(79), 0.368); expect_equal(f(80), 0.497); expect_equal(f(120), 0.497)
})

test_that("prevalence is a valid proportion, non-decreasing with age", {
  p <- ee$pfd_prevalence_by_age(seq(0, 100, 5))
  expect_true(all(p >= 0 & p <= 1))
  expect_false(is.unsorted(p))
  expect_true(all(ee$PFD_PREVALENCE_BY_AGE$prev >= 0 & ee$PFD_PREVALENCE_BY_AGE$prev <= 1))
})

test_that("[adversarial] the supply-demand producer references the canonical, not an inline formula", {
  ls <- readLines(here::here("scripts", "urps_supply_demand_national_2026-07-23.R"), warn = FALSE)
  expect_true(any(grepl("pfd_prevalence_by_age", ls)))
  expect_false(any(grepl("fifelse\\(age *< *20", ls)))   # no inline magic-number ladder remains
})
