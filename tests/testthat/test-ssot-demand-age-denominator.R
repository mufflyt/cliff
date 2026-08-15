# SSOT guard: the temporal demand-denominator age range (women 65+). `sprintf("POP_%d", 65:100)` was
# duplicated in 2 demand producers and asserted as the string "POP_65..POP_100" in the freeze-gate audit.
# Now canonical in R/demand_denominator.R (DEMAND_AGE_MIN=65, NPP_MAX_AGE=100, npp_women_65plus_cols()).
# The SPATIAL access map (geographic_access, ACS B01001 044:049) is a DIFFERENT source and stays separate.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

de <- new.env(); source(here::here("R", "demand_denominator.R"), local = de)
PRODUCERS <- c("urps_demand_module_bc_2026-07-23.R", "urps_module_bc_corrected_2026-07-23.R")
GATE      <- "urps_module_bc_gate_audit_2026-07-23.R"

test_that("demand-denominator constants are the pinned 65 / 100 integers", {
  expect_type(de$DEMAND_AGE_MIN, "integer")
  expect_identical(de$DEMAND_AGE_MIN, 65L)
  expect_identical(de$NPP_MAX_AGE, 100L)
  expect_lt(de$DEMAND_AGE_MIN, de$NPP_MAX_AGE)
  expect_false(de$DEMAND_AGE_MIN == 60L)   # a different cutoff must be a deliberate change
  expect_false(de$DEMAND_AGE_MIN == 66L)
})

test_that("[behavior-preserving] npp_women_65plus_cols() == the prior sprintf('POP_%d',65:100)", {
  cols <- de$npp_women_65plus_cols()
  expect_identical(cols, sprintf("POP_%d", 65:100))
  expect_length(cols, 36L)                              # 65..100 inclusive
  expect_identical(cols[1], "POP_65")
  expect_identical(cols[length(cols)], "POP_100")
  expect_true(all(grepl("^POP_[0-9]+$", cols)))
})

test_that("[semantic] the column set is DERIVED from the constants (tracks a change)", {
  cols <- de$npp_women_65plus_cols()
  expect_identical(cols[1], sprintf("POP_%d", de$DEMAND_AGE_MIN))
  expect_identical(cols[length(cols)], sprintf("POP_%d", de$NPP_MAX_AGE))
  # gate label derives from the constants too (no bare "POP_65..POP_100" string)
  expect_identical(sprintf("POP_%d..POP_%d", de$DEMAND_AGE_MIN, de$NPP_MAX_AGE), "POP_65..POP_100")
})

test_that("[adversarial] no demand producer/gate hardcodes the 65:100 range; all reference the SSOT", {
  for (b in PRODUCERS) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    expect_false(any(grepl('POP_%d",\\s*65:100', ls)), info = b)        # literal gone
    expect_true(any(grepl("npp_women_65plus_cols\\(\\)", ls)), info = b) # uses the helper
    expect_true(any(grepl("demand_denominator\\.R", ls)), info = b)     # sources the module
  }
  g <- readLines(here::here("scripts", GATE), warn = FALSE)
  expect_false(any(grepl('"POP_65\\.\\.POP_100"', g)))                  # gate no longer hardcodes the string
  expect_true(any(grepl("DEMAND_AGE_MIN", g)))                          # gate derives from the constant
})

test_that("[intentional difference preserved] the ACS spatial path is NOT wired to the NPP denominator", {
  ga <- readLines(here::here("scripts", "urps_module_d_geographic_access_2026-07-23.R"), warn = FALSE)
  expect_true(any(grepl('B01001_%03d", 44:49', ga)))     # still its own ACS band construction
  expect_false(any(grepl("npp_women_65plus_cols", ga)))  # deliberately separate from the temporal driver
})
