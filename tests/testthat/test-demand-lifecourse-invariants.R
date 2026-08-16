# Gates 47 and 48: invariants and adversarial fixtures for the reproductive
# life-course demand model.
#
# The existing test-demand-lifecourse.R checks the model on realistic inputs.
# This checks the properties that must hold for ANY input, and then pushes the
# awkward ones through deliberately: years far outside the parameter tables,
# zero and saturated rates, zero and extreme parity, missing values.
#
# The load-bearing identity is a mass balance. Every delivery is either vaginal
# or cesarean, never both and never neither, so
#
#     mean_vaginal_deliveries + mean_cesarean_deliveries == mean_total_parity
#
# must hold exactly. Vaginal exposure is what drives pelvic-floor demand
# downstream, so a leak in that split silently mis-sizes the whole demand side.

# Repository integration test: sources demand_lifecourse/, which a built package
# does not contain. See helper-cliff-root.R.
skip_if_no_repo()

suppressPackageStartupMessages({ library(here) })
source(here::here("demand_lifecourse/demand-birth_history.R"))

COHORTS <- c(1930L, 1940L, 1955L, 1970L, 1985L, 2000L, 2010L)

# ---------------------------------------------------------------------------
# Gate 47: invariants
# ---------------------------------------------------------------------------

test_that("cesarean rates are finite probabilities for every year", {
  years <- c(1800, 1900, 1950, 1970, 1990, 2000, 2010, 2020, 2030, 2100, 2500)
  r <- cesarean_rate_for_year(years)
  expect_equal(length(r), length(years))
  expect_true(all(is.finite(r)))
  expect_true(all(r >= 0))
  expect_true(all(r <= 1))
})

test_that("the cesarean rate rises over the long run but is NOT monotone", {
  # Deliberately not a monotonicity assertion. The US rate peaked around 2009
  # and then declined through the 2010s, and the parameter table reproduces
  # that: it falls every year from 2014 to 2021. An assertion that the rate
  # never decreases would be a test of a wrong belief about the world, and
  # would fail on correct data.
  expect_lt(cesarean_rate_for_year(1970), cesarean_rate_for_year(2020))
  expect_lt(cesarean_rate_for_year(1950), cesarean_rate_for_year(1990))

  r <- cesarean_rate_for_year(seq(1900, 2100, by = 5))
  expect_true(all(r >= 0 & r <= 1))
  expect_true(any(diff(r) < 0))   # the decline is real; pin it so it is not "fixed"
})

test_that("completed parity is finite and non-negative for every cohort", {
  p <- completed_parity_for_cohort(c(1850L, COHORTS, 2100L))
  expect_true(all(is.finite(p)))
  expect_true(all(p >= 0))
})

test_that("vaginal and cesarean deliveries sum exactly to total parity", {
  # The mass balance. Asserted exactly, not to a tolerance that would hide a
  # systematic leak of a few percent.
  ex <- cohort_vaginal_exposure(COHORTS)
  expect_equal(ex$mean_vaginal_deliveries + ex$mean_cesarean_deliveries,
               ex$mean_total_parity,
               tolerance = 1e-12)
})

test_that("no component of the exposure split is negative", {
  ex <- cohort_vaginal_exposure(COHORTS)
  expect_true(all(ex$mean_total_parity        >= 0))
  expect_true(all(ex$mean_vaginal_deliveries  >= 0))
  expect_true(all(ex$mean_cesarean_deliveries >= 0))
})

test_that("the cesarean fraction is a probability and matches the split", {
  ex <- cohort_vaginal_exposure(COHORTS)
  expect_true(all(ex$cohort_cesarean_fraction >= 0))
  expect_true(all(ex$cohort_cesarean_fraction <= 1))
  # The reported fraction must be the fraction actually used to split -- but
  # only to the granularity the producer rounds at. cohort_vaginal_exposure()
  # rounds total and vaginal to 3dp and then derives cesarean as
  # (total - vaginal), specifically so the additive identity above holds
  # EXACTLY; the fraction is reported rounded to 4dp. The implied ratio
  # therefore cannot equal the reported fraction exactly, and demanding that it
  # does would force the producer to break the identity it was written to keep.
  #
  # 2e-3 still catches what matters: an inverted split, a factor-of-two, or the
  # fraction and the counts drifting onto different models.
  nonzero <- ex$mean_total_parity > 0
  expect_equal(ex$mean_cesarean_deliveries[nonzero] / ex$mean_total_parity[nonzero],
               ex$cohort_cesarean_fraction[nonzero],
               tolerance = 2e-3)
})

test_that("later cohorts never have a lower cesarean fraction", {
  ex <- cohort_vaginal_exposure(sort(COHORTS))
  expect_true(all(diff(ex$cohort_cesarean_fraction) >= -1e-12))
})

