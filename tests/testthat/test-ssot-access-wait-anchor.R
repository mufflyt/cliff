# SSOT guard for the access-wait ANCHOR estimator (R/access_wait_anchor.R):
# a SAMPLE of observed appointment waits -> a gated access fit.
#
# Pins the properties that keep the anchor honest:
#   1. On a synthetic audit whose mean sits at a known M/M/s queue, the estimator
#      RECOVERS that adequacy and its CI covers the truth.
#   2. It inherits and sharpens wait_to_adequacy()'s refusal: it refuses a sample
#      too small to bootstrap, and (default) refuses when the bootstrap interval
#      strays into the near-balance / no-queue region rather than reporting a
#      truncated number.
#   3. The returned row IS a valid access_fit: it drops straight into the
#      capacity-evidence gate and resolves an absolute adequacy end to end.
#
# Pure base R (sources wait_adequacy.R + access_wait_anchor.R); runs in the
# minimal contract runner.
library(testthat)
library(here)

wa <- new.env()
source(here::here("R", "wait_adequacy.R"), local = wa)
source(here::here("R", "access_wait_anchor.R"), local = wa)

# A synthetic audit sample whose mean sits at a target adequacy's mean wait W_q.
synthetic_waits <- function(target_adeq, mu, s, n, shape = 4, seed = 1) {
  set.seed(seed)
  wq <- wa$mmc_wait_in_queue(s = s, mu = mu, rho = 1 / target_adeq)   # true mean wait
  stats::rgamma(n, shape = shape, scale = wq / shape)                 # E[wait] = wq
}

test_that("[recovery] a synthetic audit recovers the true adequacy", {
  waits <- synthetic_waits(target_adeq = 1.4, mu = 2, s = 6, n = 60, seed = 11)
  fit <- wa$measure_access_wait_anchor(waits, mu = 2, s = 6, n_boot = 500L, seed = 7)
  expect_true(fit$identified)
  expect_true(is.na(fit$reason))
  expect_equal(fit$adequacy, 1.4, tolerance = 0.08)      # point near the truth
  expect_lt(fit$adequacy_lo, fit$adequacy)               # interval ordered around the point
  expect_gt(fit$adequacy_hi, fit$adequacy)
  expect_gt(fit$adequacy_hi - fit$adequacy_lo, 0)        # positive width
  expect_equal(fit$frac_identified, 1)                   # nothing strayed near balance
  expect_equal(fit$n, 60L)
})

test_that("[coverage] the 95% bootstrap CI is calibrated (covers the truth ~95% of samples)", {
  # The scientific claim of the interval: over repeated audits, the 95% CI covers
  # the true adequacy about 95% of the time. Measured empirically (true ~0.95);
  # thresholded with margin so seed variation cannot flake it.
  target <- 1.4; mu <- 2; s <- 6; n <- 80; K <- 40
  covered <- 0L
  for (k in seq_len(K)) {
    waits <- synthetic_waits(target_adeq = target, mu = mu, s = s, n = n, seed = k)
    fit <- wa$measure_access_wait_anchor(waits, mu = mu, s = s, n_boot = 250L, seed = k)
    if (isTRUE(fit$identified) && fit$adequacy_lo <= target && target <= fit$adequacy_hi)
      covered <- covered + 1L
  }
  expect_gte(covered / K, 0.85)
})

test_that("[structural] the anchor never asserts a shortage (adequacy > 1 when identified)", {
  for (ta in c(1.2, 1.6, 2.5)) {
    waits <- synthetic_waits(target_adeq = ta, mu = 3, s = 8, n = 80, seed = 3)
    fit <- wa$measure_access_wait_anchor(waits, mu = 3, s = 8, n_boot = 300L, seed = 3)
    if (isTRUE(fit$identified)) expect_gt(fit$adequacy, 1)
  }
})

test_that("[refuse] a sample smaller than min_n is refused, not guessed", {
  fit <- wa$measure_access_wait_anchor(c(0.2, 0.3, 0.25), mu = 2, s = 6, min_n = 5L)
  expect_false(fit$identified)
  expect_true(is.na(fit$adequacy))
  expect_match(fit$reason, "too small")
  expect_equal(fit$n, 3L)
})

