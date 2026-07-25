# SSOT guard: the per-100,000 population rate base. `1e5 * numer / denom` was duplicated across 3 producers
# (module_a, geographic_access, supply_demand_national) to report "per 100,000 women 65+". Now canonical in
# R/units.R::RATE_PER_100K. INTENTIONALLY NOT collapsed: the same literal 1e5 used as `guess_max = 1e5` in
# read_csv/fread is a data-loading row hint (a different concept) and stays literal.
library(testthat)
library(here)

ue <- new.env(); source(here::here("R", "units.R"), local = ue)
PRODUCERS <- c("urps_module_a_effective_supply_2026-07-23.R",
               "urps_module_d_geographic_access_2026-07-23.R",
               "urps_supply_demand_national_2026-07-23.R")

test_that("RATE_PER_100K is the 1e5 per-100,000 rate base (numeric scalar)", {
  expect_type(ue$RATE_PER_100K, "double")
  expect_length(ue$RATE_PER_100K, 1L)
  expect_identical(ue$RATE_PER_100K, 1e5)
})

test_that("[behavior-preserving] a rate computed with the constant equals the prior 1e5 literal", {
  numer <- c(164, 1300, 605); denom <- c(34.7e6, 44.8e6, 33.1e6)
  expect_identical(ue$RATE_PER_100K * numer / denom, 1e5 * numer / denom)
})

test_that("[adversarial] all 3 producers use RATE_PER_100K; no bare 1e5* rate literal remains", {
  for (b in PRODUCERS) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    expect_false(any(grepl("1e5\\*", ls)), info = b)                     # bare rate literal gone
    expect_true(any(grepl("RATE_PER_100K\\*", ls)), info = b)            # uses the SSOT
    expect_true(any(grepl('source\\((here::here\\()?"R/?".*units\\.R|units\\.R"', ls)), info = b)  # sources units
  }
})

test_that("[intentional difference preserved] guess_max=1e5 is a data-loading hint, NOT the rate base", {
  # the read guess_max is its OWN constant (READ_GUESS_MAX_ROWS, iter 27) — a different concept from the
  # per-100k rate base, so a guess_max script uses that constant and does NOT reroute through RATE_PER_100K
  bh <- readLines(here::here("scripts", "build_hazard_comparison.R"), warn = FALSE)
  expect_true(any(grepl("guess_max=READ_GUESS_MAX_ROWS", bh)))
  expect_false(any(grepl("RATE_PER_100K", bh)))
})
