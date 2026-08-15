# SSOT guard: the parametric 95% CI z-multiplier (WORKFORCE_CI_Z95 = 1.96). Canonical home moved into
# R/workforce_constants.R (shared) so the data contract, the supply-line figure, and the NRMP rebuild all
# reference one value. Non-95% uses are intentionally different and must NOT be collapsed: code/03 uses
# 1.645 (a 90% CI) and R/calculate_retirement_cliff_statistics.R derives z from a general conf_level.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

ce <- new.env(); source(here::here("R", "workforce_constants.R"), local = ce)
Z <- ce$WORKFORCE_CI_Z95

test_that("canonical z-multiplier is the two-sided 95% value (1.96), well-formed", {
  expect_type(Z, "double")
  expect_length(Z, 1L)
  expect_identical(Z, 1.96)
  expect_identical(round(stats::qnorm(0.975), 2), Z)   # it IS the 95% z, not an arbitrary constant
  expect_gt(Z, 1.9); expect_lt(Z, 2.0)
})

test_that("[behavior-preserving] the contract re-exports the constant and no longer defines its own literal", {
  cc <- new.env(); suppressMessages(source(here::here("manuscript", "R", "workforce_data_contract.R"), local = cc))
  expect_identical(cc$WORKFORCE_CI_Z95, 1.96)
  ls <- readLines(here::here("manuscript", "R", "workforce_data_contract.R"), warn = FALSE)
  expect_false(any(grepl("WORKFORCE_CI_Z95\\s*<-\\s*1\\.96", ls)))   # the literal def is gone
})

test_that("[behavior-preserving] the CI multiplier reproduces the exact prior interval", {
  # figure's frozen FPMRS interval used 1.96 * SD (15.2) around the 1283..1301 track
  expect_equal(round(seq(1283 - 15.2 * Z, 1271, length.out = 5)), c(1253,1258,1262,1267,1271))
  expect_equal(round(seq(1283 + 15.2 * Z, 1330, length.out = 5)), c(1313,1317,1321,1326,1330))
})

test_that("the active supply figure references the constant, not a literal 95% z", {
  ls <- readLines(here::here("scripts", "fig_fpmrs_supply_line.R"), warn = FALSE)
  expect_true(any(grepl("15\\.2 \\* WORKFORCE_CI_Z95", ls)))
  expect_false(any(grepl("15\\.2 \\* 1\\.96", ls)))                  # no stranded literal remains
})

test_that("[intentional differences preserved] non-95% multipliers are NOT collapsed", {
  # code/03 uses 1.645 for a 90% CI (a different confidence level) -- must stay a literal 1.645
  abs_fig <- here::here("code", "03_create_abstract_figure.R")
  if (file.exists(abs_fig)) {
    la <- readLines(abs_fig, warn = FALSE)
    expect_true(any(grepl("1\\.645", la)))
    expect_false(any(grepl("WORKFORCE_CI_Z95", la)))
  }
  # the general parametrized CI derives z from conf_level via qnorm -- must stay a function, not the constant
  crs <- here::here("R", "calculate_retirement_cliff_statistics.R")
  if (file.exists(crs)) {
    lc <- readLines(crs, warn = FALSE)
    expect_true(any(grepl("qnorm\\(1 - \\(1 - conf_level\\)", lc)))
    expect_false(any(grepl("WORKFORCE_CI_Z95", lc)))
  }
})

test_that("[adversarial] no active script multiplies an SD by a bare 1.96 (must use the constant)", {
  # scope: active scripts/ producers (legacy code/ and test-oracle fixtures are intentionally literal)
  rfiles <- list.files(here::here("scripts"), pattern = "\\.R$", full.names = TRUE)
  offenders <- character()
  for (f in rfiles) {
    ls <- readLines(f, warn = FALSE)
    if (any(grepl("[*] 1\\.96|1\\.96 [*]", ls))) offenders <- c(offenders, basename(f))
  }
  expect_equal(offenders, character(0),
               info = paste("bare 1.96 SD-multiplier in active script(s):", paste(offenders, collapse = "; ")))
})
