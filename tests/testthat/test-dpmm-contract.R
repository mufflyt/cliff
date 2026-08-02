# Unit tests for the DPMM demand-contract ingestion helpers (R/dpmm_contract.R).
# These cover the alignment + 2025-rebase logic that feeds the comparison-only
# alternative D1 in scripts/urps_demand_denominators_sensitivity.R.
library(testthat)
library(here)

e <- new.env(); source(here::here("R", "dpmm_contract.R"), local = e)

mk <- function(years, idx, tier = "tier3_prevalent_pfd") {
  data.frame(denominator_tier = tier, calendar_year = years,
             denominator_index = idx, stringsAsFactors = FALSE)
}

test_that("rebases the base year to 100 (contract on a different base)", {
  ct <- mk(2025:2030, c(8, 12, 18, 26, 35, 40))     # raw-ish, 2025 = 8
  d1 <- e$dpmm_alt_d1_index(ct, 2025:2050, base_year = 2025L)
  expect_equal(d1[1], 100)                           # 2025 -> 100
  expect_equal(d1[2], 150)                           # 12/8*100
  expect_equal(d1[5], 437.5)                         # 35/8*100
})

test_that("an already-2025=100 contract is preserved by rebasing", {
  ct <- mk(2025:2029, c(100, 150, 225, 325, 437.5))
  d1 <- e$dpmm_alt_d1_index(ct, 2025:2029)
  expect_equal(d1, c(100, 150, 225, 325, 437.5))
})

test_that("years beyond the contract horizon are NA but the series is usable", {
  ct <- mk(2025:2029, c(100, 150, 225, 325, 437.5))
  d1 <- e$dpmm_alt_d1_index(ct, 2025:2050)
  yrs <- 2025:2050
  expect_true(all(is.na(d1[yrs > 2029])))
  expect_false(is.na(d1[1]))
  expect_true(e$dpmm_series_usable(d1))
})

test_that("missing base year falls back to passthrough (no rebase)", {
  ct <- mk(2026:2030, c(150, 225, 325, 437.5, 460))  # 2025 absent
  d1 <- e$dpmm_alt_d1_index(ct, 2025:2050, base_year = 2025L)
  expect_true(is.na(d1[1]))                           # 2025 absent -> NA
  expect_equal(d1[2], 150)                            # passthrough, not rebased
  expect_true(e$dpmm_series_usable(d1))
})

test_that("a tier absent from the contract yields all-NA and is not usable", {
  ct <- mk(2025:2029, c(100, 150, 225, 325, 437.5), tier = "tier4_symptomatic")
  d1 <- e$dpmm_alt_d1_index(ct, 2025:2050, tier = "tier3_prevalent_pfd")
  expect_true(all(is.na(d1)))
  expect_false(e$dpmm_series_usable(d1))
})

test_that("dpmm_alt_d1_index errors on a malformed contract", {
  expect_error(e$dpmm_alt_d1_index(data.frame(x = 1), 2025:2030))
})

test_that("read_dpmm_demand_contract returns NULL for empty/missing paths", {
  expect_null(e$read_dpmm_demand_contract(""))
  expect_null(e$read_dpmm_demand_contract(NULL))
  expect_null(e$read_dpmm_demand_contract(tempfile()))
})

test_that("read_dpmm_demand_contract reads data + calibration_status, round-trips", {
  p <- tempfile(fileext = ".csv")
  write.csv(data.frame(
    model = "DPMM", calibration_status = "uncalibrated_illustrative",
    denominator_tier = "tier3_prevalent_pfd", calendar_year = 2025:2026,
    denominator_index = c(100, 150)), p, row.names = FALSE)
  ct <- e$read_dpmm_demand_contract(p)
  expect_equal(ct$status, "uncalibrated_illustrative")
  d1 <- e$dpmm_alt_d1_index(ct$data, 2025:2026)
  expect_equal(d1, c(100, 150))
})
