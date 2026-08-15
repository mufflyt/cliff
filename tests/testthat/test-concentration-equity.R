# tests/testthat/test-concentration-equity.R
# Unit tests for R/workforce_concentration_metrics.R

library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

source(here::here("R/workforce_concentration_metrics.R"))

test_that("gini is 0 for perfect equality and approaches (n-1)/n for a monopoly", {
  expect_equal(gini(c(25, 25, 25, 25)), 0)
  expect_equal(gini(c(100, 0, 0, 0)), 0.75)          # (n-1)/n with n = 4
  expect_true(is.na(gini(c(0, 0, 0))))               # zero total -> NA
  expect_error(gini(c(-1, 2)))                       # negatives rejected
})

test_that("gini rises monotonically as mass concentrates", {
  even  <- gini(c(10, 10, 10, 10))
  mild  <- gini(c(20, 10, 8, 2))
  heavy <- gini(c(38, 1, 0, 1))
  expect_lt(even, mild)
  expect_lt(mild, heavy)
})

test_that("herfindahl_index bounds and known values hold", {
  expect_equal(herfindahl_index(c(100)), 1)                       # monopoly
  expect_equal(herfindahl_index(c(50, 50)), 0.5)                  # duopoly
  expect_equal(herfindahl_index(c(50, 30, 20)), 0.38)            # 0.25+0.09+0.04
  expect_true(is.na(herfindahl_index(c(0, 0))))
  # normalized HHI of an even split is 0
  expect_equal(herfindahl_index(c(10, 10, 10, 10), normalized = TRUE), 0)
})

test_that("lorenz_curve starts at origin, ends at (1,1), and bows below equality", {
  lc <- lorenz_curve(c(1, 1, 1, 7))
  expect_equal(lc$cum_unit_share[1], 0)
  expect_equal(lc$cum_value_share[1], 0)
  expect_equal(tail(lc$cum_unit_share, 1), 1)
  expect_equal(tail(lc$cum_value_share, 1), 1)
  # concentrated vector: value share lags unit share everywhere in the interior
  interior <- lc[-c(1, nrow(lc)), ]
  expect_true(all(interior$cum_value_share <= interior$cum_unit_share + 1e-9))
})

test_that("top_k_share captures the busiest units", {
  expect_equal(top_k_share(c(50, 30, 15, 5), k = 2), 0.8)
  expect_equal(top_k_share(c(1, 1, 1, 1), k = 10), 1)   # k > length is clamped
  expect_true(is.na(top_k_share(c(0, 0), k = 1)))
})

test_that("concentration_summary pads the full geography and flags zero units", {
  # 5 occupied units out of a 100-unit universe
  s <- concentration_summary(c(10, 5, 3, 1, 1), n_units_total = 100, label = "test")
  expect_equal(s$n_occupied, 5)
  expect_equal(s$n_units, 100)
  expect_equal(s$pct_units_zero, 95)
  expect_gt(s$gini, 0.9)   # near-total concentration across the 100 units
})

test_that("concentration_summary adds a population-weighted Gini when weights given", {
  # providers proportional to population -> maldistribution Gini ~ 0
  counts <- c(10, 20, 30)
  pop    <- c(100, 200, 300)
  s <- concentration_summary(counts, n_units_total = 3, label = "prop", weight = pop)
  expect_lt(abs(s$gini_pop_weighted), 0.05)
})

test_that("rate_dispersion returns ordered quantiles and a 90:10 ratio", {
  d <- rate_dispersion(c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10))
  expect_equal(d$n, 10)
  expect_true(d$p10 <= d$median && d$median <= d$p90)
  expect_gt(d$ratio_90_10, 1)
  expect_equal(rate_dispersion(numeric(0))$n, 0L)
})

test_that("equity_breakdown tabulates counts, percentages, and strata", {
  df <- data.frame(
    gender  = c("F", "F", "M", "M", "M", NA),
    pathway = c("ABOG", "ABU", "ABOG", "ABOG", "ABU", "ABOG"),
    stringsAsFactors = FALSE
  )
  tab <- equity_breakdown(df, gender, pathway, levels = c("F", "M"))
  expect_true(all(c("ABOG_n", "ABOG_pct", "ABU_n", "ABU_pct",
                    "overall_n", "overall_pct") %in% names(tab)))
  expect_equal(sum(tab$overall_n), nrow(df))              # every row counted once
  expect_equal(tab$overall_n[tab$level == "F"], 2)
  expect_equal(tab$overall_n[tab$level == "Missing"], 1)  # NA -> Missing row
})
