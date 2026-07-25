#!/usr/bin/env Rscript
# Fetch the large PUBLIC raw inputs that cliff does not (and should not) vendor.
#
# These two files are re-downloadable public data, too big for git, and were
# previously only present in an ephemeral scratchpad. This script pulls them from
# their canonical CMS/HRSA URLs into the config-registered locations
# (config/cliff_paths.yml -> wc_path()), so the raw-data boundary is reproducible
# without committing gigabytes.
#
#   1. medicare_prov_svc  ~3.25 GB  CMS "Medicare Physician & Other Practitioners
#                                   - by Provider and Service", data year 2024
#                                   (the source imported into signals_duckdb).
#   2. hpsa_shp           ~271 MB   HRSA HPSA primary-care shapefile bundle
#                                   (Module D geographic reference).
#
# Destinations come from wc_path(); override per-machine with the WORKFORCE_* env
# vars or config/cliff_paths.local.yml. Download URLs are the verified defaults
# below and can be overridden with the *_URL env vars (CMS/HRSA rotate paths on
# re-release; if a download 404s, refresh the URL from the portal pages named).
#
# Usage:
#   Rscript scripts/fetch_raw_inputs.R              # fetch whatever is missing
#   FETCH_FORCE=1 Rscript scripts/fetch_raw_inputs.R   # re-fetch even if present
#   Rscript scripts/fetch_raw_inputs.R medicare     # only the CMS file
#   Rscript scripts/fetch_raw_inputs.R hpsa         # only the HRSA shapefile

suppressPackageStartupMessages(library(here))
source(here::here("R", "wc_path.R"))

options(timeout = max(getOption("timeout"), 60 * 60))   # hours for multi-GB pulls

FORCE <- nzchar(Sys.getenv("FETCH_FORCE"))
which <- commandArgs(trailingOnly = TRUE)
want  <- function(x) length(which) == 0 || x %in% which

# Canonical download URLs (verified 2026-07-24). Portal pages, if these rotate:
#   CMS : https://data.cms.gov/provider-summary-by-type-of-service/medicare-physician-other-practitioners/medicare-physician-other-practitioners-by-provider-and-service
#   HRSA: https://data.hrsa.gov/data/download  (Shapefile > Health Professional Shortage Areas > Primary Care)
CMS_URL  <- Sys.getenv("WORKFORCE_MEDICARE_PROV_SVC_URL",
  "https://data.cms.gov/sites/default/files/2026-05/b5ebab5a-f490-418a-9bce-4b9f31419356/PHY_R26_P05_V10_D24_Prov_Svc.csv")
HRSA_URL <- Sys.getenv("WORKFORCE_HPSA_SHP_URL",
  "https://data.hrsa.gov/DataDownload/DD_Files/HPSA_CMPPC_SHP.zip")

.mb <- function(p) if (file.exists(p)) sprintf("%.1f MB", file.size(p) / 1e6) else "absent"

.download <- function(url, dest, min_bytes) {
  dir.create(dirname(dest), showWarnings = FALSE, recursive = TRUE)
  tmp <- paste0(dest, ".part")
  cat(sprintf("  downloading %s\n    -> %s\n", url, dest))
  ok <- tryCatch({ utils::download.file(url, tmp, mode = "wb", quiet = FALSE); TRUE },
                 error = function(e) { message("  download failed: ", conditionMessage(e)); FALSE })
  if (!ok) { unlink(tmp); return(FALSE) }
  if (file.size(tmp) < min_bytes) {
    message(sprintf("  suspiciously small (%.1f MB < %.0f MB floor) - not a valid file? URL may have moved.",
                    file.size(tmp) / 1e6, min_bytes / 1e6))
    unlink(tmp); return(FALSE)
  }
  file.rename(tmp, dest); TRUE
}

# ---- 1. CMS provider-and-service 2024 (direct CSV) --------------------------
if (want("medicare")) {
  dest <- wc_path("medicare_prov_svc")
  cat(sprintf("[medicare_prov_svc] current: %s\n", .mb(dest)))
  if (file.exists(dest) && !FORCE) {
    cat("  present; skipping (FETCH_FORCE=1 to re-fetch).\n")
  } else if (.download(CMS_URL, dest, min_bytes = 1e9)) {   # ~3.25 GB expected
    cat(sprintf("  OK: %s\n", .mb(dest)))
  } else cat("  NOT fetched.\n")
}

# ---- 2. HRSA HPSA primary-care shapefile (zip -> extract) -------------------
if (want("hpsa")) {
  shp <- wc_path("hpsa_shp")                 # .../HPSA_CMPPC_SHP_DET_CUR_VX.shp
  cat(sprintf("[hpsa_shp] current: %s\n", .mb(shp)))
  if (file.exists(shp) && !FORCE) {
    cat("  present; skipping (FETCH_FORCE=1 to re-fetch).\n")
  } else {
    zip <- file.path(tempdir(), "HPSA_CMPPC_SHP.zip")
    if (.download(HRSA_URL, zip, min_bytes = 1e8)) {        # ~271 MB expected
      dir.create(dirname(shp), showWarnings = FALSE, recursive = TRUE)
      utils::unzip(zip, exdir = dirname(shp)); unlink(zip)
      if (file.exists(shp)) cat(sprintf("  OK: extracted shapefile bundle (%s)\n", .mb(shp)))
      else cat(sprintf("  WARNING: %s not found after unzip; check the archive's layer name.\n", basename(shp)))
    } else cat("  NOT fetched.\n")
  }
}

cat("Done.\n")
