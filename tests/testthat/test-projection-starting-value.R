# tests/testthat/test-projection-starting-value.R
library(testthat)
test_that("the first projection year starts from the SSOT baseline", {
  skip_if_not_installed("mufflyaccess")
  baseline <- mufflyaccess::urps_count(
    year = 2023L,
    include_urology = TRUE
  )
  projection <- project_urps_workforce(
    baseline_year = 2023L,
    include_urology = TRUE,
    projection_years = 2023:2035,
    entrants = 0,
    retirements = 0
  )
  row_2023 <- projection[
    projection$year == 2023L,
  ]
  expect_equal(nrow(row_2023), 1L)
  expect_equal(row_2023$n_providers, baseline)
})
test_that("a zero-change scenario remains equal to baseline", {
  skip_if_not_installed("mufflyaccess")
  baseline <- mufflyaccess::urps_count(
    year = 2023L,
    include_urology = TRUE
  )
  projection <- project_urps_workforce(
    baseline_year = 2023L,
    include_urology = TRUE,
    projection_years = 2023:2035,
    entrants = 0,
    retirements = 0
  )
  expect_true(
    all(projection$n_providers == baseline)
  )
})
