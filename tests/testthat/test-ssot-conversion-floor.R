# SSOT guard: the conservative graduate-to-practice conversion floor (WORKFORCE_CONVERSION_FLOOR
# = 0.70). It is a scenario assumption reported in the manuscript ("70% to 100%") and used in BOTH
# the engine-lineage scenario script and the manuscript-lineage tipping-point call; a drift would
# make the code and the paper disagree on a stated sensitivity value.
library(testthat)
library(here)
suppressPackageStartupMessages(library(readr))

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

ce <- new.env(); source(here::here("R", "workforce_constants.R"), local = ce)
CF <- ce$WORKFORCE_CONVERSION_FLOOR

test_that("WORKFORCE_CONVERSION_FLOOR is a valid proportion (0.70)", {
  expect_type(CF, "double")
  expect_length(CF, 1L)
  expect_equal(CF, 0.70)
  expect_true(CF > 0 && CF <= 1)
})

test_that("both lineages reference the canonical floor, not a literal 0.7", {
  gg <- readLines(here::here("scripts", "graduate_growth_scenarios.R"), warn = FALSE)
  expect_true(any(grepl("WORKFORCE_CONVERSION_FLOOR\\s*\\*\\s*m", gg)))
  expect_false(any(grepl("conservative_70pct\\s*=\\s*0\\.7\\s*\\*", gg)))
  rmd <- readLines(here::here("manuscript", "manuscript_WORKFORCE_CLIFF.Rmd"), warn = FALSE)
  expect_true(any(grepl("get_tipping_missed_range\\(WORKFORCE_CONVERSION_FLOOR\\)", rmd)))
  expect_false(any(grepl("get_tipping_missed_range\\(0\\.70?\\)", rmd)))
})

test_that("the manuscript's stated '70%' matches the canonical floor", {
  expect_equal(sprintf("%.0f%%", 100 * CF), "70%")
})

test_that("the frozen sensitivity-grid conversion axis contains the canonical floor (drift guard)", {
  g <- read_csv(here::here("data", "sensitivity_grid_summary.csv"), show_col_types = FALSE)
  conv <- suppressWarnings(as.numeric(g[[ncol(g)]]))   # last column = conversion factor
  expect_true(CF %in% conv)
})
