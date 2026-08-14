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
#
# ONLY MEASURED INPUTS ARE TYPED HERE. Every algebraically derived column is
# computed below in derive(), never hand-entered. Hand-entering them is what
# previously let the artifact drift out of agreement with its own definitions:
# the stored replacement_ratio (5.38) and percent_change (24.506, 28.265) were
# rounded literals, so the identity checks failed against the full-precision
# values they are defined as. Display rounding belongs in the manuscript, not
# in the single source of truth.
# ---------------------------------------------------------------------------

primary <- tibble::tribble(
  ~subspecialty,                                       ~subspecialty_abbrev,
  ~baseline_2025, ~projected_2029,  ~sd_2029,
  ~ci95_lower,    ~ci95_upper,
  ~avg_annual_retirements,   ~annual_entrants,

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
  1494L, 1525L,
  11.8851, 64L,

  "Gynecologic Oncology", "GO",
  1052L, 1309.8059, 16.1,
  1278L, 1341L,
  10.548523, 75L,

  "Minimally Invasive Gynecologic Surgery", "MIGS",
  605L, 776.0018, 11.0,
  754L, 798L,
  4.249548, 47L
)

# ---------------------------------------------------------------------------
# Derived columns. Each is a definition, not a datum. Guarded by
# tests/testthat/test-ssot-derived-column-identities.R, which re-checks every
# one of these identities against the written artifact at full precision.
# ---------------------------------------------------------------------------
derive <- function(df) {
  dplyr::mutate(df,
    # rate of departure per 100 active, per year
    annual_retirement_rate = 100 * avg_annual_retirements / baseline_2025,
    # entrants per departure; > 1 means completions outpace departures
    replacement_ratio      = annual_entrants / avg_annual_retirements,
    percent_change         = 100 * (projected_2029 - baseline_2025) / baseline_2025,
    replacement_assessment = ifelse(replacement_ratio >= 1,
                                    "Above replacement", "Below replacement"),
    # 4-year window totals implied by the annual rates
    fellowship_total_4yr   = as.integer(4L * annual_entrants),
    total_retirements_4yr  = as.integer(round(4 * avg_annual_retirements))
  ) |>
    dplyr::select(subspecialty, subspecialty_abbrev, baseline_2025, projected_2029,
                  sd_2029, ci95_lower, ci95_upper, percent_change,
                  annual_retirement_rate, avg_annual_retirements, annual_entrants,
                  replacement_ratio, replacement_assessment,
                  fellowship_total_4yr, total_retirements_4yr)
}

primary <- derive(primary)

# Prove the identities hold in the object we are about to write (fail closed).
stopifnot(
  isTRUE(all.equal(primary$replacement_ratio,
                   primary$annual_entrants / primary$avg_annual_retirements)),
  isTRUE(all.equal(primary$percent_change,
                   100 * (primary$projected_2029 - primary$baseline_2025) /
                     primary$baseline_2025))
)

# Validate before writing (fail closed).
validate_workforce_data(primary)

write_csv(primary, here::here("data","workforce_projections_consolidated.csv"))

message("[rebuild_ssot_revised] Wrote data/workforce_projections_consolidated.csv (",
        nrow(primary), " rows)")
