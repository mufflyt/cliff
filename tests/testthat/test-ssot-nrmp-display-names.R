# SSOT guard: the NRMP fellowship-entrants producer (scripts/fetch_nrmp_fellowship_entrants.R)
# previously kept a THIRD independent copy of the subspecialty DISPLAY names in its `subspecialty`
# column. That column is now DERIVED from R/workforce_constants.R::WC_SUBS_FULL. The neighbouring
# `nrmp_label` (the string used to grep the NRMP PDF) is a DIFFERENT value and must stay distinct.
library(testthat)
library(here)
suppressPackageStartupMessages(library(readr))

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

ce <- new.env(); source(here::here("R", "workforce_constants.R"), local = ce)
SF <- ce$WC_SUBS_FULL

test_that("the emitted NRMP CSV's subspecialty column equals the canonical WC_SUBS_FULL (code<->data)", {
  csv <- read_csv(here::here("data", "nrmp_fellowship_entrants.csv"), show_col_types = FALSE)
  m <- setNames(csv$subspecialty, csv$subspecialty_abbrev)
  for (k in names(SF)) expect_identical(unname(m[[k]]), unname(SF[[k]]), info = k)
})

test_that("the derived column reproduces the exact prior literals (behavior-preserving)", {
  # the values that were hardcoded before the refactor
  old <- c(URPS = "Urogynecology and Reconstructive Pelvic Surgery",
           GO   = "Gynecologic Oncology",
           MIGS = "Minimally Invasive Gynecologic Surgery")
  derived <- unname(SF[names(old)])
  expect_identical(derived, unname(old))
})

test_that("the producer derives subspecialty from the SSOT, with no re-typed display literal", {
  ls <- readLines(here::here("scripts", "fetch_nrmp_fellowship_entrants.R"), warn = FALSE)
  expect_true(any(grepl("WC_SUBS_FULL\\[", ls)))                       # derives from canonical
  expect_true(any(grepl("workforce_constants\\.R", ls)))              # sources the SSOT module
  # the display name must NOT be re-typed as a subspecialty-column literal
  expect_false(any(grepl('subspecialty\\s*=\\s*c\\("Urogynecology', ls)))
})

test_that("nrmp_label stays DISTINCT from the display name for URPS (intentional difference kept)", {
  ls <- paste(readLines(here::here("scripts", "fetch_nrmp_fellowship_entrants.R"), warn = FALSE), collapse = "\n")
  # the PDF-grep label for URPS is deliberately not the display name
  expect_true(grepl("Female Pelvic Medicine and Reconstructive", ls, fixed = TRUE))
  expect_false(identical("Female Pelvic Medicine and Reconstructive", unname(SF[["URPS"]])))
})
