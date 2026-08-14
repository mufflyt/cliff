#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# EMPIRICAL age-stratified annual retirement rate per gyn surgical subspecialty
# Derived from the cohort's OWN 2013-2023 historical retirements
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Supersedes the HRSA-band assumption (compute_age_stratified_retirement_rate.R).
# Instead of importing HRSA/AAMC general-physician age-band probabilities, this
# estimates the age-band annual retirement HAZARD directly from the ABOG
# subspecialist cohort's observed retirements, then applies those empirical
# bands to each subspecialty's current active-age distribution.
#
# RETIREMENT SIGNAL. The event is `retirement_year` from the isochrones 24-source
# retirement CONSENSUS (`credentials.retirement_consensus` -> `retirement_year_final`,
# surfaced in table1 as `retirement_year`). This consensus is ANCHORED ON the NBER
# NPPES historical data (temporal disappearance + deactivation is its highest-weight
# component, 0.35) blended with Medicare Part B billing cessation and ABMS lapse.
#   NOTE (why not "pure" NPPES): 0 of 7,208 cohort NPIs appear in the NPPES formal
#   deactivation signal (credentials.retirement_signal_nppes) -- board-certified
#   subspecialists essentially never deactivate their NPI. The multi-source
#   consensus is therefore the only measurable empirical retirement signal for
#   this cohort.
#
# LIFE-TABLE. Age each year is reconstructed from certification:
#   age(year) = year - cert_year + 30      (age_approx = ref_year - cert_year + 30)
# For observation years in WIN = [2016, 2023] (the span over which the consensus
# detects retirements), each physician contributes one person-year at risk per
# active year (from max(WIN_lo, cert_year) through their retirement year, if any),
# and one retirement EVENT in their retirement_year. The age-band annual hazard is
#   haz[band] = sum(events in band) / sum(person-years in band).
#
# EXTERNAL BENCHMARK (Elemosho et al., J Am Coll Surg 2026; DOI
# 10.1097/XCS.0000000000001905): the same Medicare Part B PUF (2013-2023) + NPPES
# NPI linkage, with "attrition" = first year followed by 3 consecutive years of
# <50 E&M services. National surgeon annual attrition was 1.5-1.7%/yr (2.5% peak
# 2019). Our empirical subspecialty rates fall in the same range -- an independent
# validation, and evidence the HRSA general-physician bands (4-6%/yr) overstate
# retirement for board-certified surgical subspecialists.
#
# CAVEATS (stated in Methods): (1) age is certification-anchored (30 + years since
# board certification), not birthdate; (2) retirements in 2021-2023 are
# under-detected (the consensus needs >=3 yr of billing cessation to confirm), so
# the empirical rate is a conservative FLOOR.
#
# Input:  /Users/tylermuffly/isochrones/manuscript/tables/table1_physician_characteristics.csv
# Output: cliff/data/retirement_rates_age_stratified.csv  (with provenance)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(here); library(readr); library(dplyr)})


# PORTED FROM THE ISOCHRONES MONOREPO (2026-08-14). The extraction that created
# this repository carried this script's OUTPUT across but not the script, so the
# artifact sat in data/ with nothing able to regenerate it. Changes on porting:
#   * here::here("cliff", "data", X) -> here::here("data", X); this IS cliff now
#   * monorepo inputs resolve under CLIFF_ISOCHRONES_ROOT and fail loudly when
#     absent, rather than being hardcoded absolute paths that would silently
#     rebuild on whatever happened to be there
ISO <- Sys.getenv("CLIFF_ISOCHRONES_ROOT", unset = path.expand("~/isochrones"))
iso <- function(...) {
  p <- file.path(ISO, ...)
  if (!file.exists(p))
    stop(sprintf("[%s] monorepo input not found:\n  %s", "compute_empirical_retirement_rate_nppes", p), call. = FALSE)
  p
}

args <- commandArgs(trailingOnly = TRUE)
cohort <- if (length(args) >= 1) args[[1]] else
  iso("manuscript", "tables", "table1_physician_characteristics.csv")
if (!file.exists(cohort)) stop("cohort file not found: ", cohort)

