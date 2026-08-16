# Gate 51: the M/M/s queueing mathematics behind wait-based adequacy.
#
# wait_to_adequacy() inverts a queueing model to turn an observed wait into an
# implied utilisation. That inversion is the load-bearing step for every
# adequacy number downstream, and it is exactly the kind of code that is easy
# to get subtly wrong and impossible to eyeball.
#
# Three kinds of check here:
#
#   REFERENCE   erlang_b() is computed by the numerically stable recursion
#               B(k) = aB(k-1) / (k + aB(k-1)). Correct, but nothing about it
#               looks like the definition. It is checked against the textbook
#               closed form, computed independently in log space.
#
#   PROPERTY    monotonicity, bounds and stability conditions that must hold for
#               any admissible input, not just the ones someone tabulated.
#
#   ROUND TRIP  the strongest available check on an inverse: push a known
#               utilisation through the forward model and require the inverse
#               to recover it. A wrong-but-plausible inverse fails here even
#               when every bound and monotonicity check passes.
#
# Pure arithmetic in the package, so this also runs against the installed
# package under R CMD check.

# Textbook Erlang B, independent of the production recursion:
#
#            (a^s / s!)
#   B(s,a) = ------------------
#            sum_{k=0}^{s} a^k / k!
#
# Computed in log space so the factorials do not overflow for larger s.
erlang_b_reference <- function(s, a) {
  if (a == 0) return(0)
  k <- 0:s
  log_terms <- k * log(a) - lfactorial(k)
  m <- max(log_terms)
  exp(log_terms[s + 1L] - m) / sum(exp(log_terms - m))
}

test_that("erlang_b matches the textbook closed form", {
  worst <- 0
  for (s in 1:25) {
    for (a in c(0, 0.001, 0.5, 1, 2, 5, 10, 24, 50)) {
      got <- cliff:::erlang_b(s, a)
      ref <- erlang_b_reference(s, a)
      worst <- max(worst, abs(got - ref))
    }
  }
  expect_lt(worst, 1e-10,
            label = sprintf("worst erlang_b deviation from the closed form: %.3g", worst))
})

test_that("erlang_b stays a probability", {
  for (s in 1:20) {
    for (a in c(0, 0.5, 3, 17, 100)) {
      b <- cliff:::erlang_b(s, a)
      expect_gte(b, 0)
      expect_lte(b, 1)
      expect_true(is.finite(b))
    }
  }
})

test_that("erlang_b is zero offered no load, and rises with load", {
  for (s in 1:8) expect_equal(cliff:::erlang_b(s, 0), 0)

  for (s in c(1L, 4L, 12L)) {
    prev <- -Inf
    for (a in c(0, 0.1, 1, 2, 5, 10, 40)) {
      b <- cliff:::erlang_b(s, a)
      expect_gte(b, prev - 1e-12)
      prev <- b
    }
  }
})

test_that("erlang_b falls as servers are added", {
  for (a in c(0.5, 2, 9, 30)) {
    prev <- Inf
    for (s in 1:20) {
      b <- cliff:::erlang_b(s, a)
      expect_lte(b, prev + 1e-12)
      prev <- b
    }
  }
})

test_that("erlang_c refuses an unstable queue rather than returning a number", {
  # Stationary M/M/s needs rho = a/s < 1. Returning a finite value at or above
  # saturation would be worse than failing: the number looks usable.
  for (s in c(1L, 3L, 10L)) {
    expect_error(cliff:::erlang_c(s, s),       "a < s")
    expect_error(cliff:::erlang_c(s, s + 1),   "a < s")
  }
})

test_that("erlang_c stays a probability and is never below erlang_b", {
  # C(s,a) >= B(s,a): waiting is at least as likely as blocking.
  for (s in 1:15) {
    for (frac in c(0.01, 0.2, 0.5, 0.8, 0.95, 0.999)) {
      a <- frac * s
      cc <- cliff:::erlang_c(s, a)
      bb <- cliff:::erlang_b(s, a)
      expect_gte(cc, 0)
      expect_lte(cc, 1 + 1e-12)
      expect_gte(cc, bb - 1e-12)
      expect_true(is.finite(cc))
    }
  }
})

test_that("erlang_c rises with offered load", {
  for (s in c(1L, 5L, 20L)) {
    prev <- -Inf
    for (frac in c(0.01, 0.1, 0.3, 0.5, 0.7, 0.9, 0.99)) {
      cc <- cliff:::erlang_c(s, frac * s)
      expect_gte(cc, prev - 1e-12)
      prev <- cc
    }
  }
})

