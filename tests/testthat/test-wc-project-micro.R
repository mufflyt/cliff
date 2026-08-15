# wc_project_micro() is the per-provider (individual-level) stochastic
# microsimulation refinement of the deterministic wc_project(). This guard proves
# it is REAL and CORRECT: because E[Bernoulli(h)]=h and E[Poisson(e)]=e, the mean
# of the microsimulation must converge to the deterministic projection's active_2029
# and departures. If a future edit breaks that reduction, the microsimulation is no
# longer a faithful refinement of the validated aggregate model and this fails.

suppressPackageStartupMessages(library(here))

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()
source(here::here("R", "workforce_cliff_engine.R"))

.hz  <- setNames(c(0.005, 0.008, 0.012, 0.02, 0.03, 0.05, 0.12), WC_BAND_LABELS)
.ages <- as.integer(rep(c(40, 48, 52, 58, 63, 68, 72),
                        times = c(200, 150, 120, 100, 80, 50, 30)))   # ~730 providers
.ent  <- 64

test_that("wc_project_micro mean reduces to wc_project active_2029 within Monte Carlo error", {
  det <- wc_project(.ages, .ent, .hz, horizon = 4L)
  mic <- wc_project_micro(.ages, .ent, .hz, horizon = 4L, n_sims = 4000L, seed = 42L)
  se  <- mic$active_sd / sqrt(4000)
  # agree within 3 Monte Carlo standard errors (and at least within 0.5%)
  expect_lt(abs(mic$active_2029 - det$active_2029),
            max(3 * se, 0.005 * det$active_2029))
})

test_that("wc_project_micro mean reduces to wc_project departures", {
  det <- wc_project(.ages, .ent, .hz, horizon = 4L)
  mic <- wc_project_micro(.ages, .ent, .hz, horizon = 4L, n_sims = 4000L, seed = 7L)
  expect_lt(abs(mic$departures_4yr - det$departures_4yr),
            0.03 * det$departures_4yr + 3)
})

test_that("wc_project_micro is genuinely individual-level and stochastic", {
  mic <- wc_project_micro(.ages, .ent, .hz, horizon = 4L, n_sims = 500L, seed = 1L)
  expect_gt(mic$active_sd, 0)                 # real sampling spread, not a point
  expect_length(mic$active_draws, 500L)
  expect_true(all(mic$active_draws == as.integer(mic$active_draws)))  # integer people
  expect_length(mic$active_ci, 2L)
})

test_that("deterministic-entry mode still reduces (isolates departure variance)", {
  det <- wc_project(.ages, round(.ent), .hz, horizon = 4L)
  mic <- wc_project_micro(.ages, .ent, .hz, horizon = 4L, n_sims = 3000L,
                          seed = 3L, stochastic_entry = FALSE)
  se  <- mic$active_sd / sqrt(3000)
  expect_lt(abs(mic$active_2029 - det$active_2029), max(3 * se, 0.005 * det$active_2029))
})
