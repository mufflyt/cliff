# Gate 42: the production engines must agree with an independent, deliberately
# obvious reference implementation (helper-workforce-reference.R).
#
# The reference resolves age bands with an explicit if-chain instead of cut(),
# and steps a plain age -> count list one year at a time instead of collapsing
# the cohort with table()/match(). It is far slower and much harder to be
# subtly wrong in. Agreement between two implementations that share no code is
# evidence; agreement between an engine and a restatement of itself is not.
#
# Two comparisons, because the engines make different claims:
#
#   wc_project()        is deterministic, so it must match the reference to
#                       floating-point tolerance. Any difference is a bug.
#
#   wc_project_micro()  is stochastic, so its mean must match the reference
#                       within Monte Carlo error. The reference IS the exact
#                       expectation of the microsimulation under deterministic
#                       entry: departures are independent Bernoulli draws, so
#                       expected counts propagate linearly.

HZ_LABS <- c("<45", "45-49", "50-54", "55-59", "60-64", "65-69", "70+")
hz_flat <- function(p) setNames(rep(p, length(HZ_LABS)), HZ_LABS)

POP <- c(34L, 44L, 45L, 49L, 50L, 59L, 60L, 64L, 65L, 69L, 70L, 71L, 80L)

test_that("the reference reproduces the band lookup exactly, including edges", {
  # Band edges are where an off-by-one would hide. Check every boundary and
  # both sides of it against the engine's own lookup.
  ages <- c(0, 1, 44, 45, 46, 49, 50, 51, 54, 55, 56, 59, 60, 61,
            64, 65, 66, 69, 70, 71, 100)
  for (a in ages) {
    expect_identical(wcref_band(a), cliff:::wc_band_of(a),
                     info = paste("age", a))
  }
})

test_that("the reference reproduces the hazard lookup, including the NA fallback", {
  hz <- setNames(c(0.01, 0.02, 0.03, 0.05, 0.09, 0.15, 0.30), HZ_LABS)
  for (a in c(0, 30, 44, 45, 49, 50, 64, 65, 69, 70, 95)) {
    expect_equal(wcref_hazard(a, hz), unname(cliff:::wc_haz_for(a, hz)),
                 info = paste("age", a))
  }
  # An age with no band (negative) must fall back to max(hz), capped at 1.
  expect_equal(wcref_hazard(-5, hz), max(hz))
})

test_that("the deterministic engine matches the reference on fixed cases", {
  cases <- expand.grid(p = c(0, 0.02, 0.1, 0.37, 0.75, 1),
                       e = c(0, 1, 12, 64),
                       h = c(1L, 4L, 8L))
  for (i in seq_len(nrow(cases))) {
    p <- cases$p[i]; e <- cases$e[i]; h <- cases$h[i]
    got <- cliff:::wc_project(POP, entrants = e, hz = hz_flat(p), horizon = h)
    ref <- wcref_project(POP, entrants = e, hz = hz_flat(p), horizon = h,
                         entry_age = cliff:::WC_ENTRY_AGE)
    lbl <- sprintf("hz=%.2f entrants=%g horizon=%d", p, e, h)
    expect_equal(got$active_2029,    ref$active,     tolerance = 1e-9, info = lbl)
    expect_equal(got$departures_4yr, ref$departures, tolerance = 1e-9, info = lbl)
  }
})

test_that("the deterministic engine matches the reference on an age-varying hazard", {
  hz <- setNames(c(0.004, 0.008, 0.015, 0.03, 0.07, 0.14, 0.28), HZ_LABS)
  for (e in c(0, 5, 64)) {
    for (h in c(1L, 4L, 10L)) {
      got <- cliff:::wc_project(POP, entrants = e, hz = hz, horizon = h)
      ref <- wcref_project(POP, entrants = e, hz = hz, horizon = h,
                           entry_age = cliff:::WC_ENTRY_AGE)
      lbl <- sprintf("entrants=%g horizon=%d", e, h)
      expect_equal(got$active_2029,    ref$active,     tolerance = 1e-9, info = lbl)
      expect_equal(got$departures_4yr, ref$departures, tolerance = 1e-9, info = lbl)
    }
  }
})

test_that("the microsimulation mean converges to the reference expectation", {
  hz <- setNames(c(0.004, 0.008, 0.015, 0.03, 0.07, 0.14, 0.28), HZ_LABS)
  for (e in c(0, 16)) {
    h <- 4L
    m <- cliff::wc_project_micro(POP, entrants = e, hz = hz, horizon = h,
                                 n_sims = 4000L, seed = 42L,
                                 stochastic_entry = FALSE)
    ref <- wcref_project(POP, entrants = e, hz = hz, horizon = h,
                         entry_age = cliff:::WC_ENTRY_AGE)

    # Tolerance from the simulation's own spread rather than a guessed constant:
    # 4 standard errors of the mean, floored so a near-deterministic case does
    # not demand impossible precision.
    se  <- stats::sd(m$active_draws) / sqrt(length(m$active_draws))
    tol <- max(4 * se, 0.25)

    expect_lt(abs(m$active_2029 - ref$active), tol,
              label = sprintf("entrants=%g: micro mean %.3f vs reference %.3f (tol %.3f)",
                              e, m$active_2029, ref$active, tol))

    se_d  <- stats::sd(m$departures_draws) / sqrt(length(m$departures_draws))
    tol_d <- max(4 * se_d, 0.25)
    expect_lt(abs(m$departures_4yr - ref$departures), tol_d,
              label = sprintf("entrants=%g: micro departures %.3f vs reference %.3f (tol %.3f)",
                              e, m$departures_4yr, ref$departures, tol_d))
  }
})

test_that("the two production engines agree with each other", {
  # wc_project() should be the expectation wc_project_micro() simulates. If
  # these two ever diverge, one of them has been changed without the other.
  hz <- setNames(c(0.004, 0.008, 0.015, 0.03, 0.07, 0.14, 0.28), HZ_LABS)
  det   <- cliff:::wc_project(POP, entrants = 16, hz = hz, horizon = 4L)
  micro <- cliff::wc_project_micro(POP, entrants = 16, hz = hz, horizon = 4L,
                                   n_sims = 4000L, seed = 5L,
                                   stochastic_entry = FALSE)
  se  <- stats::sd(micro$active_draws) / sqrt(length(micro$active_draws))
  expect_lt(abs(micro$active_2029 - det$active_2029), max(4 * se, 0.25))
})
