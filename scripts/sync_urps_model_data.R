#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# sync_urps_model_data.R — propagate the ONE canonical URPS model-data snapshot
# to every standalone Shiny app replica, byte-for-byte, verified by SHA-256.
#
# WHY THIS EXISTS (the duplication is structural, not accidental):
#   Both Shiny apps deploy to shinyapps.io via rsconnect::deployApp(appDir=".",
#   appFiles=<app-dir-relative list>). The bundle contains ONLY those files, so
#   neither app can source() a repo-root file at runtime — each app dir must
#   physically contain its own model-data file. That forces a copy on disk.
#   This script makes the copies a SYNCED REPLICA of one canonical source rather
#   than two independently hand-maintained duplicates that silently drift (the
#   drift this repo has patched constant-by-constant: BANDS, BAND_LABELS,
#   BAND_EV/PY, GRAD_URPS, ... — see docs/SSOT_LEDGER.md iters 37-39).
#
#   CANONICAL: shiny_urps_scenarios/urps_model_data.R
#     (also sourced by the repo demand scripts urps_supply_demand_national /
#      urps_module_a, and treated as the reference by the SSOT guards).
#   REPLICAS:  shiny_urps_adequacy/data/urps_model_data.R
#
# USAGE:
#   Rscript scripts/sync_urps_model_data.R           # copy canonical -> replicas, verify by SHA-256
#   Rscript scripts/sync_urps_model_data.R --check    # verify only; non-zero exit on drift (CI / deploy preflight)
#
# The companion guard tests/testthat/test-ssot-urps-model-data-sync.R asserts the
# same byte-identity so drift is caught in the test suite, not only at sync time.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages(library(here))

CANONICAL <- here::here("shiny_urps_scenarios", "urps_model_data.R")
REPLICAS  <- c(here::here("shiny_urps_adequacy", "data", "urps_model_data.R"))

sha256 <- function(path) as.character(tools::sha256sum(path))   # base R (tools >= 4.5); md5sum fallback below
if (is.null(tryCatch(tools::sha256sum, error = function(e) NULL)))
  sha256 <- function(path) as.character(tools::md5sum(path))

check_only <- "--check" %in% commandArgs(trailingOnly = TRUE)

if (!file.exists(CANONICAL)) stop("canonical model-data file is missing: ", CANONICAL)
canon_sha <- sha256(CANONICAL)
cat(sprintf("canonical: %s\n  sha: %s\n", CANONICAL, canon_sha))

drift <- character()
for (rep in REPLICAS) {
  matches <- file.exists(rep) && identical(sha256(rep), canon_sha)
  if (check_only) {
    if (matches) cat(sprintf("  OK   %s\n", rep))
    else { cat(sprintf("  DRIFT %s\n", rep)); drift <- c(drift, rep) }
  } else if (matches) {
    cat(sprintf("  up-to-date %s\n", rep))
  } else {
    dir.create(dirname(rep), showWarnings = FALSE, recursive = TRUE)
    ok <- file.copy(CANONICAL, rep, overwrite = TRUE)
    if (!ok || !identical(sha256(rep), canon_sha))
      stop("copy/verify FAILED for replica: ", rep)   # fail loudly; never leave a half-written replica
    cat(sprintf("  synced %s\n", rep))
  }
}

if (check_only && length(drift) > 0) {
  cat("\nRESULT: ", length(drift), " replica(s) drifted from canonical. Run:\n",
      "  Rscript scripts/sync_urps_model_data.R\n", sep = "")
  quit(status = 1L)
}
cat(if (check_only) "\nRESULT: all replicas match canonical.\n" else "\nRESULT: sync complete; all replicas verified.\n")
