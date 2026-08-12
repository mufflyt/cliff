# SSOT guard: the adequacy app's physician entry-age default 34 (iter49). It was hardcoded across
# shiny_urps_adequacy/model.R (DEFAULTS) and app.R (the entry_age slider DEFAULT + reset handler). Now one
# constant model.R::ENTRY_AGE_DEFAULT drives all of them. Because the app deploys standalone (cannot source R/),
# the constant is the app-local copy of the study entry age R/workforce_constants.R::WORKFORCE_ENTRY_AGE
# (iter26/34) and is kept in sync by the parity check below.
#
# INTENTIONALLY NOT collapsed: the slider RANGE 30-45 (the selectable entry-age bounds) is a distinct scenario
# knob, left literal. Independent-oracle test fixtures (entry_age=34) stay literal (iter15 precedent).
library(testthat)
library(here)

MODEL <- here::here("shiny_urps_adequacy", "model.R")
APP   <- here::here("shiny_urps_adequacy", "app.R")
src   <- readLines(MODEL, warn = FALSE)
app   <- readLines(APP, warn = FALSE)

.eval_const <- function(name, lines) {
  hit <- grep(paste0("^\\s*", name, "\\s*<-"), lines, value = TRUE)
  stopifnot(length(hit) == 1L)
  eval(parse(text = sub("#.*$", "", hit)))
}
AGE <- .eval_const("ENTRY_AGE_DEFAULT", src)

test_that("the canonical entry-age default is a well-formed 34 within the plausible range", {
  expect_type(AGE, "integer")
  expect_length(AGE, 1L)
  expect_identical(AGE, 34L)
  expect_gte(AGE, 30L); expect_lte(AGE, 45L)     # inside the slider bounds
})

test_that("[cross-lineage parity] the app entry age matches the study WORKFORCE_ENTRY_AGE", {
  wc <- new.env(); source(here::here("R", "workforce_constants.R"), local = wc)
  expect_identical(AGE, wc$WORKFORCE_ENTRY_AGE)   # the self-contained-app copy must not drift from the SSOT
})

test_that("[adversarial] model.R + app.R reference the SSOT, not a bare entry_age=34 literal", {
  expect_true(any(grepl("entry_age=ENTRY_AGE_DEFAULT", src)))
  expect_false(any(grepl("entry_age=34L", src)))
  expect_true(any(grepl('"entry_age",.*30, 45, ENTRY_AGE_DEFAULT', app)))    # slider default wired
  expect_true(any(grepl('"entry_age",value=ENTRY_AGE_DEFAULT', app)))        # reset wired
  expect_false(any(grepl('"entry_age",value=34', app)))
})

test_that("[intentional difference] the slider RANGE 30-45 stays literal, distinct from the default", {
  expect_true(any(grepl('"entry_age",[^,]*, 30, 45, ENTRY_AGE_DEFAULT', app)))   # min 30 / max 45 literal
  expect_true(AGE > 30L && AGE < 45L)                                            # default sits strictly inside the range
})

test_that("[behavior-preserving] the entry age is unchanged (34) and integer-typed", {
  expect_identical(AGE, 34L)
  expect_true(is.integer(AGE))
})
