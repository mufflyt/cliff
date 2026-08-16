# URPS model-data snapshot for the standalone Shiny apps. Values originate from
# R/workforce_cliff_engine.R + the hierarchical-hazard pipeline.
# CANONICAL COPY: shiny_urps_scenarios/urps_model_data.R (also sourced by the repo demand scripts).
# Replicas (e.g. shiny_urps_adequacy/data/urps_model_data.R) are kept BYTE-IDENTICAL by
# scripts/sync_urps_model_data.R and drift-guarded by tests/testthat/test-ssot-urps-model-data-sync.R.
# Do NOT hand-edit this file: edit scripts/rebuild_urps_1306_snapshot.R, run it, then run sync.
# URPS_AGES comes from the SSOT, not a literal.
#
# This was a 1,306-element hardcoded vector, replicated into the adequacy app and
# kept in step by scripts/sync_urps_model_data.R plus a drift guard -- machinery
# that existed only because mufflyaccess did not serve the distribution. It does
# now, and it reconciles the ages against urps_count() on every call, so the app
# can no longer run on a cohort the SSOT does not recognise.
#
# No fallback on purpose: a silent fallback to a stale copy is exactly how the
# app came to validate a 1,306 model against 1,339 expectations.
if (!requireNamespace("mufflyaccess", quietly = TRUE)) {
  stop("Package 'mufflyaccess' is required for URPS_AGES ",
       "(renv::install(\"mufflyt/mufflyaccess\")).", call. = FALSE)
}
URPS_AGES <- mufflyaccess::urps_active_ages(
  pathway = "ABOG_PLUS_ABU", geography = "national", as = "vector"
)
# 2026-08-02 rebuild: URPS baseline is the 1,306 board-certified-active cohort
# (active_2023 == TRUE in the isochrones urps_provider_snapshot: 1,027 ABOG +
# 279 ABU net-new), vendored to data/urps_1306_active_cohort.csv. Supersedes the
# retired 1,339 roster snapshot. Ages = age_proxy_from_cert.
BAND_LABELS <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
BANDS <- c(0,45,50,55,60,65,70,Inf)  # age-band breakpoints (== engine WC_BANDS; parity-guarded in test-ssot-age-bands.R); length == BAND_LABELS + 1
GRAD_URPS <- c(61,66,63,66)  # OB/GYN+urology completers AY2020-24
# Age-band event / person-year counts per observation window (for the Beta-posterior MC).
# PRIMARY window (fully_obs) is the POOLED GO+URPS age-band hazard (manuscript
# primary; 71 pooled events; reproduces the SSOT ratio 5.38 and active_2029 1,514).
# drop2/full are the pooled GO+URPS window sensitivities.
BAND_EV <- list(fully_obs=c(24,5,6,8,13,15,0), drop2=c(12,3,2,3,7,7,0), full=c(59,15,16,18,26,23,4))
BAND_PY <- list(fully_obs=c(7635,1830,1485,1059,610,202,16), drop2=c(5175,1122,965,652,345,109,0), full=c(9833,2620,2033,1525,906,348,49))
WINDOW_LABELS <- c(fully_obs="Fully observable (2016-2021, primary)", drop2="Restricted (2016-2019)", full="Full window (2016-2023, provisional)")
HAZ_WINDOWS <- setNames(Map(function(ev,py) setNames(ifelse(py>0, ev/py, NA_real_), BAND_LABELS), BAND_EV, BAND_PY), names(BAND_EV))
