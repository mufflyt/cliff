#!/usr/bin/env Rscript
# ==============================================================================
# build_urps_projection.R  [APPLY IN: cliff]
#
# Produces the cliff -> mufflyaccess PROJECTION artifact: a long, contract-
# conforming URPS workforce projection (national, ABOG_PLUS_ABU) from the index
# year 2023 through 2040, one series per EXECUTABLE mufflyaccess scenario.
#
# Inputs (all committed + reproducible; no local cohort CSV, no runtime parquet):
#   * Starting cohort ages: scripts/urps_baseline_scenarios/urps_cohort_ages_v3.0.0.csv
#     (n_active_2023 sums to 1306 on the URPS SUBSPECIALTY-cert basis; this table is
#     the isochrones provider-snapshot parquet distilled to an age distribution by
#     scripts/urps_baseline_scenarios/extract_cohort_ages.py -- so the seed matches
#     the SSOT, NOT cliff's primary-cert cohort which would give the retired 1332).
#   * Retirement hazards + entrants: cliff's REVIEWED frozen model (BAND_EV/BAND_PY,
#     2016-2021 primary window; ENTRANTS = mean(GRAD_URPS) = 64), identical to
#     scripts/urps_baseline_scenarios/urps_scenario_analysis_v3.R.
#   * The engine: the REAL wc_project_trajectory() / wc_project_ages(), loaded
#     verbatim from R/workforce_cliff_engine.R via wc_engine_loader.R (no reimpl.).
#   * Scenario levers: mufflyaccess::urps_scenarios() (the shared dictionary).
#   * Clinical FTE: mufflyaccess::urps_effective_fte() over the projected age x
#     pathway distribution (urps_cohort_ages_by_pathway_v3.0.0.csv), applying the
#     scenario's late-career FTE lever. mufflyaccess owns the FTE definition; cliff
#     just projects the age structure and calls it.
#   * Demand + gap: mufflyaccess::urps_demand_fte() / urps_gap_fte(). A
#     PRE-CALIBRATION skeleton today (returns NA), wired unconditionally so the
#     columns light up with zero code change once the demand equations are fit.
#
# Scope: 2040 horizon, index on 2023-active (1306), national ABOG_PLUS_ABU, ALL 14
# registered scenarios. supply_headcount is the deterministic point estimate;
# lower_95 / upper_95 are the Monte Carlo 95% interval (2000 draws: Beta band
# hazards + bootstrapped entrants, seed 20260718 -- the same scheme as
# urps_scenario_analysis_v3.R). supply_clinical_fte is the deterministic age x
# pathway capacity index (each head <= 1.0 FTE, so FTE <= headcount).
# demand_clinical_fte / gap_fte are NA until the mufflyaccess demand model
# calibrates (a fail-loud guard forces a real demand population in at that point).
#
# The output is VALIDATED against the mufflyaccess projection contract, including a
# baseline_tie back to urps_count(2023) so it can never drift from the served count.
# ==============================================================================
suppressWarnings(suppressMessages({
  if (!requireNamespace("mufflyaccess", quietly = TRUE))
    stop("mufflyaccess (>= 0.10.0) is required: renv::install(\"mufflyt/mufflyaccess\").")
}))

find_root <- function() {
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) { if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
                   p <- dirname(d); if (identical(p, d)) break; d <- p }
  normalizePath(getwd(), winslash = "/")
}
ROOT <- find_root()

INDEX_YEAR <- 2023L
END_YEAR   <- 2040L
HORIZON    <- END_YEAR - INDEX_YEAR                 # 17
PATHWAY    <- "ABOG_PLUS_ABU"
GEOG_TYPE  <- "national"
GEOG_ID    <- "US"
SPECIALTY  <- "URPS"

## ---- the REAL engine (pure functions, loaded verbatim) ----------------------
source(file.path(ROOT, "scripts", "urps_baseline_scenarios", "wc_engine_loader.R"))
eng <- load_real_wc_engine(file.path(ROOT, "R", "workforce_cliff_engine.R"))
BAND_LABELS <- eng$WC_BAND_LABELS

