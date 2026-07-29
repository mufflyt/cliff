# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CANONICAL SSOT WRITER — rebuild_ssot_revised.R
#
# This is the ONLY script authorized to overwrite
# data/workforce_projections_consolidated.csv.
# All other builders (rebuild_ssot_final.R, rebuild_ssot_dynamic_acgme.R) are
# locked behind WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE=1.
#
# Usage:
#   Rscript scripts/rebuild_ssot_revised.R
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
})

source(here::here("manuscript", "R", "workforce_data_contract.R"))

# ---------------------------------------------------------------------------
# Build the primary consolidated table from peer-reviewed source values.
# These numbers are frozen from the SGS deck / NRMP / ACGME multi-year means.
# ---------------------------------------------------------------------------

primary <- tibble::tribble(
  ~subspecialty,                                       ~subspecialty_abbrev,
  ~baseline_2025, ~projected_2029,  ~sd_2029,
  ~ci95_lower,    ~ci95_upper,      ~percent_change,
  ~annual_retirement_rate, ~avg_annual_retirements,   ~annual_entrants,
  ~replacement_ratio,      ~replacement_assessment,
  ~fellowship_total_4yr,   ~total_retirements_4yr,

  "Urogynecology and Reconstructive Pelvic Surgery", "URPS",
  1295L, 1505.3672, 15.2,  # ssot-ok: legacy frozen SGS projection cohort (baseline_2025)
  1476L, 1535L, 16.245,
  0.8809, 11.408178, 64L,
  5.61, "Above replacement",
  256L, 46L,

  "Gynecologic Oncology", "GO",
  1052L, 1309.8059, 16.1,
  1278L, 1341L, 24.506,
  1.0027, 10.548523, 75L,
  7.11, "Above replacement",
  300L, 42L,

  "Minimally Invasive Gynecologic Surgery", "MIGS",
  605L, 776.0018, 11.0,
  754L, 798L, 28.265,
  0.7024, 4.249548, 47L,
  11.06, "Above replacement",
  188L, 17L
)

# Validate before writing (fail closed).
validate_workforce_data(primary)

write_csv(primary, here::here("data","workforce_projections_consolidated.csv"))

message("[rebuild_ssot_revised] Wrote data/workforce_projections_consolidated.csv (",
        nrow(primary), " rows)")
