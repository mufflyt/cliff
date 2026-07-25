# SSOT guard: the age-reconstruction assumption (engine WC_AGE_AT_CERT = 30). Physician age is
# reconstructed as REF_YEAR - cert_year + AGE_AT_CERT, which feeds band assignment -> hazards, so a
# drift here silently shifts everyone's band. Also guards the entry-age relationship.
library(testthat)
library(here)

ee <- new.env()
suppressPackageStartupMessages(source(here::here("R", "workforce_cliff_engine.R"), local = ee))

test_that("WC_AGE_AT_CERT is a valid positive-integer assumption (30 years)", {
  expect_type(ee$WC_AGE_AT_CERT, "integer")
  expect_length(ee$WC_AGE_AT_CERT, 1L)
  expect_identical(ee$WC_AGE_AT_CERT, 30L)
  expect_true(ee$WC_AGE_AT_CERT > 0L)
})

test_that("age assumptions are internally consistent (graduates enter after certification age)", {
  expect_true(ee$WC_ENTRY_AGE > ee$WC_AGE_AT_CERT)   # 34 > 30
})

test_that("semantic: reconstructed age = REF_YEAR - cert_year + AGE_AT_CERT, and bands it correctly", {
  recon <- function(cy) ee$WC_REF_YEAR - cy + ee$WC_AGE_AT_CERT
  expect_identical(recon(2020L), 34L)                       # certified 2020 -> age 34 at REF_YEAR 2024
  expect_identical(recon(ee$WC_REF_YEAR), ee$WC_AGE_AT_CERT)# certified this year -> age == cert age
  band <- function(a) as.character(cut(a, ee$WC_BANDS, labels = ee$WC_BAND_LABELS, right = FALSE))
  expect_identical(band(recon(2020L)), "<45")              # a recent certificant lands youngest
  expect_identical(band(recon(1979L)), "70+")              # 2024-1979+30 = 75 -> oldest band
})

test_that("[adversarial] no engine-sourcing script redefines AGE_AT_CERT as a literal", {
  rfiles <- list.files(here::here("scripts"), pattern = "\\.R$", full.names = TRUE)
  offenders <- character()
  for (f in rfiles) {
    ls <- readLines(f, warn = FALSE)
    if (!any(grepl("workforce_cliff_engine\\.R", ls))) next
    hit <- grepl("(^|[^_])AGE_AT_CERT\\s*<-\\s*[0-9]", ls)
    if (any(hit)) offenders <- c(offenders, sprintf("%s:%s", basename(f), paste(which(hit), collapse = ",")))
  }
  expect_equal(offenders, character(0),
               info = paste("AGE_AT_CERT re-hardcoded in engine-sourcing script(s):", paste(offenders, collapse = "; ")))
})
