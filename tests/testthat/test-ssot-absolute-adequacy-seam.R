# SSOT guard for the absolute-adequacy seam (R/absolute_adequacy_seam.R):
# calibrated CHIA demand basis -> capacity-evidence gate -> project().
#
# Pins the two properties that keep the seam honest:
#   1. The calibrated engine becomes a valid demand basis for the gate, and a
#      dropped Medicare band makes the basis NOT fully identified (never silently
#      summed over).
#   2. project_absolute_adequacy() reports an absolute adequacy ONLY through the
#      gate: resolved -> adeq_absolute == relative index x anchor (and the
#      absolute FTE gap follows by construction); refused -> every absolute
#      column NA with the gate's reason, and the guarded relative columns are
#      never touched.
#
# The core seam is pure base R (it sources capacity_evidence.R), so it runs in
# the minimal contract runner. The end-to-end block additionally drives the real
# calibration stack and skips cleanly where that stack is absent.
library(testthat)
library(here)

sm <- new.env()
source(here::here("R", "capacity_evidence.R"), local = sm)
source(here::here("R", "absolute_adequacy_seam.R"), local = sm)

# ---- chia_calibrated_all_payer_total() -------------------------------------

applied_df <- function(mult, workload) {
  data.frame(
    age_band_lower = seq(65L, by = 5L, length.out = length(mult)),
    bridge_multiplier = mult,
    calibrated_all_payer_workload = workload
  )
}

test_that("a fully covered application is a fully-identified demand basis", {
  de <- sm$chia_calibrated_all_payer_total(applied_df(c(1.8, 1.5, 1.3), c(900, 700, 500)))
  expect_true(de$fully_identified)
  expect_equal(de$total, 2100)
  expect_equal(de$n_identified, 3L)
  expect_length(de$unidentified_bands, 0L)
})

test_that("a dropped band makes the basis NOT fully identified and is reported", {
  de <- sm$chia_calibrated_all_payer_total(applied_df(c(1.8, NA, 1.3), c(900, NA, 500)))
  expect_false(de$fully_identified)
  expect_equal(de$total, 1400)          # sums identified bands only
  expect_equal(de$n_identified, 2L)
  expect_equal(de$unidentified_bands, 70L)
})

test_that("an empty application is not fully identified and totals NA", {
  de <- sm$chia_calibrated_all_payer_total(applied_df(numeric(0), numeric(0)))
  expect_false(de$fully_identified)
  expect_true(is.na(de$total))
})

test_that("the calibrated total hard-fails on a malformed application", {
  expect_error(sm$chia_calibrated_all_payer_total(data.frame(x = 1)))
})

# ---- project_absolute_adequacy() -------------------------------------------

proj_tbl <- function() {
  # internally consistent, as project()/validate_scenario_projection guarantees:
  # adeq_eff == effective / req_fte exactly (so req_fte is derived, not rounded).
  adeq_eff  <- c(1, 0.95, 0.90, 0.85)
  effective <- c(1000, 990, 980, 970)
  data.frame(
    YEAR = 2025:2028,
    adeq_eff = adeq_eff,
    effective = effective,
    req_fte = effective / adeq_eff
  )
}
af_ok <- data.frame(identified = TRUE, adequacy = 1.25)
af_no <- data.frame(identified = FALSE, adequacy = NA_real_)
de_ok <- list(fully_identified = TRUE, total = 1200)
de_no <- list(fully_identified = FALSE, total = NA_real_)

test_that("[resolved] the absolute anchor rescales the relative index", {
  out <- sm$project_absolute_adequacy(proj_tbl(), af_ok, de_ok, base_year = 2025)
  expect_true(all(out$absolute_resolved))
  expect_equal(attr(out, "absolute_anchor"), 1.25)

  # adeq_absolute = adeq_eff * anchor; base-year value == anchor
  expect_equal(out$adeq_absolute, proj_tbl()$adeq_eff * 1.25)
  expect_equal(out$adeq_absolute[out$YEAR == 2025], 1.25)

  # absolute FTE columns follow: req_fte_absolute = req_fte / anchor
  expect_equal(out$req_fte_absolute, proj_tbl()$req_fte / 1.25)
  expect_equal(out$capacity_gap_absolute, out$req_fte_absolute - out$effective)

  # the defining identity: adeq_absolute == effective / req_fte_absolute
  expect_equal(out$adeq_absolute, out$effective / out$req_fte_absolute)
})

