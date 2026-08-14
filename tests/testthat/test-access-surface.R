# Unit tests for the drive-time access-surface ingestion helpers
# (R/access_surface.R) that feed Module D v2. Pure/base-R, so the reader,
# GEOID normalisation, and population-weighted county roll-up are testable in
# isolation without the tidyverse or the real simulation artifact.
library(testthat)
library(here)

e <- new.env(); source(here::here("R", "access_surface.R"), local = e)

# Three tracts across two counties (01001 x2, 01003 x1).
mk_surface_df <- function() {
  data.frame(
    demand_id = c("01001020100", "01001020200", "01003010100"),
    access = c(10, 20, 5),
    population = c(100, 300, 200),
    isochrone_run_id = "20260508_ec2_r6i",
    calibration_status = "fitted_and_geographically_validated",
    stringsAsFactors = FALSE
  )
}

test_that("read_access_surface returns NULL for absent/empty paths", {
  expect_null(e$read_access_surface(NULL))
  expect_null(e$read_access_surface(""))
  expect_null(e$read_access_surface(file.path(tempdir(), "does-not-exist.csv")))
})

test_that("read_access_surface reads a CSV and extracts provenance", {
  p <- tempfile(fileext = ".csv")
  utils::write.csv(mk_surface_df(), p, row.names = FALSE)
  s <- e$read_access_surface(p)
  expect_true(e$access_surface_usable(s))
  expect_equal(nrow(s$data), 3L)
  expect_equal(s$provenance$isochrone_run_id, "20260508_ec2_r6i")
  expect_equal(s$provenance$calibration_status,
               "fitted_and_geographically_validated")
})

test_that("read_access_surface errors on a surface missing required columns", {
  p <- tempfile(fileext = ".csv")
  utils::write.csv(data.frame(demand_id = "01001020100", access = 1), p,
                   row.names = FALSE)
  expect_error(e$read_access_surface(p), "population")
})

test_that("integer-coerced GEOIDs are zero-padded without overflow", {
  # A CSV writer may drop the leading zero AND (for high-FIPS states) exceed the
  # 32-bit integer range; both must survive as 11-char strings.
  df <- data.frame(demand_id = c(1001020100, 56045951100),  # 01001..., 56045...
                   access = c(10, 4), population = c(100, 50))
  p <- tempfile(fileext = ".csv"); utils::write.csv(df, p, row.names = FALSE)
  s <- e$read_access_surface(p)
  expect_equal(s$data$demand_id, c("01001020100", "56045951100"))
  expect_false(anyNA(s$data$demand_id))
})

test_that("county_drive_time_access is a population-weighted mean by county", {
  cty <- e$county_drive_time_access(mk_surface_df())
  expect_setequal(cty$GEOID, c("01001", "01003"))
  a01001 <- cty$drive_time_access[cty$GEOID == "01001"]
  # (10*100 + 20*300) / (100+300) = 7000/400 = 17.5
  expect_equal(a01001, 17.5)
  expect_equal(cty$n_tracts[cty$GEOID == "01001"], 2L)
  expect_equal(cty$population[cty$GEOID == "01001"], 400)
  expect_equal(cty$drive_time_access[cty$GEOID == "01003"], 5)  # single tract
})

test_that("county_drive_time_access accepts the surface list or its data frame", {
  s <- list(data = mk_surface_df(), provenance = list())
  from_list <- e$county_drive_time_access(s)
  from_df   <- e$county_drive_time_access(mk_surface_df())
  expect_equal(from_list, from_df)
})

test_that("min_population drops small tracts before weighting", {
  cty <- e$county_drive_time_access(mk_surface_df(), min_population = 150)
  # in 01001 only the pop=300 tract survives -> access = 20
  expect_equal(cty$drive_time_access[cty$GEOID == "01001"], 20)
  expect_equal(cty$n_tracts[cty$GEOID == "01001"], 1L)
})

test_that("county_drive_time_access rejects a malformed surface", {
  expect_error(e$county_drive_time_access(data.frame(x = 1)), "access-surface")
})
