# SSOT guard: the projection horizon has ONE canonical source
# (R/workforce_constants.R::WORKFORCE_PROJECTION_HORIZON_YEARS). The engine's
# WC_HORIZON and the data contract must both derive from it, never a private literal.
library(testthat)
library(here)

test_that("canonical horizon is a valid positive-integer scalar", {
  e <- new.env(); source(here::here("R", "workforce_constants.R"), local = e)
  expect_type(e$WORKFORCE_PROJECTION_HORIZON_YEARS, "integer")
  expect_length(e$WORKFORCE_PROJECTION_HORIZON_YEARS, 1L)
  expect_false(is.na(e$WORKFORCE_PROJECTION_HORIZON_YEARS))
  expect_gte(e$WORKFORCE_PROJECTION_HORIZON_YEARS, 1L)
})

test_that("engine WC_HORIZON derives from the canonical constant (== 4L for this study)", {
  e <- new.env()
  suppressPackageStartupMessages(source(here::here("R", "workforce_cliff_engine.R"), local = e))
  expect_identical(e$WC_HORIZON, e$WORKFORCE_PROJECTION_HORIZON_YEARS)
  expect_identical(e$WC_HORIZON, 4L)   # Hall-of-Shame pin: 2025 -> 2029 = 4 transitions
})

test_that("contract and engine cannot drift: both read the same canonical horizon", {
  ce <- new.env(); source(here::here("manuscript", "R", "workforce_data_contract.R"), local = ce)
  ee <- new.env(); suppressPackageStartupMessages(source(here::here("R", "workforce_cliff_engine.R"), local = ee))
  expect_identical(ce$WORKFORCE_PROJECTION_HORIZON_YEARS, ee$WC_HORIZON)
})

test_that("wc_project() defaults its horizon to the canonical constant", {
  ee <- new.env(); suppressPackageStartupMessages(source(here::here("R", "workforce_cliff_engine.R"), local = ee))
  expect_identical(formals(ee$wc_project)$horizon, as.name("WC_HORIZON"))
})

test_that("changing the SSOT propagates to WC_HORIZON (single source, not a copy)", {
  # Load the engine, then mutate the canonical and re-derive: WC_HORIZON must follow.
  ee <- new.env(); suppressPackageStartupMessages(source(here::here("R", "workforce_cliff_engine.R"), local = ee))
  ee$WORKFORCE_PROJECTION_HORIZON_YEARS <- 6L
  ee$WC_HORIZON <- ee$WORKFORCE_PROJECTION_HORIZON_YEARS   # the engine's own assignment form
  expect_identical(ee$WC_HORIZON, 6L)
})

test_that("[adversarial] no R file reintroduces an independent horizon literal", {
  root <- here::here()
  dirs <- c(file.path(root, "R"), file.path(root, "manuscript", "R"))
  rfiles <- list.files(dirs, pattern = "\\.R$", full.names = TRUE, recursive = TRUE)
  rfiles <- setdiff(rfiles, file.path(root, "R", "workforce_constants.R"))  # the one allowed home
  offenders <- character()
  for (f in rfiles) {
    ls <- readLines(f, warn = FALSE)
    hit <- grepl("^\\s*(WC_HORIZON|WORKFORCE_PROJECTION_HORIZON_YEARS)\\s*<-\\s*[0-9]", ls)
    if (any(hit)) offenders <- c(offenders, sprintf("%s:%s", basename(f), paste(which(hit), collapse = ",")))
  }
  expect_equal(offenders, character(0),
               info = paste("horizon redefined as a bare literal in:", paste(offenders, collapse = "; ")))
})
