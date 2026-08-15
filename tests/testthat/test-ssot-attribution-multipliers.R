# SSOT guard: the Module C attribution-plasticity scenario multipliers (mid=1.0, low=0.8, high=1.2) in
# scripts/urps_demand_module_bc_2026-07-23.R (iter41). The triple was duplicated in the same file — as literal
# args attr_proc(1.0)/attr_proc(0.8)/attr_proc(1.2) AND as c(mid=1.0,low=0.8,high=1.2) in the required-FTE loop —
# so a change to the low/high band could update one and miss the other. Now one named vector URPS_ATTRIB_MULT
# drives both the procedure-count projection and the FTE loop.
#
# INTENTIONALLY NOT collapsed: the three values are distinct SCENARIOS (low/mid/high), not one value; and this
# 0.8/1.2 is the ATTRIBUTION band, semantically unrelated to iter40's workforce-outlook cutpoints (same numbers,
# different meaning) — the two must never be merged.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

MODULE_BC <- here::here("scripts", "urps_demand_module_bc_2026-07-23.R")
src <- readLines(MODULE_BC, warn = FALSE)

# Evaluate ONLY the canonical constant line (the file itself opens a DuckDB connection, so it can't be sourced).
.eval_const <- function(name, lines) {
  hit <- grep(paste0("^\\s*", name, "\\s*<-"), lines, value = TRUE)
  stopifnot(length(hit) == 1L)
  eval(parse(text = sub("#.*$", "", hit)))
}
MULT <- .eval_const("URPS_ATTRIB_MULT", src)

test_that("the canonical scenario vector is well-formed and ordered", {
  expect_named(MULT, c("mid", "low", "high"))
  expect_identical(unname(MULT[["mid"]]), 1.0)             # mid = as-observed share
  expect_lt(MULT[["low"]], MULT[["mid"]])                  # low is a downward sensitivity
  expect_gt(MULT[["high"]], MULT[["mid"]])                 # high is an upward sensitivity
  expect_true(all(MULT > 0))
})

test_that("[behavior-preserving] the scenario values equal the prior literals (1.0 / 0.8 / 1.2)", {
  expect_identical(MULT[["mid"]],  1.0)
  expect_identical(MULT[["low"]],  0.8)
  expect_identical(MULT[["high"]], 1.2)
})

test_that("[semantic] the band is symmetric +/-0.2 around the mid scenario", {
  expect_equal(MULT[["mid"]] - MULT[["low"]], MULT[["high"]] - MULT[["mid"]])   # +/-0.2 either side
})

test_that("[adversarial] module_bc references the SSOT vector, not bare 0.8/1.2 attribution literals", {
  # the procedure-count projection and the FTE loop both go through URPS_ATTRIB_MULT
  expect_true(any(grepl("attr_proc\\(URPS_ATTRIB_MULT\\[\\[\"mid\"\\]\\]\\)", src)))
  expect_true(any(grepl("m <- URPS_ATTRIB_MULT\\[\\[s\\]\\]", src)))
  # the old duplicated literals are gone
  expect_false(any(grepl("attr_proc\\(0\\.8\\)", src)))
  expect_false(any(grepl("attr_proc\\(1\\.2\\)", src)))
  expect_false(any(grepl("c\\(mid ?= ?1\\.0, ?low ?= ?0\\.8, ?high ?= ?1\\.2\\)\\[", src)))  # inline named-vector index gone
})

test_that("[intentional difference] this attribution band is NOT the workforce-outlook cutpoints", {
  # both use 0.8 and 1.2 but mean unrelated things; assert they live in different files / different symbols so a
  # future reader (or refactor) does not merge them.
  wc <- new.env(); source(here::here("R", "workforce_constants.R"), local = wc)
  expect_false(identical(wc$WORKFORCE_OUTLOOK_ADEQUATE_MIN, MULT[["high"]]) &&
               exists("URPS_ATTRIB_MULT", envir = wc))   # URPS_ATTRIB_MULT must NOT have leaked into the shared constants
  # the attribution multipliers are file-local (module_bc), the outlook cuts are in workforce_constants — distinct homes
  expect_false(any(grepl("URPS_ATTRIB_MULT", readLines(here::here("R", "workforce_constants.R"), warn = FALSE))))
})
