#!/usr/bin/env Rscript
# ==============================================================================
# Regenerate the URPS manuscript projection at the canonical v3.0.0 baseline (1306),
# using the manuscript's OWN parameter-uncertainty Monte Carlo (Beta posteriors on
# the age-band hazards + bootstrap of the 4 graduate counts), fed through the REAL
# engine wc_project(). This is cliff#1 "adopt 1306": it recomputes the URPS row of
# the frozen projection table on the 2023 board-certified active cohort.
#
# CALIBRATION: the same method is run on the legacy cohort so we can confirm the
# interval WIDTH matches the manuscript's parameter-uncertainty method (sd ~15),
# not the narrower Binomial-process draw (sd ~7). Only then is the 1306 CI trusted.
# ==============================================================================
suppressPackageStartupMessages({ library(here) })
root <- here::here(); sdir <- file.path(root, "scripts", "urps_scenario_cube")
source(file.path(root, "scripts", "urps_baseline_scenarios", "wc_engine_loader.R"))
eng <- load_real_wc_engine(file.path(root, "R", "workforce_cliff_engine.R"))
wc_project <- eng$wc_project; wc_haz_for <- eng$wc_haz_for; WC_BAND_LABELS <- eng$WC_BAND_LABELS
source(file.path(root, "R", "workforce_uncertainty.R"))   # median + PI + decision probabilities

# cohort age vectors (combined national) from the pathway/geo extract
ages <- utils::read.csv(file.path(sdir, "urps_cohort_ages_pathway_geo_v3.0.0.csv"))
ages_1306 <- with(ages[ages$geography == "national", ], rep(age, n_active_2023))   # 1306
leg <- utils::read.csv(file.path(root, "scripts", "urps_baseline_scenarios",
                                 "urps_cohort_ages_v3.0.0.csv"))
ages_legacy <- rep(leg$age, leg$n_legacy_primarycert)                              # 1301 (calibration)

# manuscript model constants (fully-observable window; same as the frozen model)
BAND_EV <- c(13.058, 2.853, 3.508, 4.002, 5.192, 4.388, 0)
BAND_PY <- c(3854, 973, 811, 488, 221, 53, 3)
GRAD_URPS <- c(61, 66, 63, 66)                    # ACGME URPS completions AY2020-24 (mean 64)
HORIZON <- 4L; ENTRY_AGE <- 34L; MC_SEED <- 20260718L; MC_DRAWS <- 10000L
HZ_POINT <- setNames(ifelse(BAND_PY > 0, BAND_EV / BAND_PY, 0), WC_BAND_LABELS)

# deterministic point estimate (real engine)
det <- function(ages) {
  r <- wc_project(ages, entrants = mean(GRAD_URPS), hz = HZ_POINT, horizon = HORIZON)
  list(baseline = length(ages), projected = r$active_2029,
       avg_dep = r$departures_4yr / HORIZON, ratio = mean(GRAD_URPS) / (r$departures_4yr / HORIZON))
}
# manuscript parameter-uncertainty MC: Beta on band hazards + bootstrap on grads
mc <- function(ages) {
  set.seed(MC_SEED)
  fin <- numeric(MC_DRAWS); rat <- numeric(MC_DRAWS)
  for (i in seq_len(MC_DRAWS)) {
    hz <- stats::rbeta(length(BAND_EV), BAND_EV + 0.5, pmax(BAND_PY - BAND_EV, 0) + 0.5)
    hz[BAND_PY == 0] <- max(hz[BAND_PY > 0]); hz <- setNames(pmin(1, hz), WC_BAND_LABELS)
    ent <- mean(sample(GRAD_URPS, length(GRAD_URPS), replace = TRUE))
    r <- wc_project(ages, entrants = ent, hz = hz, horizon = HORIZON)
    fin[i] <- r$active_2029; rat[i] <- ent / (r$departures_4yr / HORIZON)
  }
  list(final_lo = unname(stats::quantile(fin, .025)), final_hi = unname(stats::quantile(fin, .975)),
       sd = stats::sd(fin), ratio_lo = unname(stats::quantile(rat, .025)),
       ratio_hi = unname(stats::quantile(rat, .975)),
       fin = fin, rat = rat)   # retain raw draws for the uncertainty summary (item 7)
}