## ---- retirement-hazard SOURCE seam ------------------------------------------
# Historical exits are OBSERVED in mufflyaccess; future exits are SIMULATED here
# from a hazard calibrated to them. CLIFF_RETIREMENT_SOURCE selects which hazard
# the projection runs on -- default "legacy_modeled" (the reviewed frozen band
# model, byte-identical to the prior artifact). "observed_hazard" reads only
# mufflyaccess::urps_exit_hazard_by_age_year() and fails loud unless retirement is
# observed. It is NOT the production default: promote it only after the real
# provider-month evidence is populated, the hazard is validated, and the back-test
# beats the frozen model. See scripts/urps_projection/RETIREMENT_SOURCE.md.
source(file.path(ROOT, "R", "wc_retirement_hazard.R"))
RETIREMENT_SOURCE <- Sys.getenv("CLIFF_RETIREMENT_SOURCE", "legacy_modeled")

## ---- starting cohort ages (parquet-derived, sums to 1306) -------------------
ages_tbl <- utils::read.csv(
  file.path(ROOT, "scripts", "urps_baseline_scenarios", "urps_cohort_ages_v3.0.0.csv"),
  stringsAsFactors = FALSE)
ages <- rep(ages_tbl$age_proxy, ages_tbl$n_active_2023)      # integer age-proxy vector
ssot_active_2023 <- mufflyaccess::urps_count(INDEX_YEAR, "board_certified_active", GEOG_TYPE, TRUE)
if (length(ages) != ssot_active_2023)
  stop(sprintf("[build] seed cohort (%d) != urps_count(%d) (%d); the frozen ages table is out of sync with the SSOT.",
               length(ages), INDEX_YEAR, ssot_active_2023), call. = FALSE)

## ---- age x pathway split (for the clinical-FTE layer) -----------------------
# ABOG (clinical-time 1.00) vs ABU (0.70). Parquet-derived, committed, and asserted
# to sum back to the by-age cohort above. age_proxy is an ESTIMATED age proxy.
pw_tbl <- utils::read.csv(
  file.path(ROOT, "scripts", "urps_baseline_scenarios", "urps_cohort_ages_by_pathway_v3.0.0.csv"),
  stringsAsFactors = FALSE)
if (sum(pw_tbl$n_active_2023) != ssot_active_2023)
  stop("[build] by-pathway cohort does not sum to the SSOT active count.", call. = FALSE)
ages_pw <- lapply(split(pw_tbl, pw_tbl$pathway),
                  function(x) rep(x$age_proxy, x$n_active_2023))   # $ABOG, $ABU age vectors
# The by-age table drives headcount / MC; the by-pathway table drives FTE. They
# must describe the SAME cohort, or headcount and FTE would silently desync. Assert
# the by-pathway table, summed over pathway, is the by-age table age-for-age.
if (!isTRUE(all.equal(sort(ages), sort(unlist(ages_pw, use.names = FALSE)))))
  stop("[build] the by-pathway cohort ages do not match the by-age cohort; the two ",
       "frozen tables have drifted -- regenerate both from the same provider snapshot.",
       call. = FALSE)
PW_SHARE <- vapply(ages_pw, length, integer(1)) / ssot_active_2023 # entrant pathway split
# reference (2023) counts for the FTE calc, one row per age x pathway
REF_COUNTS <- data.frame(age = pw_tbl$age_proxy, pathway = pw_tbl$pathway,
                         n = pw_tbl$n_active_2023, stringsAsFactors = FALSE)

## ---- retirement hazards + entrants ------------------------------------------
# Entrants are independent of the retirement-hazard source (graduate supply, not
# departures), so they are unchanged regardless of CLIFF_RETIREMENT_SOURCE.
GRAD_URPS <- c(61, 66, 63, 66)
ENTRANTS  <- mean(GRAD_URPS)                                 # 64
# The frozen band model, verbatim from urps_scenario_analysis_v3.R (HAZARD_VERSION
# "fully_obs (BAND_EV/BAND_PY, 2016-2021 primary window)"). For source=="legacy_modeled"
# the resolver echoes these back unchanged (byte-identical projection); for
# "observed_hazard" they are ignored and the hazard comes from mufflyaccess.
LEGACY_BAND_EV <- c(13.058, 2.853, 3.508, 4.002, 5.192, 4.388, 0)
LEGACY_BAND_PY <- c(3854, 973, 811, 488, 221, 53, 3)
HAZ       <- wc_retirement_hazard(RETIREMENT_SOURCE, band_labels = BAND_LABELS,
                                  band_of = eng$wc_band_of,
                                  legacy_band_ev = LEGACY_BAND_EV,
                                  legacy_band_py = LEGACY_BAND_PY)
