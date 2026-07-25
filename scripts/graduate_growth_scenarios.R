#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Reviewer #8: graduate-supply scenarios beyond the flat four-year mean. The four
# observed ACGME completer counts (AY2020-21..2023-24) are recast into distinct,
# transparent forward assumptions and each is passed through the SAME dynamic model
# (only the annual entrant count E changes; the pooled hazard and active baseline
# are the primary values). Scenarios:
#   flat_recent_mean   status-quo four-year mean (the manuscript primary)
#   cohort_accounting  most recent observed year (fellows already in final training,
#                      the most directly projectable near-term output)
#   contraction        the lowest of the four recent years (a downside floor)
#   cautious_trend     four-year mean + half the observed linear annual trend over
#                      the horizon midpoint, capped at the highest observed year
#                      (damped, does not extrapolate growth beyond what was seen)
#   conservative_70pct 70% graduate-to-practice conversion of the mean (reference)
#   optimistic_nrmp    NRMP certified-position benchmark (reference)
# Reuses verbatim rebuild_ssot_revised.R machinery.  OUTPUT:
#   data/graduate_growth_scenarios.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({library(readr); library(dplyr); library(here)})

source(here("R","workforce_cliff_engine.R"))    # single source of truth (constants + machinery)
SUBS <- WC_SUBS; GRAD <- WC_GRAD; ENTRANTS_NRMP <- WC_ENTRANTS_NRMP; PRIMARY <- WC_PRIMARY; HORIZON <- WC_HORIZON  # NRMP benchmark: SSOT = engine WC_ENTRANTS_NRMP
coh  <- wc_load_cohort(apply_anchor = TRUE)
ages <- wc_active_ages(coh)
bc   <- wc_band_counts(coh); HAZ <- setNames(bc$ev/bc$py, bc$band)
project <- function(a, entrants) wc_project(a, entrants, HAZ)

grad_scenarios <- function(k){
  g <- GRAD[[k]]; m <- mean(g); slope <- coef(lm(g ~ seq_along(g)))[2]
  cautious <- min(max(g), m + 0.5*slope*(HORIZON/2))
  c(flat_recent_mean=m, cohort_accounting=g[length(g)], contraction=min(g),
    cautious_trend=cautious, conservative_70pct=WORKFORCE_CONVERSION_FLOOR*m, optimistic_nrmp=ENTRANTS_NRMP[[k]])
}
SC_LABELS <- c(flat_recent_mean="Flat recent mean (status-quo)", cohort_accounting="Cohort accounting (most recent year)",
               contraction="Contraction (recent low)", cautious_trend="Cautious trend",
               conservative_70pct="Conservative (70% conversion)", optimistic_nrmp="Optimistic (NRMP benchmark)")

out <- do.call(rbind, lapply(PRIMARY, function(k){
  sc <- grad_scenarios(k)
  do.call(rbind, lapply(names(sc), function(s){
    E <- sc[[s]]; d <- project(ages[[k]], E); avg <- d$departures_4yr/HORIZON; ratio <- E/avg
    data.frame(subspecialty_abbrev=k, scenario=s, scenario_label=SC_LABELS[[s]],
               annual_graduates=round(E,1), replacement_ratio=round(ratio,2),
               projected_2029=round(length(ages[[k]]) + HORIZON*(E-avg)),
               assessment=ifelse(ratio>=1.2,"Adequate",ifelse(ratio>=0.8,"Marginal","Insufficient")),
               stringsAsFactors=FALSE)
  }))
}))
write_csv(out, here("data","graduate_growth_scenarios.csv"))
cat("\n#8 GRADUATE-GROWTH SCENARIOS:\n"); print(out[,c("subspecialty_abbrev","scenario","annual_graduates","replacement_ratio","assessment")], row.names=FALSE)
cat("\nDONE\n")
