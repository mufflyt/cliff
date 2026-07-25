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
