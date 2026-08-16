# Gate 41: randomised adversarial fixtures for the workforce engines.
#
# The fixed-case tests check the model where someone thought to look. These
# generate several hundred small populations skewed hard toward the awkward
# places -- band edges, the entry age, ages far outside anything plausible,
# empty and single-person cohorts, duplicate people, hazards pinned at 0 and 1 --
# and assert the invariants on every one.
#
# Deterministic by construction: each fixture is seeded by its index, so a
# failure names an exact reproducible case rather than "it failed sometimes".
# Nothing here reads the repository, so it also runs under R CMD check against
# the installed package.

HZ_LABS <- c("<45", "45-49", "50-54", "55-59", "60-64", "65-69", "70+")

N_FIXTURES <- 300L

test_that("randomised fixtures: engine agrees with the reference implementation", {
  worst <- 0
  worst_at <- NA_integer_
  checked <- 0L

  for (i in seq_len(N_FIXTURES)) {
    ages <- wcref_random_population(i)
    hz   <- wcref_random_hazard(i)
    set.seed(i + 500000L)
    entrants <- sample(c(0, 0, 1, 3, 17, 64, 500), 1L)
    horizon  <- sample(1:6, 1L)

    got <- cliff:::wc_project(ages, entrants = entrants, hz = hz, horizon = horizon)
    ref <- wcref_project(ages, entrants = entrants, hz = hz, horizon = horizon,
                         entry_age = cliff:::WC_ENTRY_AGE)

    d <- max(abs(got$active_2029 - ref$active),
             abs(got$departures_4yr - ref$departures))
    if (d > worst) { worst <- d; worst_at <- i }
    checked <- checked + 1L
  }

  expect_equal(checked, N_FIXTURES)
  expect_lt(worst, 1e-9,
            label = sprintf("worst engine-vs-reference disagreement %.3g at fixture %d",
                            worst, worst_at))
})

test_that("randomised fixtures: mass is conserved in every case", {
  bad <- integer(0)
  for (i in seq_len(N_FIXTURES)) {
    ages <- wcref_random_population(i)
    hz   <- wcref_random_hazard(i)
    set.seed(i + 500000L)
    entrants <- sample(c(0, 0, 1, 3, 17, 64, 500), 1L)
    horizon  <- sample(1:6, 1L)

    r <- cliff:::wc_project(ages, entrants = entrants, hz = hz, horizon = horizon)
    lhs <- r$active_2029 + r$departures_4yr
    rhs <- length(ages) + horizon * entrants
    if (abs(lhs - rhs) > 1e-9) bad <- c(bad, i)
  }
  expect_equal(bad, integer(0),
               label = paste("conservation violated at fixture(s):",
                             paste(bad, collapse = ", ")))
})

test_that("randomised fixtures: outputs stay non-negative and finite", {
  bad <- integer(0)
  for (i in seq_len(N_FIXTURES)) {
    ages <- wcref_random_population(i)
    hz   <- wcref_random_hazard(i)
    set.seed(i + 500000L)
    entrants <- sample(c(0, 0, 1, 3, 17, 64, 500), 1L)
    r <- cliff:::wc_project(ages, entrants = entrants, hz = hz, horizon = 4L)
    if (!is.finite(r$active_2029) || !is.finite(r$departures_4yr) ||
        r$active_2029 < -1e-9 || r$departures_4yr < -1e-9) bad <- c(bad, i)
  }
  expect_equal(bad, integer(0),
               label = paste("non-finite or negative output at fixture(s):",
                             paste(bad, collapse = ", ")))
})

test_that("randomised fixtures: age order never changes the answer", {
  bad <- integer(0)
  for (i in seq_len(N_FIXTURES)) {
    ages <- wcref_random_population(i)
    if (length(ages) < 2L) next
    hz <- wcref_random_hazard(i)
    a <- cliff:::wc_project(ages,      entrants = 10, hz = hz, horizon = 4L)
    b <- cliff:::wc_project(rev(ages), entrants = 10, hz = hz, horizon = 4L)
    if (abs(a$active_2029 - b$active_2029) > 1e-9) bad <- c(bad, i)
  }
  expect_equal(bad, integer(0),
               label = paste("order-dependence at fixture(s):",
                             paste(bad, collapse = ", ")))
})