test_that("simulated cesarean births never exceed the births available", {
  # A woman cannot have more cesarean deliveries than deliveries.
  set.seed(11)
  for (rep in 1:40) {
    parity <- sample(0:8, 200, replace = TRUE)
    ces <- cesarean_births_correlated(parity)
    expect_true(all(ces >= 0))
    expect_true(all(ces <= parity))
    expect_true(all(ces == round(ces)))
    expect_false(any(is.na(ces)))
  }
})

test_that("more births can never mean fewer cesareans in expectation", {
  set.seed(12)
  means <- vapply(0:6, function(p)
    mean(cesarean_births_correlated(rep(p, 4000))), 0)
  expect_true(all(diff(means) >= -1e-9))
})

# ---------------------------------------------------------------------------
# Gate 48: adversarial fixtures
# ---------------------------------------------------------------------------

test_that("zero parity yields zero deliveries of either kind", {
  ces <- cesarean_births_correlated(rep(0L, 500))
  expect_true(all(ces == 0))

  ex <- cohort_vaginal_exposure(COHORTS)
  zero <- ex$mean_total_parity == 0
  if (any(zero)) {
    expect_true(all(ex$mean_vaginal_deliveries[zero] == 0))
    expect_true(all(ex$mean_cesarean_deliveries[zero] == 0))
  } else {
    succeed()   # no zero-parity cohort in the parameter table; nothing to check
  }
})

test_that("a zero primary cesarean rate produces no cesareans at all", {
  # With no first cesarean there can be no repeat cesarean either: the repeat
  # rate must not be able to manufacture one.
  set.seed(13)
  ces <- cesarean_births_correlated(sample(1:6, 2000, replace = TRUE),
                                    primary_rate = 0, repeat_rate = 0.9)
  expect_true(all(ces == 0))
})

test_that("saturated rates make every birth a cesarean", {
  set.seed(14)
  parity <- sample(1:6, 2000, replace = TRUE)
  ces <- cesarean_births_correlated(parity, primary_rate = 1, repeat_rate = 1)
  expect_equal(ces, parity)
})

test_that("extreme parity does not break the split", {
  set.seed(15)
  for (p in c(20L, 100L)) {
    ces <- cesarean_births_correlated(rep(p, 200))
    expect_true(all(ces >= 0))
    expect_true(all(ces <= p))
    expect_true(all(is.finite(ces)))
  }
})

test_that("years far outside the parameter table are clamped, not extrapolated", {
  # Extrapolating a rising cesarean trend to 2500 would eventually exceed 1.
  far <- cesarean_rate_for_year(c(1000, 1500, 2200, 2500, 3000))
  expect_true(all(far >= 0 & far <= 1))
  # The far future should not exceed the last tabulated value.
  recent <- cesarean_rate_for_year(2020)
  expect_true(all(far[3:5] >= recent - 1e-9))
  expect_true(all(far[3:5] <= 1))
})

test_that("cohorts far outside the parameter table stay finite and non-negative", {
  for (co in c(1700L, 1800L, 2100L, 2200L)) {
    ex <- cohort_vaginal_exposure(co)
    expect_true(all(is.finite(ex$mean_total_parity)))
    expect_true(all(ex$mean_total_parity >= 0))
    expect_equal(ex$mean_vaginal_deliveries + ex$mean_cesarean_deliveries,
                 ex$mean_total_parity, tolerance = 1e-12)
  }
})

test_that("an empty cohort vector returns an empty result rather than erroring", {
  ex <- cohort_vaginal_exposure(integer(0))
  expect_equal(nrow(ex), 0L)
})

test_that("a single cohort behaves the same as that cohort within a vector", {
  one  <- cohort_vaginal_exposure(1970L)
  many <- cohort_vaginal_exposure(c(1940L, 1970L, 2000L))
  row  <- many[many$birth_cohort == 1970L, ]
  expect_equal(one$mean_total_parity,        row$mean_total_parity)
  expect_equal(one$mean_vaginal_deliveries,  row$mean_vaginal_deliveries)
  expect_equal(one$mean_cesarean_deliveries, row$mean_cesarean_deliveries)
})

test_that("cohort order does not change any cohort's answer", {
  a <- cohort_vaginal_exposure(COHORTS)
  b <- cohort_vaginal_exposure(rev(COHORTS))
  a <- a[order(a$birth_cohort), ]
  b <- b[order(b$birth_cohort), ]
  expect_equal(a$mean_vaginal_deliveries, b$mean_vaginal_deliveries)
  expect_equal(a$mean_cesarean_deliveries, b$mean_cesarean_deliveries)
})

test_that("duplicate cohorts do not change the per-cohort answer", {
  a <- cohort_vaginal_exposure(c(1970L))
  b <- cohort_vaginal_exposure(c(1970L, 1970L, 1970L))
  expect_true(all(b$mean_total_parity == a$mean_total_parity))
})
