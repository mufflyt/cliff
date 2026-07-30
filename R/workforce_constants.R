# Canonical workforce-cliff constants (single source of truth).
#
# Sourced by BOTH the data contract (manuscript/R/workforce_data_contract.R) and the
# projection engine (R/workforce_cliff_engine.R) so shared study-design constants are
# defined in exactly one place and cannot drift between them.
#
# WORKFORCE_PROJECTION_HORIZON_YEARS
#   Meaning : the study projection horizon in whole years. 2025 -> 2029 is FOUR annual
#             transitions. Every "over the next N years" statement and every
#             `x * horizon` calculation MUST use this. Fellowship and retirement totals
#             are BOTH reported over this same horizon (fellowship_total_4yr,
#             total_retirements_4yr) so they are directly comparable.
#   Units   : whole years (integer).
#   Range   : positive integer.
#   Source  : study design (baseline year 2025, endpoint 2029).
#   History : a prior separate 5-year fellowship-report horizon was removed 2026-07-15
#             (mixing a 5-year fellowship count with 4-year retirements is an
#             apples-to-oranges trap).

WORKFORCE_PROJECTION_HORIZON_YEARS <- 4L

# Fail loudly if the canonical value is malformed (type/shape/range).
stopifnot(
  is.integer(WORKFORCE_PROJECTION_HORIZON_YEARS),
  length(WORKFORCE_PROJECTION_HORIZON_YEARS) == 1L,
  !is.na(WORKFORCE_PROJECTION_HORIZON_YEARS),
  WORKFORCE_PROJECTION_HORIZON_YEARS >= 1L
)

# PROJECTION_BASELINE_YEAR
#   Meaning : the projection baseline / first projected year. The supply projection ages the cohort
#             forward from here, and every reporting index is rebased to it (index(baseline)=100). With
#             WORKFORCE_PROJECTION_HORIZON_YEARS this fixes the endpoint (2025 + 4 = 2029).
#   Units   : calendar year (integer).
#   Range   : a single 4-digit year.
#   Source  : study design (baseline year of the age-structured projection).
#   Consumers: the SUPPLY engine (R/workforce_cliff_engine.R::WC_YEAR0) AND the DEMAND lineage
#             (R/demand_denominator.R::DEMAND_INDEX_BASE_YEAR) both alias this, so the two lineages that
#             previously each hardcoded 2025 now share ONE definition and cannot drift.
PROJECTION_BASELINE_YEAR <- 2025L
stopifnot(
  is.integer(PROJECTION_BASELINE_YEAR),
  length(PROJECTION_BASELINE_YEAR) == 1L,
  !is.na(PROJECTION_BASELINE_YEAR),
  PROJECTION_BASELINE_YEAR == 2025L   # pin the published baseline; a change must be deliberate
)

# WORKFORCE_ENTRY_AGE
#   Meaning : the age at which a newly completed fellowship graduate ENTERS the active workforce and begins
#             being exposed to age-band departure risk. Fellows certify ~age 30 (the engine's WC_AGE_AT_CERT)
#             and enter practice a few years later; each projected annual entrant cohort is injected into the
#             age-structured projection at this age.
#   Units   : years (integer).
#   Range   : a plausible physician entry age (25-45).
#   Source  : study design (age-structured projection entry age).
#   Consumers: the SUPPLY engine (R/workforce_cliff_engine.R::WC_ENTRY_AGE) AND the demand-side effective-supply
#             projection (scripts/urps_module_a_effective_supply_*.R::ENTRY_AGE) both alias this, so the two
#             lineages that previously each hardcoded 34 now share ONE definition and cannot drift.
WORKFORCE_ENTRY_AGE <- 34L
stopifnot(
  is.integer(WORKFORCE_ENTRY_AGE),
  length(WORKFORCE_ENTRY_AGE) == 1L,
  !is.na(WORKFORCE_ENTRY_AGE),
  WORKFORCE_ENTRY_AGE >= 25L, WORKFORCE_ENTRY_AGE <= 45L,
  WORKFORCE_ENTRY_AGE == 34L   # pin the published entry age; a change must be deliberate
)

