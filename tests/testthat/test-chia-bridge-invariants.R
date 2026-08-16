# Gate 50: invariants of the CHIA <-> Medicare all-payer bridge.
#
# The bridge scales Medicare volume up to an all-payer estimate by dividing by
# the share of that band's care Medicare actually captures. Two things make it
# worth property-testing rather than spot-checking:
#
#   * the multiplier is a RECIPROCAL, so a capture near zero produces an
#     enormous multiplier. Under-65 capture is 0.05, i.e. a 20x scale-up from a
#     denominator nobody would defend. The floor exists to refuse that case,
#     and the tests below pin the refusal rather than the number.
#
#   * "not identified" and "zero" are different answers, and collapsing them is
#     the kind of error that silently deflates a national total.
#
# Pure arithmetic in the package: also runs against the installed package.

calibrated_contract <- function() {
  ct <- cliff:::chia_bridge_contract()
  ct$calibration_status <- "calibrated"
  ct
}

med <- function(v) data.frame(age_lower = c(0L, 65L, 75L, 85L),
                              medicare_volume = v)

test_that("the shipped contract is internally consistent", {
  ct <- cliff:::chia_bridge_contract()
  # multiplier is exactly the reciprocal of capture; a drift between the two
  # would silently rescale every all-payer number.
  expect_equal(ct$multiplier, 1 / ct$medicare_capture, tolerance = 1e-12)
  expect_true(all(is.finite(ct$multiplier)))
  expect_true(all(ct$medicare_capture > 0))    # no division by zero, ever
  expect_true(all(ct$medicare_capture <= 1))   # capture is a share
  expect_true(all(ct$multiplier >= 1))         # all-payer >= Medicare, always
})

test_that("capture must be strictly positive and at most 1", {
  ct <- calibrated_contract()

  zero <- ct; zero$medicare_capture[2] <- 0
  expect_error(cliff:::validate_chia_bridge_contract(zero))

  neg <- ct; neg$medicare_capture[2] <- -0.1
  expect_error(cliff:::validate_chia_bridge_contract(neg))

  over <- ct; over$medicare_capture[2] <- 1.5
  expect_error(cliff:::validate_chia_bridge_contract(over))
})

test_that("directionality: all-payer volume is never below Medicare volume", {
  # The bridge scales UP. A result below the Medicare input would mean the
  # multiplier had been inverted -- the single most consequential sign error
  # available here.
  b <- cliff:::bridge_medicare_to_all_payer(med(c(10, 100, 50, 20)),
                                            contract = calibrated_contract())
  ok <- b$identified
  expect_true(any(ok))
  expect_true(all(b$all_payer_volume[ok] >= b$medicare_volume[ok] - 1e-9))
})

test_that("identified rows equal volume times multiplier exactly", {
  b <- cliff:::bridge_medicare_to_all_payer(med(c(10, 100, 50, 20)),
                                            contract = calibrated_contract())
  ok <- b$identified
  expect_equal(b$all_payer_volume[ok],
               b$medicare_volume[ok] * b$multiplier[ok],
               tolerance = 1e-9)
})

test_that("zero Medicare volume bridges to zero, not to NA", {
  # Zero volume is a measurement, not a missing value. Collapsing it to NA
  # would drop the band from any total built by summing identified rows.
  b <- cliff:::bridge_medicare_to_all_payer(med(c(0, 0, 0, 0)),
                                            contract = calibrated_contract())
  ok <- b$identified
  expect_true(any(ok))
  expect_true(all(b$all_payer_volume[ok] == 0))
})

test_that("a band below the capture floor is refused, not silently scaled", {
  b <- cliff:::bridge_medicare_to_all_payer(med(c(10, 100, 50, 20)),
                                            contract = calibrated_contract())
  under65 <- b$age_lower == 0L                 # capture 0.05, floor 0.50
  expect_false(b$identified[under65])
  expect_true(is.na(b$all_payer_volume[under65]))
  expect_match(b$reason[under65], "capture")
})