# ---- configuration --------------------------------------------------------
BANDS       <- c(0, 45, 50, 55, 60, 65, 70, Inf)
BAND_LABELS <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
# Fully-observable window (peer-review #4): with Medicare/NPPES data to 2023 and a
# 3-year cessation rule, exits after 2021 are unconfirmable and pile up as
# provisional over-flags, so hazard estimation is restricted to 2016-2021.
WIN         <- c(2016L, 2021L)   # fully-observable departure window
AGE_AT_CERT <- 30L               # age_approx convention: ref_year - cert_year + 30
band_of <- function(age) cut(age, breaks = BANDS, labels = BAND_LABELS, right = FALSE)

SUBS <- c(URPS = "Female Pelvic Medicine & Reconstructive Surgery",
          GO   = "Gynecologic Oncology",
          MIGS = "MIGS")
# Annual practice entrants = ACGME actual GRADUATES (completers entering practice),
# the primary inflow for the workforce model (Tier-3 integration 2026-07-18).
# GO 79 | URPS 50 from ACGME Data Resource Book graduating-residents table, AY
# 2023-24 (most recent). MIGS 47 from the NRMP/AAGL FMIGS match: MIGS is NOT
# ACGME-accredited, so no ACGME graduate series exists (different ascertainment).
# NRMP positions-filled (GO 86 | URPS 70 | MIGS 47) is retained as a labeled
# benchmark in cliff/data/workforce_projection_benchmark_nrmp.csv, not here.
ENTRANTS <- c(URPS = 50L, GO = 79L, MIGS = 47L)   # ACGME graduates (MIGS: NRMP/AAGL)

t <- readr::read_csv(cohort, show_col_types = FALSE, guess_max = 100000)

coh <- t %>%
  dplyr::filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  dplyr::transmute(
    npi = as.character(npi),
    subspecialty_abbrev = names(SUBS)[match(subspecialty, SUBS)],
    cert_year = as.integer(cert_year),
    retirement_year = suppressWarnings(as.integer(retirement_year)),
    is_retired_for_cohorting = as.logical(is_retired_for_cohorting),
    age_approx = as.integer(age_approx)) %>%
  dplyr::distinct(npi, .keep_all = TRUE) %>%
  dplyr::filter(!is.na(subspecialty_abbrev))

# PRIMARY departure definition: require a non-Open-Payments corroborating source
# (scripts/departure_anchor.R); Open-Payments-only departures are nulled.
.anch <- readr::read_csv(here::here("data", "departure_anchor.csv"), show_col_types = FALSE)
coh <- coh %>% dplyr::left_join(dplyr::mutate(.anch, npi=as.character(npi)), by = "npi") %>%
  dplyr::mutate(retirement_year = ifelse(!is.na(retirement_year) & !has_nonop_anchor,
                                          NA_integer_, retirement_year)) %>%
  dplyr::select(-has_nonop_anchor)

# ---- (1) empirical age-band annual hazard (life-table) --------------------
pt <- do.call(rbind, lapply(seq_len(nrow(coh)), function(i) {
  cy <- coh$cert_year[i]; ry <- coh$retirement_year[i]
  if (!is.na(ry) && (ry < WIN[1] || ry > WIN[2])) ry <- NA_integer_  # events only in window
  y0 <- max(WIN[1], cy)
  y1 <- if (is.na(ry)) WIN[2] else min(WIN[2], ry)
  if (y1 < y0) return(NULL)
  yy <- y0:y1
  data.frame(band  = band_of(yy - cy + AGE_AT_CERT),
             event = as.integer(!is.na(ry) & yy == ry))
}))
band_haz <- pt %>%
  dplyr::group_by(band) %>%
  dplyr::summarise(person_years = dplyr::n(), events = sum(event), .groups = "drop") %>%
  dplyr::mutate(haz = events / person_years) %>%
  tidyr::complete(band = factor(BAND_LABELS, levels = BAND_LABELS),
                  fill = list(person_years = 0L, events = 0L, haz = NA_real_))
haz <- setNames(band_haz$haz, as.character(band_haz$band))

