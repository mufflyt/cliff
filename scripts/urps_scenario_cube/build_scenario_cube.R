#!/usr/bin/env Rscript
# ==============================================================================
# build_scenario_cube.R -- PROTOTYPE NurseCast-style URPS workforce scenario cube.
#
# One precomputed table (data/workforce_scenario_cube.csv):
#   pathway x geography x scenario x year -> (supply_headcount, supply_clinical_fte,
#   95% band, entrants, exits, net_change), 2023-2040. The Shiny apps read a slice
#   rather than re-running the projection (the NurseCast precompute-then-serve pattern).
#
#   pathway    : ABOG, ABU, combined (combined = ABOG + ABU, kept additive)
#   geography  : national (US), conus (CONUS)
#   scenario   : the nine mufflyaccess registry scenarios (urps_scenarios() v1.0.0):
#                baseline, retire_2yr_earlier, retire_5yr_earlier, retire_2yr_later,
#                fellowship_plus_10pct, fellowship_constrained, lower_late_career_fte,
#                combined_pessimistic, combined_investment
#   -> 3 x 2 x 4 x 18 = 432 rows.
#
# Reuses cliff's ACTUAL machinery, nothing reinvented:
#   * engine   : wc_project's recurrence via wc_haz_for (wc_engine_loader.R, pure defs)
#   * hazards  : published pooled GO+URPS age-band hazards (events/PY 2016-2021)
#   * cohorts  : 2023 board-certified active age structure per (pathway, geography)
#                from the isochrones v3.0.0 provider snapshot; reconciles to the SSOT
#                cells (ABOG 1027/1026, ABU 279/277, combined 1306/1303)
#   * clinical : age-productivity curve from shiny_urps_adequacy, with the pathway
#                clinical-time factor (ABOG 1.0, ABU 0.70). Both are shares in
#                [0, 1], so clinical FTE never exceeds headcount in any cell and
#                stays additive across pathway/geography rows.
#
# Scenarios (prototype definitions):
#   baseline                   : observed age-band exit; standard FTE
#   earlier_exit_2yr           : exit shifted 2 y earlier (face the hazard of age+2)
#   lower_late_career_fte      : clinical FTE reduced 15% from age 60 (headcount same)
#   fellowship_expansion_10pct : entrants +10%
#
# PROTOTYPE, not a published estimand. FTE is a capacity index in units of
# peak-age full-clinical-time providers (per head: rel_to_peak x clinical-time
# share, so at most 1.0), NOT absolute hours. Entrants are
# split by pathway using the national active-stock share (ABOG ~50, ABU ~14 per yr)
# and applied identically to conus (the 3 non-conus providers are negligible). No
# demand saturation -> do NOT read the 2040 level as a forecast. See README.md.
# ==============================================================================
suppressPackageStartupMessages({ library(here) })
root <- here::here(); sdir <- file.path(root, "scripts", "urps_scenario_cube")
source(file.path(root, "scripts", "urps_baseline_scenarios", "wc_engine_loader.R"))
eng <- load_real_wc_engine(file.path(root, "R", "workforce_cliff_engine.R"))
wc_haz_for <- eng$wc_haz_for; WC_BAND_LABELS <- eng$WC_BAND_LABELS

ages <- utils::read.csv(file.path(sdir, "urps_cohort_ages_pathway_geo_v3.0.0.csv"))
APC  <- utils::read.csv(file.path(root, "shiny_urps_adequacy", "data",
                                  "urps_module_a_age_productivity_2026-07-23.csv"))
wfun <- function(a) { a <- pmin(pmax(a, min(APC$age)), max(APC$age)); APC$rel_to_peak[match(a, APC$age)] }

# ---- parameters --------------------------------------------------------------
INDEX_YEAR <- 2023L; END_YEAR <- 2040L; HORIZON <- END_YEAR - INDEX_YEAR
ENTRANTS_TOTAL <- 64L; ENTRY_AGE <- 34L; MC_SEED <- 20260718L; MC_DRAWS <- 2000L
LATE_ONSET <- 60L                                          # mufflyaccess registry: late_career_fte_onset_age
CT <- c(ABOG = 1.0, ABU = 0.70)                            # pathway clinical-time share
BAND_EV <- c(13.058, 2.853, 3.508, 4.002, 5.192, 4.388, 0)
BAND_PY <- c(3854, 973, 811, 488, 221, 53, 3)
HZ <- setNames(ifelse(BAND_PY > 0, BAND_EV / BAND_PY, 0), WC_BAND_LABELS)

cohort <- function(p, g) { s <- ages[ages$pathway == p & ages$geography == g, ]
                           list(av = s$age, n = as.numeric(s$n_active_2023)) }
