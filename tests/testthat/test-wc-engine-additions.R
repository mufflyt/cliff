# Gate for the two backward-compatible engine additions used by the URPS
# projection producer:
#   1. wc_project(..., age_shift) -- shifts the retirement-hazard curve along age
#      (retirement_shift_years); age_shift = 0 must be byte-identical to before.
#   2. wc_project_trajectory(...) -- the same recurrence, emitting per-year rows;
#      its endpoint must reproduce wc_project() exactly.
# Loader-based (pure functions, no data/IO), so it runs anywhere.
suppressWarnings(suppressMessages(library(testthat)))

repo_root <- function() {
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) { if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
                   p <- dirname(d); if (identical(p, d)) break; d <- p }
  getwd()
}
engine <- file.path(repo_root(), "R", "workforce_cliff_engine.R")
sdir   <- file.path(repo_root(), "scripts", "urps_baseline_scenarios")
skip_if_not(file.exists(engine), "engine not present")
source(file.path(sdir, "wc_engine_loader.R"))
eng <- load_real_wc_engine(engine)

B    <- eng$WC_BAND_LABELS
hz   <- setNames(c(0.01, 0.02, 0.03, 0.05, 0.09, 0.16, 0.30), B)
ages <- rep(35:75, each = 5L)          # a fixed, deterministic age structure
ent  <- 64                             # WC_ENTRANTS["URPS"] = mean(61,66,63,66)

test_that("age_shift default is 0 and is byte-identical to an explicit 0", {
  for (H in c(1L, 4L, 17L))
    expect_identical(eng$wc_project(ages, ent, hz, horizon = H),
                     eng$wc_project(ages, ent, hz, horizon = H, age_shift = 0L))
})

test_that("wc_project_trajectory reproduces wc_project's endpoint exactly", {
  for (H in c(1L, 4L, 17L)) for (sh in c(0L, -2L, -5L, 2L)) {
    tr <- eng$wc_project_trajectory(ages, ent, hz, horizon = H, age_shift = sh)
    pr <- eng$wc_project(ages, ent, hz, horizon = H, age_shift = sh)
    expect_equal(nrow(tr), H)
    expect_setequal(names(tr), c("step", "active", "entrants", "departures"))
    expect_equal(tr$active[H], pr$active_2029)                 # final headcount matches
    expect_equal(sum(tr$departures), pr$departures_4yr)        # total exits match
    expect_equal(tr$entrants, rep(ent, H))                     # entrants injected each year
    expect_true(all(tr$departures >= 0))
  }
})

test_that("net flow reconciles within the trajectory (supply moves by entrants - exits)", {
  tr <- eng$wc_project_trajectory(ages, ent, hz, horizon = 17L, age_shift = -2L)
  # active[t] = active[t-1] + entrants - departures[t]; seed prior with the start count
  start <- length(ages)
  prev <- c(start, utils::head(tr$active, -1))
  expect_equal(tr$active, prev + tr$entrants - tr$departures)
})

test_that("age_shift moves retirement the right way: earlier -> fewer survivors", {
  surv <- vapply(c(-5L, -2L, 0L, 2L),
                 function(s) eng$wc_project(ages, ent, hz, horizon = 17L, age_shift = s)$active_2029,
                 numeric(1))
  expect_true(all(diff(surv) > 0))     # -5 < -2 < 0 < +2 in survivors
})
