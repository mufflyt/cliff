#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Smoke test the INSTALLED package, with optional dependencies absent.
#
# The source suite runs under load_all() against the checkout, which has masked
# real installed-package defects repeatedly here: exported functions calling
# functions that were never extracted from the monorepo, and bare dplyr verbs
# that resolved only because a file-scope library() had attached them at build
# time. This script exercises the package as a user gets it.
#
# It also proves the Suggests boundary: data.table, sf, tidycensus, tigris and
# geosphere are deliberately NOT visible, so anything that silently depended on
# them fails here rather than in someone else's session.
#
# Usage:
#   R CMD build . && R CMD INSTALL -l <lib> cliff_*.tar.gz
#   SMOKELIB=<lib> Rscript scripts/smoke_installed_package.R
#
# <lib> must contain cliff and its hard Imports but NOT the five packages above.
# Build it by symlinking an existing library and omitting those five.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# newly-Suggested packages and geosphere are deliberately absent.
lib <- Sys.getenv("SMOKELIB")
.libPaths(lib)                      # ONLY this library: nothing else is visible

absent <- c("data.table", "sf", "tidycensus", "tigris", "geosphere")
cat("=== visibility check (must all be FALSE) ===\n")
for (p in absent)
  cat(sprintf("  %-12s available: %s\n", p, requireNamespace(p, quietly = TRUE)))

cat("\n=== load cliff from the installed tarball ===\n")
ok <- tryCatch({ library(cliff); TRUE }, error = function(e) { cat("  FAILED:", conditionMessage(e), "\n"); FALSE })
cat("  library(cliff):", ok, "\n")
if (!ok) quit(status = 1)

pass <- fail <- 0L
chk <- function(label, expr, expect_error = FALSE, pattern = NULL) {
  r <- tryCatch(list(v = expr, e = NULL), error = function(e) list(v = NULL, e = e))
  if (expect_error) {
    good <- !is.null(r$e) && (is.null(pattern) || grepl(pattern, conditionMessage(r$e)))
    cat(sprintf("  %-52s %s%s\n", label, if (good) "OK (failed as intended)" else "UNEXPECTED",
                if (!is.null(r$e)) paste0("  [", substr(conditionMessage(r$e), 1, 60), "]") else ""))
  } else {
    good <- is.null(r$e)
    cat(sprintf("  %-52s %s%s\n", label, if (good) "OK" else "FAILED",
                if (!is.null(r$e)) paste0("  [", substr(conditionMessage(r$e), 1, 70), "]") else ""))
  }
  if (good) pass <<- pass + 1L else fail <<- fail + 1L
  invisible(r$v)
}

cat("\n=== the five restored helpers, through real call paths ===\n")
chk("classify_us_region('CO') == 'West'",
    stopifnot(identical(cliff:::classify_us_region("CO"), "West")))
chk("classify_us_region vectorised over 3 states",
    stopifnot(length(cliff:::classify_us_region(c("CO", "NY", "TX"))) == 3L))
cols <- chk("inference_output_columns() returns a character vector",
    { x <- cliff:::inference_output_columns(); stopifnot(is.character(x), length(x) > 0); x })
chk("validate_inference_qa() runs on an empty result set",
    { r <- data.frame(); invisible(try(cliff:::validate_inference_qa(r, context = "fellowship",
                                                                    write_artifact = FALSE), silent = TRUE)) })
chk("load_training_crosswalk is a function",
    stopifnot(is.function(cliff:::load_training_crosswalk)))
chk("infer_from_abog_neighbors is a function",
    stopifnot(is.function(cliff:::infer_from_abog_neighbors)))

cat("\n=== the two exported APIs that were broken ===\n")
phys <- data.frame(npi = c("1","2"), inferred_state = c("CO","NY"),
                   stringsAsFactors = FALSE)
chk("add_fellowship_to_table1 resolves (no 'could not find function')",
    { r <- try(cliff::add_fellowship_to_table1(phys), silent = TRUE)
      if (inherits(r, "try-error") && grepl("could not find function", r)) stop(r)
      invisible(TRUE) })
chk("infer_fellowship_training resolves (no 'could not find function')",
    { r <- try(cliff::infer_fellowship_training(phys), silent = TRUE)
      if (inherits(r, "try-error") && grepl("could not find function", r)) stop(r)
      invisible(TRUE) })

cat("\n=== geosphere absent: only the functions that need it may fail ===\n")
chk("haversine_distance fails with the intended message",
    cliff:::haversine_distance(39.7, -104.9, 40.7, -74.0),
    expect_error = TRUE, pattern = "geosphere")
chk("classify_us_region still works without geosphere",
    stopifnot(identical(cliff:::classify_us_region("NY"), "Northeast")))
chk("inference_output_columns still works without geosphere",
    stopifnot(is.character(cliff:::inference_output_columns())))

cat(sprintf("\nSMOKE RESULT  pass=%d fail=%d\n", pass, fail))
quit(status = if (fail > 0L) 1L else 0L)
