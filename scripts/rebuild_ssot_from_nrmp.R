#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Rebuild the workforce-projection table using NRMP fellowship entrants
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Replaces the unsourced annual_entrants (URPS 60 / GO 50 / MIGS 45) with the
# authoritative NRMP "positions filled" counts (URPS 70 / GO 86 / MIGS 47;
# cliff/data/nrmp_fellowship_entrants.csv), keeps the baseline and retirement
# inputs unchanged, and recomputes every derived column via the SAME contract
# formulas the manuscript loader enforces.
#
# Writes a CORRECTED CANDIDATE to cliff/data/workforce_projections_NRMP_corrected.csv.
# It does NOT overwrite the live SSOT (cliff/data/workforce_projections_consolidated.csv)
# — adopting it reverses the manuscript's GO finding and requires updating the
# contract tests, so promotion is a deliberate, PI-sanctioned step.
#
# CAVEAT (carried, not fixed here): sd_2029 is inherited from the frozen archival
# run for the OLD entrants; the ±1.96·SD interval is a placeholder for the
# corrected projection and should be re-derived from a live simulation.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(here); library(dplyr); library(readr)})
source(here::here("manuscript", "R", "workforce_data_contract.R"))

HZ <- WORKFORCE_PROJECTION_HORIZON_YEARS  # 4
Z  <- WORKFORCE_CI_Z95                    # 1.96

current <- readr::read_csv(here::here("data", "workforce_projections_consolidated.csv"),
                           show_col_types = FALSE)
nrmp <- readr::read_csv(here::here("data", "nrmp_fellowship_entrants.csv"),
                        show_col_types = FALSE) %>%
  dplyr::select(subspecialty_abbrev, nrmp_entrants = annual_entrants)

rebuilt <- current %>%
  dplyr::left_join(nrmp, by = "subspecialty_abbrev") %>%
  dplyr::mutate(
    old_entrants           = annual_entrants,
    annual_entrants        = nrmp_entrants,                                  # NRMP filled
    # baseline, annual_retirement_rate, avg_annual_retirements, sd_2029 UNCHANGED
    projected_2029         = baseline_2025 + HZ * (annual_entrants - avg_annual_retirements),
    percent_change         = 100 * (projected_2029 - baseline_2025) / baseline_2025,
    replacement_ratio      = annual_entrants / avg_annual_retirements,
    replacement_assessment = classify_replacement(replacement_ratio),
    ci95_lower             = pmax(round(projected_2029 - Z * sd_2029), 0),   # placeholder SD
    ci95_upper             = round(projected_2029 + Z * sd_2029),
    fellowship_total_4yr   = annual_entrants * HZ,
    total_retirements_4yr  = round(avg_annual_retirements * HZ)
  )

# Validate the rebuilt table against the SAME fail-loud contract as the manuscript.
validate_cols <- rebuilt %>%
  dplyr::select(dplyr::all_of(c(WORKFORCE_REQUIRED_COLUMNS,
                                "fellowship_total_4yr", "total_retirements_4yr")))
validate_workforce_data(as.data.frame(validate_cols), source_hint = "NRMP-rebuilt")

out_path <- here::here("data", "workforce_projections_NRMP_corrected.csv")
readr::write_csv(dplyr::select(rebuilt, -old_entrants, -nrmp_entrants), out_path)

# --- Old vs corrected comparison ------------------------------------------
cmp <- rebuilt %>%
  dplyr::transmute(
    Subspec = subspecialty_abbrev,
    Baseline = baseline_2025,
    `Entrants (old→NRMP)` = sprintf("%d→%d", as.integer(old_entrants), as.integer(annual_entrants)),
    `Mean retire/yr` = round(avg_annual_retirements, 1),
    `Ratio` = sprintf("%.2f", replacement_ratio),
    `Proj 2029` = round(projected_2029),
    `Change %` = sprintf("%+.1f", percent_change),
    Assessment = replacement_assessment
  )
cat("\n=== CORRECTED PROJECTIONS (NRMP entrants) ===\n")
print(as.data.frame(cmp), row.names = FALSE)
cat(sprintf("\nCombined workforce: %d (2025) -> %d (2029) = %+.1f%%\n",
            sum(rebuilt$baseline_2025), round(sum(rebuilt$projected_2029)),
            100 * (sum(rebuilt$projected_2029) - sum(rebuilt$baseline_2025)) / sum(rebuilt$baseline_2025)))
cat("\nContract validation PASSED. Wrote candidate:", out_path, "\n")
cat("NOTE: live SSOT NOT modified. Promotion requires PI sign-off + test updates.\n")
