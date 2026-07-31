#!/usr/bin/env Rscript
# ==============================================================================
# build_scenario_cube.R -- PROTOTYPE NurseCast-style URPS workforce scenario cube.
#
# A single precomputed table: year x scenario x (supply_headcount, supply_clinical_fte)
# for 2023-2040, four named scenarios, national both-pathway. The Shiny apps read
# this frozen table rather than re-running the projection interactively (the
# NurseCast "precompute all supported combinations, serve a slice" pattern).
#
# Reuses cliff's ACTUAL machinery, nothing reinvented:
#   * engine   : wc_project's recurrence via wc_haz_for/wc_band constants
#                (scripts/urps_baseline_scenarios/wc_engine_loader.R -> pure defs)
#   * hazards  : the published pooled GO+URPS age-band hazards (events/PY 2016-2021)
#   * cohort   : the 2023 board-certified active age structure (n=1,306, both pathways)
#   * clinical : the age-productivity curve from shiny_urps_adequacy
#                (age_productivity_2026-07-23.csv), normalized so effective(2023) ==
#                headcount(2023). The pathway clinical-time blend is a constant and
#                cancels in that normalization, so only the age curve is needed here.
#
# Scenarios (prototype definitions; the FIRST slice recommended for the cube):
#   baseline                   : observed age-band exit; standard age-productivity FTE
#   earlier_exit_2yr           : exit shifted 2 y earlier (face the hazard of age+2)
#   lower_late_career_fte      : clinical FTE reduced 15% from age 60 (headcount same)
#   fellowship_expansion_10pct : entrants +10% (64 -> 70/yr)
#
# NOT a published estimand: this is a prototype to demonstrate the cube schema and
# the precompute-then-read pattern. FTE is a normalized capacity index (effective
# providers, 2023 = headcount), NOT absolute hours; geography is national only and
# pathway is the combined both-pathway cohort (per-geography / per-pathway splits
# are the documented next slice). See scripts/urps_scenario_cube/README.md.
# ==============================================================================
suppressPackageStartupMessages({ library(here) })
root <- here::here(); sdir <- file.path(root, "scripts", "urps_scenario_cube")
source(file.path(root, "scripts", "urps_baseline_scenarios", "wc_engine_loader.R"))
eng <- load_real_wc_engine(file.path(root, "R", "workforce_cliff_engine.R"))
wc_haz_for <- eng$wc_haz_for; WC_BAND_LABELS <- eng$WC_BAND_LABELS

# ---- inputs ------------------------------------------------------------------
ages_tbl <- utils::read.csv(file.path(root, "scripts", "urps_baseline_scenarios",
                                      "urps_cohort_ages_v3.0.0.csv"))
ages0 <- rep(ages_tbl$age, ages_tbl$n_active_2023)          # 2023 active cohort (1,306)
av0 <- as.integer(names(table(ages0))); n0 <- as.numeric(table(ages0)); N0 <- length(ages0)
APC <- utils::read.csv(file.path(root, "shiny_urps_adequacy", "data",
                                 "urps_module_a_age_productivity_2026-07-23.csv"))
wfun <- function(a) { a <- pmin(pmax(a, min(APC$age)), max(APC$age)); APC$rel_to_peak[match(a, APC$age)] }

# ---- parameters --------------------------------------------------------------
INDEX_YEAR <- 2023L; END_YEAR <- 2040L; HORIZON <- END_YEAR - INDEX_YEAR
ENTRANTS <- 64L; ENTRY_AGE <- 34L; MC_SEED <- 20260718L; MC_DRAWS <- 2000L
LATE_FTE_FACTOR <- 0.85                                     # prototype: 15% FTE cut from age 60
BAND_EV <- c(13.058, 2.853, 3.508, 4.002, 5.192, 4.388, 0)
BAND_PY <- c(3854, 973, 811, 488, 221, 53, 3)
HZ <- setNames(ifelse(BAND_PY > 0, BAND_EV / BAND_PY, 0), WC_BAND_LABELS)

# clinical-FTE weights (age-productivity), normalized so effective(2023)==headcount(2023)
w_base <- function(av) wfun(av)
w_late <- function(av) wfun(av) * ifelse(av >= 60, LATE_FTE_FACTOR, 1)
DENOM  <- sum(n0 * w_base(av0))
fte_of <- function(av, n, wf) N0 * sum(n * wf(av)) / DENOM

