#!/usr/bin/env Rscript
# PRODUCER for data/departure_window_sensitivity.csv (previously a producerless
# frozen artifact on the retired 1,339 / 5.61 lineage).
#
# For GO and URPS, the completion-to-departure ratio under three observation
# windows, on the CURRENT 1,306 (URPS) / 1,052 (GO) cohort:
#   fully_obs (2016-2021, PRIMARY) = the SSOT replacement_ratio by definition
#      (read from data/workforce_projections_consolidated.csv), so the primary
#      window can never drift from the headline (GO 7.11, URPS 5.38).
#   drop2 (2016-2019) / full (2016-2023) = recomputed with the pooled GO+URPS
#      window hazards (urps_model_data.R BAND_EV/BAND_PY) applied to each cohort's
#      active-age distribution through the shared engine projector (wc_project).
suppressPackageStartupMessages({library(here); library(readr); library(dplyr)})
source(here::here("R", "workforce_cliff_engine.R"))
source(here::here("shiny_urps_scenarios", "urps_model_data.R"))  # BAND_EV/BAND_PY (pooled windows)

ssot <- readr::read_csv(here::here("data", "workforce_projections_consolidated.csv"),
                        show_col_types = FALSE)
ssot_ratio <- function(ab) ssot$replacement_ratio[ssot$subspecialty_abbrev == ab]

# Cohort active-age vectors on the current baseline.
urps_ages <- sort(as.integer(readr::read_csv(
  here::here("data", "urps_1306_active_cohort.csv"), show_col_types = FALSE)$age))
go_ages <- wc_active_ages(wc_load_cohort())$GO
ages_of <- list(URPS = urps_ages, GO = go_ages)
base_of <- c(URPS = length(urps_ages), GO = length(go_ages))
entr_of <- c(URPS = mean(WC_GRAD$URPS), GO = mean(WC_GRAD$GO))

win_years <- c(fully_obs = "2016-2021", drop2 = "2016-2019", full = "2016-2023")
hz_for_window <- function(w) {
  ev <- BAND_EV[[w]]; py <- BAND_PY[[w]]
  h <- ifelse(py > 0, ev / py, NA); h[is.na(h)] <- max(h, na.rm = TRUE)
  h <- pmin(1, h); names(h) <- BAND_LABELS; h
}
ratio_window <- function(ab, w) {
  if (w == "fully_obs") return(ssot_ratio(ab))               # primary == SSOT
  pr <- wc_project(ages_of[[ab]], entrants = entr_of[[ab]], hz = hz_for_window(w),
                   horizon = WC_HORIZON)
  round(entr_of[[ab]] / (pr$departures_4yr / WC_HORIZON), 2)
}

rows <- do.call(rbind, lapply(c("URPS", "GO"), function(ab) {
  do.call(rbind, lapply(names(win_years), function(w) {
    r <- ratio_window(ab, w)
    mean_annual_dep <- entr_of[[ab]] / r
    data.frame(window = win_years[[w]], label = w, subspecialty_abbrev = ab,
               rate = round(100 * mean_annual_dep / base_of[[ab]], 2),
               dynamic_ratio = round(r, 2),
               assessment = ifelse(r >= 1.05, "Above replacement",
                             ifelse(r >= 0.95, "At replacement", "Below replacement")),
               stringsAsFactors = FALSE)
  }))
}))
readr::write_csv(rows, here::here("data", "departure_window_sensitivity.csv"))
cat("Wrote data/departure_window_sensitivity.csv\n")
print(rows[, c("subspecialty_abbrev", "label", "dynamic_ratio")])
