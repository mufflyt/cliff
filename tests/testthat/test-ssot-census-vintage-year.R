# SSOT guard: the Census vintage year (2023), used for BOTH the ACS 5-year pull and the tigris boundary pull.
# They MUST be the same year (geographic_access merges ACS estimates onto tigris polygons by GEOID; a
# vintage mismatch breaks the join). Canonical in R/conus.R::CENSUS_VINTAGE_YEAR.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

ce <- new.env(); source(here::here("R", "conus.R"), local = ce)
D <- c("urps_module_d_differential_distance.R", "urps_module_d_differential_map.R",
       "urps_module_d_geographic_access_2026-07-23.R", "urps_module_d_map_2026-07-23.R")

test_that("CENSUS_VINTAGE_YEAR is the pinned 2023 (integer, plausible range)", {
  expect_type(ce$CENSUS_VINTAGE_YEAR, "integer")
  expect_identical(ce$CENSUS_VINTAGE_YEAR, 2023L)
  expect_gte(ce$CENSUS_VINTAGE_YEAR, 2009L); expect_lte(ce$CENSUS_VINTAGE_YEAR, 2100L)
})

test_that("[adversarial] all module-D scripts derive the vintage; no bare year=2023 remains", {
  for (b in D) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    expect_false(any(grepl("year ?= ?2023", ls)), info = b)             # literal gone
    expect_true(any(grepl("year=CENSUS_VINTAGE_YEAR", ls)), info = b)   # uses the SSOT
    expect_true(any(grepl('source\\("R/conus\\.R"\\)', ls)), info = b)  # sources the module
  }
})

test_that("[semantic] the ACS data year and the tigris boundary year share ONE constant (GEOID match)", {
  ga <- readLines(here::here("scripts", "urps_module_d_geographic_access_2026-07-23.R"), warn = FALSE)
  # both get_acs(year=) and counties(year=) reference the same constant
  expect_true(any(grepl("get_acs\\(.*year=CENSUS_VINTAGE_YEAR", ga)))
  expect_true(any(grepl("counties\\(.*year=CENSUS_VINTAGE_YEAR", ga)))
})
