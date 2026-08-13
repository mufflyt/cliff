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
  # cliff#1 v3.0.0 re-derivation: baseline = canonical 2023 board-certified active
  # (1306 = 1027 ABOG + 279 ABU_NET_NEW), projected with the SAME POOLED GO+URPS
  # age-band hazard used by the frozen primary (5.61), now applied to the 1306
  # active-age distribution + the manuscript parameter-uncertainty MC (Beta on the
  # pooled events, graduate bootstrap, seed 20260718, 10000 draws). The ratio moves
  # 5.61 (1295) -> 5.38 (1306): a small age-distribution effect, NOT the large
  # "engine-driven" drop erroneously reported from an earlier run that mistakenly
  # used the URPS-anchored hazard. See scripts/urps_scenario_cube/regen_urps_1306_projection.R.
  1306L, 1514.4596, 7.91,   # ssot-ok: historical data row in a regeneration script, not a live baseline claim
  1494L, 1525L, 15.96168,
  0.910, 11.8851, 64L,
  5.38, "Above replacement",
  256L, 48L,

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