# WORKFORCE_CONVERSION_FLOOR
#   Meaning : conservative graduate-to-practice conversion factor — the fraction of fellowship
#             completers assumed to enter active U.S. clinical practice in the subspecialty. The
#             uncertainty analysis brackets conversion from this floor up to 1.0 (all completers
#             enter); this floor is the "conservative (70% conversion)" scenario and the input to
#             the tipping-point / graduate-growth sensitivities.
#   Units   : proportion in (0, 1].
#   Source  : study design (conservative sensitivity floor; reported range "70% to 100%").
WORKFORCE_CONVERSION_FLOOR <- 0.70
stopifnot(
  is.numeric(WORKFORCE_CONVERSION_FLOOR),
  length(WORKFORCE_CONVERSION_FLOOR) == 1L,
  WORKFORCE_CONVERSION_FLOOR > 0,
  WORKFORCE_CONVERSION_FLOOR <= 1
)

# WC_SUBS / WC_SUBS_FULL — subspecialty abbreviation -> name mappings.
#   WC_SUBS      : the DATA-MATCH string used to filter the cohort by subspecialty. URPS is stored in
#                  the source data under its prior "Female Pelvic Medicine & Reconstructive Surgery" label.
#   WC_SUBS_FULL : the DISPLAY name (URPS -> "Urogynecology and Reconstructive Pelvic Surgery").
#   The two are INTENTIONALLY different for URPS (match vs display) and must NOT be collapsed.
#   WC_SUBS_FULL must equal the frozen SSOT csv `subspecialty` column (a code<->data guard enforces this).
#   Units   : named character vectors keyed by abbreviation (URPS/GO/MIGS).
#   Source  : study design (ABOG/ABU subspecialty naming).
WC_SUBS      <- c(URPS = "Female Pelvic Medicine & Reconstructive Surgery", GO = "Gynecologic Oncology", MIGS = "MIGS")
WC_SUBS_FULL <- c(URPS = "Urogynecology and Reconstructive Pelvic Surgery", GO = "Gynecologic Oncology", MIGS = "Minimally Invasive Gynecologic Surgery")
stopifnot(
  identical(names(WC_SUBS), names(WC_SUBS_FULL)),
  setequal(names(WC_SUBS_FULL), c("URPS", "GO", "MIGS")),
  all(nzchar(WC_SUBS)), all(nzchar(WC_SUBS_FULL)),
  WC_SUBS[["URPS"]] != WC_SUBS_FULL[["URPS"]]      # match vs display are distinct for URPS (do not collapse)
)

# WORKFORCE_CI_Z95
#   Meaning : the standard-normal multiplier for a two-sided 95% confidence interval, used for every
#             parametric workforce CI reported as `mean +/- z * SD` (projection endpoints, supply figure,
#             replacement-ratio appendix). The study uses the conventional rounded 1.96 (== round(qnorm(0.975), 2)).
#   Units   : dimensionless z-score (standard deviations).
#   Range   : (1.9, 2.0); must round to qnorm(0.975).
#   Source  : study design (parametric 95% CI convention).
#   Consumers: manuscript/R/workforce_data_contract.R (re-exported), scripts/fig_fpmrs_supply_line.R,
#             scripts/rebuild_ssot_from_nrmp.R, R/manuscript_consolidate_existing_results.R.
#   NOT for : non-95% intervals (code/03_create_abstract_figure.R deliberately uses 1.645 for a 90% CI) or
#             the general parametrized CI in R/calculate_retirement_cliff_statistics.R (z = qnorm from conf_level).
WORKFORCE_CI_Z95 <- 1.96
stopifnot(
  is.numeric(WORKFORCE_CI_Z95),
  length(WORKFORCE_CI_Z95) == 1L,
  !is.na(WORKFORCE_CI_Z95),
  WORKFORCE_CI_Z95 > 1.9, WORKFORCE_CI_Z95 < 2.0,
  round(stats::qnorm(0.975), 2) == WORKFORCE_CI_Z95   # it IS the two-sided 95% z (rounded), not an arbitrary number
)

