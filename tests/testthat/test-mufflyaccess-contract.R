# tests/testthat/test-mufflyaccess-contract.R
# cliff consumes the mufflyaccess measure x year x geography contract (v3.0.0).
# Values are the verified canonical cells from mufflyaccess 0.10.0 (URPS-subspecialty
# -cert basis); pathway sub-counts come from urps_count(), never from subtracting
# literals. 1332/1329 are the RETIRED v2.1.0 primary-cert cells (never current).
library(testthat)
test_that("mufflyaccess is installed and available", {
  expect_true(
    requireNamespace("mufflyaccess", quietly = TRUE),
    info = "cliff requires a pinned mufflyaccess installation for its canonical URPS baseline"
  )
})
test_that("cliff uses the canonical qualified 2023 active baseline", {
  skip_if_not_installed("mufflyaccess")
  skip_if_not("urps_count" %in% getNamespaceExports("mufflyaccess"),
              "mufflyaccess::urps_count() not available")
  # 2023 board_certified_active, national
  abog_nat <- mufflyaccess::urps_count(year = 2023L, measure = "board_certified_active",
                                       geography = "national", include_urology = FALSE)
  both_nat <- mufflyaccess::urps_count(year = 2023L, measure = "board_certified_active",
                                       geography = "national", include_urology = TRUE)
  expect_equal(abog_nat, 1027L)   # v3.0.0 2023 board-certified active ABOG (was roster 1031)
  expect_equal(both_nat, 1306L)   # v3.0.0 both-pathway (was retired v2.1.0 1332)
  expect_false(both_nat == 1332L) # never the retired primary-cert cell
  # 2023 board_certified_active, CONUS
  both_conus <- mufflyaccess::urps_count(year = 2023L, measure = "board_certified_active",
                                         geography = "conus", include_urology = TRUE)
  expect_equal(both_conus, 1303L) # v3.0.0 (was retired 1329)
})
test_that("2025 roster_snapshot is a DISTINCT cell (1339), not the 2023 active count", {
  skip_if_not_installed("mufflyaccess")
  skip_if_not("urps_count" %in% getNamespaceExports("mufflyaccess"),
              "mufflyaccess::urps_count() not available")
  roster_2025 <- mufflyaccess::urps_count(year = 2025L, measure = "roster_snapshot",
                                          geography = "national", include_urology = TRUE)
  active_2023 <- mufflyaccess::urps_count(year = 2023L, measure = "board_certified_active",
                                          geography = "national", include_urology = TRUE)
  expect_equal(roster_2025, 1339L)
  expect_equal(active_2023, 1306L)
  expect_false(roster_2025 == active_2023)   # 1339 (roster) != 1306 (2023 active)
})
