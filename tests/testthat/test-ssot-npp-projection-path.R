# SSOT guard: the Census NPP projection file path. `SCR <- here::here("data","census")` + the np2023_d1_<series>.csv
# names were copy-pasted across 3 demand producers. Now canonical in R/demand_denominator.R::npp_projection_path(series).
library(testthat)
library(here)

de <- new.env(); source(here::here("R", "demand_denominator.R"), local = de)
PRODUCERS <- c("urps_demand_module_bc_2026-07-23.R", "urps_module_bc_corrected_2026-07-23.R",
               "urps_supply_demand_national_2026-07-23.R")

test_that("npp_projection_path resolves data/census/np2023_d1_<series>.csv for each series", {
  for (s in c("mid", "low", "hi")) {
    p <- de$npp_projection_path(s)
    expect_true(grepl(file.path("data", "census", sprintf("np2023_d1_%s.csv", s)), p, fixed = TRUE), info = s)
  }
  expect_identical(de$npp_projection_path(), de$npp_projection_path("mid"))   # default = mid
})

test_that("[semantic] the primary (mid) NPP file exists at the canonical path", {
  expect_true(file.exists(de$npp_projection_path("mid")))
})

test_that("[fail-loud] an unknown series is rejected", {
  expect_error(de$npp_projection_path("bogus"))   # match.arg
})

test_that("[adversarial] all 3 producers use the helper; no bare SCR/np2023 path literal remains", {
  for (b in PRODUCERS) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    expect_false(any(grepl("SCR\\s*<-\\s*here::here", ls)), info = b)             # census-dir literal gone
    expect_false(any(grepl("file.path\\(SCR", ls)), info = b)                      # bare path construction gone
    expect_true(any(grepl("npp_projection_path\\(", ls)), info = b)               # uses the SSOT
  }
})
