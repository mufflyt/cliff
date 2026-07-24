# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# NON-CANONICAL builder: rebuild_ssot_dynamic_acgme.R
#
# Pulls current ACGME fellowship data and recomputes workforce projections.
# Writing to workforce_projections_consolidated.csv is REFUSED unless
# WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE=1 is set. The authoritative
# writer is scripts/rebuild_ssot_revised.R.
#
# Usage (override — research use only):
#   WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE=1 Rscript scripts/rebuild_ssot_dynamic_acgme.R
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
})

if (!identical(Sys.getenv("WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE"), "1")) {
  stop("REFUSED: rebuild_ssot_dynamic_acgme.R is not the canonical SSOT writer. ",
       "Use scripts/rebuild_ssot_revised.R, or set ",
       "WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE=1 to override.",
       call. = FALSE)
}

source(here::here("manuscript", "R", "workforce_data_contract.R"))

# Dynamic ACGME data fetch and projection recomputation would go here.
# Stub: re-emits the frozen table under the override.
df <- load_workforce_data()

write_csv(df, here::here("data", "workforce_projections_consolidated.csv"))
message("[rebuild_ssot_dynamic_acgme] Wrote workforce_projections_consolidated.csv (override active)")
