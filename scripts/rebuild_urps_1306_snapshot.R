#!/usr/bin/env Rscript
# Regenerate the canonical URPS model-data snapshot on the 1,306 board-certified-
# active cohort (supersedes the retired 1,339 roster / partial-pooled 5.02 lineage).
#
# PRODUCER for shiny_urps_scenarios/urps_model_data.R. Deterministic:
#   URPS_AGES        <- ages of the 1,306 active_2023 cohort
#                       (data/urps_1306_active_cohort.csv, vendored from the
#                        isochrones urps_provider_snapshot.parquet: 1,027 ABOG +
#                        279 ABU net-new; two-method match to the SSOT baseline).
#   BAND_EV/PY fully_obs <- POOLED GO+URPS band events/person-years (71 events;
#                       data/hazard_by_band_pooled_vs_unpooled.csv), so the
#                       primary window reproduces the SSOT pooled ratio 5.38.
#   drop2/full       <- pooled GO+URPS window sensitivities (unchanged).
# After running, run scripts/sync_urps_model_data.R to update the byte-identical
# replicas (drift-guarded by tests/testthat/test-ssot-urps-model-data-sync.R).
suppressPackageStartupMessages({library(here); library(readr)})

coh <- readr::read_csv(here::here("data", "urps_1306_active_cohort.csv"),
                       show_col_types = FALSE)
stopifnot(nrow(coh) == 1306L)
ages <- sort(as.integer(coh$age))

hz <- readr::read_csv(here::here("data", "hazard_by_band_pooled_vs_unpooled.csv"),
                      show_col_types = FALSE)
band_labels <- c("<45", "45-49", "50-54", "55-59", "60-64", "65-69", "70+")
stopifnot(identical(hz$band, band_labels))
pooled_ev <- as.integer(hz$pooled_events)
pooled_py <- as.integer(hz$pooled_py)
stopifnot(sum(pooled_ev) == 71L)   # 36 GO + 35 URPS pooled departure events

vec <- function(x) paste0("c(", paste(x, collapse = ","), ")")
lines <- c(
  "# URPS model-data snapshot for the standalone Shiny apps. Values originate from",
  "# R/workforce_cliff_engine.R + the hierarchical-hazard pipeline.",
  "# CANONICAL COPY: shiny_urps_scenarios/urps_model_data.R (also sourced by the repo demand scripts).",
  "# Replicas (e.g. shiny_urps_adequacy/data/urps_model_data.R) are kept BYTE-IDENTICAL by",
  "# scripts/sync_urps_model_data.R and drift-guarded by tests/testthat/test-ssot-urps-model-data-sync.R.",
  "# Do NOT hand-edit this file: edit scripts/rebuild_urps_1306_snapshot.R, run it, then run sync.",
  paste0("URPS_AGES <- ", vec(ages)),
  "# 2026-08-02 rebuild: URPS baseline is the 1,306 board-certified-active cohort",
  "# (active_2023 == TRUE in the isochrones urps_provider_snapshot: 1,027 ABOG +",
  "# 279 ABU net-new), vendored to data/urps_1306_active_cohort.csv. Supersedes the",
  "# retired 1,339 roster snapshot. Ages = age_proxy_from_cert.",
  'BAND_LABELS <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")',
  "BANDS <- c(0, 45, 50, 55, 60, 65, 70, Inf)  # age-band breakpoints (== engine WC_BANDS; parity-guarded in test-ssot-age-bands.R); length == BAND_LABELS + 1",
  "GRAD_URPS <- c(61,66,63,66)  # OB/GYN+urology completers AY2020-24",
  "# Age-band event / person-year counts per observation window (for the Beta-posterior MC).",
  "# PRIMARY window (fully_obs) is the POOLED GO+URPS age-band hazard (manuscript",
  "# primary; 71 pooled events; reproduces the SSOT ratio 5.38 and active_2029 1,514).",
  "# drop2/full are the pooled GO+URPS window sensitivities.",
  paste0("BAND_EV <- list(fully_obs=", vec(pooled_ev),
         ", drop2=c(12,3,2,3,7,7,0), full=c(59,15,16,18,26,23,4))"),
  paste0("BAND_PY <- list(fully_obs=", vec(pooled_py),
         ", drop2=c(5175,1122,965,652,345,109,0), full=c(9833,2620,2033,1525,906,348,49))"),
  'WINDOW_LABELS <- c(fully_obs="Fully observable (2016-2021, primary)", drop2="Restricted (2016-2019)", full="Full window (2016-2023, provisional)")',
  "HAZ_WINDOWS <- setNames(Map(function(ev,py) setNames(ifelse(py>0, ev/py, NA_real_), BAND_LABELS), BAND_EV, BAND_PY), names(BAND_EV))"
)
out <- here::here("shiny_urps_scenarios", "urps_model_data.R")
writeLines(lines, out)
cat("Wrote", out, "with URPS_AGES length", length(ages),
    "and pooled fully_obs hazard (", sum(pooled_ev), "events ).\n")
