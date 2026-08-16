#!/usr/bin/env Rscript
# Gates 61 and 63: run both Shiny applications' own test suites.
#
# Both apps ship testthat suites -- five files between them, including
# app-vs-package parity guards -- and CI had never run any of them. They are
# publication surface: the apps present the same projection the manuscript
# does, and test-app-absolute-parity in the main suite exists precisely because
# an app once carried a divergent copy of a package calculation.
#
# The browser-driving shinytest2 suite (gate 62) is NOT run here; it needs Chrome
# and is wired separately as a nightly-only step.
#
# Known failures live in scripts/ci/shiny_test_debt.txt and CI fails when that
# set GROWS, so a real regression is still caught while a pre-existing,
# already-diagnosed divergence does not hold the gate permanently red.
#
#   Rscript scripts/ci/run_shiny_suites.R
#   Rscript scripts/ci/run_shiny_suites.R --write-debt

args <- commandArgs(trailingOnly = TRUE)
write_debt <- "--write-debt" %in% args
root <- Sys.getenv("CLIFF_ROOT", ".")
setwd(root)

debt_path <- file.path("scripts", "ci", "shiny_test_debt.txt")
APPS <- c("shiny_urps_adequacy", "shiny_urps_scenarios")

suppressPackageStartupMessages(library(testthat))

failing <- character(0)
total <- list()

for (app in APPS) {
  dir <- file.path(app, "tests", "testthat")
  if (!dir.exists(dir)) { cat("  (no suite)", app, "\n"); next }

  cat("== ", app, " ==\n", sep = "")
  res <- tryCatch(
    testthat::test_dir(dir, reporter = "silent", stop_on_failure = FALSE),
    error = function(e) { cat("  SUITE ERROR: ", conditionMessage(e), "\n"); NULL })
  if (is.null(res)) { failing <- c(failing, paste0(app, " :: <suite failed to run>")); next }

  d <- as.data.frame(res)
  total[[app]] <- c(files = nrow(d), pass = sum(d$passed),
                    fail = sum(d$failed), skip = sum(d$skipped))
  cat(sprintf("  files=%d pass=%d fail=%d skip=%d\n",
              nrow(d), sum(d$passed), sum(d$failed), sum(d$skipped)))

  bad <- d[d$failed > 0, c("file", "test"), drop = FALSE]
  if (nrow(bad))
    failing <- c(failing, sprintf("%s :: %s :: %s", app, bad$file, bad$test))
}

failing <- sort(unique(failing))

cat("\n== failing tests ==\n")
if (!length(failing)) cat("  (none)\n")
for (f in failing) cat("  x", f, "\n")

if (write_debt) {
  writeLines(c(
    "# Shiny application tests that currently fail.",
    "#",
    "# CI fails when this set GROWS. Shrink it by fixing the app or the",
    "# expectation and deleting the line; never add a line to make CI pass.",
    "#   Rscript scripts/ci/run_shiny_suites.R --write-debt",
    failing), debt_path)
  cat("\ndebt registry written ->", debt_path, "(", length(failing), "entries )\n")
  quit(status = 0)
}

known <- character(0)
if (file.exists(debt_path)) {
  known <- readLines(debt_path, warn = FALSE)
  known <- trimws(known[!grepl("^\\s*#", known) & nzchar(trimws(known))])
}

novel <- setdiff(failing, known)
fixed <- setdiff(known, failing)

if (length(fixed)) {
  cat("\n-- now passing (trim the debt registry) --\n")
  for (f in fixed) cat("  +", f, "\n")
}

summ <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summ)) {
  cat("### Shiny application suites\n\n| app | files | pass | fail | skip |\n|---|--:|--:|--:|--:|\n",
      file = summ, append = TRUE)
  for (a in names(total))
    cat(sprintf("| `%s` | %d | %d | %d | %d |\n", a, total[[a]][["files"]],
                total[[a]][["pass"]], total[[a]][["fail"]], total[[a]][["skip"]]),
        file = summ, append = TRUE)
  cat("\n", file = summ, append = TRUE)
}

if (length(novel)) {
  cat("\n== NEW SHINY TEST FAILURES ==\n")
  for (f in novel) cat("  x", f, "\n")
  quit(status = 1)
}

cat("\n== no new Shiny test failures ==\n")
quit(status = 0)
