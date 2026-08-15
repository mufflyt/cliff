# SSOT guard for the CHIA all-payer demand-bridge CALIBRATION engine
# (R/chia_demand_bridge_calibration.R) -- the "real extract" path that
# R/chia_medicare_bridge.R's provisional contract promises.
#
# Pins the two properties that make this estimator honest:
#   1. SEMANTICS. bridge_multiplier is a VOLUME ratio (all-payer volume /
#      Medicare-FFS volume), the same meaning as chia_medicare_bridge.R's
#      1/capture multiplier, so apply()'s `ffs_workload * multiplier` recovers
#      an all-payer VOLUME. A rate ratio would carry an ffs_pop/all_pop factor
#      and silently under-count; the regression guard below forbids it by
#      constructing data where the two interpretations diverge sharply.
#   2. REFUSAL. apply_chia_demand_bridge() must REFUSE (error) unless the
#      calibration actually cleared its gate (status == "calibrated"); an
#      uncalibrated fit can never masquerade as an identified denominator.
#
# The calibration path pulls in the tidyverse + splines + broom stack, so the
# whole file skips cleanly where that stack is absent (e.g. the minimal
# base-R contract runner) and runs for real wherever it is installed.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

heavy_stack <- c("dplyr", "tibble", "purrr", "scales", "splines", "broom", "readr")

skip_unless_stack <- function() {
  for (pkg in heavy_stack) {
    testthat::skip_if_not_installed(pkg)
  }
}

cd <- new.env()
source(here::here("R", "chia_demand_bridge_calibration.R"), local = cd)

# A synthetic CHIA world with a KNOWN age-graded volume multiplier. All-payer
# volume = FFS volume * true_mult(age). The Medicare-FFS population share
# (capture) climbs steeply across the 65 boundary, so the VOLUME ratio and the
# RATE ratio diverge by up to ~20x -- the lever the regression guard pulls on.
make_chia_world <- function() {
  ages  <- c(50, 55, 60, 65, 70, 75, 80, 85)
  years <- 2018:2021
  # smooth (log-linear-ish) decline so a df=3 spline fits it well
  true_mult <- c(`50` = 4.0, `55` = 3.2, `60` = 2.6, `65` = 1.8,
                 `70` = 1.5, `75` = 1.3, `80` = 1.2, `85` = 1.15)
  # capture rises steeply with age (Medicare near-absent < 65, dominant 65+)
  ffs_share <- c(`50` = 0.05, `55` = 0.08, `60` = 0.15, `65` = 0.70,
                 `70` = 0.80, `75` = 0.85, `80` = 0.88, `85` = 0.90)

  claims <- list()
  pop <- list()
  for (yr in years) {
    for (ag in ages) {
      tot_pop <- 100000
      ffs_pop <- round(tot_pop * ffs_share[[as.character(ag)]])
      ffs_vol <- 800 + 5 * (ag - 50)
      all_vol <- ffs_vol * true_mult[[as.character(ag)]]
      claims[[length(claims) + 1L]] <-
        data.frame(year = yr, age = ag, payer = "Medicare FFS", wrvu = ffs_vol)
      claims[[length(claims) + 1L]] <-
        data.frame(year = yr, age = ag, payer = "Commercial", wrvu = all_vol - ffs_vol)
      pop[[length(pop) + 1L]] <-
        data.frame(year = yr, age = ag, payer = "Medicare FFS", population = ffs_pop)
      pop[[length(pop) + 1L]] <-
        data.frame(year = yr, age = ag, payer = "Commercial", population = tot_pop - ffs_pop)
    }
  }
  list(
    claims = do.call(rbind, claims),
    pop = do.call(rbind, pop),
    ages = ages,
    true_mult = true_mult,
    ffs_share = ffs_share
  )
}

calibrate_quiet <- function(world) {
  suppressMessages(
    cd$calibrate_chia_demand_bridge(
      world$claims, world$pop,
      age_band_width = 5L, n_boot = 150L
    )
  )
}

