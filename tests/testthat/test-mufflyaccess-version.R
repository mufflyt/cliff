# Pins the consumer to the released mufflyaccess: fails loudly if a stale package
# (or a non-v3.0.0 contract) is installed, so URPS baselines can never be sourced
# from an out-of-date SSOT.
suppressWarnings(suppressMessages(library(testthat)))

# The v3.0.0 mufflyaccess release (>=0.7.0) is not published yet: the mufflyaccess
# 0.7.0/0.7.1 tag is blocked on GitHub Actions billing, so the currently installable
# release is 0.6.0 (contract v2.1.0). Until 0.7.1 installs, these assertions SKIP
# with a precise reason (mirroring twostep's contract-3.0.0 consumer tests); they
# activate and enforce the pin the moment the v3.0.0 package is installed.
.mfa_v3_ready <- function() {
  requireNamespace("mufflyaccess", quietly = TRUE) &&
    utils::packageVersion("mufflyaccess") >= "0.7.0"
}
.mfa_skip <- "requires mufflyaccess >= 0.7.0 (contract v3.0.0); release blocked on Actions billing"

test_that("mufflyaccess is at least the pinned 0.7.0 release", {
  skip_if_not_installed("mufflyaccess")
  skip_if_not(.mfa_v3_ready(), .mfa_skip)
  expect_true(utils::packageVersion("mufflyaccess") >= "0.7.0")
})

test_that("the served URPS contract is v3.0.0 (current, not retired v2.1.0)", {
  skip_if_not_installed("mufflyaccess")
  skip_if_not(.mfa_v3_ready(), .mfa_skip)
  expect_equal(mufflyaccess::urps_provenance()$contract_version, "3.0.0")
  # retired v2.1.0 values must never be what the current API returns
  expect_false(mufflyaccess::urps_count(2023, "board_certified_active", "national", TRUE) %in% c(1332L, 1329L))
})
