# SSOT guard: the readr::read_csv() guess_max default (1e5), shared by the read-heavy regeneration/sensitivity
# scripts. Previously `guess_max=1e5` was copy-pasted across 6 scripts (10 sites). Now canonical in
# R/wc_path.R::READ_GUESS_MAX_ROWS. Distinct from R/units.R::RATE_PER_100K (also 1e5, but a per-100k rate base).
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

pe <- new.env(); source(here::here("R", "wc_path.R"), local = pe)
CONSUMERS <- c("abu_pathway_sensitivity.R", "build_hazard_comparison.R", "departure_anchor.R",
               "hierarchical_hazard_partial_pooling.R", "scenario_projection_trajectories.R",
               "validate_departure_classifier_external.R")

test_that("READ_GUESS_MAX_ROWS is the 1e5 read guess_max (numeric scalar)", {
  expect_type(pe$READ_GUESS_MAX_ROWS, "double")
  expect_length(pe$READ_GUESS_MAX_ROWS, 1L)
  expect_identical(pe$READ_GUESS_MAX_ROWS, 1e5)
})

test_that("[behavior-preserving] the constant equals the prior literal guess_max", {
  expect_identical(pe$READ_GUESS_MAX_ROWS, 1e5)   # read_csv(guess_max=.) unchanged
})

test_that("[adversarial] all 6 consumers use the constant; no bare guess_max=1e5 remains", {
  for (b in CONSUMERS) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    expect_false(any(grepl("guess_max=1e5", ls)), info = b)                 # literal gone
    expect_true(any(grepl("guess_max=READ_GUESS_MAX_ROWS", ls)), info = b)  # uses the SSOT
  }
})

test_that("[intentional difference] it is the READ hint in wc_path.R, NOT the per-100k rate base", {
  # the canonical read default lives in wc_path.R
  wp <- readLines(here::here("R", "wc_path.R"), warn = FALSE)
  expect_true(any(grepl("READ_GUESS_MAX_ROWS\\s*<-\\s*1e5", wp)))
  # the same literal 1e5 as a RATE base stays a separate constant in units.R
  ue <- new.env(); source(here::here("R", "units.R"), local = ue)
  expect_identical(ue$RATE_PER_100K, 1e5)                # coincidentally equal value...
  expect_false(exists("RATE_PER_100K", envir = pe, inherits = FALSE))  # ...but a distinct constant
})