N_NAT  <- sum(ages$n_active_2023[ages$geography == "national"])         # 1,306
shr    <- function(p) sum(ages$n_active_2023[ages$pathway == p & ages$geography == "national"]) / N_NAT
ENTR   <- c(ABOG = round(ENTRANTS_TOTAL * shr("ABOG")), ABU = round(ENTRANTS_TOTAL * shr("ABU")))

# Clinical FTE is measured against a peak-age, full-clinical-time provider: both
# wfun() (rel_to_peak) and CT are shares in [0, 1], so per-head FTE <= 1 and hence
# supply_clinical_fte <= supply_headcount holds by construction, for every
# pathway/geography/year cell. That is the invariant mufflyaccess enforces in
# validate_urps_projection ("a head is at most 1.0 clinical FTE").
#
# There used to be a global SCALE here that forced combined-national-2023 FTE to
# equal that cell's headcount (1,306). It could not be satisfied: CT is 0.70 for
# ABU, so pinning the COMBINED mean to 1.0 FTE/head forces the ABOG component
# above 1.0 to absorb the residual. It did -- ABOG ran at 1.068 FTE/head and 59
# of 972 rows violated the invariant, with the whole series inflated by ~7%.
# Normalising to a contradictory target is dropped rather than retuned.
fte_of <- function(av, n, p, late_factor) sum(n * wfun(av) * CT[[p]] * ifelse(av >= LATE_ONSET, late_factor, 1))

# deterministic per-year age structure + flows
project_years <- function(coh, entrants, haz_shift = 0L) {
  av <- coh$av; n <- coh$n; out <- vector("list", HORIZON + 1L)
  out[[1]] <- list(av = av, n = n, exits = 0, entr = 0)
  for (h in seq_len(HORIZON)) {
    hz <- wc_haz_for(av + haz_shift, HZ); ex <- sum(n * hz); sv <- n * (1 - hz); av2 <- av + 1L
    ix <- match(ENTRY_AGE, av2)
    if (is.na(ix)) { av2 <- c(av2, ENTRY_AGE); sv <- c(sv, entrants) } else sv[ix] <- sv[ix] + entrants
    av <- av2; n <- sv; out[[h + 1L]] <- list(av = av, n = n, exits = ex, entr = entrants)
  }
  out
}
# Monte Carlo headcount matrix (Binomial draws, fixed seed)
mc_hc <- function(coh, entrants, haz_shift = 0L) {
  av0 <- coh$av; n0 <- as.integer(round(coh$n)); set.seed(MC_SEED); m <- matrix(NA_real_, MC_DRAWS, HORIZON + 1L)
  for (d in seq_len(MC_DRAWS)) {
    av <- av0; n <- n0; m[d, 1] <- sum(n)
    for (h in seq_len(HORIZON)) {
      hz <- wc_haz_for(av + haz_shift, HZ); ret <- stats::rbinom(length(n), n, hz)
      sv <- n - ret; av2 <- av + 1L; ix <- match(ENTRY_AGE, av2)
      if (is.na(ix)) { av2 <- c(av2, ENTRY_AGE); sv <- c(sv, entrants) } else sv[ix] <- sv[ix] + entrants
      av <- av2; n <- sv; m[d, h + 1L] <- sum(n)
    }
  }
  m
}

# The nine scenarios of the mufflyaccess registry (urps_scenarios(), v1.0.0).
# Lever mapping: haz_shift = -retirement_shift_years (registry sign is -=earlier);
# em = entrant_multiplier; late_factor = late_career_fte_factor (onset LATE_ONSET).
# Composites (combined_*) are just their combined lever values. THIS MUST MATCH
# mufflyaccess::urps_scenarios(); the mufflyaccess cube validator cross-checks that
# every served scenario_id is registered.
SCEN <- list(
  baseline               = list(haz_shift =  0L, em = 1.00, late_factor = 1.00),
  retire_2yr_earlier     = list(haz_shift =  2L, em = 1.00, late_factor = 1.00),
  retire_5yr_earlier     = list(haz_shift =  5L, em = 1.00, late_factor = 1.00),
  retire_2yr_later       = list(haz_shift = -2L, em = 1.00, late_factor = 1.00),
  fellowship_plus_10pct  = list(haz_shift =  0L, em = 1.10, late_factor = 1.00),
  fellowship_constrained = list(haz_shift =  0L, em = 0.90, late_factor = 1.00),
  lower_late_career_fte  = list(haz_shift =  0L, em = 1.00, late_factor = 0.75),
  combined_pessimistic   = list(haz_shift =  2L, em = 0.90, late_factor = 0.75),
  combined_investment    = list(haz_shift = -2L, em = 1.10, late_factor = 1.00))