BAND_EV   <- unname(HAZ$band_ev)
BAND_PY   <- unname(HAZ$band_py)
HZ_POINT  <- HAZ$hz_point
message("[build] retirement_source: ", RETIREMENT_SOURCE,
        " (", HAZ$provenance$hazard_artifact, ")")

## ---- Monte Carlo 95% interval (same scheme as urps_scenario_analysis_v3.R) ---
# Uncertainty from two sources: band hazards ~ Beta(ev + 0.5, py - ev + 0.5) (an
# empty band takes the max drawn hazard), and entrants bootstrapped from GRAD_URPS
# then scaled by the scenario's entrant_multiplier. The recurrence is the REAL
# wc_project_trajectory(); we take per-year 2.5% / 97.5% quantiles over the draws.
SEED  <- 20260718L
DRAWS <- 2000L
mc_bounds <- function(entrant_multiplier, age_shift) {
  m <- matrix(NA_real_, DRAWS, HORIZON)
  for (i in seq_len(DRAWS)) {
    hz <- stats::rbeta(length(BAND_EV), BAND_EV + 0.5, pmax(BAND_PY - BAND_EV, 0) + 0.5)
    hz[BAND_PY == 0] <- max(hz[BAND_PY > 0]); hz <- setNames(pmin(1, hz), BAND_LABELS)
    ent <- entrant_multiplier * mean(sample(GRAD_URPS, length(GRAD_URPS), replace = TRUE))
    m[i, ] <- eng$wc_project_trajectory(ages, ent, hz, horizon = HORIZON, age_shift = age_shift)$active
  }
  data.frame(lower_95 = apply(m, 2, stats::quantile, probs = 0.025, names = FALSE),
             upper_95 = apply(m, 2, stats::quantile, probs = 0.975, names = FALSE))
}

## ---- clinical-FTE layer (mufflyaccess FTE model, age x pathway) -------------
# supply_clinical_fte is the raw age x pathway capacity index: each head weighted
# by urps_fte_weight(age, pathway, late lever) = rel_to_peak(age) * clinical_time
# (ABOG 1.0 / ABU 0.70) * late-career factor. All three factors are <= 1, so with
# scale = 1 the FTE is bounded above by the headcount (the contract invariant).
# Not anchored, so FTE(2023) < headcount reflects the current age/pathway mix.
# Per-pathway aging: each pathway is projected separately (same hazards; entrants
# split by the 2023 pathway share) and recombined, so the ABU 0.70 differential is
# carried through the age structure rather than folded into a blended constant.
fte_series <- function(entrant_multiplier, age_shift, late_from_age, late_factor) {
  ent_pw <- ENTRANTS * entrant_multiplier * PW_SHARE          # entrants per pathway
  ag <- Map(function(a, e) eng$wc_project_ages(a, e, HZ_POINT, horizon = HORIZON, age_shift = age_shift),
            ages_pw, ent_pw[names(ages_pw)])
  # combine the pathways per step into one (age, pathway, n) frame, weight it
  per_step <- function(h) {
    counts <- do.call(rbind, lapply(names(ag), function(pw) {
      d <- ag[[pw]]; d <- d[d$step == h, ]
      data.frame(age = d$age, pathway = pw, n = d$n, stringsAsFactors = FALSE)
    }))
    mufflyaccess::urps_effective_fte(counts, scale = 1,
                                     late_from_age = late_from_age, late_factor = late_factor)
  }
  vapply(seq_len(HORIZON), per_step, numeric(1))
}

