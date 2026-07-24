# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Guards the single-authoritative-SSOT-writer invariant. rebuild_ssot_revised.R is
# the ONLY script that may write cliff/data/workforce_projections_consolidated.csv;
# the other builders must fail closed unless WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE=1.
# Prevents the silent headline (7.1/5.6) drift from a stale competing builder.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
library(testthat)
.root <- tryCatch(here::here(), error = function(e) {
  d <- normalizePath("."); while (!file.exists(file.path(d, "scripts", "rebuild_ssot_revised.R")) &&
       dirname(d) != d) d <- dirname(d); d })
rd <- function(f) paste(readLines(file.path(.root, "scripts", f), warn = FALSE), collapse = "\n")

test_that("non-canonical SSOT builders fail closed on the consolidated write", {
  for (f in c("rebuild_ssot_final.R", "rebuild_ssot_dynamic_acgme.R")) {
    src <- rd(f)
    # writes the consolidated CSV ...
    expect_true(grepl("workforce_projections_consolidated.csv", src, fixed = TRUE), info = f)
    # ... but only behind the fail-closed guard, keyed to the override env var
    expect_true(grepl("WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE", src, fixed = TRUE), info = f)
    expect_true(grepl("REFUSED", src, fixed = TRUE), info = f)
  }
})

test_that("rebuild_ssot_revised.R is the marked canonical writer", {
  src <- rd("rebuild_ssot_revised.R")
  expect_true(grepl("CANONICAL SSOT WRITER", src, fixed = TRUE))
  expect_true(grepl("write_csv(primary, here::here(\"cliff\",\"data\",\"workforce_projections_consolidated.csv\"))", src, fixed = TRUE))
  # it must NOT carry the refusal guard itself (it is the one allowed to write);
  # the canonical marker comment may name the override var when describing the variants,
  # so we assert the absence of the REFUSED stop rather than the env-var mention.
  expect_false(grepl("stop(\"REFUSED", src, fixed = TRUE))
})

test_that("rebuild_ssot_from_nrmp.R does not write the consolidated SSOT", {
  src <- rd("rebuild_ssot_from_nrmp.R")
  expect_false(grepl("write_csv\\([^)]*workforce_projections_consolidated", src))
  expect_false(grepl("write.csv\\([^)]*workforce_projections_consolidated", src))
})

test_that("the guard expression refuses when the override is unset and allows when set", {
  guard <- function() if (!identical(Sys.getenv("WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE"), "1"))
    stop("REFUSED", call. = FALSE)
  old <- Sys.getenv("WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE", unset = NA)
  on.exit(if (is.na(old)) Sys.unsetenv("WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE") else
            Sys.setenv(WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE = old))
  Sys.unsetenv("WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE")
  expect_error(guard(), "REFUSED")
  Sys.setenv(WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE = "1")
  expect_silent(guard())
})
