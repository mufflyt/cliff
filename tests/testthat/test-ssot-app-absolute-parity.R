# SSOT PARITY GUARD: the Shiny app's local absolute-adequacy layer
# (shiny_urps_adequacy/data/absolute_adequacy.R) must agree EXACTLY with the
# canonical package seam (R/capacity_evidence.R + R/absolute_adequacy_seam.R).
#
# The app deploys standalone and cannot source R/, so it carries a pure-base-R
# port of the gate + seam under `app_`-prefixed names. This guard sources BOTH
# implementations side by side and asserts they produce identical results on the
# resolved branch, the refused branch, and the calibrated-total helper — so the
# port can never silently drift from the single source of truth. Same posture as
# tests/testthat/test-ssot-adequacy-base-year.R (constant parity) but for logic.
#
# Pure base R on both sides -> runs in the minimal contract runner.
library(testthat)
library(here)

pk <- new.env()   # canonical package implementation
source(here::here("R", "capacity_evidence.R"), local = pk)
source(here::here("R", "absolute_adequacy_seam.R"), local = pk)

ap <- new.env()   # app-local port
source(here::here("shiny_urps_adequacy", "data", "absolute_adequacy.R"), local = ap)

# Shared fixtures -------------------------------------------------------------
proj_fix <- function() data.frame(
  YEAR      = 2025:2027,
  adeq_eff  = c(1, 0.95, 0.90),
  effective = c(1000, 990, 980),
  req_fte   = c(1000, 1042, 1089)
)
BY <- 2025L

# The columns the seam adds; compared value-by-value so attribute differences
# (the two envs use different bundle class strings) don't mask a real match.
added_cols <- c("adeq_absolute", "absolute_resolved", "absolute_reason",
                "req_fte_absolute", "capacity_gap_absolute")

expect_seam_parity <- function(app_out, pk_out) {
  for (col in added_cols) expect_equal(app_out[[col]], pk_out[[col]], info = col)
  for (a in c("absolute_anchor", "absolute_resolved", "absolute_reason")) {
    expect_equal(attr(app_out, a), attr(pk_out, a), info = a)
  }
  # the guarded RELATIVE columns must be carried through untouched by both
  expect_equal(app_out$adeq_eff, proj_fix()$adeq_eff)
  expect_equal(app_out$adeq_eff, pk_out$adeq_eff)
}

test_that("RESOLVED branch: app port anchors identically to the package seam", {
  af <- data.frame(identified = TRUE, adequacy = 1.25)
  de <- list(fully_identified = TRUE, total = 1200)
  app_out <- ap$app_project_absolute_adequacy(proj_fix(), af, de, base_year = BY)
  pk_out  <- pk$project_absolute_adequacy(proj_fix(), af, de, base_year = BY)
  expect_true(attr(app_out, "absolute_resolved"))
  expect_equal(attr(app_out, "absolute_anchor"), 1.25)
  expect_equal(app_out$adeq_absolute, c(1.25, 1.1875, 1.125))   # relative index x anchor
  expect_seam_parity(app_out, pk_out)
})

test_that("REFUSED branch (absent evidence): identical NA/reason to the seam", {
  # The app's real runtime path: no access fit, no demand basis -> refuse.
  app_out <- ap$absolute_adequacy_layer(proj_fix(), base_year = BY)
  af <- data.frame(identified = FALSE, adequacy = NA_real_)
  de <- list(fully_identified = FALSE, total = NA_real_)
  pk_out <- pk$project_absolute_adequacy(proj_fix(), af, de, base_year = BY)
  expect_false(attr(app_out, "absolute_resolved"))
  expect_true(all(is.na(app_out$adeq_absolute)))
  expect_match(attr(app_out, "absolute_reason"), "access fit not identified")
  expect_match(attr(app_out, "absolute_reason"), "demand basis not fully identified")
  expect_seam_parity(app_out, pk_out)
})

test_that("partial evidence (fit only) refuses the same way in both", {
  af <- data.frame(identified = TRUE, adequacy = 1.4)
  de <- list(fully_identified = FALSE, total = NA_real_)
  app_out <- ap$app_project_absolute_adequacy(proj_fix(), af, de, base_year = BY)
  pk_out  <- pk$project_absolute_adequacy(proj_fix(), af, de, base_year = BY)
  expect_false(attr(app_out, "absolute_resolved"))
  expect_seam_parity(app_out, pk_out)
})

test_that("gate + calibrated-total helpers match element-for-element", {
  # resolve_adequacy_gated parity across all four evidence combinations
  grid <- expand.grid(fit = c(TRUE, FALSE), dem = c(TRUE, FALSE))
  for (i in seq_len(nrow(grid))) {
    af <- data.frame(identified = grid$fit[i], adequacy = if (grid$fit[i]) 1.3 else NA_real_)
    de <- list(fully_identified = grid$dem[i], total = if (grid$dem[i]) 1000 else NA_real_)
    a <- ap$app_resolve_adequacy_gated(ap$app_capacity_evidence_bundle(af, de))
    p <- pk$resolve_adequacy_gated(pk$capacity_evidence_bundle(af, de))
    expect_equal(a$resolved, p$resolved, info = sprintf("fit=%s dem=%s", grid$fit[i], grid$dem[i]))
    expect_equal(a$adequacy, p$adequacy)
    expect_equal(a$reason,   p$reason)
  }
  # calibrated all-payer total parity, incl. a dropped band
  applied <- data.frame(
    age_band_lower = c(65L, 70L, 75L),
    bridge_multiplier = c(1.8, NA, 1.3),
    calibrated_all_payer_workload = c(900, NA, 500)
  )
  a <- ap$app_chia_calibrated_all_payer_total(applied)
  p <- pk$chia_calibrated_all_payer_total(applied)
  expect_equal(a$fully_identified, p$fully_identified)
  expect_equal(a$total, p$total)
  expect_equal(a$n_identified, p$n_identified)
  expect_equal(a$unidentified_bands, p$unidentified_bands)
})
