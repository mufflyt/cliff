# Engine-equivalence gate: the scenario analysis must use cliff's ACTUAL
# wc_project(), not a lookalike. We (1) prove the loaded function is
# character-identical to the definition in R/workforce_cliff_engine.R, and
# (2) validate its numeric behaviour on a fixture battery with hand-computed
# expected values, reporting the maximum absolute and relative differences.
suppressWarnings(suppressMessages(library(testthat)))

repo_root <- function() {
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) { if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
                   p <- dirname(d); if (identical(p, d)) break; d <- p }
  getwd()
}
sdir   <- file.path(repo_root(), "scripts", "urps_baseline_scenarios")
engine <- file.path(repo_root(), "R", "workforce_cliff_engine.R")
skip_if_not(file.exists(engine), "engine not present")
source(file.path(sdir, "wc_engine_loader.R"))
eng <- load_real_wc_engine(engine)
wc_project <- eng$wc_project

test_that("the loaded wc_project IS the engine's function (structural identity)", {
  # re-extract wc_project's definition expression straight from the engine and
  # eval it independently; the body + formals must be structurally identical
  # (robust to deparse formatting) -- proving no reimplementation slipped in.
  exprs <- parse(engine)
  ref <- NULL
  for (e in exprs) if (is.call(e) && identical(e[[1L]], as.name("<-")) &&
                       is.name(e[[2L]]) && identical(as.character(e[[2L]]), "wc_project")) {
    renv <- new.env(parent = baseenv()); renv$WC_ENTRY_AGE <- 34L; renv$WC_HORIZON <- 4L
    ref <- eval(e[[3L]], renv)
  }
  expect_true(is.function(ref))
  expect_identical(body(wc_project), body(ref))       # same recurrence, exactly
  expect_identical(formals(wc_project), formals(ref)) # same signature/defaults
  for (nm in c("wc_haz_for", "wc_band_of"))
    expect_true(is.function(eng[[nm]]), info = nm)
})

# hand-computed fixtures for the REAL wc_project recurrence:
#   each year: dep += sum(count * hz_band); survivors = count*(1-hz); age+1;
#   inject `entrants` at age 34. wc_haz_for: NA band -> max(hz); hz capped at 1.
B <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
hz0   <- setNames(rep(0, 7), B)                       # zero hazard
hz1b  <- setNames(c(0,0.1,0,0,0,0,0), B)              # one band active (45-49)
fixtures <- list(
  list(name = "zero hazard, fixed entrants, horizon 4",
       ages = c(40,50,60), entrants = 10, hz = hz0, horizon = 4,
       exp_active = 3 + 4*10, exp_dep = 0),
  list(name = "one band, zero entrants, horizon 1",
       ages = c(47,48,49), entrants = 0, hz = hz1b, horizon = 1,
       exp_active = 3 * (1 - 0.1), exp_dep = 3 * 0.1),
  list(name = "boundary ages 45/50, zero entrants, horizon 1",
       ages = c(45,50), entrants = 0, hz = setNames(c(0,0.2,0.5,0,0,0,0), B), horizon = 1,
       exp_active = (1-0.2) + (1-0.5), exp_dep = 0.2 + 0.5),   # 45->"45-49"=0.2, 50->"50-54"=0.5
  list(name = "zero hazard, zero entrants, horizon 4 (pure survival)",
       ages = c(41,42,43), entrants = 0, hz = hz0, horizon = 4,
       exp_active = 3, exp_dep = 0)
)

test_that("wc_project matches hand-computed fixtures (report max abs/rel diff)", {
  ad <- rd <- 0
  for (f in fixtures) {
    r <- wc_project(f$ages, entrants = f$entrants, hz = f$hz, horizon = f$horizon)
    da <- abs(r$active_2029 - f$exp_active); dd <- abs(r$departures_4yr - f$exp_dep)
    ad <- max(ad, da, dd)
    rd <- max(rd, da / max(abs(f$exp_active), 1), dd / max(abs(f$exp_dep), 1e-9))
    expect_equal(r$active_2029, f$exp_active, tolerance = 1e-9, info = f$name)
    expect_equal(r$departures_4yr, f$exp_dep, tolerance = 1e-9, info = f$name)
  }
  message(sprintf("[equivalence] max abs diff = %.3e, max rel diff = %.3e across %d fixtures",
                  ad, rd, length(fixtures)))
  expect_lt(ad, 1e-9)
})

test_that("wc_project is deterministic and horizons compose", {
  a <- wc_project(c(40,55,66), 5, setNames(c(0.01,0.02,0.03,0.04,0.05,0.06,0.1), B), 4)
  b <- wc_project(c(40,55,66), 5, setNames(c(0.01,0.02,0.03,0.04,0.05,0.06,0.1), B), 4)
  expect_identical(a, b)                                            # deterministic
  h1 <- wc_project(c(50,50,50), 0, setNames(c(0,0,0.1,0,0,0,0), B), 1)$active_2029
  h4 <- wc_project(c(50,50,50), 0, setNames(c(0,0,0.1,0,0,0,0), B), 4)$active_2029
  expect_lt(h4, h1)                                                 # more attrition over 4 yr
})

test_that("the Monte Carlo uncertainty model is reproducible under a fixed seed", {
  BAND_EV <- c(13.058,2.853,3.508,4.002,5.192,4.388,0); BAND_PY <- c(3854,973,811,488,221,53,3)
  draw <- function() {
    hz <- stats::rbeta(7, BAND_EV + 0.5, pmax(BAND_PY - BAND_EV, 0) + 0.5)
    hz[BAND_PY == 0] <- max(hz[BAND_PY > 0]); setNames(pmin(1, hz), B)
  }
  set.seed(20260718L); a <- vapply(1:50, function(i) wc_project(c(45,55,65), 64, draw(), 4)$active_2029, numeric(1))
  set.seed(20260718L); b <- vapply(1:50, function(i) wc_project(c(45,55,65), 64, draw(), 4)$active_2029, numeric(1))
  expect_identical(a, b)                                            # same seed -> identical draws
})
