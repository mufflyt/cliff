# Benchmark reproduction test (item 8: publish benchmark datasets every commit
# must reproduce). Re-runs the real projection engine on the FROZEN benchmark
# inputs (benchmark/urps_cohort_ages_v3.0.0.csv) at the published parameters and
# asserts it still lands on the FROZEN golden outputs (benchmark/
# urps_projection_golden.csv). An accidental change to the engine, the age-band
# hazards, or the graduate counts fails here instead of silently moving a
# published number.
#
# To intentionally re-freeze after a reviewed change:
#   Rscript benchmark/generate_urps_benchmark.R
# then commit the updated benchmark/ fixtures with the code change.

suppressPackageStartupMessages({ library(here) })

bdir <- here::here("benchmark")
ages_csv   <- file.path(bdir, "urps_cohort_ages_v3.0.0.csv")
golden_csv <- file.path(bdir, "urps_projection_golden.csv")

test_that("the benchmark fixtures exist and are well-formed", {
  expect_true(file.exists(ages_csv))
  expect_true(file.exists(golden_csv))
  ages <- utils::read.csv(ages_csv)
  expect_setequal(names(ages), c("age", "n_active_2023"))
  expect_true(all(ages$n_active_2023 >= 0))
  g <- utils::read.csv(golden_csv, stringsAsFactors = FALSE)
  expect_true(all(c("baseline", "projected_2029", "departures_4yr",
                    "band_ev", "band_py", "grad_urps", "horizon", "entrants_annual") %in% names(g)))
})

test_that("the real engine reproduces the frozen golden projection", {
  eng_loader <- here::here("scripts", "urps_baseline_scenarios", "wc_engine_loader.R")
  skip_if_not(file.exists(eng_loader), "engine loader not present")
  source(eng_loader)
  eng <- load_real_wc_engine(here::here("R", "workforce_cliff_engine.R"))

  ages_tab <- utils::read.csv(ages_csv)
  ages <- rep(ages_tab$age, ages_tab$n_active_2023)
  g <- utils::read.csv(golden_csv, stringsAsFactors = FALSE)

  # frozen parameters travel WITH the golden row, so the test is self-contained
  band_ev <- as.numeric(strsplit(g$band_ev, ";")[[1]])
  band_py <- as.numeric(strsplit(g$band_py, ";")[[1]])
  grad    <- as.numeric(strsplit(g$grad_urps, ";")[[1]])
  hz <- setNames(ifelse(band_py > 0, band_ev / band_py, 0), eng$WC_BAND_LABELS)

  # baseline cohort size must match the frozen baseline exactly
  expect_equal(length(ages), g$baseline)
  expect_equal(mean(grad), g$entrants_annual)

  r <- eng$wc_project(ages, entrants = mean(grad), hz = hz, horizon = g$horizon)

  # deterministic engine -> reproduce to floating-point tolerance
  expect_equal(r$active_2029,   g$projected_2029, tolerance = 1e-6)
  expect_equal(r$departures_4yr, g$departures_4yr, tolerance = 1e-6)
})

test_that("a drift in the hazards would break reproduction (negative control)", {
  eng_loader <- here::here("scripts", "urps_baseline_scenarios", "wc_engine_loader.R")
  skip_if_not(file.exists(eng_loader), "engine loader not present")
  source(eng_loader)
  eng <- load_real_wc_engine(here::here("R", "workforce_cliff_engine.R"))

  ages_tab <- utils::read.csv(ages_csv)
  ages <- rep(ages_tab$age, ages_tab$n_active_2023)
  g <- utils::read.csv(golden_csv, stringsAsFactors = FALSE)
  band_ev <- as.numeric(strsplit(g$band_ev, ";")[[1]])
  band_py <- as.numeric(strsplit(g$band_py, ";")[[1]])
  grad    <- as.numeric(strsplit(g$grad_urps, ";")[[1]])

  # perturb the hazards by +20% -> projection must NOT reproduce the golden value
  hz_bad <- setNames(ifelse(band_py > 0, 1.2 * band_ev / band_py, 0), eng$WC_BAND_LABELS)
  r_bad <- eng$wc_project(ages, entrants = mean(grad), hz = hz_bad, horizon = g$horizon)
  expect_false(isTRUE(all.equal(r_bad$active_2029, g$projected_2029, tolerance = 1e-6)))
})
