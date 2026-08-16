# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# A deliberately slow, deliberately obvious reference workforce projection.
#
# Gate 42. The production engines are written for speed and concision:
# wc_project() collapses the cohort with table()/match() and vectorised
# arithmetic; wc_project_micro() simulates providers as a vector it filters and
# regrows each year. Both are correct as far as anyone knows, but "as far as
# anyone knows" is exactly the claim under test, and a test that reimplements
# the same clever trick tests nothing.
#
# So this reference is written the boring way on purpose:
#
#   * age bands resolved by an explicit if-chain, not cut(). Band edges are
#     where off-by-one errors live, and cut()'s `right = FALSE` is easy to
#     mirror by accident rather than by intent.
#   * the cohort held as an age -> count list, stepped one year at a time with
#     plain loops. No vectorisation, no matching, no tables.
#   * departures accumulated as they happen, so the conservation identity is a
#     consequence of the code rather than something asserted about it.
#
# It is far too slow for production and that is the point: it is easy to read
# and hard to be subtly wrong in. Where the reference and an engine disagree,
# neither is assumed right -- the test says so and a human decides.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Mirror of wc_band_of(), written as explicit comparisons.
# WC_BANDS = c(0, 45, 50, 55, 60, 65, 70, Inf) with right = FALSE, so every band
# is left-closed/right-open and an age below the first break is NA.
wcref_band <- function(age) {
  if (length(age) != 1L) stop("wcref_band is scalar by design")
  if (is.na(age)) return(NA_character_)
  if (age < 0)    return(NA_character_)   # cut() returns NA below the first break
  if (age < 45)   return("<45")
  if (age < 50)   return("45-49")
  if (age < 55)   return("50-54")
  if (age < 60)   return("55-59")
  if (age < 65)   return("60-64")
  if (age < 70)   return("65-69")
  if (is.infinite(age)) return(NA_character_)  # [70, Inf) excludes Inf itself
  "70+"
}

# Mirror of wc_haz_for(): band lookup, NA -> max(hz), capped at 1.
wcref_hazard <- function(age, hz) {
  b <- wcref_band(age)
  h <- if (is.na(b)) NA_real_ else unname(hz[b])
  if (length(h) != 1L || is.na(h)) h <- max(hz, na.rm = TRUE)
  min(1, h)
}

# Expected (deterministic) projection.
#
# Returns the exact expectation of the microsimulation with deterministic entry:
# departures are Bernoulli and independent, so expected counts propagate
# linearly and fractional "people" are the correct bookkeeping here.
wcref_project <- function(ages, entrants, hz, horizon, entry_age = 34L) {
  ages <- as.integer(ages[!is.na(ages)])

  cohort <- list()                       # age (character) -> count
  for (a in ages) {
    k <- as.character(a)
    cohort[[k]] <- (if (is.null(cohort[[k]])) 0 else cohort[[k]]) + 1
  }

  departures <- 0
  for (year in seq_len(horizon)) {
    nxt <- list()
    for (k in names(cohort)) {
      a <- as.integer(k)
      m <- cohort[[k]]
      h <- wcref_hazard(a, hz)

      departures <- departures + m * h
      survivors  <- m * (1 - h)

      k2 <- as.character(a + 1L)
      nxt[[k2]] <- (if (is.null(nxt[[k2]])) 0 else nxt[[k2]]) + survivors
    }
    # Entrants arrive after the departure step, so they are first exposed in the
    # following year -- matching both production engines.
    ke <- as.character(entry_age)
    nxt[[ke]] <- (if (is.null(nxt[[ke]])) 0 else nxt[[ke]]) + entrants
    cohort <- nxt
  }

  active <- 0
  for (k in names(cohort)) active <- active + cohort[[k]]

  list(active = active, departures = departures)
}

# A tiny population generator for the randomised fixtures. Deterministic given
# a seed, and biased hard toward the awkward cases: band edges, the entry age,
# empty and single-person cohorts, ages far outside anything plausible.
wcref_random_population <- function(seed) {
  set.seed(seed)
  edges <- c(0L, 44L, 45L, 49L, 50L, 54L, 55L, 59L, 60L, 64L, 65L, 69L, 70L,
             34L, 33L, 35L, 100L, 120L)
  n <- sample(0:12, 1L)
  if (n == 0L) return(integer(0))
  if (runif(1) < 0.5) sample(edges, n, replace = TRUE)
  else                as.integer(sample(25:95, n, replace = TRUE))
}

# Hazard vectors over the engine's bands, again skewed toward the extremes.
wcref_random_hazard <- function(seed) {
  set.seed(seed + 100000L)
  labs <- c("<45", "45-49", "50-54", "55-59", "60-64", "65-69", "70+")
  u <- runif(1)
  v <- if (u < 0.15) rep(0, length(labs))
       else if (u < 0.28) rep(1, length(labs))
       else if (u < 0.40) sort(runif(length(labs)))          # monotone in age
       # Hazards above 1 are nonsense as probabilities but reachable through a
       # miscalibrated input, and wc_haz_for() caps them for exactly that
       # reason. Mutation testing showed the cap was never exercised without
       # this branch: removing pmin(1, h) survived the whole suite.
       else if (u < 0.52) runif(length(labs), 0.5, 3)
       else runif(length(labs))
  setNames(v, labs)
}
