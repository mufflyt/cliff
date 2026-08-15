# SSOT guard: the primary hazard-estimation observation window (engine WC_WIN = 2016-2021).
# It defines which departures are right-censoring-safe; a drifted bound would change every
# hazard. Guards the canonical shape and ties the Shiny prose label to the constant.
library(testthat)
library(here)

# Repository integration test: sources R/ or data/ from the SOURCE TREE via
# here(). An installed package has no R/*.R files, so this is inapplicable
# rather than broken there. See helper-cliff-root.R.
skip_if_no_repo()

ee <- new.env()
suppressPackageStartupMessages(source(here::here("R", "workforce_cliff_engine.R"), local = ee))

WIN <- ee$WC_WIN

test_that("canonical observation window is a valid 2-year integer range (2016-2021)", {
  expect_type(WIN, "integer")
  expect_length(WIN, 2L)
  expect_identical(WIN, c(2016L, 2021L))
  expect_true(WIN[[1]] < WIN[[2]])
})

test_that("observation window is consistent with the study reference/obs-end years", {
  # window must sit within [study start, last observable] and be strictly before REF_YEAR
  expect_true(WIN[[1]] >= 2013L)                 # study window start floor
  expect_true(WIN[[2]] <  ee$WC_REF_YEAR)        # 2021 < 2024 (3-yr follow-up headroom)
  expect_true(WIN[[2]] <= ee$WC_OBS_END)         # 2021 <= 2023 last fully-observable
})

test_that("Shiny primary-window LABEL is derived-consistent with WC_WIN (prose ties to constant)", {
  se <- new.env(); source(here::here("shiny_urps_scenarios", "urps_model_data.R"), local = se)
  lab <- se$WINDOW_LABELS[["fully_obs"]]
  expect_true(grepl(sprintf("%d-%d", WIN[[1]], WIN[[2]]), lab, fixed = TRUE),
              info = paste("fully_obs label:", lab))
})

test_that("[adversarial] no engine-sourcing script redefines the observation window as a literal", {
  rfiles <- list.files(here::here("scripts"), pattern = "\\.R$", full.names = TRUE)
  offenders <- character()
  for (f in rfiles) {
    ls <- readLines(f, warn = FALSE)
    if (!any(grepl("workforce_cliff_engine\\.R", ls))) next
    hit <- grepl("\\bWIN\\s*<-\\s*c\\(20", ls)
    if (any(hit)) offenders <- c(offenders, sprintf("%s:%s", basename(f), paste(which(hit), collapse = ",")))
  }
  expect_equal(offenders, character(0),
               info = paste("obs window re-hardcoded in engine-sourcing script(s):", paste(offenders, collapse = "; ")))
})