test_that("queue wait is positive, finite, and rises with utilisation", {
  for (s in c(1L, 3L, 12L)) {
    for (mu in c(0.5, 1, 7)) {
      prev <- -Inf
      for (rho in c(0.05, 0.2, 0.5, 0.75, 0.9, 0.97)) {
        w <- cliff:::mmc_wait_in_queue(s, mu, rho)
        expect_true(is.finite(w))
        expect_gt(w, 0)
        expect_gte(w, prev - 1e-12)
        prev <- w
      }
    }
  }
})

test_that("queue wait scales exactly as 1/mu", {
  # Wq = C / (s * mu * (1 - rho)): doubling the service rate must halve the wait
  # exactly, not approximately.
  for (s in c(1L, 4L, 9L)) {
    for (rho in c(0.2, 0.6, 0.9)) {
      w1 <- cliff:::mmc_wait_in_queue(s, 1,  rho)
      w2 <- cliff:::mmc_wait_in_queue(s, 2,  rho)
      w10 <- cliff:::mmc_wait_in_queue(s, 10, rho)
      expect_equal(w2,  w1 / 2,  tolerance = 1e-12)
      expect_equal(w10, w1 / 10, tolerance = 1e-12)
    }
  }
})

test_that("queue wait diverges as utilisation approaches saturation", {
  s <- 4L; mu <- 1
  w <- vapply(c(0.9, 0.99, 0.999, 0.9999),
              function(r) cliff:::mmc_wait_in_queue(s, mu, r), 0)
  expect_true(all(diff(w) > 0))
  expect_gt(w[4], 100 * w[1])
})

test_that("wait_to_adequacy inverts the forward model exactly", {
  # The load-bearing property. Any inverse that is wrong but plausible fails
  # here even if every bound and monotonicity check above passes.
  for (s in c(1L, 3L, 8L)) {
    for (mu in c(0.5, 1, 4)) {
      for (rho in c(0.05, 0.25, 0.5, 0.75, 0.9, 0.97)) {
        w <- cliff:::mmc_wait_in_queue(s, mu, rho)
        got <- cliff:::wait_to_adequacy(w, mu = mu, s = s)
        lbl <- sprintf("s=%d mu=%g rho=%g", s, mu, rho)
        expect_true(got$identified, info = lbl)
        expect_equal(got$rho, rho, tolerance = 1e-6, info = lbl)
      }
    }
  }
})

test_that("wait_to_adequacy declines to identify a non-existent queue", {
  for (w in c(0, -1, -1e6)) {
    r <- cliff:::wait_to_adequacy(w, mu = 2, s = 3L)
    expect_false(r$identified)
    expect_true(is.na(r$rho))
    expect_match(r$reason, "no queue")
  }
})

test_that("wait_to_adequacy declines above the utilisation ceiling", {
  # Beyond the ceiling the mapping is so flat that a wait no longer pins down a
  # utilisation. Saying so beats returning a precise-looking number.
  s <- 3L; mu <- 1
  ceiling_wait <- cliff:::mmc_wait_in_queue(s, mu, cliff:::WAIT_ADEQUACY_RHO_CEILING)
  for (w in c(ceiling_wait, ceiling_wait * 2, ceiling_wait * 100)) {
    r <- cliff:::wait_to_adequacy(w, mu = mu, s = s)
    expect_false(r$identified)
    expect_true(is.na(r$rho))
  }
})

test_that("recovered utilisation rises with the observed wait", {
  s <- 4L; mu <- 1
  prev <- -Inf
  for (rho in c(0.1, 0.3, 0.5, 0.7, 0.85, 0.95)) {
    w <- cliff:::mmc_wait_in_queue(s, mu, rho)
    r <- cliff:::wait_to_adequacy(w, mu = mu, s = s)
    expect_true(r$identified)
    expect_gte(r$rho, prev - 1e-9)
    prev <- r$rho
  }
})

test_that("the queueing functions reject malformed input rather than coercing it", {
  expect_error(cliff:::erlang_b(0, 1))            # s >= 1
  expect_error(cliff:::erlang_b(2.5, 1))          # integer servers
  expect_error(cliff:::erlang_b(2, -1))           # non-negative load
  expect_error(cliff:::erlang_b(2, NA_real_))
  expect_error(cliff:::mmc_wait_in_queue(2, 0, 0.5))    # mu > 0
  expect_error(cliff:::mmc_wait_in_queue(2, 1, 0))      # rho > 0
  expect_error(cliff:::mmc_wait_in_queue(2, 1, 1))      # rho < 1
  expect_error(cliff:::wait_to_adequacy(1, mu = -1, s = 1L))
})
