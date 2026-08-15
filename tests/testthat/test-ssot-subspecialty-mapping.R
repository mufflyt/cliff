# SSOT guard: the subspecialty abbreviation->name mappings (WC_SUBS match / WC_SUBS_FULL display),
# now canonical in R/workforce_constants.R (shared by both lineages). Display names must equal the
# frozen SSOT csv, and the match-vs-display distinction for URPS must be preserved.
library(testthat)
library(here)
suppressPackageStartupMessages(library(readr))

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

ce <- new.env(); source(here::here("R", "workforce_constants.R"), local = ce)
SF <- ce$WC_SUBS_FULL
SM <- ce$WC_SUBS

test_that("canonical subspecialty mappings are well-formed named vectors (URPS/GO/MIGS)", {
  expect_setequal(names(SF), c("URPS", "GO", "MIGS"))
  expect_identical(names(SM), names(SF))
  expect_identical(unname(SF[["URPS"]]), "Urogynecology and Reconstructive Pelvic Surgery")
  expect_identical(unname(SF[["GO"]]),   "Gynecologic Oncology")
  expect_identical(unname(SF[["MIGS"]]), "Minimally Invasive Gynecologic Surgery")
})

test_that("code<->data: WC_SUBS_FULL equals the frozen SSOT csv subspecialty column (drift guard)", {
  s <- read_csv(here::here("data", "workforce_projections_consolidated.csv"), show_col_types = FALSE)
  csv_map <- setNames(s$subspecialty, s$subspecialty_abbrev)
  for (k in names(SF)) expect_identical(unname(SF[[k]]), unname(csv_map[[k]]), info = k)
})

test_that("match vs display names stay DISTINCT for URPS (intentional difference preserved)", {
  expect_false(SM[["URPS"]] == SF[["URPS"]])   # "Female Pelvic Medicine..." != "Urogynecology..."
  expect_identical(unname(SM[["GO"]]), unname(SF[["GO"]]))   # GO identical in both
})

test_that("the engine still exposes WC_SUBS/WC_SUBS_FULL after the move (behavior-preserving)", {
  ee <- new.env(); suppressMessages(source(here::here("R", "workforce_cliff_engine.R"), local = ee))
  expect_identical(ee$WC_SUBS_FULL, SF)
  expect_identical(ee$WC_SUBS, SM)
})

test_that("[adversarial] no engine-sourcing script redefines WC_SUBS_FULL as a literal", {
  rfiles <- list.files(here::here("scripts"), pattern = "\\.R$", full.names = TRUE)
  offenders <- character()
  for (f in rfiles) {
    ls <- readLines(f, warn = FALSE)
    if (!any(grepl("workforce_cliff_engine\\.R", ls))) next
    if (any(grepl("WC_SUBS_FULL\\s*<-\\s*c\\(", ls))) offenders <- c(offenders, basename(f))
  }
  expect_equal(offenders, character(0),
               info = paste("WC_SUBS_FULL re-hardcoded in engine-sourcing script(s):", paste(offenders, collapse = "; ")))
})
