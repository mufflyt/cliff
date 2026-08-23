# calculate_two_prop_test() is exported and used by calculate_rural_metro_comparison(),
# but had no executed test path, so the nightly coverage ratchet failed when the
# untested-export count rose from 43 to 44. These cover every branch the function
# can return: the prop.test path, both guard clauses, and the p-value formatter.
suppressWarnings(suppressMessages(library(testthat)))

test_that("a well-powered comparison runs prop.test and reports the p-value", {
  res <- calculate_two_prop_test(30, 100, 100, 500)

  expect_equal(res$method, "prop.test")
  expect_true(is.finite(res$p_value))
  expect_gte(res$p_value, 0)
  expect_lte(res$p_value, 1)
  expect_equal(res$significant, res$p_value < 0.05)
  expect_equal(res$note, "Two-proportion z-test")
  # agrees with the underlying test rather than re-deriving it
  expect_equal(res$p_value, stats::prop.test(c(30, 100), c(100, 500))$p.value)
})

test_that("samples below min_sample_size return descriptive_only, not a test", {
  res <- suppressMessages(calculate_two_prop_test(5, 20, 10, 25))

  expect_equal(res$method, "descriptive_only")
  expect_true(is.na(res$p_value))
  expect_equal(res$p_value_formatted, "n<30")
  expect_false(res$significant)
  expect_match(res$note, "too small")
})

test_that("the small-sample guard honours a caller-supplied min_sample_size", {
  # n=20/25 is ample when the floor is lowered, so the test path is taken
  res <- calculate_two_prop_test(5, 20, 10, 25, min_sample_size = 10)
  expect_equal(res$method, "prop.test")
})

test_that("a zero denominator returns insufficient_data", {
  # reachable only past the small-sample guard, so the floor is lowered to 0
  res <- calculate_two_prop_test(0, 0, 10, 50, min_sample_size = 0)

  expect_equal(res$method, "insufficient_data")
  expect_true(is.na(res$p_value))
  expect_equal(res$p_value_formatted, "insufficient data")
  expect_false(res$significant)
})

test_that("p-values are formatted by magnitude", {
  # a large, unambiguous difference drives p below 0.001
  tiny <- calculate_two_prop_test(5, 1000, 900, 1000)
  expect_lt(tiny$p_value, 0.001)
  expect_equal(tiny$p_value_formatted, "<0.001")

  # every formatted value is either the sentinel or a fixed-decimal number
  for (res in list(tiny, calculate_two_prop_test(30, 100, 100, 500))) {
    expect_match(res$p_value_formatted, "^(<0\\.001|[0-9]+\\.[0-9]{2,3})$")
  }
})

test_that("the returned object always carries the documented fields", {
  for (res in list(
    calculate_two_prop_test(30, 100, 100, 500),
    suppressMessages(calculate_two_prop_test(5, 20, 10, 25)),
    calculate_two_prop_test(0, 0, 10, 50, min_sample_size = 0)
  )) {
    expect_true(all(c("method", "p_value", "p_value_formatted", "significant", "note") %in% names(res)))
    expect_true(is.logical(res$significant) && length(res$significant) == 1L)
    expect_false(is.na(res$significant))
  }
})