test_that("[refuse] near-balance samples (long waits) are refused, not truncated", {
  # Target adequacy just above the identified floor -> W_q enormous -> the whole
  # bootstrap sits in / near the refused band.
  waits <- synthetic_waits(target_adeq = 1.004, mu = 2, s = 6, n = 60, seed = 5)
  fit <- wa$measure_access_wait_anchor(waits, mu = 2, s = 6, n_boot = 300L, seed = 5)
  expect_false(fit$identified)
  expect_true(is.na(fit$adequacy))
  expect_lt(fit$frac_identified, 1)                      # some/all replicates refused
})

test_that("[refuse] relaxing require_full_interval reports the point but flags the fraction", {
  waits <- synthetic_waits(target_adeq = 1.05, mu = 2, s = 6, n = 80, seed = 9)
  strict  <- wa$measure_access_wait_anchor(waits, mu = 2, s = 6, n_boot = 300L, seed = 9)
  relaxed <- wa$measure_access_wait_anchor(waits, mu = 2, s = 6, n_boot = 300L, seed = 9,
                                           require_full_interval = FALSE)
  # If the point identifies but some replicates stray, strict refuses where relaxed resolves.
  if (isTRUE(relaxed$identified) && strict$frac_identified < 1) {
    expect_false(strict$identified)
    expect_gt(relaxed$adequacy, 1)
  }
  expect_true(relaxed$frac_identified <= 1)
})

test_that("negative waits are impossible and fail loud", {
  expect_error(wa$measure_access_wait_anchor(c(0.2, -0.1, 0.3, 0.4, 0.5), mu = 2, s = 6),
               "must be >= 0")
})

test_that("NA waits are dropped and counted", {
  waits <- c(synthetic_waits(1.5, mu = 2, s = 6, n = 40, seed = 2), NA, NA)
  fit <- wa$measure_access_wait_anchor(waits, mu = 2, s = 6, n_boot = 200L, seed = 2)
  expect_equal(fit$n_missing, 2L)
  expect_equal(fit$n, 40L)
})

test_that("the seed makes the bootstrap reproducible and does not perturb the caller's RNG", {
  waits <- synthetic_waits(1.4, mu = 2, s = 6, n = 50, seed = 4)
  a <- wa$measure_access_wait_anchor(waits, mu = 2, s = 6, n_boot = 200L, seed = 42)
  b <- wa$measure_access_wait_anchor(waits, mu = 2, s = 6, n_boot = 200L, seed = 42)
  expect_equal(a$adequacy_lo, b$adequacy_lo)
  expect_equal(a$adequacy_hi, b$adequacy_hi)
  # caller RNG stream is untouched by the seeded bootstrap
  set.seed(100); before <- runif(1)
  set.seed(100); wa$measure_access_wait_anchor(waits, mu = 2, s = 6, n_boot = 50L, seed = 42)
  after <- runif(1)
  expect_equal(before, after)
})

test_that("[end to end] the measured anchor resolves an absolute adequacy through the gate", {
  ce <- new.env()
  source(here::here("R", "capacity_evidence.R"), local = ce)
  source(here::here("R", "absolute_adequacy_seam.R"), local = ce)

  waits <- synthetic_waits(target_adeq = 1.5, mu = 2, s = 6, n = 80, seed = 21)
  anchor <- wa$measure_access_wait_anchor(waits, mu = 2, s = 6, n_boot = 300L, seed = 21)
  expect_true(anchor$identified)

  # A fully identified demand basis + the measured anchor -> the gate resolves.
  demand <- list(fully_identified = TRUE, total = 1000)
  proj <- data.frame(YEAR = 2025:2027, adeq_eff = c(1, 0.95, 0.90),
                     effective = c(1000, 990, 980), req_fte = c(1000, 1042, 1089))
  out <- ce$project_absolute_adequacy(proj, anchor, demand, base_year = 2025)
  expect_true(attr(out, "absolute_resolved"))
  expect_equal(attr(out, "absolute_anchor"), anchor$adequacy)
  expect_equal(out$adeq_absolute[1], anchor$adequacy)          # base-year absolute == anchor
})
