# Gate 52: the access-surface seam into Module D.
#
# test-access-surface.R already covers reading and aggregating a surface. This
# covers the decision that sits between them: whether a surface is allowed to
# enter Module D at all.
#
# The failure this guards against is not a crash. It is a malformed, empty or
# absent surface being treated as a usable one, so Module D produces an access
# number derived from nothing and no error is ever raised. "No surface" and
# "a surface saying access is zero" must never be the same answer.

test_that("a NULL surface is not usable", {
  # read_access_surface() returns NULL for an absent path, so NULL is the normal
  # representation of "there is no surface" rather than an error case.
  expect_false(cliff:::access_surface_usable(NULL))
})

test_that("an empty surface is not usable", {
  empty <- list(data = data.frame(demand_id = character(0),
                                  access = numeric(0),
                                  population = numeric(0)),
                provenance = list())
  expect_false(cliff:::access_surface_usable(empty))
})

test_that("a surface whose data is not a data frame is not usable", {
  for (bad in list(list(data = NULL, provenance = list()),
                   list(data = "not a data frame", provenance = list()),
                   list(data = list(1, 2, 3), provenance = list()),
                   list(provenance = list()))) {
    expect_false(cliff:::access_surface_usable(bad))
  }
})

test_that("a populated surface is usable", {
  ok <- list(data = data.frame(demand_id = c("01001020100", "01001020200"),
                               access = c(12.5, 30.0),
                               population = c(1000, 2000)),
             provenance = list(calibration_status = "calibrated"))
  expect_true(cliff:::access_surface_usable(ok))
})

test_that("an absent path yields NULL rather than an empty-but-usable surface", {
  # The distinction that matters: a missing file must not become a surface with
  # zero rows that later reads as "access is zero everywhere".
  expect_null(cliff:::read_access_surface(file.path(tempdir(), "no-such-file.csv")))
  expect_null(cliff:::read_access_surface(""))
  expect_null(cliff:::read_access_surface(NULL))
})

test_that("a surface missing required columns is refused loudly, not silently dropped", {
  p <- tempfile(fileext = ".csv")
  on.exit(unlink(p), add = TRUE)
  utils::write.csv(data.frame(demand_id = "01001020100", access = 10),
                   p, row.names = FALSE)   # no `population`
  expect_error(cliff:::read_access_surface(p), "missing column")
})

test_that("what read_access_surface accepts, the usability gate agrees on", {
  # The two must not disagree: a surface that parses but is then judged unusable
  # (or vice versa) is how an unvalidated artifact slips through.
  p <- tempfile(fileext = ".csv")
  on.exit(unlink(p), add = TRUE)

  utils::write.csv(data.frame(demand_id = c("01001020100", "01001020200"),
                              access = c(5, 15), population = c(10, 20)),
                   p, row.names = FALSE)
  s <- cliff:::read_access_surface(p)
  expect_true(cliff:::access_surface_usable(s))

  # A syntactically valid file with no rows parses, and must be judged unusable.
  utils::write.csv(data.frame(demand_id = character(0), access = numeric(0),
                              population = numeric(0)),
                   p, row.names = FALSE)
  s0 <- cliff:::read_access_surface(p)
  expect_false(cliff:::access_surface_usable(s0))
})

test_that("county aggregation refuses a malformed surface rather than guessing", {
  expect_error(cliff:::county_drive_time_access(NULL))
  expect_error(cliff:::county_drive_time_access(list(data = data.frame(x = 1))))
})

test_that("provenance travels with the surface", {
  # An access number with no record of which isochrone run produced it cannot be
  # audited later. Provenance columns present in the file must survive the read.
  p <- tempfile(fileext = ".csv")
  on.exit(unlink(p), add = TRUE)
  utils::write.csv(
    data.frame(demand_id = "01001020100", access = 10, population = 100,
               isochrone_run_id = "run-2026-08-01", calibration_status = "calibrated"),
    p, row.names = FALSE)
  s <- cliff:::read_access_surface(p)
  expect_equal(s$provenance$isochrone_run_id, "run-2026-08-01")
  expect_equal(s$provenance$calibration_status, "calibrated")
})

test_that("GEOIDs keep their leading zeros through the read", {
  # An integer-coerced GEOID silently renames a county. Alabama (01...) becomes
  # a different place, and the join downstream quietly drops or mismatches it.
  p <- tempfile(fileext = ".csv")
  on.exit(unlink(p), add = TRUE)
  utils::write.csv(data.frame(demand_id = 1001020100,   # leading zero lost by CSV
                              access = 10, population = 100),
                   p, row.names = FALSE)
  s <- cliff:::read_access_surface(p)
  expect_equal(nchar(s$data$demand_id), 11L)
  expect_match(s$data$demand_id, "^0")
})
