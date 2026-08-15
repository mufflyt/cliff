# SSOT guard for the wait-time -> adequacy inversion (R/wait_adequacy.R).
#
# Pins the identifiability ceiling, checks the queueing math against closed-form
# M/M/1 identities, and — the point of the module — asserts the estimator is
# STRUCTURALLY incapable of manufacturing a shortage (adequacy <= 1) from a wait
# time, and refuses in the near-balance region instead of fabricating a number.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

wa <- new.env()
source(here::here("R", "wait_adequacy.R"), local = wa)

test_that("the identifiability ceiling is pinned and well-formed", {
  expect_type(wa$WAIT_ADEQUACY_RHO_CEILING, "double")
  expect_length(wa$WAIT_ADEQUACY_RHO_CEILING, 1L)
  expect_identical(wa$WAIT_ADEQUACY_RHO_CEILING, 0.99)
  expect_gt(wa$WAIT_ADEQUACY_RHO_CEILING, 0)
  expect_lt(wa$WAIT_ADEQUACY_RHO_CEILING, 1)
  # the adequacy floor is exactly the algebraic image of the utilisation ceiling
  expect_equal(wa$WAIT_ADEQUACY_MIN_IDENTIFIED, 1 / wa$WAIT_ADEQUACY_RHO_CEILING)
  expect_gt(wa$WAIT_ADEQUACY_MIN_IDENTIFIED, 1)
})

test_that("[closed form] Erlang-C reduces to the known M/M/1 identity C(1, a) = a", {
  for (a in c(0.1, 0.5, 0.9)) expect_equal(wa$erlang_c(1, a), a)
  # Erlang-B/C basic bounds
  expect_gte(wa$erlang_b(3, 2), 0); expect_lte(wa$erlang_b(3, 2), 1)
  expect_gte(wa$erlang_c(3, 2), 0); expect_lte(wa$erlang_c(3, 2), 1)
  # unstable load (a >= s) is rejected loudly
  expect_error(wa$erlang_c(2, 2))
})

test_that("[closed form] M/M/1 mean wait matches W_q = lambda / (mu (mu - lambda))", {
  mu <- 3; rho <- 0.6; lambda <- rho * mu
  expect_equal(wa$mmc_wait_in_queue(s = 1, mu = mu, rho = rho),
               lambda / (mu * (mu - lambda)))
})

test_that("mean wait is strictly increasing in utilisation (unique invertible root)", {
  rhos <- seq(0.05, 0.95, by = 0.05)
  wq <- vapply(rhos, function(r) wa$mmc_wait_in_queue(s = 4, mu = 2, rho = r), numeric(1))
  expect_true(all(diff(wq) > 0))
})

test_that("[round trip] inverting a forward-simulated wait recovers rho and adequacy", {
  for (params in list(list(s = 1L, mu = 3, rho = 0.6),
                      list(s = 4L, mu = 2, rho = 0.8),
                      list(s = 7L, mu = 5, rho = 0.5))) {
    w  <- wa$mmc_wait_in_queue(params$s, params$mu, params$rho)
    r  <- wa$wait_to_adequacy(wait = w, mu = params$mu, s = params$s)
    expect_true(r$identified)
    expect_equal(r$rho, params$rho, tolerance = 1e-6)
    expect_equal(r$adequacy, 1 / params$rho, tolerance = 1e-6)
    expect_gt(r$adequacy, 1)                       # surplus region, always
  }
})

test_that("[refusal] wait time never manufactures a shortage: adequacy is always > 1 or NA", {
  # sweep a wide range of observed waits, server counts, and service rates
  grid <- expand.grid(wait = c(1e-3, 0.01, 0.1, 0.5, 1, 5, 50, 1e4),
                      mu = c(1, 2, 5), s = c(1L, 3L, 8L))
  for (i in seq_len(nrow(grid))) {
    r <- wa$wait_to_adequacy(wait = grid$wait[i], mu = grid$mu[i], s = grid$s[i])
    if (isTRUE(r$identified)) {
      expect_false(is.na(r$adequacy))
      expect_gt(r$adequacy, 1)                     # never <= 1 when it commits
      expect_gte(r$adequacy, wa$WAIT_ADEQUACY_MIN_IDENTIFIED)
    } else {
      expect_true(is.na(r$adequacy))               # refused, not faked
      expect_false(is.na(r$reason))
    }
  }
})

test_that("[refusal] the near-balance region is declined, not pinned", {
  # a wait far beyond the wait at the ceiling utilisation must be refused
  w_ceiling <- wa$mmc_wait_in_queue(s = 4, mu = 2, rho = wa$WAIT_ADEQUACY_RHO_CEILING)
  r <- wa$wait_to_adequacy(wait = w_ceiling * 10, mu = 2, s = 4)
  expect_false(r$identified)
  expect_true(is.na(r$adequacy))
  expect_match(r$reason, "not identified")
})

test_that("[edge] a non-positive wait is reported as unbounded surplus, not adequacy = Inf", {
  r <- wa$wait_to_adequacy(wait = 0, mu = 2, s = 4)
  expect_false(r$identified)
  expect_true(is.na(r$adequacy))
  expect_match(r$reason, "unbounded")
})

test_that("[contract] the return shape is a stable one-row frame with the documented columns", {
  r <- wa$wait_to_adequacy(wait = 0.5, mu = 2, s = 4)
  expect_s3_class(r, "data.frame")
  expect_identical(nrow(r), 1L)
  expect_identical(names(r),
                   c("wait", "mu", "s", "rho", "adequacy", "identified", "reason"))
  expect_type(r$identified, "logical")
})
