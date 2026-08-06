#!/usr/bin/env Rscript
# ==============================================================================
# Generate the frozen URPS projection benchmark fixture (item 8: publish
# benchmark datasets every commit must reproduce).
#
# Freezes (a) the deterministic model INPUTS as a small version-controlled CSV
# (the national 2023 URPS age distribution) and (b) the GOLDEN deterministic
# OUTPUTS (projected 2029 workforce + 4-year departures) computed by the real
# engine wc_project() at the published parameters. tests/testthat/
# test-benchmark-reproduce.R re-runs the engine on the frozen inputs and asserts
# it still lands on the golden outputs -- so an accidental change to the engine,
# the hazards, or the graduate counts fails CI instead of silently moving a
# published number.
#
# Run ONLY to (re)freeze the benchmark after an INTENTIONAL, reviewed change:
#   Rscript benchmark/generate_urps_benchmark.R
# ==============================================================================
suppressPackageStartupMessages({ library(here) })
root <- here::here()
bdir <- file.path(root, "benchmark"); dir.create(bdir, showWarnings = FALSE)
source(file.path(root, "scripts", "urps_baseline_scenarios", "wc_engine_loader.R"))
eng <- load_real_wc_engine(file.path(root, "R", "workforce_cliff_engine.R"))
wc_project <- eng$wc_project; WC_BAND_LABELS <- eng$WC_BAND_LABELS

# --- frozen inputs (published v3.0.0 parameters) ---
BAND_EV   <- c(13.058, 2.853, 3.508, 4.002, 5.192, 4.388, 0)
BAND_PY   <- c(3854, 973, 811, 488, 221, 53, 3)
GRAD_URPS <- c(61, 66, 63, 66)                 # ACGME URPS completions AY2020-24 (mean 64)
HORIZON   <- 4L
HZ_POINT  <- setNames(ifelse(BAND_PY > 0, BAND_EV / BAND_PY, 0), WC_BAND_LABELS)

# national 2023 URPS age distribution -> frozen benchmark input CSV
src <- utils::read.csv(file.path(root, "scripts", "urps_scenario_cube",
                                 "urps_cohort_ages_pathway_geo_v3.0.0.csv"))
age_tab <- aggregate(n_active_2023 ~ age, data = src[src$geography == "national", ], FUN = sum)
age_tab <- age_tab[order(age_tab$age), ]
utils::write.csv(age_tab, file.path(bdir, "urps_cohort_ages_v3.0.0.csv"), row.names = FALSE)

# --- golden deterministic outputs ---
ages <- rep(age_tab$age, age_tab$n_active_2023)
r <- wc_project(ages, entrants = mean(GRAD_URPS), hz = HZ_POINT, horizon = HORIZON)

golden <- data.frame(
  fixture         = "urps_projection_v3.0.0_deterministic",
  baseline        = length(ages),
  entrants_annual = mean(GRAD_URPS),
  horizon         = HORIZON,
  projected_2029  = r$active_2029,
  departures_4yr  = r$departures_4yr,
  band_ev         = paste(BAND_EV, collapse = ";"),
  band_py         = paste(BAND_PY, collapse = ";"),
  grad_urps       = paste(GRAD_URPS, collapse = ";"),
  stringsAsFactors = FALSE
)
utils::write.csv(golden, file.path(bdir, "urps_projection_golden.csv"), row.names = FALSE)

cat(sprintf("froze benchmark: baseline=%d projected_2029=%.10f departures_4yr=%.10f\n",
            golden$baseline, golden$projected_2029, golden$departures_4yr))
cat("wrote benchmark/urps_cohort_ages_v3.0.0.csv and benchmark/urps_projection_golden.csv\n")
