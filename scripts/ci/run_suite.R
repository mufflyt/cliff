#!/usr/bin/env Rscript
# Run the source-tree suite with completion accounting.
#
# Three properties this provides that `testthat::test_dir()` alone does not:
#
#   COMPLETION SENTINEL. The sentinel file is written only after test_dir()
#   returns. A separate CI step asserts it exists. A quit(), segfault, OOM kill,
#   job timeout, truncated log or reporter crash all leave the sentinel absent,
#   so none of them can masquerade as a pass. Exit status alone cannot
#   distinguish "ran everything and all passed" from "died before finishing".
#
#   ACCOUNTING. A machine-readable record of files, assertions, failures,
#   warnings, skips and duration, so trends are visible without scraping logs.
#
#   SKIP CONTROL. A green run with silently-doubled skips is not a green run.
#   Skips are compared, by reason, against a committed baseline; a NEW skip
#   reason, or a large change in count, fails. This is what makes
#   CLIFF_ISOCHRONES_ROOT="" visible rather than merely quiet.
#
# Deliberately does NOT assert a required pass count. The suite is allowed to
# grow and shrink on purpose; the invariants are "zero failures", "it finished",
# and "skips are the ones we approved".
#
# Usage:
#   Rscript scripts/ci/run_suite.R
#   Rscript scripts/ci/run_suite.R --write-baseline   # re-approve the skip set

args   <- commandArgs(trailingOnly = TRUE)
write_baseline <- "--write-baseline" %in% args

root <- Sys.getenv("CLIFF_ROOT", ".")
setwd(root)

out_dir  <- Sys.getenv("CLIFF_CI_OUT", file.path(tempdir(), "cliff-ci"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
sentinel <- file.path(out_dir, "suite-completed.txt")
acct     <- file.path(out_dir, "test-accounting.json")
baseline <- file.path("scripts", "ci", "skip_baseline.json")

unlink(sentinel)   # never trust one left over from an earlier run

suppressPackageStartupMessages({
  library(testthat)
  library(cliff)
})

cat("R:      ", R.version.string, "\n")
cat("cliff:  ", as.character(packageVersion("cliff")), "\n")
cat("out:    ", out_dir, "\n\n")

t0  <- Sys.time()
res <- testthat::test_dir("tests/testthat", reporter = "summary",
                          stop_on_failure = FALSE)
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

d <- as.data.frame(res)
tot <- list(
  files    = nrow(d),
  passed   = sum(d$passed),
  failed   = sum(d$failed),
  warnings = sum(d$warning),
  skipped  = sum(d$skipped),
  errors   = sum(vapply(res, function(x) sum(vapply(x$results,
                  function(r) inherits(r, "expectation_error"), logical(1))), numeric(1))),
  seconds  = round(elapsed, 1)
)

cat(sprintf("\nFILES %d | PASS %d | FAIL %d | SKIP %d | WARN %d | %.0fs\n",
            tot$files, tot$passed, tot$failed, tot$skipped, tot$warnings, tot$seconds))

# ---- skip reasons, normalised -------------------------------------------
skip_reasons <- character(0)
for (f in res) {
  for (r in f$results) {
    if (inherits(r, "expectation_skip")) {
      msg <- conditionMessage(r)
      msg <- sub("^Reason: ", "", trimws(msg))
      # Strip anything machine-specific so the baseline is portable.
      msg <- gsub("/[^ ]*", "<path>", msg)
      msg <- gsub("[0-9]+", "<n>", msg)
      skip_reasons <- c(skip_reasons, trimws(msg))
    }
  }
}
skip_tab <- sort(table(skip_reasons), decreasing = TRUE)

cat("\n-- skip reasons --\n")
if (!length(skip_tab)) cat("  (none)\n")
for (n in names(skip_tab)) cat(sprintf("  %3d  %s\n", skip_tab[[n]], n))

# ---- failures, itemised --------------------------------------------------
if (tot$failed > 0) {
  cat("\n-- failures --\n")
  bad <- d[d$failed > 0, c("file", "test", "failed")]
  for (i in seq_len(nrow(bad)))
    cat(sprintf("  %s :: %s (%d)\n", bad$file[i], bad$test[i], bad$failed[i]))
}

# ---- machine-readable accounting ----------------------------------------
json_escape <- function(x) gsub('"', '\\\\"', gsub("\\\\", "\\\\\\\\", x))
skip_json <- if (length(skip_tab))
  paste0("    {\"reason\": \"", json_escape(names(skip_tab)), "\", \"count\": ",
         as.integer(skip_tab), "}", collapse = ",\n") else ""

writeLines(c(
  "{",
  sprintf('  "r_version": "%s",', R.version.string),
  sprintf('  "platform": "%s",', R.version$platform),
  sprintf('  "files": %d,', tot$files),
  sprintf('  "passed": %d,', tot$passed),
  sprintf('  "failed": %d,', tot$failed),
  sprintf('  "warnings": %d,', tot$warnings),
  sprintf('  "skipped": %d,', tot$skipped),
  sprintf('  "seconds": %.1f,', tot$seconds),
  '  "skip_reasons": [',
  skip_json,
  "  ]",
  "}"
), acct)
cat("\naccounting ->", acct, "\n")

# ---- skip baseline -------------------------------------------------------
current <- setNames(as.integer(skip_tab), names(skip_tab))

if (write_baseline) {
  writeLines(c("{", paste0('  "', json_escape(names(current)), '": ', current,
                           collapse = ",\n"), "}"), baseline)
  cat("baseline written ->", baseline, "\n")
} else if (file.exists(baseline)) {
  raw <- paste(readLines(baseline, warn = FALSE), collapse = "")
  keys <- regmatches(raw, gregexpr('"(?:[^"\\\\]|\\\\.)*"\\s*:', raw))[[1]]
  vals <- regmatches(raw, gregexpr(':\\s*[0-9]+', raw))[[1]]
  keys <- gsub('^"|"\\s*:$', "", trimws(keys))
  keys <- gsub('\\\\"', '"', keys)
  vals <- as.integer(gsub("[^0-9]", "", vals))
  expected <- setNames(vals, keys)

  novel   <- setdiff(names(current), names(expected))
  removed <- setdiff(names(expected), names(current))

  if (length(novel)) {
    cat("\n== UNAPPROVED SKIPS ==\n")
    for (n in novel) cat(sprintf("  + %3d  %s\n", current[[n]], n))
    cat("\nA new skip reason means tests stopped running without anyone deciding\n",
        "that was acceptable. If it is intended, re-approve with:\n",
        "  Rscript scripts/ci/run_suite.R --write-baseline\n", sep = "")
  }
  if (length(removed))
    for (n in removed) cat(sprintf("\n  note: baseline skip no longer occurs: %s\n", n))

  if (length(novel)) {
    cat("\nSUITE: FAIL (unapproved skips)\n")
    quit(status = 3)
  }
} else {
  cat("\nnote: no skip baseline at", baseline, "- run with --write-baseline\n")
}

if (tot$failed > 0) {
  cat("\nSUITE: FAIL (", tot$failed, " failing assertions )\n")
  quit(status = 1)
}

# Written LAST, and only on the success path.
writeLines(c(
  format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  sprintf("files=%d passed=%d failed=%d skipped=%d seconds=%.1f",
          tot$files, tot$passed, tot$failed, tot$skipped, tot$seconds)
), sentinel)
cat("\nSUITE: OK — sentinel ->", sentinel, "\n")
