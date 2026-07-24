# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# NON-CANONICAL builder: rebuild_ssot_final.R
#
# This script CANNOT overwrite data/workforce_projections_consolidated.csv
# unless the caller explicitly sets WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE=1.
# The authoritative writer is scripts/rebuild_ssot_revised.R.
#
# Usage (override — CI use only):
#   WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE=1 Rscript scripts/rebuild_ssot_final.R
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
})

if (!identical(Sys.getenv("WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE"), "1")) {
  stop("REFUSED: rebuild_ssot_final.R is not the canonical SSOT writer. ",
       "Use scripts/rebuild_ssot_revised.R, or set ",
       "WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE=1 to override.",
       call. = FALSE)
}

source(here::here("manuscript", "R", "workforce_data_contract.R"))

# Dynamic rebuild logic would go here (reads raw inputs, recomputes projections).
# For now this is a stub that re-emits the frozen table.
df <- load_workforce_data()

write_csv(df, here::here("data", "workforce_projections_consolidated.csv"))
message("[rebuild_ssot_final] Wrote workforce_projections_consolidated.csv (override active)")