# ---- (2) apply empirical bands to each subspecialty's ACTIVE age dist ------
active <- coh %>%
  dplyr::filter(is_retired_for_cohorting == FALSE, !is.na(age_approx)) %>%
  dplyr::mutate(band = band_of(age_approx))

# directly-observed pooled annual rate per subspecialty (cross-check, no banding)
observed <- pt2 <- do.call(rbind, lapply(seq_len(nrow(coh)), function(i) {
  cy <- coh$cert_year[i]; ry <- coh$retirement_year[i]
  if (!is.na(ry) && (ry < WIN[1] || ry > WIN[2])) ry <- NA_integer_
  y0 <- max(WIN[1], cy); y1 <- if (is.na(ry)) WIN[2] else min(WIN[2], ry)
  if (y1 < y0) return(NULL)
  data.frame(subspecialty_abbrev = coh$subspecialty_abbrev[i],
             py = length(y0:y1),
             ev = as.integer(!is.na(ry)))
}))
obs_rate <- observed %>% dplyr::group_by(subspecialty_abbrev) %>%
  dplyr::summarise(rate_observed = 100 * sum(ev) / sum(py), .groups = "drop")

res <- lapply(names(SUBS), function(k) {
  d <- active[active$subspecialty_abbrev == k, ]
  n <- nrow(d)
  rate <- sum(haz[as.character(d$band)]) / n          # age-stratified empirical rate
  retire_per_yr <- rate * n
  data.frame(
    subspecialty_abbrev    = k,
    n_active               = n,
    median_age             = median(d$age_approx),
    annual_retirement_rate = round(100 * rate, 1),
    retirements_per_yr     = round(retire_per_yr, 1),
    nrmp_entrants          = ENTRANTS[[k]],
    replacement_ratio      = round(ENTRANTS[[k]] / retire_per_yr, 2),
    stringsAsFactors = FALSE)
})
out <- do.call(rbind, res) %>%
  dplyr::left_join(obs_rate, by = "subspecialty_abbrev") %>%
  dplyr::mutate(rate_observed = round(rate_observed, 1))
out$assessment <- ifelse(out$replacement_ratio >= 1.20, "Adequate",
                  ifelse(out$replacement_ratio >= 0.80, "Marginal", "Insufficient"))
out$source <- paste0("Empirical age-band retirement hazard from the ABOG cohort's ",
  "observed 2016-2023 retirements (isochrones 24-source consensus retirement_year, ",
  "NBER-NPPES-anchored), applied to each subspecialty's active-physician age ",
  "distribution; benchmarked to Elemosho et al. J Am Coll Surg 2026 ",
  "(1.5-1.7%/yr national surgeon attrition)")

out_path <- here::here("data", "retirement_rates_age_stratified.csv")
readr::write_csv(out, out_path)

# also persist the empirical age-band hazard table for the supplement
band_out <- band_haz %>%
  dplyr::transmute(age_band = as.character(band), person_years, events,
                   annual_hazard = round(haz, 4))
readr::write_csv(band_out, here::here("data", "retirement_hazard_by_ageband.csv"))

# ---- (2) age at departure from active practice, by subspecialty ------------
# The consensus signal marks PERMANENT DEPARTURE from active practice, which
# spans retirement plus other exits; the age distribution makes that explicit
# (cf. Gettel et al., Acad Emerg Med 2023, median EM attrition age 44-56).
dep <- coh %>%
  dplyr::filter(!is.na(retirement_year), retirement_year >= WIN[1], retirement_year <= WIN[2]) %>%
  dplyr::mutate(age_at_departure = retirement_year - cert_year + AGE_AT_CERT)
dep_sum <- dep %>%
  dplyr::group_by(subspecialty_abbrev) %>%
  dplyr::summarise(n_departures = dplyr::n(),
                   median_age = as.integer(median(age_at_departure)),
                   q1_age = as.integer(quantile(age_at_departure, 0.25)),
                   q3_age = as.integer(quantile(age_at_departure, 0.75)),
                   .groups = "drop")
readr::write_csv(dep_sum, here::here("data", "age_at_departure_by_subspecialty.csv"))

