# SSOT guard: the tigris cartographic-boundary resolution ("20m") used for every module-D county/state pull.
# It MUST be consistent across the scripts (differential_distance + geographic_access both compute county-
# centroid distances; a different generalization shifts the centroids). Canonical in R/conus.R::CENSUS_CB_RESOLUTION.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

ce <- new.env(); source(here::here("R", "conus.R"), local = ce)
D <- c("urps_module_d_differential_distance.R", "urps_module_d_differential_map.R",
       "urps_module_d_geographic_access_2026-07-23.R", "urps_module_d_map_2026-07-23.R")

test_that("CENSUS_CB_RESOLUTION is the pinned '20m' (valid tigris cb resolution)", {
  expect_type(ce$CENSUS_CB_RESOLUTION, "character")
  expect_identical(ce$CENSUS_CB_RESOLUTION, "20m")
  expect_true(ce$CENSUS_CB_RESOLUTION %in% c("20m", "5m", "500k"))
})

test_that("[adversarial] every module-D boundary pull derives the resolution; no bare '20m' remains", {
  for (b in D) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    has_boundary <- any(grepl("counties\\(|states\\(", ls))
    if (!has_boundary) next
    expect_false(any(grepl('resolution ?= ?"20m"', ls)), info = b)              # literal gone
    expect_true(any(grepl("resolution=CENSUS_CB_RESOLUTION", ls)), info = b)    # uses the SSOT
    expect_true(any(grepl('source\\("R/conus\\.R"\\)', ls)), info = b)
  }
})

test_that("[semantic] the same constant reaches both the distance-computing scripts (centroids align)", {
  dd <- readLines(here::here("scripts", "urps_module_d_differential_distance.R"), warn = FALSE)
  ga <- readLines(here::here("scripts", "urps_module_d_geographic_access_2026-07-23.R"), warn = FALSE)
  expect_true(any(grepl("resolution=CENSUS_CB_RESOLUTION", dd)))
  expect_true(any(grepl("resolution=CENSUS_CB_RESOLUTION", ga)))
})
