#!/usr/bin/env Rscript
# Bundled-artifact byte identity.
#
# The Shiny apps ship copies of generated artifacts so they are self-contained
# when deployed. A copy is a fact stored twice, and both copies drifted:
#
#   shiny_urps_scenarios/data/graduation_active_transition_projection.csv
#       URPS 1339 / 1544 / 1466   vs   data/ 1306 / 1514 / 1437
#   shiny_urps_adequacy/data/urps_supply_demand_national_2026-07-23.csv
#       2025 supply 1339          vs   data/ 1306
#       (every derived per-100k and ratio column differed, in every year)
#
# Neither app's own tests could catch it, because nothing compared the two. The
# adequacy app was presenting a stale supply trajectory while its 403 tests
# passed.
#
# This is a stopgap. The real fix is for these facts to have ONE home -- an
# accessor in mufflyaccess rather than a file copied per app -- at which point
# this gate becomes unnecessary. Until then it makes the duplication visible the
# moment it diverges instead of months later.
#
# App-only files (no counterpart in data/) are reported, not failed: an app may
# legitimately ship something the repo does not generate.
#
#   Rscript scripts/ci/check_bundled_artifacts.R

root <- Sys.getenv("CLIFF_ROOT", ".")
setwd(root)

app_dirs <- Filter(dir.exists,
                   c("shiny_urps_scenarios/data", "shiny_urps_adequacy/data"))
if (!length(app_dirs)) { cat("no bundled app data directories\n"); quit(status = 0) }

diverged <- character(0)
app_only <- character(0)
matched  <- 0L

cat("== bundled artifact byte identity ==\n")

for (d in app_dirs) {
  files <- list.files(d, pattern = "[.](csv|tsv|rds)$", full.names = TRUE,
                      ignore.case = TRUE)
  for (f in files) {
    base <- basename(f)
    canonical <- file.path("data", base)
    if (!file.exists(canonical)) {
      app_only <- c(app_only, f)
      next
    }
    a <- tools::md5sum(canonical); b <- tools::md5sum(f)
    if (identical(unname(a), unname(b))) {
      matched <- matched + 1L
    } else {
      diverged <- c(diverged, sprintf("%s  !=  %s", f, canonical))
    }
  }
}

cat("  byte-identical to data/ :", matched, "\n")
cat("  DIVERGED                :", length(diverged), "\n")
cat("  app-only (informational):", length(app_only), "\n")

if (length(app_only)) {
  cat("\n-- app-only, no repo counterpart --\n")
  for (f in app_only) cat("   ", f, "\n")
}

if (length(diverged)) {
  cat("\n== DIVERGED BUNDLED ARTIFACTS ==\n")
  for (f in diverged) cat("  x", f, "\n")
  cat("\nA bundled copy no longer matches the artifact it was copied from. The\n",
      "app is shipping different numbers from the repository. Refresh it:\n",
      "  cp data/<file> <app>/data/<file>\n",
      "and regenerate the artifact first if data/ is itself out of date.\n", sep = "")
  quit(status = 1)
}

cat("\n== every bundled copy matches data/ ==\n")
quit(status = 0)