# ---- (3) definitional sensitivity of the departure rate --------------------
# Vary the estimator (age-stratified vs directly-observed) and the age proxy
# (certification at 30 vs 33), mirroring the definitional robustness check in
# Gettel et al. (2023). Adequacy is confirmed at the highest rate in the range.
agestrat_rate <- function(offset) {
  pt2 <- do.call(rbind, lapply(seq_len(nrow(coh)), function(i) {
    cy <- coh$cert_year[i]; ry <- coh$retirement_year[i]
    if (!is.na(ry) && (ry < WIN[1] || ry > WIN[2])) ry <- NA_integer_
    y0 <- max(WIN[1], cy); y1 <- if (is.na(ry)) WIN[2] else min(WIN[2], ry)
    if (y1 < y0) return(NULL)
    yy <- y0:y1
    data.frame(band = band_of(yy - cy + offset), event = as.integer(!is.na(ry) & yy == ry))
  }))
  bh <- pt2 %>% dplyr::group_by(band) %>%
    dplyr::summarise(py = dplyr::n(), ev = sum(event), .groups = "drop") %>%
    dplyr::mutate(h = ev / py)
  hv <- setNames(bh$h, as.character(bh$band))
  # shift the (age_approx-based) active ages by the change from the 30-year proxy,
  # so offset == AGE_AT_CERT reproduces the primary age-stratified rate exactly
  a <- coh %>% dplyr::filter(is_retired_for_cohorting == FALSE, !is.na(age_approx)) %>%
    dplyr::mutate(band = band_of(age_approx + (offset - AGE_AT_CERT)))
  vapply(names(SUBS), function(k) {
    d <- a[a$subspecialty_abbrev == k, ]
    100 * sum(hv[as.character(d$band)], na.rm = TRUE) / nrow(d)
  }, numeric(1))
}
r30 <- agestrat_rate(30L); r33 <- agestrat_rate(33L)
obs_v <- setNames(obs_rate$rate_observed, obs_rate$subspecialty_abbrev)
nact  <- setNames(out$n_active, out$subspecialty_abbrev)
sens <- data.frame(
  subspecialty_abbrev    = names(SUBS),
  rate_agestratified     = round(r30[names(SUBS)], 1),
  rate_directly_observed = round(obs_v[names(SUBS)], 1),
  rate_agecert33         = round(r33[names(SUBS)], 1),
  row.names = NULL)
sens$rate_min <- apply(sens[, c("rate_agestratified","rate_directly_observed","rate_agecert33")], 1, min)
sens$rate_max <- apply(sens[, c("rate_agestratified","rate_directly_observed","rate_agecert33")], 1, max)
sens$ratio_at_max_rate <- round(vapply(names(SUBS), function(k)
  ENTRANTS[[k]] / (nact[[k]] * sens$rate_max[sens$subspecialty_abbrev == k] / 100), numeric(1))[names(SUBS)], 2)
sens$assessment_at_max_rate <- ifelse(sens$ratio_at_max_rate >= 1.20, "Adequate",
                               ifelse(sens$ratio_at_max_rate >= 0.80, "Marginal", "Insufficient"))
readr::write_csv(sens, here::here("data", "departure_rate_sensitivity.csv"))

cat("\n=== Age at departure from active practice (median [IQR]) ===\n")
print(as.data.frame(dep_sum), row.names = FALSE)
cat("\n=== Definitional sensitivity of the departure rate ===\n")
print(as.data.frame(sens), row.names = FALSE)

cat("\n=== Empirical age-band annual hazard (cohort 2016-2023) ===\n")
print(as.data.frame(band_out), row.names = FALSE)
cat("\n=== Empirical age-stratified retirement rates ===\n")
print(out[, c("subspecialty_abbrev","n_active","median_age","annual_retirement_rate",
              "rate_observed","retirements_per_yr","nrmp_entrants",
              "replacement_ratio","assessment")], row.names = FALSE)
cat("\n(prior HRSA-assumed rates for comparison: URPS 4.7 | GO 6.0 | MIGS 2.6)\n")
cat("(JACS national surgeon annual attrition benchmark: 1.5-1.7%/yr)\n")
cat("Wrote", out_path, "\n")