yrs <- INDEX_YEAR + 0:HORIZON
# conform to mufflyaccess urps_projection_schema() (0.10.0): specialty column +
# count-contract certification_pathway vocabulary + net_change = entrants - exits.
SPECIALTY <- "URPS"
PMAP <- c(ABOG = "ABOG", ABU = "ABU_NET_NEW", combined = "ABOG_PLUS_ABU")
# flow triplet: NA at the index year (no flow yet); net_change == entrants - exits
# EXACTLY as displayed (rounded), satisfying the projection-contract flow identity.
mk_flow <- function(en, ex) {
  en_r <- round(en); ex_r <- round(ex, 1); nc <- en_r - ex_r
  en_r[1] <- NA; ex_r[1] <- NA; nc[1] <- NA
  list(entrants = en_r, exits = ex_r, net_change = nc)
}
frame <- function(s, p, g, hc, ft, lo, hi, en, ex) {
  fl <- mk_flow(en, ex)
  data.frame(year = yrs, scenario_id = s, specialty = SPECIALTY,
             certification_pathway = unname(PMAP[[p]]), geography_type = g,
             geography_id = if (g == "national") "US" else "CONUS",
             supply_headcount = round(hc), supply_clinical_fte = round(ft, 1),
             lower_95 = round(lo), upper_95 = round(hi),
             entrants = fl$entrants, exits = fl$exits, net_change = fl$net_change,
             stringsAsFactors = FALSE)
}
mk_row <- function(s, p, g, det_p, mc_p, late_factor) {
  hc <- vapply(det_p, function(y) sum(y$n), numeric(1))
  ft <- vapply(det_p, function(y) fte_of(y$av, y$n, p, late_factor), numeric(1))
  ex <- vapply(det_p, function(y) y$exits, numeric(1)); en <- vapply(det_p, function(y) y$entr, numeric(1))
  frame(s, p, g, hc, ft, apply(mc_p, 2, stats::quantile, .025), apply(mc_p, 2, stats::quantile, .975), en, ex)
}

rows <- list()
for (s in names(SCEN)) { cfg <- SCEN[[s]]
  for (g in c("national", "conus")) {
    det <- mc <- list()
    for (p in c("ABOG", "ABU")) {
      e <- round(ENTR[[p]] * cfg$em)
      det[[p]] <- project_years(cohort(p, g), e, cfg$haz_shift)
      mc[[p]]  <- mc_hc(cohort(p, g), e, cfg$haz_shift)
    }
    rows[[length(rows) + 1L]] <- mk_row(s, "ABOG", g, det[["ABOG"]], mc[["ABOG"]], cfg$late_factor)
    rows[[length(rows) + 1L]] <- mk_row(s, "ABU",  g, det[["ABU"]],  mc[["ABU"]],  cfg$late_factor)
    # combined = ABOG + ABU (additive headcount, FTE, flows; CI from summed draws)
    ix <- seq_len(HORIZON + 1L)
    comb_det <- lapply(ix, function(i) list(
      n = c(det[["ABOG"]][[i]]$n, det[["ABU"]][[i]]$n),  # placeholder; hc/fte computed below
      exits = det[["ABOG"]][[i]]$exits + det[["ABU"]][[i]]$exits,
      entr  = det[["ABOG"]][[i]]$entr  + det[["ABU"]][[i]]$entr))
    hc <- vapply(ix, function(i) sum(det[["ABOG"]][[i]]$n) + sum(det[["ABU"]][[i]]$n), numeric(1))
    ft <- vapply(ix, function(i) fte_of(det[["ABOG"]][[i]]$av, det[["ABOG"]][[i]]$n, "ABOG", cfg$late_factor) +
                                 fte_of(det[["ABU"]][[i]]$av,  det[["ABU"]][[i]]$n,  "ABU",  cfg$late_factor), numeric(1))
    ex <- vapply(comb_det, function(y) y$exits, numeric(1)); en <- vapply(comb_det, function(y) y$entr, numeric(1))
    cmc <- mc[["ABOG"]] + mc[["ABU"]]
    rows[[length(rows) + 1L]] <- frame(s, "combined", g, hc, ft,
      apply(cmc, 2, stats::quantile, .025), apply(cmc, 2, stats::quantile, .975), en, ex)
  }
}
cube <- do.call(rbind, rows)
utils::write.csv(cube, file.path(root, "data", "workforce_scenario_cube.csv"), row.names = FALSE)
cat(sprintf("wrote data/workforce_scenario_cube.csv: %d rows (3 pathways x 2 geographies x %d scenarios x %d years)\n",
            nrow(cube), length(SCEN), HORIZON + 1L))
cat("\n== 2023 & 2040 baseline headcount / FTE by certification_pathway x geography ==\n")
print(cube[cube$scenario_id == "baseline" & cube$year %in% c(2023, 2040),
           c("year","certification_pathway","geography_type","supply_headcount","supply_clinical_fte")], row.names = FALSE)
