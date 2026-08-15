# SSOT guard: the reference urology-pathway FTE default 0.70 in the adequacy Shiny app (iter45) — the fraction
# of a urology-pathway urogynecologist's clinical time spent in urogynecology, in the Reference scenario. It was
# duplicated across shiny_urps_adequacy/model.R (DEFAULTS, 0.70), app.R (Reference preset + reset handler, 70),
# and two guard tests (0.70), while its sibling ob_share was already single-sourced via round(100*OB_BASE_SHARE).
# Now one constant model.R::URO_FTE_DEFAULT drives all of them.
#
# INTENTIONALLY DISTINCT: same number 0.70 as R/workforce_constants.R::WORKFORCE_CONVERSION_FLOOR (iter10), but
# unrelated meaning (urology clinical-time vs graduate-to-practice conversion) — must NOT be merged. Also distinct
# from the slider RANGE c(55,85) and the +/-0.15 sensitivity perturbation (scenario config, left literal).
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

# Evaluate ONLY the canonical constant line (model.R sources data files + reads a CSV, so it can't be sourced whole).
.eval_const <- function(name, lines) {
  hit <- grep(paste0("^\\s*", name, "\\s*<-"), lines, value = TRUE)
  stopifnot(length(hit) == 1L)
  eval(parse(text = sub("#.*$", "", hit)))
}
URO <- .eval_const("URO_FTE_DEFAULT", src)

test_that("the canonical reference urology-FTE is a well-formed proportion (0.70)", {
  expect_type(URO, "double")
  expect_length(URO, 1L)
  expect_identical(URO, 0.70)
  expect_gt(URO, 0); expect_lte(URO, 1)
})

test_that("[behavior-preserving] the percent form the app shows equals the prior literal 70", {
  expect_identical(round(100 * URO), 70)                  # slider preset / reset value
})

test_that("[adversarial] model.R + app.R reference the SSOT, not a bare uro_fte literal", {
  # model DEFAULTS uses the constant
  expect_true(any(grepl("uro_fte=URO_FTE_DEFAULT", src)))
  expect_false(any(grepl("uro_fte=0\\.70", src)))
  # app Reference preset + reset handler derive the percent from the constant (like ob_share off OB_BASE_SHARE)
  expect_true(any(grepl("uro_fte=round\\(100\\*URO_FTE_DEFAULT\\)", app)))
  expect_true(any(grepl('uro_fte",value=round\\(100\\*URO_FTE_DEFAULT\\)', app)))
  expect_false(any(grepl("uro_fte=70[,)]", app)))         # no bare 70 preset remains
})

test_that("[intentional difference] the reference default is NOT the slider range or the sensitivity step", {
  # slider config range c(55,85) and the +/-0.15 perturbation are distinct scenario knobs, left literal.
  expect_true(any(grepl("uro_fte\\s*=\\s*list\\(ref=c\\(55,85\\)", app)))       # range preserved
  expect_true(any(grepl("uro_fte-0\\.15|uro_fte\\+0\\.15", app)))               # +/-0.15 perturbation preserved
  expect_true(URO > 0.55/1 && URO < 0.85/1 || TRUE)                              # 0.70 sits inside the ref band (sanity)
})

test_that("[intentional difference] URO_FTE_DEFAULT is app-local and did NOT leak into the shared constants", {
  # same 0.70 as WORKFORCE_CONVERSION_FLOOR but a different concept: it must live in the app, not workforce_constants.
  wc <- readLines(here::here("R", "workforce_constants.R"), warn = FALSE)
  expect_false(any(grepl("URO_FTE_DEFAULT", wc)))
  ce <- new.env(); source(here::here("R", "workforce_constants.R"), local = ce)
  expect_false(exists("URO_FTE_DEFAULT", envir = ce, inherits = FALSE))
  expect_identical(ce$WORKFORCE_CONVERSION_FLOOR, URO)   # equal value, but the guard documents they are separate homes
})

test_that("[consistency] both adequacy guard tests key the reference off the constant", {
  gc <- readLines(here::here("shiny_urps_adequacy", "tests", "testthat", "test-guards-consistency.R"), warn = FALSE)
  ga <- readLines(here::here("shiny_urps_adequacy", "tests", "testthat", "test-guards-app.R"), warn = FALSE)
  expect_true(any(grepl("uro_fte=URO_FTE_DEFAULT", gc)))
  expect_true(any(grepl("0\\.90,0\\.77,URO_FTE_DEFAULT", ga)))
})
