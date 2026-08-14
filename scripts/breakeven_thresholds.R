#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Break-even thresholds: what would push each cohort to replacement ratio = 1.0
# (the point at which graduate output no longer replaces departures).
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# For each single lever, holding the others at their primary value:
#   - departure rate at which ratio = 1: graduates / baseline (as a rate and as a
#     multiple of the empirical rate)
#   - graduate count at which ratio = 1: equals mean annual departures (and the
#     percentage drop from the current graduate count)
#   - entrant-to-incumbent clinical-effort multiplier at which ratio = 1: 1 / ratio
# Plus a compound worst-case (rate x3 AND graduates -30% AND effort 0.65).
#
# OUTPUT: cliff/data/breakeven_thresholds.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(readr); library(dplyr); library(here)})

r <- read_csv(here::here("data","workforce_projections_consolidated.csv"),
              show_col_types = FALSE)
r <- r[match(c("GO","URPS","MIGS"), r$subspecialty_abbrev), ]

out <- r %>% transmute(
  subspecialty_abbrev,
  replacement_ratio = round(replacement_ratio, 2),
  breakeven_departure_rate_pct = round(100 * annual_entrants / baseline_2025, 1),
  breakeven_rate_multiple = round((annual_entrants / baseline_2025) / (annual_retirement_rate/100), 1),
  breakeven_graduates = round(avg_annual_retirements),
  graduate_drop_pct = round(100 * (1 - avg_annual_retirements / annual_entrants)),
  breakeven_effort_multiplier = round(1 / replacement_ratio, 2),
  compound_worstcase_ratio = round((annual_entrants * 0.70 * 0.65) / (avg_annual_retirements * 3), 2))
out$compound_below_replacement <- out$compound_worstcase_ratio < 1.0
write_csv(out, here::here("data","breakeven_thresholds.csv"))

cat("=== Break-even thresholds (single lever to reach replacement ratio = 1.0) ===\n\n")
print(as.data.frame(out), row.names = FALSE)
cat("\nCompound worst-case = departure rate x3 AND graduates -30% AND entrant effort 0.65.\n")
cat("Wrote cliff/data/breakeven_thresholds.csv\n")