test_that("a clean synthetic world calibrates and recovers the VOLUME multiplier", {
  skip_unless_stack()
  world <- make_chia_world()
  res <- calibrate_quiet(world)

  expect_identical(res$status$status[[1]], "calibrated")
  expect_identical(res$status$workload_basis[[1]], "wrvu")
  expect_gte(res$status$n_age_bands[[1]], 3L)

  got <- res$bridge$bridge_multiplier
  names(got) <- as.character(res$bridge$age_band_lower)
  truth <- world$true_mult[names(got)]

  # spline over 8 bands -> tight but not exact
  rel_err <- abs(got - truth) / truth
  expect_lt(mean(rel_err), 0.10)
  expect_lt(max(rel_err), 0.20)
})

test_that("[regression] the multiplier is a VOLUME ratio, not a rate ratio", {
  skip_unless_stack()
  world <- make_chia_world()
  res <- calibrate_quiet(world)

  got <- res$bridge$bridge_multiplier
  names(got) <- as.character(res$bridge$age_band_lower)
  vol_ratio  <- world$true_mult[names(got)]
  rate_ratio <- vol_ratio * world$ffs_share[names(got)]  # the WRONG target

  err_to_volume <- mean(abs(got - vol_ratio) / vol_ratio)
  err_to_rate   <- mean(abs(got - rate_ratio) / rate_ratio)

  # must sit on the volume ratio and be nowhere near the rate ratio
  expect_lt(err_to_volume, 0.10)
  expect_gt(err_to_rate, 0.30)
})

test_that("apply() recovers all-payer VOLUME as ffs_workload * multiplier", {
  skip_unless_stack()
  world <- make_chia_world()
  res <- calibrate_quiet(world)

  nat <- data.frame(
    age = world$ages,
    wrvu = 800 + 5 * (world$ages - 50),
    population = round(100000 * world$ffs_share[as.character(world$ages)])
  )
  out <- suppressWarnings(suppressMessages(
    cd$apply_chia_demand_bridge(nat, res, age_band_width = 5L)
  ))

  got   <- out$calibrated_all_payer_workload
  names(got) <- as.character(out$age_band_lower)
  truth <- (800 + 5 * (world$ages - 50)) * world$true_mult[as.character(world$ages)]
  names(truth) <- as.character(world$ages)

  rel_err <- abs(got[names(truth)] - truth) / truth
  expect_lt(max(rel_err), 0.20)

  # the multiplier column and the workload column are internally consistent
  expect_equal(
    out$calibrated_all_payer_workload,
    out$ffs_workload * out$bridge_multiplier
  )
})

test_that("[refusal] apply() refuses an uncalibrated bridge", {
  skip_unless_stack()
  not_cal <- list(
    status = tibble::tibble(status = "not_calibrated"),
    bridge = tibble::tibble(
      age_band_lower = c(50, 55), age_band = c("50-54", "55-59"),
      bridge_multiplier = c(2, 1.5),
      bridge_boot_low = c(1.8, 1.3), bridge_boot_high = c(2.2, 1.7),
      bridge_mean = c(2, 1.5), bridge_sd = c(0.1, 0.1)
    )
  )
  nat <- data.frame(age = c(50, 55), wrvu = c(800, 825), population = c(5000, 8000))
  expect_error(
    suppressMessages(cd$apply_chia_demand_bridge(nat, not_cal)),
    "Refusing"
  )
})

test_that("calibration refuses when too few eligible cells survive the gate", {
  skip_unless_stack()
  world <- make_chia_world()
  # push the FFS-workload floor above every cell -> nothing eligible
  expect_error(
    suppressMessages(
      cd$calibrate_chia_demand_bridge(
        world$claims, world$pop,
        min_ffs_workload = 1e9, n_boot = 10L
      )
    ),
    "eligible"
  )
})

test_that("calibration errors when no workload column is available", {
  skip_unless_stack()
  world <- make_chia_world()
  claims_no_workload <- world$claims[, c("year", "age", "payer")]
  expect_error(
    suppressMessages(
      cd$calibrate_chia_demand_bridge(claims_no_workload, world$pop)
    ),
    "wrvu_col|encounter_col|patient_col"
  )
})
