# Regression tests for FREIDA coordinate loading. Coordinates are a pair: taking
# latitude from one source and longitude from another fabricates a location that
# exists in neither source.

library(testthat)

.write_freida_coordinate_fixture <- function(dir, extra_columns = list()) {
  x <- data.frame(
    pgm_title = "Synthetic Fellowship",
    inst_title = "Synthetic Institution",
    pgm_field_address_locality = "Denver",
    pgm_field_address_administrative_area = "CO",
    pgm_field_program_id = "P1",
    Specialty = "Synthetic Specialty",
    primary_teaching_title = "Synthetic Hospital",
    primary_teaching_field_annual_births = 100,
    primary_teaching_field_neonatal_icu = 10,
    primary_teaching_field_number_beds = 200,
    primary_teaching_field_trauma_center = "Yes",
    survey_field_first_year_positions = 2,
    primary_teaching_field_address_postal_code = "80218",
    primary_teaching_field_address_address_line1 = "100 Synthetic Street",
    stringsAsFactors = FALSE
  )
  for (nm in names(extra_columns)) x[[nm]] <- extra_columns[[nm]]
  utils::write.csv(
    x,
    file.path(dir, "freida_otolaryngology_fellowship_details_cleaned.csv"),
    row.names = FALSE,
    na = ""
  )
}

.read_fixture_programs <- function(dir) {
  suppressWarnings(suppressMessages(
    load_freida_programs("fellowship", freida_dir = dir)
  ))
}

test_that("FREIDA loading accepts a contact-only coordinate pair", {
  skip_if_not_installed("readr")
  dir <- tempfile("freida-contact-only-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE, force = TRUE), add = TRUE)

  .write_freida_coordinate_fixture(dir, list(
    contact_field_geolocation_lat = 39.7392,
    contact_field_geolocation_lon = -104.9903
  ))

  programs <- .read_fixture_programs(dir)
  expect_equal(nrow(programs), 1L)
  expect_equal(programs$lat, 39.7392)
  expect_equal(programs$lon, -104.9903)
})

test_that("FREIDA loading accepts a program-only coordinate pair", {
  skip_if_not_installed("readr")
  dir <- tempfile("freida-pgm-only-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE, force = TRUE), add = TRUE)

  .write_freida_coordinate_fixture(dir, list(
    pgm_field_geolocation_lat = 39.7392,
    pgm_field_geolocation_lon = -104.9903
  ))

  programs <- .read_fixture_programs(dir)
  expect_equal(nrow(programs), 1L)
  expect_equal(programs$lat, 39.7392)
  expect_equal(programs$lon, -104.9903)
})

test_that("incomplete contact coordinates do not mix latitude and longitude sources", {
  skip_if_not_installed("readr")
  dir <- tempfile("freida-mixed-pair-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE, force = TRUE), add = TRUE)

  .write_freida_coordinate_fixture(dir, list(
    contact_field_geolocation_lat = 39.0000,
    contact_field_geolocation_lon = NA_real_,
    pgm_field_geolocation_lat = 40.0000,
    pgm_field_geolocation_lon = -105.0000
  ))

  programs <- .read_fixture_programs(dir)
  expect_equal(nrow(programs), 1L)
  expect_equal(programs$lat, 40.0000)
  expect_equal(programs$lon, -105.0000)
})
