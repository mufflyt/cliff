# Gates 39 and 40: mathematical invariants of the workforce projection engines.
#
# These are properties the model must satisfy for ANY input, not assertions
# about one committed number. A projection can reproduce its golden benchmark
# exactly and still be wrong everywhere else; these tests cover the everywhere
# else. They are pure arithmetic, need no repository material, and so also run
# against the installed package under R CMD check.
#
# Engines under test:
#   cliff:::wc_project()        deterministic age-structured cohort flow
#   cliff::wc_project_micro()   stochastic microsimulation
#
# Where an invariant is exact it is asserted exactly. Where the engine is
# stochastic it is asserted on the draws, not on a mean that could hide a
# violation by averaging over it.

HZ_LABS <- c("<45", "45-49", "50-54", "55-59", "60-64", "65-69", "70+")
hz_flat <- function(p) setNames(rep(p, length(HZ_LABS)), HZ_LABS)

# A population with mass in several bands, including both band edges.
POP <- c(34L, 44L, 45L, 49L, 50L, 59L, 60L, 64L, 65L, 69L, 70L, 71L, 80L)

# ---------------------------------------------------------------------------
# Gate 39: invariants
# ---------------------------------------------------------------------------

test_that("zero hazard and zero entrants leaves the workforce exactly unchanged", {
  r <- cliff:::wc_project(POP, entrants = 0, hz = hz_flat(0), horizon = 4L)
  expect_equal(r$active_2029, length(POP))
  expect_equal(r$departures_4yr, 0)
})

test_that("zero hazard and zero entrants is unchanged in the microsimulation too", {
  m <- cliff::wc_project_micro(POP, entrants = 0, hz = hz_flat(0), horizon = 4L,
                               n_sims = 50L, seed = 1L, stochastic_entry = FALSE)
  # Every draw, not just the mean: an averaged invariant is not an invariant.
  expect_true(all(m$active_draws == length(POP)))
  expect_true(all(m$departures_draws == 0))
})

test_that("hazard 1 retires everyone present at the first step", {
  # With hazard 1 and no entry, the cohort is empty after one year and stays so.
  r <- cliff:::wc_project(POP, entrants = 0, hz = hz_flat(1), horizon = 4L)
  expect_equal(r$active_2029, 0)
  expect_equal(r$departures_4yr, length(POP))

  m <- cliff::wc_project_micro(POP, entrants = 0, hz = hz_flat(1), horizon = 4L,
                               n_sims = 25L, seed = 2L, stochastic_entry = FALSE)
  expect_true(all(m$active_draws == 0))
  expect_true(all(m$departures_draws == length(POP)))
})

test_that("hazard boundaries are deterministic: 0 and 1 have zero variance", {
  for (p in c(0, 1)) {
    m <- cliff::wc_project_micro(POP, entrants = 0, hz = hz_flat(p), horizon = 3L,
                                 n_sims = 40L, seed = 7L, stochastic_entry = FALSE)
    expect_equal(length(unique(m$active_draws)), 1L,
                 info = paste("hazard", p, "should be deterministic"))
  }
})

test_that("more entrants cannot decrease the projected workforce", {
  hz <- hz_flat(0.05)
  prev <- -Inf
  for (e in c(0, 1, 5, 10, 50, 200)) {
    r <- cliff:::wc_project(POP, entrants = e, hz = hz, horizon = 4L)
    expect_gte(r$active_2029, prev)
    prev <- r$active_2029
  }
})

test_that("larger departure hazards cannot increase the projected workforce", {
  prev <- Inf
  for (p in c(0, 0.01, 0.05, 0.2, 0.5, 0.9, 1)) {
    r <- cliff:::wc_project(POP, entrants = 10, hz = hz_flat(p), horizon = 4L)
    expect_lte(r$active_2029, prev + 1e-9)
    prev <- r$active_2029
  }
})

test_that("larger departure hazards cannot decrease departures", {
  prev <- -Inf
  for (p in c(0, 0.01, 0.05, 0.2, 0.5, 0.9, 1)) {
    r <- cliff:::wc_project(POP, entrants = 10, hz = hz_flat(p), horizon = 4L)
    expect_gte(r$departures_4yr, prev - 1e-9)
    prev <- r$departures_4yr
  }
})

test_that("outputs are never negative", {
  for (p in c(0, 0.3, 1)) {
    for (e in c(0, 25)) {
      r <- cliff:::wc_project(POP, entrants = e, hz = hz_flat(p), horizon = 4L)
      expect_gte(r$active_2029, 0)
      expect_gte(r$departures_4yr, 0)
    }
  }
})

test_that("the projection does not depend on the order of the age vector", {
  hz <- hz_flat(0.07)
  a <- cliff:::wc_project(POP,          entrants = 12, hz = hz, horizon = 4L)
  b <- cliff:::wc_project(rev(POP),     entrants = 12, hz = hz, horizon = 4L)
  set.seed(99); c3 <- cliff:::wc_project(sample(POP), entrants = 12, hz = hz, horizon = 4L)

  expect_equal(a$active_2029, b$active_2029)
  expect_equal(a$active_2029, c3$active_2029)
  expect_equal(a$departures_4yr, b$departures_4yr)
  expect_equal(a$departures_4yr, c3$departures_4yr)
})