test_that("an uncalibrated band is refused and says why", {
  b <- cliff:::bridge_medicare_to_all_payer(med(c(10, 100, 50, 20)))  # shipped: none calibrated
  expect_false(any(b$identified))
  expect_true(all(is.na(b$all_payer_volume)))
  expect_true(all(grepl("not calibrated", b$reason)))
})

test_that("every unidentified row carries a reason and every identified row does not", {
  for (status in c("calibrated", "not_calibrated")) {
    ct <- cliff:::chia_bridge_contract()
    ct$calibration_status <- status
    b <- cliff:::bridge_medicare_to_all_payer(med(c(1, 2, 3, 4)), contract = ct)
    expect_true(all(!is.na(b$reason[!b$identified])))
    expect_true(all(is.na(b$reason[b$identified])))
    # Identified and NA output must never co-occur: that pair is what makes a
    # missing band look like a real zero downstream.
    expect_true(all(!is.na(b$all_payer_volume[b$identified])))
    expect_true(all(is.na(b$all_payer_volume[!b$identified])))
  }
})

test_that("bridged volume is monotone in Medicare volume", {
  ct <- calibrated_contract()
  prev <- rep(-Inf, 4)
  for (scale in c(0, 1, 5, 100, 1e6)) {
    b <- cliff:::bridge_medicare_to_all_payer(med(c(10, 100, 50, 20) * scale),
                                              contract = ct)
    v <- ifelse(is.na(b$all_payer_volume), -Inf, b$all_payer_volume)
    expect_true(all(v >= prev - 1e-6))
    prev <- ifelse(b$identified, b$all_payer_volume, -Inf)
  }
})

test_that("the capture floor is what decides identification, at the boundary too", {
  floor_v <- cliff:::CHIA_BRIDGE_MIN_MEDICARE_CAPTURE
  ct <- calibrated_contract()

  # exactly at the floor: identified (the guard is >=)
  ct$medicare_capture[2] <- floor_v
  ct$multiplier[2] <- 1 / floor_v
  b <- cliff:::bridge_medicare_to_all_payer(med(c(1, 1, 1, 1)), contract = ct)
  expect_true(b$identified[b$age_lower == 65L])

  # a hair below: refused
  ct$medicare_capture[2] <- floor_v - 1e-9
  ct$multiplier[2] <- 1 / ct$medicare_capture[2]
  b2 <- cliff:::bridge_medicare_to_all_payer(med(c(1, 1, 1, 1)), contract = ct)
  expect_false(b2$identified[b2$age_lower == 65L])
})

test_that("negative or missing Medicare volume is rejected, not bridged", {
  ct <- calibrated_contract()
  expect_error(cliff:::bridge_medicare_to_all_payer(med(c(-1, 1, 1, 1)), contract = ct))
  expect_error(cliff:::bridge_medicare_to_all_payer(med(c(NA, 1, 1, 1)), contract = ct))
})

test_that("a band outside the contract is rejected rather than dropped", {
  # Silently discarding an unknown band would understate the national total
  # while every row that remained still looked correct.
  ct <- calibrated_contract()
  bad <- data.frame(age_lower = c(65L, 999L), medicare_volume = c(10, 10))
  expect_error(cliff:::bridge_medicare_to_all_payer(bad, contract = ct))
})

test_that("bridging is row-wise: one band's volume cannot affect another's", {
  ct <- calibrated_contract()
  a <- cliff:::bridge_medicare_to_all_payer(med(c(10, 100, 50, 20)), contract = ct)
  b <- cliff:::bridge_medicare_to_all_payer(med(c(10, 100, 50, 99999)), contract = ct)
  keep <- a$age_lower != 85L
  expect_equal(a$all_payer_volume[keep], b$all_payer_volume[keep])
})
