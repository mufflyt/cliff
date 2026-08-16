#!/usr/bin/env Rscript
# Gate 68/69: coverage regression, and every export exercised.
#
# Deliberately NOT a fixed percentage threshold. An arbitrary 90% line on a
# package whose suite is largely repository-integrity guards would measure the
# wrong thing and get gamed. What matters is that coverage does not silently
# FALL -- so the committed baseline is the bar, with a tolerance for the noise
# that comes from tests skipping in different environments.
#
# Gate 69 is the stricter and more useful half: every exported function must be
# touched by at least one executed test path. That is independent of the overall
# percentage, and it catches the case that matters -- a public API nobody calls.
#
#   Rscript scripts/ci/check_coverage.R
#   Rscript scripts/ci/check_coverage.R --write-baseline

args <- commandArgs(trailingOnly = TRUE)
write_baseline <- "--write-baseline" %in% args
root <- Sys.getenv("CLIFF_ROOT", ".")
setwd(root)

baseline_path <- file.path("scripts", "ci", "coverage_baseline.txt")
TOLERANCE <- 2.0   # percentage points

if (!requireNamespace("covr", quietly = TRUE)) {
  cat("covr unavailable\n"); quit(status = 1)
}

cat("== measuring coverage ==\n")
cov <- covr::package_coverage(type = "tests", quiet = TRUE)
pct <- covr::percent_coverage(cov)
cat(sprintf("  line coverage: %.2f%%\n", pct))

# ---- gate 69: exported functions with no executed test path ----------------
exports <- tryCatch({
  ns <- readLines("NAMESPACE", warn = FALSE)
  e <- grep("^export\\(", ns, value = TRUE)
  gsub("^export\\(|\\)$", "", e)
}, error = function(...) character(0))

df <- as.data.frame(cov)
covered_fns <- unique(df$functions[df$value > 0])
untested <- sort(setdiff(exports, covered_fns))

cat(sprintf("  exports: %d, with an executed test path: %d, untouched: %d\n",
            length(exports), length(exports) - length(untested), length(untested)))
if (length(untested)) for (f in utils::head(untested, 40)) cat("    -", f, "\n")

summ <- Sys.getenv("GITHUB_STEP_SUMMARY")
if (nzchar(summ))
  cat(sprintf("### Coverage\n\n**%.2f%%** of lines in `R/`; %d of %d exports exercised.\n\n",
              pct, length(exports) - length(untested), length(exports)),
      file = summ, append = TRUE)

if (write_baseline) {
  writeLines(c(
    "# Coverage baseline. CI fails on a DROP of more than the tolerance, never",
    "# on failing to reach an arbitrary target: a fixed percentage on a suite",
    "# that is largely repository-integrity guards measures the wrong thing.",
    "#   Rscript scripts/ci/check_coverage.R --write-baseline",
    sprintf("line_coverage_pct: %.2f", pct),
    sprintf("tolerance_pct: %.2f", TOLERANCE),
    sprintf("untested_exports: %d", length(untested))), baseline_path)
  cat("\nbaseline written ->", baseline_path, "\n")
  quit(status = 0)
}

if (!file.exists(baseline_path)) {
  cat("\nno baseline; create one with --write-baseline\n"); quit(status = 0)
}

bl <- readLines(baseline_path, warn = FALSE)
num <- function(key, default = NA_real_) {
  l <- grep(paste0("^", key, ":"), bl, value = TRUE)
  if (!length(l)) return(default)
  as.numeric(trimws(sub(".*:", "", l[1])))
}
base_pct <- num("line_coverage_pct")
tol      <- num("tolerance_pct", TOLERANCE)
base_unt <- num("untested_exports", NA_real_)

cat(sprintf("\n  baseline: %.2f%% (tolerance %.2f pp)\n", base_pct, tol))

fail <- character(0)
if (!is.na(base_pct) && pct < base_pct - tol)
  fail <- c(fail, sprintf("coverage fell from %.2f%% to %.2f%% (more than %.2f pp)",
                          base_pct, pct, tol))
if (!is.na(base_unt) && length(untested) > base_unt)
  fail <- c(fail, sprintf("untested exports rose from %d to %d",
                          as.integer(base_unt), length(untested)))

if (pct > base_pct + tol)
  cat(sprintf("  note: coverage ROSE to %.2f%% - re-baseline to lock the gain in\n", pct))

if (length(fail)) {
  cat("\n== COVERAGE REGRESSION ==\n")
  for (f in fail) cat("  x", f, "\n")
  quit(status = 1)
}
cat("\n== no coverage regression ==\n")
quit(status = 0)
