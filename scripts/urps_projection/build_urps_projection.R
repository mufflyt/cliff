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
#   * The engine: the REAL wc_project_trajectory(), loaded verbatim from
#     R/workforce_cliff_engine.R via wc_engine_loader.R (no reimplementation).
#   * Scenario levers: mufflyaccess::urps_scenarios() (the shared dictionary).
#
# Scope (Phase 2b): 2040 horizon, index on 2023-active (1306), ABOG_PLUS_ABU only.
# supply_headcount is the deterministic point estimate; lower_95 / upper_95 are the
# Monte Carlo 95% interval (2000 draws: Beta band hazards + bootstrapped entrants,
# seed 20260718 -- the same scheme as urps_scenario_analysis_v3.R). FTE / demand
# scenarios are excluded (requires_fte_model / requires_demand_model);
# supply_clinical_fte stays NA until the FTE model wires in.
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

## ---- starting cohort ages (parquet-derived, sums to 1306) -------------------
ages_tbl <- utils::read.csv(
  file.path(ROOT, "scripts", "urps_baseline_scenarios", "urps_cohort_ages_v3.0.0.csv"),
  stringsAsFactors = FALSE)
ages <- rep(ages_tbl$age_proxy, ages_tbl$n_active_2023)      # integer age-proxy vector
ssot_active_2023 <- mufflyaccess::urps_count(INDEX_YEAR, "board_certified_active", GEOG_TYPE, TRUE)
if (length(ages) != ssot_active_2023)
  stop(sprintf("[build] seed cohort (%d) != urps_count(%d) (%d); the frozen ages table is out of sync with the SSOT.",
               length(ages), INDEX_YEAR, ssot_active_2023), call. = FALSE)

## ---- frozen retirement hazards + entrants (cliff's reviewed model) ----------
# Verbatim from urps_scenario_analysis_v3.R (HAZARD_VERSION "fully_obs
# (BAND_EV/BAND_PY, 2016-2021 primary window)"); deterministic point estimate.
GRAD_URPS <- c(61, 66, 63, 66)
ENTRANTS  <- mean(GRAD_URPS)                                 # 64
BAND_EV   <- c(13.058, 2.853, 3.508, 4.002, 5.192, 4.388, 0)
BAND_PY   <- c(3854, 973, 811, 488, 221, 53, 3)
HZ_POINT  <- setNames(ifelse(BAND_PY > 0, BAND_EV / BAND_PY, NA_real_), BAND_LABELS)

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

## ---- run each executable scenario through the real trajectory ---------------
sc   <- mufflyaccess::urps_scenarios()
exec <- sc$scenario_id[!sc$requires_fte_model & !sc$requires_demand_model]

series_for <- function(id) {
  lv    <- mufflyaccess::urps_scenario(id)
  ent   <- ENTRANTS * lv$entrant_multiplier                 # entrant_multiplier lever
  shift <- as.integer(lv$retirement_shift_years)            # retirement_shift_years lever
  tr    <- eng$wc_project_trajectory(ages, ent, HZ_POINT, horizon = HORIZON, age_shift = shift)
  bnd   <- mc_bounds(lv$entrant_multiplier, shift)          # per-year 95% interval on supply
  idx <- data.frame(year = INDEX_YEAR, supply_headcount = length(ages),
                    lower_95 = NA_real_, upper_95 = NA_real_,
                    entrants = NA_real_, exits = NA_real_, net_change = NA_real_)  # index year: no flow
  fwd <- data.frame(year = INDEX_YEAR + tr$step, supply_headcount = tr$active,
                    lower_95 = bnd$lower_95, upper_95 = bnd$upper_95,
                    entrants = tr$entrants, exits = tr$departures,
                    net_change = tr$entrants - tr$departures)
  out <- rbind(idx, fwd)
  data.frame(
    year = as.integer(out$year), scenario_id = id, specialty = SPECIALTY,
    certification_pathway = PATHWAY, geography_type = GEOG_TYPE, geography_id = GEOG_ID,
    supply_headcount = out$supply_headcount, supply_clinical_fte = NA_real_,
    lower_95 = out$lower_95, upper_95 = out$upper_95,
    entrants = out$entrants, exits = out$exits, net_change = out$net_change,
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
cat(sprintf("[build] wrote %d rows (%d scenarios x %d years) -> %s; contract validated.\n",
            nrow(tbl), length(exec), HORIZON + 1L, out_csv))
invisible(tbl)
