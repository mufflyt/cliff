# SSOT guard: the tigris cartographic-boundary resolution ("20m") used for every module-D county/state pull.
# It MUST be consistent across the scripts that pull boundaries (geographic_access computes county polygons;
# the two map scripts draw them; differential_distance is now drive-time-only and pulls no boundaries). A
# different generalization shifts the county polygons/centroids. Canonical in R/conus.R::CENSUS_CB_RESOLUTION.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

ce <- new.env(); source(here::here("R", "conus.R"), local = ce)
# differential_distance is drive-time-only now (no boundary pull), so it is not
# in this list; the adversarial test below also self-skips any script without a
# counties()/states() call.
D <- c("urps_module_d_differential_map.R",
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

test_that("[semantic] the same constant reaches the boundary-pulling scripts (polygons align)", {
  ga <- readLines(here::here("scripts", "urps_module_d_geographic_access_2026-07-23.R"), warn = FALSE)
  dm <- readLines(here::here("scripts", "urps_module_d_differential_map.R"), warn = FALSE)
  expect_true(any(grepl("resolution=CENSUS_CB_RESOLUTION", ga)))
  expect_true(any(grepl("resolution=CENSUS_CB_RESOLUTION", dm)))
})
