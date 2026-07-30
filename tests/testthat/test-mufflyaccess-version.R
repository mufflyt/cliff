# Pins the consumer to the released mufflyaccess: fails loudly if a stale package
# (or a non-v3.0.0 contract) is installed, so URPS baselines can never be sourced
# from an out-of-date SSOT.
suppressWarnings(suppressMessages(library(testthat)))

test_that("mufflyaccess is at least the pinned 0.7.0 release", {
  skip_if_not_installed("mufflyaccess")
  expect_true(utils::packageVersion("mufflyaccess") >= "0.7.0")
})

test_that("the served URPS contract is v3.0.0 (current, not retired v2.1.0)", {
  skip_if_not_installed("mufflyaccess")
  expect_equal(mufflyaccess::urps_provenance()$contract_version, "3.0.0")
  # retired v2.1.0 values must never be what the current API returns
  expect_false(mufflyaccess::urps_count(2023, "board_certified_active", "national", TRUE) %in% c(1332L, 1329L))
})
