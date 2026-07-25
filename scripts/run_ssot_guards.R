#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# run_ssot_guards.R — run the full single-source-of-truth (SSOT) guard suite.
#
# Runs every tests/testthat/test-ssot-*.R guard and prints a one-line pass/fail
# summary. This is the fast "verification pass" for the SSOT maintenance work
# documented in docs/SSOT_LEDGER.md: every canonicalised constant/function has a
# semantic + adversarial guard here, so a green run confirms none of them have
# drifted (a bare literal reappearing, a consumer un-wiring, an intentional
# difference collapsed).
#
#   Usage: Rscript scripts/run_ssot_guards.R
#   Exit : 0 if all guards pass, 1 if any fail (CI-friendly).
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressMessages({ library(testthat); library(here) })

fs <- list.files(here::here("tests", "testthat"),
                 pattern = "^test-ssot-.*[.]R$", full.names = TRUE)
cat("SSOT guard files:", length(fs), "\n")

tot_p <- 0L; tot_f <- 0L
for (f in fs) {
  r <- as.data.frame(test_file(f, reporter = "silent"))
  tot_p <- tot_p + sum(r$passed)
  tot_f <- tot_f + sum(r$failed)
  if (sum(r$failed) > 0L) cat(sprintf("  FAIL %-48s %d\n", basename(f), sum(r$failed)))
}
cat(sprintf("SSOT guards: %d passed, %d FAILED\n", tot_p, tot_f))
if (tot_f > 0L) quit(status = 1L)
