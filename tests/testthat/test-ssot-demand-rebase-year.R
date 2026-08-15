# SSOT guard: the demographic-growth REBASE YEAR (g(base)=1). Both demand producers divide the women-65+
# series by the base-year count via w65[YEAR==2024]; the year was hardcoded in each. Now canonical in
# R/demand_denominator.R::DEMAND_REBASE_YEAR. It is DISTINCT from the Medicare-claims data vintage (also
# 2024, a different concept) and from the supply-side index base (2025) — neither is collapsed into it.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

de <- new.env(); source(here::here("R", "demand_denominator.R"), local = de)
PRODUCERS <- c("urps_demand_module_bc_2026-07-23.R", "urps_module_bc_corrected_2026-07-23.R")

test_that("DEMAND_REBASE_YEAR is the pinned base year 2024 (integer, in range)", {
  expect_type(de$DEMAND_REBASE_YEAR, "integer")
  expect_identical(de$DEMAND_REBASE_YEAR, 2024L)
  expect_gte(de$DEMAND_REBASE_YEAR, 2000L); expect_lte(de$DEMAND_REBASE_YEAR, 2100L)
  expect_false(de$DEMAND_REBASE_YEAR == 2025L)   # NOT the supply-side index base
})

test_that("[behavior-preserving] filtering YEAR==DEMAND_REBASE_YEAR selects the same row as ==2024", {
  yrs <- c(2023, 2024, 2025, 2050)
  expect_identical(yrs == de$DEMAND_REBASE_YEAR, yrs == 2024)   # int constant vs double column: same mask
  expect_equal(which(yrs == de$DEMAND_REBASE_YEAR), 2L)
})

test_that("[adversarial] both producers rebase via the constant, not a hardcoded w65[YEAR==2024]", {
  for (b in PRODUCERS) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    expect_false(any(grepl("w65\\[YEAR==2024\\]", ls)), info = b)         # literal rebase gone
    expect_true(any(grepl("YEAR==DEMAND_REBASE_YEAR", ls)), info = b)     # uses the SSOT
    expect_true(any(grepl("demand_denominator\\.R", ls)), info = b)       # sources the module
  }
})

test_that("[intentional difference preserved] Medicare vintage + supply index base are NOT the rebase constant", {
  bc <- readLines(here::here("scripts", "urps_demand_module_bc_2026-07-23.R"), warn = FALSE)
  # Medicare data-year table name stays a literal 2024 (a different concept), NOT wired to the constant
  expect_true(any(grepl("medicare_part_b_by_service_2024", bc)))
  expect_false(any(grepl("medicare_part_b_by_service_.*DEMAND_REBASE_YEAR", bc)))
  # the supply-side index base (module_a) is the 2025 projection baseline (DEMAND_INDEX_BASE_YEAR,
  # canonicalised in iter 22), NOT the 2024 demand rebase year -- the two demand base years stay distinct
  ma <- readLines(here::here("scripts", "urps_module_a_effective_supply_2026-07-23.R"), warn = FALSE)
  expect_true(any(grepl("YEAR==DEMAND_INDEX_BASE_YEAR", ma)))
  expect_false(any(grepl("DEMAND_REBASE_YEAR", ma)))
})