# ---- deterministic projection: per-year age structure + flows ----------------
project_years <- function(entrants, hz, haz_shift = 0L) {
  av <- av0; n <- n0; out <- vector("list", HORIZON + 1L)
  out[[1]] <- list(av = av, n = n, exits = 0, entr = 0)
  for (h in seq_len(HORIZON)) {
    hz_age <- wc_haz_for(av + haz_shift, hz)
    exits <- sum(n * hz_age); sv <- n * (1 - hz_age); av2 <- av + 1L
    ix <- match(ENTRY_AGE, av2)
    if (is.na(ix)) { av2 <- c(av2, ENTRY_AGE); sv <- c(sv, entrants) } else sv[ix] <- sv[ix] + entrants
    av <- av2; n <- sv
    out[[h + 1L]] <- list(av = av, n = n, exits = exits, entr = entrants)
  }
  out
}

# ---- Monte Carlo headcount 95% band (Binomial draws, fixed seed) -------------
mc_band <- function(entrants, hz, haz_shift = 0L) {
  n0i <- as.integer(n0); set.seed(MC_SEED)
  hc <- matrix(NA_real_, MC_DRAWS, HORIZON + 1L)
  for (d in seq_len(MC_DRAWS)) {
    av <- av0; n <- n0i; hc[d, 1] <- sum(n)
    for (h in seq_len(HORIZON)) {
      hz_age <- wc_haz_for(av + haz_shift, hz); ret <- stats::rbinom(length(n), n, hz_age)
      sv <- n - ret; av2 <- av + 1L; ix <- match(ENTRY_AGE, av2)
      if (is.na(ix)) { av2 <- c(av2, ENTRY_AGE); sv <- c(sv, entrants) } else sv[ix] <- sv[ix] + entrants
      av <- av2; n <- sv; hc[d, h + 1L] <- sum(n)
    }
  }
  list(lo = apply(hc, 2, stats::quantile, .025), hi = apply(hc, 2, stats::quantile, .975))
}

# ---- scenario definitions ----------------------------------------------------
SCEN <- list(
  baseline                   = list(entrants = ENTRANTS,           haz_shift = 0L, wf = w_base),
  earlier_exit_2yr           = list(entrants = ENTRANTS,           haz_shift = 2L, wf = w_base),
  lower_late_career_fte      = list(entrants = ENTRANTS,           haz_shift = 0L, wf = w_late),
  fellowship_expansion_10pct = list(entrants = round(ENTRANTS*1.1),haz_shift = 0L, wf = w_base))

rows <- do.call(rbind, lapply(names(SCEN), function(s) {
  cfg <- SCEN[[s]]; yr <- project_years(cfg$entrants, HZ, cfg$haz_shift); band <- mc_band(cfg$entrants, HZ, cfg$haz_shift)
  hc <- vapply(yr, function(y) sum(y$n), numeric(1))
  ft <- vapply(yr, function(y) fte_of(y$av, y$n, cfg$wf), numeric(1))
  ex <- vapply(yr, function(y) y$exits, numeric(1)); en <- vapply(yr, function(y) y$entr, numeric(1))
  data.frame(
    year = INDEX_YEAR + 0:HORIZON, scenario_id = s, pathway = "combined",
    geography_type = "national", geography_id = "US",
    supply_headcount = round(hc), supply_clinical_fte = round(ft, 1),
    lower_95 = round(band$lo), upper_95 = round(band$hi),
    entrants = round(en), exits = round(ex, 1),
    net_change = round(c(NA, diff(hc))), stringsAsFactors = FALSE)
}))

dir.create(sdir, showWarnings = FALSE, recursive = TRUE)
utils::write.csv(rows, file.path(root, "data", "workforce_scenario_cube.csv"), row.names = FALSE)
cat(sprintf("wrote data/workforce_scenario_cube.csv: %d rows, %d scenarios x %d years\n",
            nrow(rows), length(SCEN), HORIZON + 1L))
cat("\n== 2023 and 2040 headcount / FTE by scenario ==\n")
print(rows[rows$year %in% c(2023, 2040), c("year","scenario_id","supply_headcount","supply_clinical_fte","lower_95","upper_95")], row.names = FALSE)
