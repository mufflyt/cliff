# SSOT guard: the frozen projection Monte-Carlo iteration count
# (WORKFORCE_MONTE_CARLO_ITERATIONS). It is a published number ("10,000-iteration Monte Carlo").
# The constant was a dead alias holding a stale 1,000 (10x-off); corrected to 10,000 and the
# manuscript now derives its stated count from it. This guards the value + code<->doc agreement.
library(testthat)
library(here)

ce <- new.env(); source(here::here("manuscript", "R", "workforce_data_contract.R"), local = ce)
N <- ce$WORKFORCE_MONTE_CARLO_ITERATIONS

test_that("MC iteration constant is the corrected 10,000 (integer)", {
  expect_type(N, "integer")
  expect_length(N, 1L)
  expect_identical(N, 10000L)
  expect_equal(format(N, big.mark = ","), "10,000")
})

test_that("workforce_statistics aliases the canonical constant, not an independent literal", {
  ws <- readLines(here::here("manuscript", "R", "workforce_statistics.R"), warn = FALSE)
  expect_true(any(grepl("N_MONTE_CARLO_ITERATIONS\\s*<-\\s*WORKFORCE_MONTE_CARLO_ITERATIONS", ws)))
})

test_that("the manuscript derives its stated iteration count from the constant, not a bare literal", {
  rmd <- readLines(here::here("manuscript", "manuscript_WORKFORCE_CLIFF.Rmd"), warn = FALSE)
  expect_true(any(grepl("format\\(WORKFORCE_MONTE_CARLO_ITERATIONS", rmd)))
  expect_false(any(grepl("a 10,000-iteration Monte Carlo", rmd)))   # no bare literal remains
})

test_that("code<->doc: the supply-line figure caption's count matches the canonical", {
  cap <- paste(readLines(here::here("scripts", "fig_fpmrs_supply_line.R"), warn = FALSE), collapse = "\n")
  expect_true(grepl(format(N, big.mark = ","), cap, fixed = TRUE))   # "10,000" appears in the caption
})
