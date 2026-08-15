# tests/testthat/test-demand-lifecourse.R
# Guards for the reproductive life-course demand model (population + exposure +
# parameter tables). See DEMAND_LIFECOURSE_MODEL_SPEC.md.

library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

source(here::here("demand_lifecourse/demand-population.R"))
source(here::here("demand_lifecourse/demand-birth_history.R"))

test_that("population layer returns non-negative female pop with a birth-cohort axis", {
  pop <- lifecourse_population("mid")
  expect_true(all(c("year", "age", "birth_cohort", "n_women") %in% names(pop)))
  expect_true(all(pop$n_women >= 0))
  expect_true(all(pop$age >= PFD_MODEL_AGE_MIN))
  expect_equal(pop$birth_cohort, pop$year - pop$age)
})

test_that("cesarean interpolation is bounded and clamps outside the anchor range", {
  r <- cesarean_rate_for_year(c(1965, 1996, 2009, 2024))
  expect_true(all(r > 0 & r < 1))
  # clamp: before first / after last anchor returns the endpoint values
  expect_equal(cesarean_rate_for_year(1900), cesarean_rate_for_year(1965))
  expect_equal(cesarean_rate_for_year(2100), cesarean_rate_for_year(2024))
})

test_that("cohort exposure decomposes parity into vaginal + cesarean", {
  ex <- cohort_vaginal_exposure(c(1935, 1965, 1985))
  # vaginal + cesarean deliveries reconstruct total parity
  expect_equal(ex$mean_vaginal_deliveries + ex$mean_cesarean_deliveries,
               ex$mean_total_parity, tolerance = 1e-6)
  expect_true(all(ex$cohort_cesarean_fraction >= 0 & ex$cohort_cesarean_fraction <= 1))
})

test_that("later cohorts carry less vaginal-delivery exposure (the core signal)", {
  ex <- cohort_vaginal_exposure(c(1935, 1950, 1965, 1975, 1985))
  # monotonic decline in mean vaginal deliveries across these cohorts
  expect_true(all(diff(ex$mean_vaginal_deliveries) < 0))
  # and the cesarean fraction rises monotonically
  expect_true(all(diff(ex$cohort_cesarean_fraction) > 0))
})

test_that("attach_birth_history joins exposure onto every population cell", {
  pop <- lifecourse_population("mid")
  j <- attach_birth_history(pop)
  expect_equal(nrow(j), nrow(pop))
  expect_false(any(is.na(j$mean_vaginal_deliveries)))
})

test_that("parameter tables load with the documented schema and cite every row", {
  base <- here::here("demand_lifecourse/params")
  dose <- read.csv(file.path(base, "parity_disease_dose_response.csv"))
  mods <- read.csv(file.path(base, "risk_modifiers.csv"))
  path <- read.csv(file.path(base, "care_pathway.csv"))
  staff <- read.csv(file.path(base, "staffing_conversion.csv"))

  expect_true(all(c("condition", "effect_size", "confidence", "source") %in% names(dose)))
  # no row may be missing a source citation
  for (df in list(dose, mods, path, staff)) {
    expect_true(all(nzchar(trimws(df$source))))
  }
  # confidence grades are drawn from the documented vocabulary
  expect_true(all(dose$confidence %in% c("high", "medium", "low")))
  # the landmark POP mode-of-delivery estimate is present and in range
  gy <- dose[dose$source |> grepl(pattern = "Gyhagen") & dose$condition == "POP", ]
  expect_true(any(gy$effect_size > 2 & gy$effect_size < 3))
})
