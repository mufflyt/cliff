# cliff CHARTER guard: cliff CONSUMES the national URPS baseline from mufflyaccess and does NOT redefine it.
# Enforces (1) the baseline seam delegates to mufflyaccess::urps_count(); (2) no live cliff R producer
# re-hardcodes the national headline counts; (3) once mufflyaccess ships urps_count(), the seam returns the
# SSOT values (1031 ABOG-only / 1339 ABOG+ABU for 2023). See R/urps_baseline.R and docs/CHARTER_cliff.md.
library(testthat)
library(here)

test_that("the baseline seam delegates to mufflyaccess::urps_count (charter dependency direction)", {
  src <- readLines(here::here("R", "urps_baseline.R"), warn = FALSE)
  expect_true(any(grepl("mufflyaccess::urps_count", src)))          # single source
  expect_true(any(grepl("include_urology", src)))                   # both cohorts
  code <- src[!grepl("^\\s*#", src)]                                # scan CODE only (the header prose names rosters)
  expect_false(any(grepl("read.*abog|read.*abu|fread.*roster", code, ignore.case = TRUE)))  # no roster-reading code
})

test_that("[adversarial] no live cliff R code hardcodes the national URPS baseline (cannot redefine it)", {
  # The URPS-baseline-specific headline counts (1339 ABOG+ABU, 1031 ABOG-only, 1295 legacy) must not be
  # re-hardcoded in cliff producers — cliff obtains them only via urps_baseline()/mufflyaccess. Data CSVs,
  # tests, and the archival reconciliation doc are exempt; this scans live R producers only.
  files <- list.files(c(here::here("R"), here::here("scripts"), here::here("manuscript", "R")),
                      pattern = "\\.R$", full.names = TRUE, recursive = TRUE)
  files <- setdiff(files, here::here("R", "urps_baseline.R"))       # the seam names them in prose/docs
  offenders <- character()
  for (f in files) {
    ls <- readLines(f, warn = FALSE)
    ls <- ls[!grepl("^\\s*#", ls)]                                  # ignore comments
    if (any(grepl("\\b(1339|1031|1295)\\b", ls)))
      offenders <- c(offenders, basename(f))
  }
  expect_equal(offenders, character(0),
    info = paste("national URPS baseline hardcoded in cliff live code — must come via urps_baseline():",
                 paste(offenders, collapse = "; ")))
})

test_that("once mufflyaccess ships urps_count(), the seam returns the SSOT headline values", {
  have_api <- requireNamespace("mufflyaccess", quietly = TRUE) &&
    "urps_count" %in% getNamespaceExports("mufflyaccess")
  skip_if_not(have_api, "mufflyaccess::urps_count() not yet available (isochrones -> mufflyaccess chain pending)")
  e <- new.env(); source(here::here("R", "urps_baseline.R"), local = e)
  expect_identical(as.integer(e$urps_baseline(2023L, include_urology = FALSE)), 1031L)
  expect_identical(as.integer(e$urps_baseline(2023L, include_urology = TRUE)),  1339L)
})

test_that("until the SSOT API ships, the seam fails loud rather than silently deriving a baseline", {
  have_api <- requireNamespace("mufflyaccess", quietly = TRUE) &&
    "urps_count" %in% getNamespaceExports("mufflyaccess")
  skip_if(have_api, "mufflyaccess::urps_count() is available; the fail-loud path no longer applies")
  e <- new.env(); source(here::here("R", "urps_baseline.R"), local = e)
  expect_error(e$urps_baseline(2023L), "mufflyaccess release that provides urps_count")
})