## ---- demand + gap (mufflyaccess demand model; NA until it calibrates) --------
# urps_demand_fte() is a PRE-CALIBRATION skeleton: it returns NA_real_ for every
# scenario until urps_demand_params() carries fitted coefficients, and cliff is
# meant to call it unconditionally (the NA propagates to gap_fte; the contract
# allows NA in optional columns). So demand_clinical_fte / gap_fte are wired now
# and light up with zero code change once the equations are fit. Guard against a
# silent placeholder: the day the model calibrates, this producer must be given a
# projected age x sex demand population (and visits_per_fte) rather than the stub.
# Activate mufflyaccess's free LITERATURE_PROXY demand model (provisional; derived
# from the Wu-2014 PFD prevalence age gradient + documented ambulatory priors) so
# demand_clinical_fte / gap_fte FILL IN instead of NA. When the real MEPS/NAMCS
# fit lands, point this option at the fitted CSV (or drop it) -- no other change.
.demand_proxy <- system.file("extdata", "urps_demand_params_literature_proxy.csv",
                             package = "mufflyaccess")
if (nzchar(.demand_proxy))
  options(mufflyaccess.urps_demand_params_path = .demand_proxy)
DEMAND_MODE <- unique(mufflyaccess::urps_demand_params()$calibration_status)
message("[build] demand model: ", DEMAND_MODE,
        if (DEMAND_MODE == "not_calibrated") " (demand_clinical_fte / gap_fte will be NA)" else
          " (demand_clinical_fte / gap_fte populated)")

# Reference demand denominator: CONUS adult-female population by 5-year age band
# (ACS 2016-2020 5-yr scale; an ILLUSTRATIVE reference for the proxy, not a precise
# extract -- the proxy LEVEL is provisional). Design-matrix columns match the
# demand model: age (band midpoint), sex_male, bmi (documented mean), ins_medicare
# (age >= 65), n. Held CONSTANT across projection years (population aging is a
# future refinement; the demand scenario levers still move demand between scenarios).
.band_mid <- c(42, 47, 52, 57, 62, 67, 72, 77, 82, 88)
.band_n   <- c(10.2, 10.0, 10.3, 10.9, 10.6, 9.3, 7.5, 5.0, 3.3, 3.7) * 1e6
DEMAND_POP <- data.frame(age = .band_mid, sex_male = 0L, bmi = 29,
                         ins_medicare = as.integer(.band_mid >= 65),
                         n = round(.band_n))
VISITS_PER_FTE <- 3000   # annual URPS ambulatory visits per clinical FTE (documented assumption)

## ---- run each scenario through the real trajectory --------------------------
# Every registered scenario: the supply / FTE levers drive the projection; the
# demand levers resolve into demand_clinical_fte (NA until calibration). MC bounds
# depend only on the supply levers, so they are memoized by (entrant_multiplier,
# retirement_shift_years) -- the demand scenarios reuse baseline's draws.
sc   <- mufflyaccess::urps_scenarios()
exec <- sc$scenario_id
.mc_cache <- new.env(parent = emptyenv())
mc_cached <- function(entrant_multiplier, age_shift) {
  key <- paste(entrant_multiplier, age_shift, sep = "|")
  if (is.null(.mc_cache[[key]])) .mc_cache[[key]] <- mc_bounds(entrant_multiplier, age_shift)
  .mc_cache[[key]]
}

