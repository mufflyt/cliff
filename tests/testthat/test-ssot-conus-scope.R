# SSOT guard: the CONUS geographic scope. The non-CONUS FIPS list c("02","15","72","60","66","69","78")
# was copy-pasted across 4 Module-D scripts (+ a variant setdiff(1:56,c(2,15)) encoding), and the CONUS
# lon/lat bounding box was duplicated 3x. Both are now canonical in R/conus.R (CONUS_EXCLUDE_FIPS +
# is_conus_fips(); CONUS_LON/CONUS_LAT + in_conus_bbox()). Guards cover value, semantics, behavior
# preservation (incl NA / De Morgan), and that no consumer re-hardcodes them.
library(testthat)
library(here)

ce <- new.env(); source(here::here("R", "conus.R"), local = ce)
D_SCRIPTS <- c("urps_module_d_differential_distance.R", "urps_module_d_differential_map.R",
               "urps_module_d_geographic_access_2026-07-23.R", "urps_module_d_map_2026-07-23.R")

test_that("CONUS_EXCLUDE_FIPS is the well-formed 7-code AK/HI + territories list", {
  expect_type(ce$CONUS_EXCLUDE_FIPS, "character")
  expect_length(ce$CONUS_EXCLUDE_FIPS, 7L)
  expect_setequal(ce$CONUS_EXCLUDE_FIPS, c("02","15","72","60","66","69","78"))
  expect_true(all(c("02","15") %in% ce$CONUS_EXCLUDE_FIPS))   # the two non-contiguous states
  expect_true(all(grepl("^[0-9]{2}$", ce$CONUS_EXCLUDE_FIPS)))
})

test_that("[semantic] is_conus_fips classifies STATEFP and GEOID prefixes correctly", {
  expect_false(ce$is_conus_fips("02"))   # AK
  expect_false(ce$is_conus_fips("15"))   # HI
  expect_false(ce$is_conus_fips("72"))   # PR
  expect_true(ce$is_conus_fips("06"))    # CA
  expect_true(ce$is_conus_fips("11"))    # DC is CONUS
  expect_false(ce$is_conus_fips("02123"))  # GEOID prefix AK
  expect_true(ce$is_conus_fips("06075"))   # GEOID prefix CA
  expect_identical(ce$is_conus_fips(c("01","02","15","48")), c(TRUE, FALSE, FALSE, TRUE))
})

test_that("[semantic] in_conus_bbox: interior TRUE, exterior FALSE, open boundary FALSE, NA->NA", {
  expect_true(ce$in_conus_bbox(-100, 40))    # interior
  expect_false(ce$in_conus_bbox(-150, 61))   # Alaska
  expect_false(ce$in_conus_bbox(-125, 40))   # on west edge (open interval)
  expect_false(ce$in_conus_bbox(-100, 50))   # on north edge (open interval)
  expect_true(is.na(ce$in_conus_bbox(NA_real_, 40)))   # NA preserved (3-valued)
})

test_that("[behavior-preserving] helpers reproduce the exact prior literal expressions (incl NA)", {
  NONCONUS <- c("02","15","72","60","66","69","78")
  fp <- c("01","02","06","15","11","72","48","78","36")
  expect_identical(ce$is_conus_fips(fp), !(fp %in% NONCONUS))
  g <- expand.grid(lon = c(-150,-125,-100,-66,-50,NA), lat = c(10,24,40,50,60,NA))
  expect_identical(with(g, ce$in_conus_bbox(lon, lat)),
                   with(g, lon > -125 & lon < -66 & lat > 24 & lat < 50))
  expect_identical(with(g, !ce$in_conus_bbox(lon, lat)),                 # De Morgan incl NA
                   with(g, lon <= -125 | lon >= -66 | lat <= 24 | lat >= 50))
})

test_that("[adversarial] no Module-D script re-hardcodes the FIPS list or the bbox literals", {
  offenders_fips <- character(); offenders_box <- character(); missing_src <- character()
  for (b in D_SCRIPTS) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    if (any(grepl('NONCONUS\\s*<-\\s*c\\(|c\\("02","15","72"', ls))) offenders_fips <- c(offenders_fips, b)
    # bbox longitude literals as COORDINATES (minus not preceded by a digit, so age
    # ranges like "65-66" in comments are not false positives)
    is_box_lit <- grepl('(?<![0-9])-125|(?<![0-9])-66', ls, perl = TRUE)
    if (any(is_box_lit & !grepl("CONUS_LON|CONUS_LAT|in_conus_bbox|R/conus", ls))) offenders_box <- c(offenders_box, b)
    if (!any(grepl('source\\("R/conus\\.R"\\)', ls))) missing_src <- c(missing_src, b)
  }
  expect_equal(offenders_fips, character(0), info = paste("FIPS literal still in:", paste(offenders_fips, collapse="; ")))
  expect_equal(offenders_box,  character(0), info = paste("bbox literal still in:", paste(offenders_box, collapse="; ")))
  expect_equal(missing_src,    character(0), info = paste("missing source(R/conus.R):", paste(missing_src, collapse="; ")))
})

test_that("[consistency] every Module-D script references the canonical helpers", {
  for (b in D_SCRIPTS) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    expect_true(any(grepl("is_conus_fips|in_conus_bbox", ls)), info = b)
  }
})
