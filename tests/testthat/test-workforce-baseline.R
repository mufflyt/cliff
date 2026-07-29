# tests/testthat/test-workforce-baseline.R
library(testthat)
test_that("cliff baseline is loaded from mufflyaccess", {
  skip_if_not_installed("mufflyaccess")
  baseline <- load_workforce_baseline(
    year = 2023L,
    include_urology = TRUE
  )
  expect_equal(
    baseline$n_providers,
    mufflyaccess::urps_count(
      year = 2023L,
      include_urology = TRUE
    )
  )
  expect_identical(
    baseline$source_package,
    "mufflyaccess"
  )
  expect_identical(
    baseline$measure_year,
    2023L
  )
})
test_that("cliff does not relabel measure year as model year", {
  baseline <- load_workforce_baseline(
    year = 2023L,
    include_urology = TRUE
  )
  expect_identical(
    baseline$measure_year,
    2023L
  )
  expect_true(
    "model_start_year" %in% names(baseline)
  )
  expect_false(
    identical(
      baseline$measure_year,
      baseline$model_start_year
    ),
    info = paste(
      "Measure year and model start year must be",
      "separate explicit fields"
    )
  )
})
