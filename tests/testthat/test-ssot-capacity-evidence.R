# SSOT guard for the capacity-evidence bundle + absolute-adequacy gate
# (R/capacity_evidence.R).
#
# Verifies the bundle schema, the sufficiency rule (access fit identified AND
# all-payer demand fully identified), and — the point of the module — that the
# gate refuses to report an absolute adequacy on incomplete evidence. The final
# block is an INTEGRATION test: it composes all three estimators (wait_adequacy
# -> chia_medicare_bridge -> capacity_evidence) end to end.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

ce <- new.env()
source(here::here("R", "capacity_evidence.R"), local = ce)

af_ok  <- function(adeq = 1.4) data.frame(identified = TRUE,  adequacy = adeq)
af_no  <- function()          data.frame(identified = FALSE, adequacy = NA_real_)
de_ok  <- function(total = 1000) list(fully_identified = TRUE,  total = total)
de_no  <- function()             list(fully_identified = FALSE, total = NA_real_)

test_that("the bundle constructor validates shape and round-trips its parts", {
  b <- ce$capacity_evidence_bundle(af_ok(1.3), de_ok(900), label = "national")
  expect_s3_class(b, "capacity_evidence_bundle")
  expect_identical(b$label, "national")
  expect_true(b$access_fit$identified)
  expect_equal(b$demand_evidence$total, 900)
})

test_that("the validator hard-fails on malformed evidence", {
  # access fit missing the required columns
  expect_error(ce$capacity_evidence_bundle(data.frame(x = 1), de_ok()))
  # demand evidence missing fully_identified
  expect_error(ce$capacity_evidence_bundle(af_ok(), list(total = 1)))
  # access fit not one row
  expect_error(ce$capacity_evidence_bundle(
    data.frame(identified = c(TRUE, TRUE), adequacy = c(1.1, 1.2)), de_ok()))
})

test_that("sufficiency requires BOTH an identified fit and a fully-identified demand basis", {
  expect_true(ce$capacity_evidence_sufficient(ce$capacity_evidence_bundle(af_ok(), de_ok()))$sufficient)

  s_af <- ce$capacity_evidence_sufficient(ce$capacity_evidence_bundle(af_no(), de_ok()))
  expect_false(s_af$sufficient)
  expect_match(paste(s_af$reasons, collapse = " "), "access fit not identified")

  s_de <- ce$capacity_evidence_sufficient(ce$capacity_evidence_bundle(af_ok(), de_no()))
  expect_false(s_de$sufficient)
  expect_match(paste(s_de$reasons, collapse = " "), "demand basis not fully identified")

  s_both <- ce$capacity_evidence_sufficient(ce$capacity_evidence_bundle(af_no(), de_no()))
  expect_false(s_both$sufficient)
  expect_length(s_both$reasons, 2L)
})

test_that("[gate] adequacy resolves ONLY on sufficient evidence", {
  r <- ce$resolve_adequacy_gated(ce$capacity_evidence_bundle(af_ok(1.42), de_ok(), "national"))
  expect_true(r$resolved)
  expect_equal(r$adequacy, 1.42)
  expect_identical(r$label, "national")
  expect_true(is.na(r$reason))
})

test_that("[gate refusal] a missing access fit or demand band declines the absolute number", {
  for (b in list(ce$capacity_evidence_bundle(af_no(), de_ok()),
                 ce$capacity_evidence_bundle(af_ok(), de_no()),
                 ce$capacity_evidence_bundle(af_no(), de_no()))) {
    r <- ce$resolve_adequacy_gated(b)
    expect_false(r$resolved)
    expect_true(is.na(r$adequacy))       # never fabricated
    expect_false(is.na(r$reason))
  }
})

test_that("[gate contract] the resolution return shape is stable", {
  r <- ce$resolve_adequacy_gated(ce$capacity_evidence_bundle(af_ok(), de_ok()))
  expect_identical(names(r),
                   c("label", "resolved", "adequacy", "access_identified",
                     "demand_fully_identified", "reason"))
})

test_that("[integration a->b->c] the three estimators compose end to end", {
  wa <- new.env(); source(here::here("R", "wait_adequacy.R"), local = wa)
  cb <- new.env(); source(here::here("R", "chia_medicare_bridge.R"), local = cb)

  # (a) an observed short wait in a 4-channel clinic -> an identified adequacy > 1
  access_fit <- wa$wait_to_adequacy(wait = 0.5, mu = 2, s = 4)
  expect_true(access_fit$identified)
  expect_gt(access_fit$adequacy, 1)

  # (b) an all-payer demand basis from a CALIBRATED synthetic bridge over 65+ bands
  calib <- data.frame(age_lower = c(65L, 75L, 85L),
                      medicare_capture = c(0.72, 0.82, 0.88),
                      multiplier = 1 / c(0.72, 0.82, 0.88),
                      calibration_status = "calibrated", stringsAsFactors = FALSE)
  md <- data.frame(age_lower = c(65L, 75L, 85L), medicare_volume = c(400, 300, 120))
  demand_evidence <- cb$chia_bridge_all_payer_total(
    cb$bridge_medicare_to_all_payer(md, contract = calib))
  expect_true(demand_evidence$fully_identified)

  # (c) both identified -> the gate resolves the absolute adequacy
  good <- ce$capacity_evidence_bundle(access_fit, demand_evidence, label = "national")
  res  <- ce$resolve_adequacy_gated(good)
  expect_true(res$resolved)
  expect_equal(res$adequacy, access_fit$adequacy)

  # now drop one band below the capture floor -> demand not fully identified ->
  # the SAME access fit is refused at the gate (evidence chain broken).
  md2 <- rbind(data.frame(age_lower = 0L, medicare_volume = 10), md)
  calib2 <- rbind(data.frame(age_lower = 0L, medicare_capture = 0.05,
                             multiplier = 1 / 0.05, calibration_status = "calibrated"), calib)
  demand_partial <- cb$chia_bridge_all_payer_total(
    cb$bridge_medicare_to_all_payer(md2, contract = calib2))
  expect_false(demand_partial$fully_identified)
  res2 <- ce$resolve_adequacy_gated(
    ce$capacity_evidence_bundle(access_fit, demand_partial, label = "national"))
  expect_false(res2$resolved)
  expect_true(is.na(res2$adequacy))
})