test_that("[refusal] an unidentified demand basis blocks the absolute anchor", {
  out <- sm$project_absolute_adequacy(proj_tbl(), af_ok, de_no, base_year = 2025)
  expect_false(any(out$absolute_resolved))
  expect_true(all(is.na(out$adeq_absolute)))
  expect_true(all(is.na(out$req_fte_absolute)))
  expect_true(all(is.na(out$capacity_gap_absolute)))
  expect_false(isTRUE(attr(out, "absolute_resolved")))
  expect_match(unique(out$absolute_reason), "demand basis not fully identified")
})

test_that("[refusal] an unidentified access fit blocks the absolute anchor", {
  out <- sm$project_absolute_adequacy(proj_tbl(), af_no, de_ok, base_year = 2025)
  expect_false(any(out$absolute_resolved))
  expect_true(all(is.na(out$adeq_absolute)))
  expect_match(unique(out$absolute_reason), "access fit not identified")
})

test_that("the guarded relative columns are never touched, resolved or not", {
  base <- proj_tbl()
  for (de in list(de_ok, de_no)) {
    out <- sm$project_absolute_adequacy(base, af_ok, de, base_year = 2025)
    expect_equal(out$adeq_eff, base$adeq_eff)
    expect_equal(out$effective, base$effective)
    expect_equal(out$req_fte, base$req_fte)
  }
})

test_that("the input projection is not mutated (copy semantics)", {
  base <- proj_tbl()
  invisible(sm$project_absolute_adequacy(base, af_ok, de_ok, base_year = 2025))
  expect_false("adeq_absolute" %in% names(base))
})

test_that("a non-normalised base-year index is refused (fail loud)", {
  bad <- proj_tbl()
  bad$adeq_eff[bad$YEAR == 2025] <- 1.2      # not 1 at base
  expect_error(
    sm$project_absolute_adequacy(bad, af_ok, de_ok, base_year = 2025),
    "not 1"
  )
})

test_that("a base_year matching no unique row is refused", {
  expect_error(
    sm$project_absolute_adequacy(proj_tbl(), af_ok, de_ok, base_year = 2099),
    "exactly one projection row"
  )
})

# ---- end-to-end: real calibration stack ------------------------------------

test_that("[integration] a calibrated bridge flows through to an absolute adequacy", {
  for (pkg in c("dplyr", "tibble", "purrr", "scales", "splines", "broom")) {
    skip_if_not_installed(pkg)
  }
  cal <- new.env()
  source(here::here("R", "chia_demand_bridge_calibration.R"), local = cal)

  # synthetic CHIA world with a known age-graded VOLUME multiplier
  ages  <- c(65, 70, 75, 80, 85)
  years <- 2018:2021
  true_mult <- c(`65` = 1.8, `70` = 1.5, `75` = 1.3, `80` = 1.2, `85` = 1.15)
  claims <- list(); pop <- list()
  for (yr in years) for (ag in ages) {
    ffs_vol <- 800 + 5 * (ag - 65)
    claims[[length(claims) + 1L]] <-
      data.frame(year = yr, age = ag, payer = "Medicare FFS", wrvu = ffs_vol)
    claims[[length(claims) + 1L]] <-
      data.frame(year = yr, age = ag, payer = "Commercial",
                 wrvu = ffs_vol * true_mult[[as.character(ag)]] - ffs_vol)
    pop[[length(pop) + 1L]] <-
      data.frame(year = yr, age = ag, payer = "Medicare FFS", population = 50000)
    pop[[length(pop) + 1L]] <-
      data.frame(year = yr, age = ag, payer = "Commercial", population = 50000)
  }
  res <- suppressMessages(cal$calibrate_chia_demand_bridge(
    do.call(rbind, claims), do.call(rbind, pop), age_band_width = 5L, n_boot = 100L))
  skip_if_not(identical(res$status$status[[1]], "calibrated"))

  nat <- data.frame(age = ages, wrvu = 800 + 5 * (ages - 65), population = 50000)
  applied <- suppressWarnings(suppressMessages(
    cal$apply_chia_demand_bridge(nat, res, age_band_width = 5L)))

  de <- sm$chia_calibrated_all_payer_total(applied)
  expect_true(de$fully_identified)          # every national band covered

  out <- sm$project_absolute_adequacy(proj_tbl(), af_ok, de, base_year = 2025)
  expect_true(all(out$absolute_resolved))
  expect_equal(out$adeq_absolute[out$YEAR == 2025], 1.25)
})
