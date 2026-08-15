# SSOT guard: the adequacy app's projection START year BASE_YEAR (iter51). BASE_YEAR is already single-sourced
# within the app (defined once at model.R, referenced by name), so this is a DRIFT GUARD (no refactor): the
# app-local BASE_YEAR must match the study projection baseline R/workforce_constants.R::PROJECTION_BASELINE_YEAR
# (iter23). The app deploys standalone and cannot source R/, so nothing else enforces the match. This completes
# the app's projection-window parity set: BASE_YEAR (start) + PROJECTION_END_YEAR (end, iter46).
#
# INTENTIONALLY NOT collapsed: the `per100k_2025` / `women_per_efte_2025` output COLUMN identifiers are schema
# names with the year baked in, left literal (cf. iter24's _2050 columns); the "2025 index != 100" diagnostic
# string is an error message, not a value.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

MODEL <- here::here("shiny_urps_adequacy", "model.R")
src   <- readLines(MODEL, warn = FALSE)

.eval_const <- function(name, lines) {
  hit <- grep(paste0("^\\s*", name, "\\s*<-"), lines, value = TRUE)
  stopifnot(length(hit) == 1L)
  eval(parse(text = sub("#.*$", "", hit)))
}
BASE <- .eval_const("BASE_YEAR", src)
END  <- .eval_const("PROJECTION_END_YEAR", src)

test_that("the app base year is a well-formed 2025 before the horizon end", {
  expect_type(BASE, "integer")
  expect_length(BASE, 1L)
  expect_identical(BASE, 2025L)
  expect_lt(BASE, END)                    # start precedes end (2025 < 2050)
})

test_that("[cross-lineage parity] BASE_YEAR matches the study PROJECTION_BASELINE_YEAR", {
  wc <- new.env(); source(here::here("R", "workforce_constants.R"), local = wc)
  expect_identical(BASE, wc$PROJECTION_BASELINE_YEAR)     # the self-contained-app copy must not drift from the SSOT
})

test_that("[single-source] BASE_YEAR is defined once and used by name, not re-hardcoded", {
  expect_identical(sum(grepl("^\\s*BASE_YEAR\\s*<-", src)), 1L)         # exactly one definition
  # no bare 2025 VALUE remains in live code other than the definition (schema columns + error strings excluded)
  live <- src[!grepl("^\\s*#", src) &
              !grepl("BASE_YEAR <-", src) &
              !grepl("per100k_2025|women_per_efte_2025", src) &
              !grepl("index != 100", src)]
  expect_false(any(grepl("2025", live)))
})

test_that("[intentional difference] the _2025 output column identifiers stay literal (schema)", {
  expect_true(any(grepl("per100k_2025", src)))
  expect_true(any(grepl("women_per_efte_2025", src)))
})

test_that("[behavior-preserving] the projected-year span BASE_YEAR:PROJECTION_END_YEAR is 2025..2050", {
  expect_identical(BASE:END, 2025L:2050L)
  expect_identical(END - BASE + 1L, 26L)
})