series_for <- function(id) {
  lv       <- mufflyaccess::urps_scenario(id)
  ent      <- ENTRANTS * lv$entrant_multiplier              # entrant_multiplier lever
  shift    <- as.integer(lv$retirement_shift_years)         # retirement_shift_years lever
  late_from <- if (!is.na(lv$late_career_fte_onset_age)) as.integer(lv$late_career_fte_onset_age) else NULL
  late_fac  <- lv$late_career_fte_factor                    # late-career FTE lever
  tr       <- eng$wc_project_trajectory(ages, ent, HZ_POINT, horizon = HORIZON, age_shift = shift)
  bnd      <- mc_cached(lv$entrant_multiplier, shift)       # per-year 95% interval on supply
  fte_fwd  <- fte_series(lv$entrant_multiplier, shift, late_from, late_fac)
  fte_idx  <- mufflyaccess::urps_effective_fte(REF_COUNTS, scale = 1,
                                               late_from_age = late_from, late_factor = late_fac)
  dem      <- mufflyaccess::urps_demand_fte(DEMAND_POP, VISITS_PER_FTE, scenario_id = id)  # NA (skeleton)
  idx <- data.frame(year = INDEX_YEAR, supply_headcount = length(ages), supply_clinical_fte = fte_idx,
                    lower_95 = NA_real_, upper_95 = NA_real_,
                    entrants = NA_real_, exits = NA_real_, net_change = NA_real_)  # index year: no flow
  fwd <- data.frame(year = INDEX_YEAR + tr$step, supply_headcount = tr$active, supply_clinical_fte = fte_fwd,
                    lower_95 = bnd$lower_95, upper_95 = bnd$upper_95,
                    entrants = tr$entrants, exits = tr$departures,
                    net_change = tr$entrants - tr$departures)
  out <- rbind(idx, fwd)
  data.frame(
    year = as.integer(out$year), scenario_id = id, specialty = SPECIALTY,
    certification_pathway = PATHWAY, geography_type = GEOG_TYPE, geography_id = GEOG_ID,
    supply_headcount = out$supply_headcount, supply_clinical_fte = out$supply_clinical_fte,
    lower_95 = out$lower_95, upper_95 = out$upper_95,
    entrants = out$entrants, exits = out$exits, net_change = out$net_change,
    demand_clinical_fte = dem,                                             # NA until calibrated
    gap_fte = vapply(out$supply_clinical_fte,                              # per-row (urps_gap_fte is scalar)
                     function(s) mufflyaccess::urps_gap_fte(s, dem), numeric(1)),
    stringsAsFactors = FALSE)
}

set.seed(SEED)                                              # reproducible MC across runs
tbl <- do.call(rbind, lapply(exec, series_for))
tbl <- tbl[order(match(tbl$scenario_id, exec), tbl$year), ]
rownames(tbl) <- NULL

## ---- validate against the contract (incl. tie back to the served count) -----
mufflyaccess::validate_urps_projection(tbl, baseline_tie = list(
  year = INDEX_YEAR, measure = "board_certified_active",
  geography_type = GEOG_TYPE, certification_pathway = PATHWAY))

out_dir <- file.path(ROOT, "scripts", "urps_projection")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
out_csv <- file.path(out_dir, "urps_projection_2023_2040_v1.csv")
utils::write.csv(tbl, out_csv, row.names = FALSE, na = "")

## ---- provenance sidecar (req 7): what retirement process produced this run ---
# Recorded next to the artifact, NOT as contract columns (the projection contract
# has a fixed schema). Every projection carries at least: retirement_source, the
# hazard artifact / version / hash, ascertainment status, confirmation window, and
# the uncertainty method -- so an "observed_hazard" run can never be mistaken for a
# frozen-model run, and vice versa.
prov <- c(HAZ$provenance, list(
  seed = SEED, mc_draws = DRAWS, horizon = HORIZON,
  index_year = INDEX_YEAR, end_year = END_YEAR,
  entrants_mean = ENTRANTS, engine = "R/workforce_cliff_engine.R::wc_project_trajectory",
  artifact = basename(out_csv)))
prov_json <- file.path(out_dir, "urps_projection_2023_2040_v1.provenance.json")
if (requireNamespace("jsonlite", quietly = TRUE)) {
  jsonlite::write_json(prov, prov_json, auto_unbox = TRUE, pretty = TRUE,
                       null = "null", na = "null")
} else {
  writeLines(vapply(names(prov), function(k) paste0(k, ": ", paste(prov[[k]], collapse = ", ")),
                    character(1)), prov_json)
}
cat(sprintf("[build] wrote %d rows (%d scenarios x %d years) -> %s; contract validated.\n",
            nrow(tbl), length(exec), HORIZON + 1L, out_csv))
cat(sprintf("[build] retirement_source=%s; provenance -> %s\n",
            RETIREMENT_SOURCE, basename(prov_json)))
invisible(tbl)
