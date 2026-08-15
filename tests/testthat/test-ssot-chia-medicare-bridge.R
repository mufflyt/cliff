# SSOT guard for the CHIA <-> Medicare all-payer workload bridge
# (R/chia_medicare_bridge.R).
#
# Pins the identifiability floor, enforces the contract schema (multiplier ==
# 1/capture lockstep, monotone age gradient), checks the all-payer math on a
# CALIBRATED synthetic contract, and — the point of the module — asserts the
# bridge refuses (never fabricates an all-payer number) for uncalibrated bands
# and for bands whose Medicare capture is below the floor.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

cb <- new.env()
source(here::here("R", "chia_medicare_bridge.R"), local = cb)

test_that("the capture floor is pinned and well-formed", {
  expect_type(cb$CHIA_BRIDGE_MIN_MEDICARE_CAPTURE, "double")
  expect_identical(cb$CHIA_BRIDGE_MIN_MEDICARE_CAPTURE, 0.5)
  expect_gt(cb$CHIA_BRIDGE_MIN_MEDICARE_CAPTURE, 0)
  expect_lt(cb$CHIA_BRIDGE_MIN_MEDICARE_CAPTURE, 1)
  expect_equal(cb$CHIA_BRIDGE_MAX_MULTIPLIER, 1 / cb$CHIA_BRIDGE_MIN_MEDICARE_CAPTURE)
  expect_gt(cb$CHIA_BRIDGE_MAX_MULTIPLIER, 1)
})

test_that("the shipped contract is a valid, provisional, age-graded skeleton", {
  ct <- cb$chia_bridge_contract()
  expect_s3_class(ct, "data.frame")
  expect_identical(names(ct),
                   c("age_lower", "medicare_capture", "multiplier", "calibration_status"))
  # strictly increasing bands, split at the Medicare boundary 65
  expect_false(is.unsorted(ct$age_lower, strictly = TRUE))
  expect_true(65L %in% ct$age_lower)
  # multiplier is exactly 1/capture (lockstep encodings)
  expect_equal(ct$multiplier, 1 / ct$medicare_capture)
  # capture rises with age (the age gradient)
  expect_false(is.unsorted(ct$medicare_capture))
  # shipped provisional -> nothing calibrated
  expect_true(all(ct$calibration_status == "not_calibrated"))
})

test_that("the contract validator hard-fails on schema violations", {
  ok <- cb$chia_bridge_contract()
  expect_error(cb$validate_chia_bridge_contract(within(ok, multiplier <- multiplier * 2)))  # broken lockstep
  bad_status <- ok; bad_status$calibration_status <- "maybe"
  expect_error(cb$validate_chia_bridge_contract(bad_status))                                 # closed vocab
  bad_cap <- ok; bad_cap$medicare_capture[1] <- 1.5; bad_cap$multiplier <- 1 / bad_cap$medicare_capture
  expect_error(cb$validate_chia_bridge_contract(bad_cap))                                    # capture > 1
})

test_that("[refusal] the shipped provisional contract resolves NOTHING", {
  md <- data.frame(age_lower = c(0L, 65L, 75L, 85L),
                   medicare_volume = c(10, 400, 300, 120))
  b <- cb$bridge_medicare_to_all_payer(md)
  expect_true(all(!b$identified))
  expect_true(all(is.na(b$all_payer_volume)))
  expect_true(all(!is.na(b$reason)))
  expect_match(b$reason[b$age_lower == 65L], "not calibrated")
  agg <- cb$chia_bridge_all_payer_total(b)
  expect_true(is.na(agg$total))
  expect_false(agg$fully_identified)
})

# A CALIBRATED synthetic contract (what a real CHIA/Medicare extract would yield)
# lets us exercise the math and the capture-floor refusal.
calib <- function() {
  cap <- c(0.05, 0.72, 0.82, 0.88)   # under-65 below the 0.5 floor; 65+ above it
  data.frame(age_lower = c(0L, 65L, 75L, 85L),
             medicare_capture = cap, multiplier = 1 / cap,
             calibration_status = "calibrated", stringsAsFactors = FALSE)
}

test_that("[math] a calibrated band lifts Medicare volume by exactly 1/capture", {
  md <- data.frame(age_lower = c(65L, 75L, 85L), medicare_volume = c(400, 300, 120))
  b <- cb$bridge_medicare_to_all_payer(md, contract = calib())
  expect_true(all(b$identified))
  expect_equal(b$all_payer_volume, c(400 / 0.72, 300 / 0.82, 120 / 0.88))
  # all-payer always exceeds Medicare (multiplier > 1)
  expect_true(all(b$all_payer_volume > b$medicare_volume))
  agg <- cb$chia_bridge_all_payer_total(b)
  expect_true(agg$fully_identified)
  expect_equal(agg$total, sum(400 / 0.72, 300 / 0.82, 120 / 0.88))
})

test_that("[refusal] a calibrated but below-floor band (under 65) is declined, not scaled", {
  md <- data.frame(age_lower = c(0L, 65L), medicare_volume = c(10, 400))
  b <- cb$bridge_medicare_to_all_payer(md, contract = calib())
  under65 <- b[b$age_lower == 0L, ]
  expect_false(under65$identified)
  expect_true(is.na(under65$all_payer_volume))
  expect_match(under65$reason, "below|capture 0.05 < floor")
  # the 65+ band still resolves
  expect_true(b$identified[b$age_lower == 65L])
  # aggregate flags the dropped band
  agg <- cb$chia_bridge_all_payer_total(b)
  expect_false(agg$fully_identified)
  expect_true(0L %in% agg$unidentified_bands)
  expect_equal(agg$n_identified, 1L)
})

test_that("[edge] requesting a band absent from the contract fails loudly", {
  md <- data.frame(age_lower = c(55L), medicare_volume = c(100))   # 55 not a contract band
  expect_error(cb$bridge_medicare_to_all_payer(md, contract = calib()))
})

test_that("[contract] the bridge return shape is stable", {
  md <- data.frame(age_lower = 65L, medicare_volume = 400)
  b <- cb$bridge_medicare_to_all_payer(md, contract = calib())
  expect_identical(names(b),
                   c("age_lower", "medicare_volume", "medicare_capture", "multiplier",
                     "calibration_status", "all_payer_volume", "identified", "reason"))
  expect_type(b$identified, "logical")
})
