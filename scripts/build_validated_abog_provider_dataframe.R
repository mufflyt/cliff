#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Regenerate the ABOG provider dataframe from the VALIDATED 2026 refresh.
#
# The 2026 ABOG re-scrape (isochrones' refresh_merged_clean.csv) is left-joined
# onto the original roster by abog_id (isochrones' build_refreshed_abog_roster.R
# does this coalesce; that OUTPUT, abog_physician_data_refreshed_2026.csv, is
# read here as the base). But a coalesced certStatus alone conflates two very
# different things: a physician actually re-scraped in 2026, and one whose OLD
# active-looking status was simply carried forward because the re-scrape never
# reached them (12,626 of 79,385 rows, 2026-08-22 audit). Trusting the merged
# certStatus at face value reads the second group as confirmed-current when
# they are not.
#
# This script adds isochrones' validated current-use classification
# (validate_abog_refresh_integrity(), R/validators/abog_refresh_integrity.R) as
# additional columns -- cert_category_current, refresh_is_current,
# cert_status_is_expired -- WITHOUT touching the raw certStatus/mocStatus/etc.
# fields. Non-destructive: provenance stays intact, downstream code opts in to
# the validated field rather than the raw one.
#
# OUTPUT: data/abog_provider_dataframe_8_17_2025_1948_only_workforce_directory.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(here); library(readr); library(dplyr)})

# ---- monorepo inputs -------------------------------------------------------
# These live in the isochrones monorepo, not this repository. Point
# CLIFF_ISOCHRONES_ROOT at a checkout to regenerate. Failing loudly beats
# silently rebuilding on a stale or absent refresh.
ISO <- Sys.getenv("CLIFF_ISOCHRONES_ROOT", unset = path.expand("~/isochrones"))
iso <- function(...) {
  p <- file.path(ISO, ...)
  if (!file.exists(p)) {
    stop(sprintf(paste0(
      "[build_validated_abog_provider_dataframe] monorepo input not found:\n  %s\n",
      "Set CLIFF_ISOCHRONES_ROOT to an isochrones checkout (currently %s)."
    ), p, ISO), call. = FALSE)
  }
  p
}

source(iso("R", "validators", "abog_refresh_integrity.R"))

cat("[build] Reading coalesced 2026-refreshed roster (isochrones build_refreshed_abog_roster.R output)...\n")
refreshed <- read_csv(
  iso("abog_scrape", "abog_physician_data_refreshed_2026.csv"),
  show_col_types = FALSE, col_types = cols(.default = "c")
)
cat(sprintf("[build] Rows: %s\n", format(nrow(refreshed), big.mark = ",")))

cat("[build] Reading raw 2026 refresh for integrity classification...\n")
raw_refresh <- read_csv(
  iso("abog_scrape", "refresh_merged_clean.csv"),
  show_col_types = FALSE, col_types = cols(.default = "c")
) %>%
  transmute(
    userid = as.integer(userid), ID = as.integer(userid),
    name = name, certStatus, cert_category, refresh_source
  )

audit <- validate_abog_refresh_integrity(raw_refresh, as_of_date = Sys.Date())

error_issues <- dplyr::filter(audit$issues, severity == "error")
if (nrow(error_issues) > 0) {
  cat(sprintf(
    "[build] WARNING: %d error-severity integrity issue(s) -- writing anyway (non-destructive), review before trusting confirmed-current counts:\n",
    nrow(error_issues)
  ))
  print(error_issues)
}

classification <- audit$roster %>%
  transmute(
    abog_id = as.character(userid),
    cert_category_current, refresh_is_current, cert_status_is_expired
  )

out <- refreshed %>%
  mutate(abog_id = as.character(abog_id)) %>%
  left_join(classification, by = "abog_id")

n_unclassified <- sum(is.na(out$cert_category_current))
if (n_unclassified > 0) {
  stop(sprintf(
    "[build_validated_abog_provider_dataframe] %d rows failed to join a validated classification -- refusing to write a partially-classified file.",
    n_unclassified
  ), call. = FALSE)
}

out_path <- here::here(
  "data", "abog_provider_dataframe_8_17_2025_1948_only_workforce_directory.csv"
)
write_csv(out, out_path, na = "")
cat(sprintf("[build] Wrote %s (%s rows)\n", out_path, format(nrow(out), big.mark = ",")))
cat("[build] cert_category_current distribution:\n")
print(table(out$cert_category_current, useNA = "ifany"))
