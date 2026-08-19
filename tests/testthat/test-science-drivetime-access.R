# Science invariants for the drive-time access model (Module D).
#
# These guard the SCIENTIFIC correctness of the two drive-time computations, not
# just code hygiene:
#   1. the differential drive-time metric (Herb 2021, on drive time) computed by
#      scripts/urps_module_d_differential_distance.R::compute_differential_drivetime;
#   2. the population-weighted county roll-up of the E2SFCA access surface
#      (R/access_surface.R::county_drive_time_access) -- complementary invariants
#      beyond the worked example in test-access-surface.R.
# Pure/base-R (differential needs data.table only for its data.table core), so
# the science is testable without the real Valhalla artifacts or tidyverse.
library(testthat)
library(here)

# Repository integration test: sources scripts/ and R/ from the source tree.
skip_if_no_repo()

## ── 1. differential DRIVE TIME science ───────────────────────────────────────
# differential_minutes = drive_min(county -> nearest urogyn)
#                      - drive_min(county -> nearest general OB/GYN)
test_that("[science] differential drive time is the signed urogyn-minus-OBGYN gap", {
  skip_if_not_installed("data.table")
  dt <- data.table::data.table
  # source the generator's pure functions without running its file pipeline
  env <- new.env(parent = globalenv())
  suppressWarnings(suppressMessages(
    source(here::here("scripts", "urps_module_d_differential_distance.R"),
           local = env)))
  cdd <- env$compute_differential_drivetime

  uro <- dt(GEOID = c("A", "B", "C"),  # C: urogyn only -> no differential
            minutes = c(30, 12.34, 45))
  ob  <- dt(GEOID = c("A", "B", "D"),  # D: OB/GYN only -> no differential
            minutes = c(20, 15.0, 8))
  out <- as.data.frame(cdd(uro, ob))

  # (a) INNER JOIN: only counties with BOTH layers get a differential; no
  #     fabricated rows for a county missing one provider set.
  expect_setequal(out$GEOID, c("A", "B"))

  # (b) DEFINITIONAL: differential is exactly urogyn - obgyn, rounded to 0.1 min.
  gap <- setNames(out$differential_minutes, out$GEOID)
  expect_equal(unname(gap["A"]), 10.0)          # 30 - 20  (desert: +10 min)
  expect_equal(unname(gap["B"]), round(12.34 - 15.0, 1))  # -2.7 (metro: urogyn nearer)

  # (c) SIGN REGIME: the metric is signed -- positive where subspecialty care is
  #     farther (deserts) and negative where a urogyn is as near as / nearer than
  #     the nearest generalist (dense metros). Both must be representable.
  expect_true(any(out$differential_minutes > 0))
  expect_true(any(out$differential_minutes < 0))

  # (d) ACCOUNTING round-trip: differential + OB/GYN time == urogyn time (within
  #     the 0.1-min rounding), so the gap cannot silently drift from its parts.
  expect_equal(out$differential_minutes + out$drive_minutes_to_obgyn,
               out$drive_minutes_to_urogyn, tolerance = 0.05)

  # (e) reported times are rounded to 0.1 min (no spurious precision).
  expect_equal(out$drive_minutes_to_urogyn, round(out$drive_minutes_to_urogyn, 1))
  expect_equal(out$drive_minutes_to_obgyn,  round(out$drive_minutes_to_obgyn, 1))
})

## ── 2. E2SFCA county access roll-up science ──────────────────────────────────
# county access = sum(access_i * pop_i) / sum(pop_i) over the county's tracts.
e <- new.env(); source(here::here("R", "access_surface.R"), local = e)

# One county (06075) of three tracts spanning a wide access range.
mk <- function(access, population, county = "06075")
  data.frame(demand_id = paste0(county, sprintf("%06d", seq_along(access))),
             access = access, population = population, stringsAsFactors = FALSE)

test_that("[science] a population-weighted mean is bounded by its tract inputs", {
  # A weighted mean can never exceed the max or fall below the min of its inputs;
  # a bug that summed (instead of averaged) or mis-weighted would violate this.
  s <- mk(access = c(5, 22.5, 40), population = c(120, 300, 45))
  cty <- e$county_drive_time_access(s)
  a <- cty$drive_time_access[cty$GEOID == "06075"]
  expect_gte(a, min(s$access))
  expect_lte(a, max(s$access))
  # and it equals the exact weighted mean
  expect_equal(a, sum(s$access * s$population) / sum(s$population))
})

test_that("[science] county access is invariant to the population scale (relative weights)", {
  s  <- mk(access = c(8, 26), population = c(2, 5))
  s2 <- mk(access = c(8, 26), population = c(2, 5) * 1000L)   # same relative weights
  expect_equal(e$county_drive_time_access(s)$drive_time_access,
               e$county_drive_time_access(s2)$drive_time_access)
})

test_that("[science] non-negative tract access yields non-negative county access", {
  # E2SFCA accessibility is an intensity >= 0; the roll-up must preserve that.
  s <- mk(access = c(0, 3.2, 19), population = c(50, 60, 70))
  cty <- e$county_drive_time_access(s)
  expect_true(all(cty$drive_time_access >= 0))
})

test_that("[science] non-finite tracts are dropped, never propagated into the mean", {
  # A tract with NA/Inf access or population must not poison the county value.
  good <- mk(access = c(10, 20), population = c(100, 100))          # mean 15
  bad  <- data.frame(demand_id = c("06075999998", "06075999999"),
                     access = c(NA_real_, Inf), population = c(100, NA_real_),
                     stringsAsFactors = FALSE)
  cty <- e$county_drive_time_access(rbind(good, bad))
  expect_equal(cty$drive_time_access[cty$GEOID == "06075"], 15)
  expect_equal(cty$n_tracts[cty$GEOID == "06075"], 2L)             # only the good tracts
})

test_that("[science] the county key is the 5-digit prefix of the 11-digit tract GEOID", {
  # High-FIPS county that overflows a 32-bit int if parsed numerically.
  s <- data.frame(demand_id = c("56045951100", "56045951200"),
                  access = c(4, 6), population = c(10, 30),
                  stringsAsFactors = FALSE)
  cty <- e$county_drive_time_access(s)
  expect_identical(cty$GEOID, "56045")
  expect_equal(cty$drive_time_access, (4 * 10 + 6 * 30) / 40)      # 5.5
})
