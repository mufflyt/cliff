# SSOT guard: the projection baseline year 2025 in the manuscript Figure 1 builder (iter50). The trajectory
# builder in manuscript/R/create_figure1_workforce_projection.R already wired its horizon to
# WORKFORCE_PROJECTION_HORIZON_YEARS (iter1) but still hardcoded `base_year <- 2025L` — an un-wired copy of the
# shared PROJECTION_BASELINE_YEAR (iter23), reachable via the contract it already sources. Now it references the
# canonical, so the figure's x-axis start cannot drift from the study baseline.
#
# INTENTIONALLY NOT collapsed: the `baseline_2025` COLUMN identifiers (create_workforce_table, the contract,
# the trajectory mutate) are schema names with the year baked in, left literal (cf. iter24's _2050 columns).
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

FIG <- here::here("manuscript", "R", "create_figure1_workforce_projection.R")
src <- readLines(FIG, warn = FALSE)

# The constant arrives via the contract the figure sources; load it the same way the figure does.
ce <- new.env()
ok <- tryCatch({ suppressMessages(suppressWarnings(source(here::here("manuscript", "R", "workforce_data_contract.R"), local = ce))); TRUE },
               error = function(e) FALSE)

test_that("[adversarial] the trajectory builder references the SSOT, not a bare base_year literal", {
  expect_true(any(grepl("base_year <- PROJECTION_BASELINE_YEAR", src)))
  expect_false(any(grepl("base_year <- 2025L", src)))
})

test_that("PROJECTION_BASELINE_YEAR is reachable via the contract and is the pinned 2025", {
  skip_if_not(ok, "contract could not be sourced")
  expect_identical(ce$PROJECTION_BASELINE_YEAR, 2025L)
  expect_true(exists("WORKFORCE_PROJECTION_HORIZON_YEARS", envir = ce, inherits = FALSE))  # horizon shares the env
})

test_that("[behavior-preserving] base_year + horizon reproduces the figure's 2025-2029 x-axis", {
  skip_if_not(ok, "contract could not be sourced")
  base_year <- ce$PROJECTION_BASELINE_YEAR
  horizon   <- ce$WORKFORCE_PROJECTION_HORIZON_YEARS
  expect_identical(base_year + 0:horizon, 2025:2029)        # the `year = base_year + 0:horizon` axis
  expect_identical(base_year + horizon, 2029L)              # endpoint unchanged
})

test_that("[cross-lineage consistency] the figure baseline equals the demand-lineage index base", {
  skip_if_not(ok, "contract could not be sourced")
  de <- new.env(); source(here::here("R", "demand_denominator.R"), local = de)
  expect_identical(ce$PROJECTION_BASELINE_YEAR, de$DEMAND_INDEX_BASE_YEAR)   # supply-fig baseline == demand index base (iter22)
})

test_that("[intentional difference] the baseline_2025 COLUMN names stay literal (schema, not the value)", {
  expect_true(any(grepl("baseline_2025", src)))            # the schema column identifier is preserved
  # the only NON-column 2025 (the base_year assignment) is now the constant, not a literal
  nonschema <- src[grepl("base_year", src)]
  expect_false(any(grepl("2025", nonschema)))
})
