# wc_path() documents must_exist as applying to the resolved path. Environment
# overrides are still resolved paths; returning them early used to bypass that
# contract and let missing external inputs fail much later and less clearly.

library(testthat)

test_that("wc_path must_exist applies to environment overrides", {
  skip_if_no_repo()
  wc_path <- getFromNamespace("wc_path", "cliff")

  old <- Sys.getenv("WORKFORCE_COHORT_CSV", unset = NA_character_)
  on.exit({
    if (is.na(old)) Sys.unsetenv("WORKFORCE_COHORT_CSV") else Sys.setenv(WORKFORCE_COHORT_CSV = old)
  }, add = TRUE)

  missing <- file.path(tempdir(), "definitely-not-a-cohort.csv")
  Sys.setenv(WORKFORCE_COHORT_CSV = missing)
  expect_error(
    wc_path("cohort_csv", must_exist = TRUE),
    "file not found",
    fixed = TRUE
  )

  existing <- tempfile(fileext = ".csv")
  writeLines("npi\n1234567893", existing)
  Sys.setenv(WORKFORCE_COHORT_CSV = existing)
  expect_equal(wc_path("cohort_csv", must_exist = TRUE), path.expand(existing))
})
