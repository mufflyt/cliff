# SSOT guard: the metres-per-mile conversion. `MI <- 1609.344` was copy-pasted in two Module-D producer
# scripts (differential_distance, geographic_access) and used in BOTH directions (m->mi as `/MI`, mi->m as
# `mi*MI`). Now canonical in R/units.R (METERS_PER_MILE + meters_to_miles()/miles_to_meters()). The map
# scripts read precomputed mile columns and do not convert.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

ue <- new.env(); source(here::here("R", "units.R"), local = ue)
D_CONVERTERS <- c("urps_module_d_differential_distance.R", "urps_module_d_geographic_access_2026-07-23.R")

test_that("METERS_PER_MILE is the exact statute mile (1609.344 m), well-formed", {
  expect_type(ue$METERS_PER_MILE, "double")
  expect_length(ue$METERS_PER_MILE, 1L)
  expect_identical(ue$METERS_PER_MILE, 1609.344)
  expect_equal(ue$METERS_PER_MILE, 5280 * 12 * 0.0254)   # 5280 ft * 12 in * 0.0254 m/in
  # a rounded copy is a DIFFERENT value the guard must reject
  expect_false(ue$METERS_PER_MILE == 1609)
  expect_false(ue$METERS_PER_MILE == 1609.34)
})

test_that("[semantic] conversions are correct and round-trip", {
  expect_equal(ue$miles_to_meters(1),   1609.344)
  expect_equal(ue$miles_to_meters(100), 160934.4)
  expect_equal(ue$meters_to_miles(1609.344), 1)
  expect_equal(ue$meters_to_miles(ue$miles_to_meters(37.5)), 37.5)   # round-trip
  expect_true(is.na(ue$meters_to_miles(NA_real_)))                   # NA-preserving
})

test_that("[behavior-preserving] helpers reproduce the exact prior /MI and *MI (incl NA)", {
  MI <- 1609.344
  m  <- c(0, 1609.344, 50000, NA, 160934.4)
  mi <- c(0, 1, 50, 100, NA)
  expect_identical(ue$meters_to_miles(m),  m / MI)
  expect_identical(ue$miles_to_meters(mi), mi * MI)
})

test_that("[adversarial] neither converter script redefines MI or hardcodes 1609 as a factor", {
  offenders <- character(); missing_src <- character()
  for (b in D_CONVERTERS) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    if (any(grepl("MI\\s*<-\\s*1609|1609\\.34", ls))) offenders <- c(offenders, b)
    if (!any(grepl('source\\("R/units\\.R"\\)', ls))) missing_src <- c(missing_src, b)
    expect_true(any(grepl("meters_to_miles|miles_to_meters", ls)), info = b)  # uses the helpers
  }
  expect_equal(offenders, character(0), info = paste("MI/1609 literal still in:", paste(offenders, collapse="; ")))
  expect_equal(missing_src, character(0), info = paste("missing source(R/units.R):", paste(missing_src, collapse="; ")))
})
