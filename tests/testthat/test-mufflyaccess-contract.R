# tests/testthat/test-mufflyaccess-contract.R
library(testthat)
test_that("mufflyaccess is installed and available", {
  expect_true(
    requireNamespace(
      "mufflyaccess",
      quietly = TRUE
    ),
    info = paste(
      "cliff requires a pinned mufflyaccess installation",
      "for its canonical URPS baseline"
    )
  )
})
test_that("cliff uses the canonical 2023 baseline", {
  skip_if_not_installed("mufflyaccess")
  abog <- mufflyaccess::urps_count(
    year = 2023L,
    include_urology = FALSE
  )
  combined <- mufflyaccess::urps_count(
    year = 2023L,
    include_urology = TRUE
  )
  expect_equal(abog, 1031L)
  expect_equal(combined, 1339L)
  expect_equal(combined - abog, 308L)
})
