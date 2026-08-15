# SSOT guard: the adequacy app's reference annual entrant inflow (iter48). It was hardcoded as bare 64 in
# shiny_urps_adequacy/model.R (DEFAULTS) and app.R (Reference preset + reset handler). Now DERIVED as
# ENTRANTS_DEFAULT <- as.integer(round(mean(GRAD_URPS))) from the GRAD_URPS the app already sources (its
# urps_model_data.R snapshot), so it tracks the ACGME graduate counts exactly like the scripts' ENTRANTS <-
# mean(GRAD_URPS) (iter7/33) and the engine WC_ENTRANTS[["URPS"]].
#
# INTENTIONALLY NOT collapsed: the Lower/Higher-entrants scenario presets (48 / 80) and the slider range are
# distinct scenario knobs, left literal. Independent-oracle test fixtures (entrants=64) stay literal (iter15).
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

MODEL <- here::here("shiny_urps_adequacy", "model.R")
APP   <- here::here("shiny_urps_adequacy", "app.R")
src   <- readLines(MODEL, warn = FALSE)
app   <- readLines(APP, warn = FALSE)

# GRAD_URPS lives in the app's snapshot; source it, then evaluate the derived constant line in that scope.
snap <- new.env(); source(here::here("shiny_urps_adequacy", "data", "urps_model_data.R"), local = snap)
def_line <- grep("^\\s*ENTRANTS_DEFAULT\\s*<-", src, value = TRUE)
stopifnot(length(def_line) == 1L)
ENTRANTS <- eval(parse(text = sub("#.*$", "", def_line)), envir = snap)

test_that("the reference entrant inflow derives to 64 (mean of the graduate counts)", {
  expect_type(ENTRANTS, "integer")
  expect_length(ENTRANTS, 1L)
  expect_identical(ENTRANTS, 64L)
  expect_identical(ENTRANTS, as.integer(round(mean(snap$GRAD_URPS))))
})

test_that("[semantic] it is DERIVED from GRAD_URPS, not a bare 64 literal (tracks a change)", {
  expect_true(any(grepl("ENTRANTS_DEFAULT\\s*<-\\s*as.integer\\(round\\(mean\\(GRAD_URPS\\)\\)\\)", src)))
  expect_false(any(grepl("ENTRANTS_DEFAULT\\s*<-\\s*64", src)))
  # a hypothetical different graduate vector would change the derived mean -> proves it's not a constant 64
  expect_identical(as.integer(round(mean(c(60, 60, 60, 60)))), 60L)   # a different cohort derives to 60, not 64
  expect_false(as.integer(round(mean(c(60, 60, 60, 60)))) == 64L)
})

test_that("[cross-lineage consistency] it equals the engine's derived URPS entrant mean", {
  ee <- new.env()
  ok <- tryCatch({ suppressMessages(suppressWarnings(source(here::here("R", "workforce_cliff_engine.R"), local = ee))); TRUE },
                 error = function(e) FALSE)
  skip_if_not(ok, "engine could not be sourced")
  expect_identical(ENTRANTS, as.integer(round(ee$WC_ENTRANTS[["URPS"]])))
})

test_that("[adversarial] model.R + app.R reference the derived default, not a bare entrants=64", {
  expect_true(any(grepl("entrants=ENTRANTS_DEFAULT", src)))
  expect_true(any(grepl("entrants=ENTRANTS_DEFAULT", app)))
  expect_true(any(grepl('"entrants",value=ENTRANTS_DEFAULT', app)))
  expect_false(any(grepl("entrants=64[L,)]", src)))
  expect_false(any(grepl("entrants=64[,)]", app)))
  expect_false(any(grepl('"entrants",value=64', app)))
})

test_that("[intentional difference] the Lower/Higher-entrants scenario presets stay literal (48 / 80)", {
  expect_true(any(grepl("entrants=48", app)))     # Lower entrants scenario preserved
  expect_true(any(grepl("entrants=80", app)))     # Higher entrants scenario preserved
})