# WORKFORCE_OUTLOOK_ADEQUATE_MIN / WORKFORCE_OUTLOOK_MARGINAL_MIN + classify_workforce_outlook()
#   Meaning : the "Workforce Outlook" categorisation of a replacement ratio (graduates / retirements) into
#             Adequate / Marginal / Insufficient, as published in the manuscript workforce table caption and
#             the replacement-ratio appendix:
#               Adequate     if RR >= 1.2   (>= a 20% entry-over-exit buffer)
#               Marginal     if 0.8 <= RR < 1.2
#               Insufficient if RR < 0.8    (net workforce decline)
#   Units   : dimensionless replacement ratio thresholds.
#   Range   : 0 < MARGINAL_MIN < ADEQUATE_MIN.
#   Source  : study design (manuscript "Workforce Outlook" bands; appendix_workforce_replacement_ratio.Rmd).
#   Consumers: scripts/graduate_growth_scenarios.R (the only site that COMPUTES the label). The manuscript
#             table (create_workforce_table.R) carries the outlook as reviewed data + states these cutpoints in
#             its caption; a guard checks that caption + the appendix math against these constants.
#   DISTINCT FROM: the contract's replacement classification classify_replacement() (Above/At/Below replacement,
#             cuts 0.95/1.05 via WORKFORCE_REPLACEMENT_* in manuscript/R/workforce_data_contract.R). The two are
#             SEPARATE schemes (different labels, different cutpoints, different tables) and must NOT be merged.
WORKFORCE_OUTLOOK_ADEQUATE_MIN <- 1.2   # RR >= this -> "Adequate"
WORKFORCE_OUTLOOK_MARGINAL_MIN <- 0.8   # RR >= this (and < ADEQUATE_MIN) -> "Marginal"; below -> "Insufficient"
stopifnot(
  is.numeric(WORKFORCE_OUTLOOK_ADEQUATE_MIN), length(WORKFORCE_OUTLOOK_ADEQUATE_MIN) == 1L,
  is.numeric(WORKFORCE_OUTLOOK_MARGINAL_MIN), length(WORKFORCE_OUTLOOK_MARGINAL_MIN) == 1L,
  WORKFORCE_OUTLOOK_MARGINAL_MIN > 0,
  WORKFORCE_OUTLOOK_MARGINAL_MIN < WORKFORCE_OUTLOOK_ADEQUATE_MIN   # ordered bands
)

#' Classify a replacement ratio into a workforce-outlook label
#'
#' Map a fellowship-replacement ratio (annual graduates / annual retirements) to
#' the manuscript "Workforce Outlook" category, using the shared cutpoints
#' `WORKFORCE_OUTLOOK_ADEQUATE_MIN` (>= 1.2) and `WORKFORCE_OUTLOOK_MARGINAL_MIN`
#' (>= 0.8).
#'
#' @details This is the manuscript workforce-table scheme
#'   (Adequate / Marginal / Insufficient). It is INTENTIONALLY DISTINCT from the
#'   data contract's replacement classifier `classify_replacement()`
#'   (Above / At / Below replacement, cutpoints 0.95 / 1.05, in
#'   `manuscript/R/workforce_data_contract.R`): different labels, different
#'   cutpoints, different tables. The two must not be merged.
#' @param ratio Numeric vector of replacement ratios (graduates / retirements);
#'   `NA` propagates.
#' @return A character vector the same length as `ratio`, each `"Adequate"`
#'   (ratio >= 1.2), `"Marginal"` (0.8 <= ratio < 1.2), or `"Insufficient"`
#'   (ratio < 0.8).
#' @seealso `WORKFORCE_OUTLOOK_ADEQUATE_MIN`, `WORKFORCE_OUTLOOK_MARGINAL_MIN`.
#'   Guarded by `tests/testthat/test-ssot-workforce-outlook.R`.
#' @examples
#' classify_workforce_outlook(c(0.7, 1.0, 1.3))  # "Insufficient" "Marginal" "Adequate"
classify_workforce_outlook <- function(ratio) {
  ifelse(ratio >= WORKFORCE_OUTLOOK_ADEQUATE_MIN, "Adequate",
         ifelse(ratio >= WORKFORCE_OUTLOOK_MARGINAL_MIN, "Marginal", "Insufficient"))
}