test_that("randomised fixtures: monotone in entrants and in hazard", {
  bad_e <- integer(0); bad_h <- integer(0)
  for (i in seq_len(120L)) {
    ages <- wcref_random_population(i)
    hz   <- wcref_random_hazard(i)

    lo <- cliff:::wc_project(ages, entrants = 1,  hz = hz, horizon = 4L)
    hi <- cliff:::wc_project(ages, entrants = 40, hz = hz, horizon = 4L)
    if (hi$active_2029 < lo$active_2029 - 1e-9) bad_e <- c(bad_e, i)

    soft <- setNames(pmin(1, hz * 0.5), HZ_LABS)
    hard <- setNames(pmin(1, hz * 2.0), HZ_LABS)
    a <- cliff:::wc_project(ages, entrants = 10, hz = soft, horizon = 4L)
    b <- cliff:::wc_project(ages, entrants = 10, hz = hard, horizon = 4L)
    if (b$active_2029 > a$active_2029 + 1e-9) bad_h <- c(bad_h, i)
  }
  expect_equal(bad_e, integer(0),
               label = paste("more entrants reduced the workforce at:",
                             paste(bad_e, collapse = ", ")))
  expect_equal(bad_h, integer(0),
               label = paste("a harsher hazard grew the workforce at:",
                             paste(bad_h, collapse = ", ")))
})

test_that("randomised fixtures: the microsimulation conserves mass in every draw", {
  # A smaller sample: the microsimulation is orders of magnitude slower, and the
  # deterministic engine above already covers the space densely.
  for (i in seq_len(25L)) {
    ages <- wcref_random_population(i)
    if (!length(ages)) next          # micro requires a non-empty cohort by design
    hz <- wcref_random_hazard(i)
    entrants <- 5; horizon <- 3L

    m <- cliff::wc_project_micro(ages, entrants = entrants, hz = hz,
                                 horizon = horizon, n_sims = 20L, seed = i,
                                 stochastic_entry = FALSE)
    expect_true(
      all(m$active_draws + m$departures_draws ==
            length(ages) + horizon * round(entrants)),
      info = sprintf("fixture %d: conservation violated in the microsimulation", i))
  }
})

# ---------------------------------------------------------------------------
# Named pathological cases, asserted explicitly rather than left to chance.
# ---------------------------------------------------------------------------

test_that("an empty cohort projects the entrant stream alone", {
  hz <- setNames(rep(0, 7), HZ_LABS)
  r <- cliff:::wc_project(integer(0), entrants = 5, hz = hz, horizon = 4L)
  expect_equal(r$active_2029, 20)      # 4 years x 5, none departing
  expect_equal(r$departures_4yr, 0)
})

test_that("the microsimulation refuses an empty cohort rather than guessing", {
  hz <- setNames(rep(0.1, 7), HZ_LABS)
  expect_error(
    cliff::wc_project_micro(integer(0), entrants = 5, hz = hz, horizon = 4L,
                            n_sims = 2L),
    "length\\(ages\\)")
})

test_that("a one-person cohort behaves like the reference", {
  hz <- setNames(c(0.01, 0.02, 0.03, 0.05, 0.09, 0.15, 0.30), HZ_LABS)
  for (a in c(0L, 34L, 44L, 45L, 69L, 70L, 120L)) {
    got <- cliff:::wc_project(a, entrants = 0, hz = hz, horizon = 4L)
    ref <- wcref_project(a, entrants = 0, hz = hz, horizon = 4L,
                         entry_age = cliff:::WC_ENTRY_AGE)
    expect_equal(got$active_2029, ref$active, tolerance = 1e-9,
                 info = paste("single provider aged", a))
  }
})

test_that("duplicate providers are counted once each, not collapsed", {
  hz <- setNames(rep(0, 7), HZ_LABS)
  for (n in c(1L, 5L, 50L)) {
    r <- cliff:::wc_project(rep(60L, n), entrants = 0, hz = hz, horizon = 4L)
    expect_equal(r$active_2029, n)
  }
})

test_that("an entrant stream of zero leaves a decaying cohort only", {
  hz <- setNames(rep(0.5, 7), HZ_LABS)
  r <- cliff:::wc_project(rep(50L, 16), entrants = 0, hz = hz, horizon = 4L)
  expect_equal(r$active_2029, 16 * 0.5^4, tolerance = 1e-9)
})

test_that("ages outside every band fall back to the maximum hazard", {
  hz <- setNames(c(0.01, 0.02, 0.03, 0.05, 0.09, 0.15, 0.30), HZ_LABS)
  # A negative age has no band; wc_haz_for() falls back to max(hz).
  r <- cliff:::wc_project(-5L, entrants = 0, hz = hz, horizon = 1L)
  expect_equal(r$departures_4yr, max(hz), tolerance = 1e-9)
})