test_that("a longer horizon never reduces cumulative departures", {
  hz <- hz_flat(0.1)
  prev <- -Inf
  for (h in 1:6) {
    r <- cliff:::wc_project(POP, entrants = 5, hz = hz, horizon = h)
    expect_gte(r$departures_4yr, prev - 1e-9)
    prev <- r$departures_4yr
  }
})

test_that("a hazard above 1 is capped, so counts can never go negative", {
  # Nothing stops a miscalibrated hazard vector arriving with values above 1.
  # Uncapped, survivors = count * (1 - h) would be NEGATIVE -- negative people,
  # silently propagating into every downstream number. wc_haz_for() caps at 1.
  #
  # This test exists because mutation testing showed that deleting the cap
  # survived the entire suite: no fixture had ever supplied h > 1.
  hz_hot <- setNames(c(1.5, 2, 3, 10, 1.01, 5, 100), HZ_LABS)
  r <- cliff:::wc_project(POP, entrants = 0, hz = hz_hot, horizon = 4L)

  expect_gte(r$active_2029, 0)
  expect_equal(r$active_2029, 0)                    # everyone leaves at h >= 1
  expect_equal(r$departures_4yr, length(POP))       # and nobody leaves twice
})

test_that("a hazard above 1 conserves mass rather than inventing departures", {
  hz_hot <- setNames(rep(4, 7), HZ_LABS)
  for (e in c(0, 11)) {
    h <- 4L
    r <- cliff:::wc_project(POP, entrants = e, hz = hz_hot, horizon = h)
    expect_equal(r$active_2029, length(POP) + h * e - r$departures_4yr,
                 tolerance = 1e-9)
    expect_gte(r$active_2029, 0)
    expect_lte(r$departures_4yr, length(POP) + h * e + 1e-9)
  }
})

test_that("the microsimulation also caps hazards above 1", {
  hz_hot <- setNames(rep(2.5, 7), HZ_LABS)
  m <- cliff::wc_project_micro(POP, entrants = 0, hz = hz_hot, horizon = 3L,
                               n_sims = 20L, seed = 4L, stochastic_entry = FALSE)
  expect_true(all(m$active_draws == 0))
  expect_true(all(m$departures_draws == length(POP)))
})

test_that("NA ages are dropped rather than propagating", {
  m <- cliff::wc_project_micro(c(POP, NA, NA), entrants = 0, hz = hz_flat(0),
                               horizon = 2L, n_sims = 5L, seed = 3L,
                               stochastic_entry = FALSE)
  expect_true(all(m$active_draws == length(POP)))
  expect_false(any(is.na(m$active_draws)))
})

# ---------------------------------------------------------------------------
# Gate 40: mass conservation
#
#   ending workforce  ==  starting workforce + entrants admitted - departures
#
# Entrants who themselves depart within the horizon are counted in departures,
# so the identity holds regardless of when anyone arrives or leaves. Asserted
# with deterministic entry, because with Poisson entry the number admitted is
# random and the engines do not report it -- an unobserved term would make the
# identity untestable rather than true.
# ---------------------------------------------------------------------------

test_that("deterministic engine: start + entrants - departures == end", {
  for (p in c(0, 0.03, 0.25, 0.8, 1)) {
    for (e in c(0, 7, 64)) {
      for (h in c(1L, 4L, 9L)) {
        r <- cliff:::wc_project(POP, entrants = e, hz = hz_flat(p), horizon = h)
        expect_equal(r$active_2029,
                     length(POP) + h * e - r$departures_4yr,
                     tolerance = 1e-9,
                     info = sprintf("hz=%.2f entrants=%d horizon=%d", p, e, h))
      }
    }
  }
})

test_that("microsimulation: the identity holds in EVERY draw, not on average", {
  for (p in c(0, 0.2, 0.75, 1)) {
    for (e in c(0, 9)) {
      h <- 4L
      m <- cliff::wc_project_micro(POP, entrants = e, hz = hz_flat(p), horizon = h,
                                   n_sims = 60L, seed = 11L, stochastic_entry = FALSE)
      expect_true(
        all(m$active_draws + m$departures_draws == length(POP) + h * round(e)),
        info = sprintf("hz=%.2f entrants=%d: conservation violated in %d draw(s)",
                       p, e,
                       sum(m$active_draws + m$departures_draws !=
                             length(POP) + h * round(e))))
    }
  }
})

test_that("nobody is counted twice: departures never exceed everyone who existed", {
  for (p in c(0.1, 0.5, 1)) {
    e <- 20
    h <- 4L
    r <- cliff:::wc_project(POP, entrants = e, hz = hz_flat(p), horizon = h)
    expect_lte(r$departures_4yr, length(POP) + h * e + 1e-9)
  }
})