# WORKFORCE_OBSERVED_START_YEAR
#   Meaning : the FIRST year of the study's observed administrative data window (the earliest Medicare
#             fee-for-service year used for the panel / observed supply series / truth-contract year bound).
#   Units   : calendar year (integer).
#   Range   : a single 4-digit year.
#   Source  : study design (observed data begins 2013).
#   Consumers: scripts/urps_module_a_age_productivity_2026-07-23.R (panel `yrs`), scripts/fig_fpmrs_supply_line.R
#             (`OBS_START`), R/validators/validate_workforce_truth_contract.R (`year_min_allowed`).
#   NOT the window END: the observed window END differs by context and is DELIBERATELY separate — the
#             truth-contract study scope ends 2023, while the Medicare panel / observed supply series run to the
#             latest available year 2024. This constant is ONLY the shared start; do not fold an end year into it.
WORKFORCE_OBSERVED_START_YEAR <- 2013L
stopifnot(
  is.integer(WORKFORCE_OBSERVED_START_YEAR),
  length(WORKFORCE_OBSERVED_START_YEAR) == 1L,
  !is.na(WORKFORCE_OBSERVED_START_YEAR),
  WORKFORCE_OBSERVED_START_YEAR == 2013L,               # pin the published observed-window start
  WORKFORCE_OBSERVED_START_YEAR < PROJECTION_BASELINE_YEAR   # observation precedes the projection baseline
)

# WORKFORCE_OBSERVED_END_YEAR
#   Meaning : the LAST fully-observable / confirmable year of the study window — the 3-year-administrative-
#             follow-up boundary through which a departure can be confirmed (departures dated after this are
#             right-censored). It is the upper bound of the truth-contract study scope (2013-2023) and the end
#             of the hazard-observation window's fully-observable range.
#   Units   : calendar year (integer).
#   Range   : a single 4-digit year, after the observed start, at/before the reference year.
#   Source  : study design (data end 2023-2024 minus the 3-year confirmation rule -> 2023).
#   Consumers: the engine (R/workforce_cliff_engine.R::WC_OBS_END aliases this) AND
#             R/validators/validate_workforce_truth_contract.R (`year_max_allowed`).
#   DISTINCT FROM: the reference / latest-data year 2024 (engine WC_REF_YEAR; the Medicare panel and observed
#             supply series in scripts/urps_module_a_age_productivity_* and fig_fpmrs_supply_line run to 2024).
#             The confirmable-observation end (2023) and the latest-available-data year (2024) are separate
#             concepts and must NOT be collapsed.
WORKFORCE_OBSERVED_END_YEAR <- 2023L
stopifnot(
  is.integer(WORKFORCE_OBSERVED_END_YEAR),
  length(WORKFORCE_OBSERVED_END_YEAR) == 1L,
  !is.na(WORKFORCE_OBSERVED_END_YEAR),
  WORKFORCE_OBSERVED_END_YEAR == 2023L,                          # pin the published observation-confirmable end
  WORKFORCE_OBSERVED_END_YEAR > WORKFORCE_OBSERVED_START_YEAR    # end follows start
)

# WORKFORCE_REFERENCE_YEAR
#   Meaning : the reference / latest-available-data year — the year the cohort's ages are reckoned as-of and the
#             most recent Medicare fee-for-service year in the panel. Physician age is reconstructed as
#             (reference year − certification year + age-at-certification), and the age-productivity panel runs
#             through this year.
#   Units   : calendar year (integer).
#   Range   : a single 4-digit year, after the observation-confirmable end, before the projection baseline.
#   Source  : study design (latest available Medicare data = 2024).
#   Consumers: the engine (R/workforce_cliff_engine.R::WC_REF_YEAR aliases this; the 4 engine-sourcing scripts
#             alias WC_REF_YEAR) AND scripts/urps_module_a_age_productivity_2026-07-23.R (age-as-of year + panel end).
#   DISTINCT FROM: the observation-confirmable end 2023 (WORKFORCE_OBSERVED_END_YEAR; 3-yr follow-up boundary).
#             The latest-data year (2024) is one year past the last confirmable-departure year (2023); they are
#             separate concepts and must NOT be collapsed. Also distinct from the module_bc Medicare *table/column*
#             identifiers `medicare_part_b_by_service_2024` / `national_2024` (schema names, left literal).
WORKFORCE_REFERENCE_YEAR <- 2024L
stopifnot(
  is.integer(WORKFORCE_REFERENCE_YEAR),
  length(WORKFORCE_REFERENCE_YEAR) == 1L,
  !is.na(WORKFORCE_REFERENCE_YEAR),
  WORKFORCE_REFERENCE_YEAR == 2024L,                             # pin the published reference / latest-data year
  WORKFORCE_REFERENCE_YEAR > WORKFORCE_OBSERVED_END_YEAR,        # latest data is past the confirmable-observation end
  WORKFORCE_REFERENCE_YEAR < PROJECTION_BASELINE_YEAR           # reference precedes the projection baseline
)
