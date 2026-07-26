# SSOT guard: the adequacy app's projection horizon END year 2050 (iter46). It was duplicated across
# shiny_urps_adequacy/model.R (DEFAULTS end_year=2050L) and app.R (the end_year slider MAX + DEFAULT, and the
# reset handler). Now one constant model.R::PROJECTION_END_YEAR drives all of them. Because the app deploys
# standalone (cannot source R/), the constant is the app-local copy of the manuscript horizon end
# R/demand_denominator.R::DEMAND_HORIZON_END_YEAR (iter24) and is kept in sync by the parity check below.
#
# INTENTIONALLY NOT collapsed: the slider MINIMUM 2035 (shortest selectable horizon) and BASE_YEAR 2025 (the
# projection START) are distinct values, left literal. The independent-oracle test fixtures (end_year=2050 in the
# fingerprint lists) are all-literal snapshots, left literal per iter15's precedent.
library(testthat)
library(here)

MODEL <- here::here("shiny_urps_adequacy", "model.R")
APP   <- here::here("shiny_urps_adequacy", "app.R")
src   <- readLines(MODEL, warn = FALSE)
app   <- readLines(APP, warn = FALSE)

# Evaluate ONLY the canonical constant line (model.R reads data files, so it can't be sourced whole).
.eval_const <- function(name, lines) {
  hit <- grep(paste0("^\\s*", name, "\\s*<-"), lines, value = TRUE)
  stopifnot(length(hit) == 1L)
  eval(parse(text = sub("#.*$", "", hit)))
}
END      <- .eval_const("PROJECTION_END_YEAR", src)
BASEYEAR <- .eval_const("BASE_YEAR", src)

test_that("the canonical horizon-end is a well-formed 2050 after the base year", {
  expect_type(END, "integer")
  expect_length(END, 1L)
  expect_identical(END, 2050L)
  expect_gt(END, BASEYEAR)                 # end after start (2050 > 2025)
})

test_that("[cross-lineage parity] the app horizon end matches the manuscript DEMAND_HORIZON_END_YEAR", {
  de <- new.env(); source(here::here("R", "demand_denominator.R"), local = de)
  expect_identical(END, de$DEMAND_HORIZON_END_YEAR)      # the self-contained-app copy must not drift from the SSOT
})

test_that("[adversarial] model.R + app.R reference the SSOT, not a bare 2050 horizon literal", {
  expect_true(any(grepl("end_year=PROJECTION_END_YEAR", src)))
  expect_false(any(grepl("end_year=2050L", src)))
  expect_true(any(grepl('"end_year",\\s*slab\\("Projection horizon \\(year\\)"\\),\\s*2035,\\s*PROJECTION_END_YEAR,\\s*PROJECTION_END_YEAR', app)))
  expect_true(any(grepl('"end_year",value=PROJECTION_END_YEAR', app)))
  expect_false(any(grepl('"end_year",value=2050', app)))
})

test_that("[intentional difference] the slider MIN 2035 and BASE_YEAR 2025 are distinct, left literal", {
  expect_true(any(grepl("2035,\\s*PROJECTION_END_YEAR", app)))   # min horizon 2035 stays a literal
  expect_identical(BASEYEAR, 2025L)                              # start year is its own constant, != END
  expect_true(END != BASEYEAR)
})

test_that("[behavior-preserving] the projected-year span is unchanged (2025..2050 inclusive)", {
  expect_identical(BASEYEAR:END, 2025L:2050L)                    # BASE_YEAR:end_year loop bound identical
  expect_identical(END - BASEYEAR + 1L, 26L)                     # 26 projected years, as before
})