report <- function(tag, ages) {
  d <- det(ages); m <- mc(ages)
  cat(sprintf("%-14s baseline=%d  projected_2029=%.1f  avg_dep=%.2f  ratio=%.2f  CI=[%d,%d]  sd=%.1f  ratioCI=[%.2f,%.2f]\n",
              tag, d$baseline, d$projected, d$avg_dep, d$ratio,
              round(m$final_lo), round(m$final_hi), m$sd, m$ratio_lo, m$ratio_hi))
  c(d, m)
}
cat("== URPS projection at v3.0.0 baseline (manuscript parameter-uncertainty MC, ", MC_DRAWS, " draws) ==\n", sep = "")
cat("Frozen published (1295, archival):  projected_2029=1505.4  avg_dep=11.41  ratio=5.61  CI=[1476,1535]  sd=15.2\n\n")
leg_r  <- report("legacy_1301", ages_legacy)     # calibration: width should be ~15, not ~7
new_r  <- report("v3.0.0_1306", ages_1306)       # the adopted number

# write the regenerated URPS row (consolidated-CSV schema) for rebuild_ssot_revised.R
out <- data.frame(
  subspecialty = "Urogynecology and Reconstructive Pelvic Surgery", subspecialty_abbrev = "URPS",
  baseline_2025 = new_r$baseline, projected_2029 = round(new_r$projected, 4), sd_2029 = round(new_r$sd, 2),
  ci95_lower = round(new_r$final_lo), ci95_upper = round(new_r$final_hi),
  percent_change = round(100 * (new_r$projected - new_r$baseline) / new_r$baseline, 6),
  annual_retirement_rate = round(new_r$avg_dep / new_r$baseline, 5),
  avg_annual_retirements = round(new_r$avg_dep, 6), annual_entrants = 64L,
  replacement_ratio = round(new_r$ratio, 2), replacement_assessment = "Above replacement",
  fellowship_total_4yr = 256L, total_retirements_4yr = round(new_r$avg_dep * HORIZON),
  stringsAsFactors = FALSE)
utils::write.csv(out, file.path(sdir, "urps_row_1306_regenerated.csv"), row.names = FALSE)
cat("\nwrote scripts/urps_scenario_cube/urps_row_1306_regenerated.csv\n")

# ── Uncertainty report (item 7): communicate the distribution, not one number ──
# Decision probabilities from the SAME MC draws. shortage_pct / improve_pct are 0
# (any net decline / any growth) plus a 5% variant; adjust the X% here if the
# manuscript needs a different shortage threshold.
u0 <- wc_uncertainty_summary(new_r$fin, new_r$rat, baseline = new_r$baseline,
                             shortage_pct = 0, improve_pct = 0)
u5 <- wc_uncertainty_summary(new_r$fin, new_r$rat, baseline = new_r$baseline,
                             shortage_pct = 5, improve_pct = 5)
unc <- rbind(cbind(subspecialty_abbrev = "URPS", scenario = "any_change", u0),
             cbind(subspecialty_abbrev = "URPS", scenario = "5pct_threshold", u5))
utils::write.csv(unc, file.path(sdir, "urps_uncertainty_1306.csv"), row.names = FALSE)
cat("\n== URPS uncertainty (item 7) ==\n")
cat(wc_uncertainty_sentence(u0), "\n")
cat(sprintf("At a 5%% threshold: P(shortage worsens >=5%%) = %.1f%%, P(access improves >=5%%) = %.1f%%.\n",
            100 * u5$p_shortage_exceeds, 100 * u5$p_access_improves))
cat("wrote scripts/urps_scenario_cube/urps_uncertainty_1306.csv\n")
