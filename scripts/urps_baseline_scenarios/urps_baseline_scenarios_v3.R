#!/usr/bin/env Rscript
# ==============================================================================
# URPS baseline-scenario comparison (contract v3.0.0)
#
# Shows how the CHOICE of 2023 baseline moves the 2025->2029 workforce projection,
# as THREE explicit scenarios -- instead of silently re-baselining the published
# projection. The published (legacy 1295) projection is REPRODUCED FROM THE FROZEN
# RECORD and is never re-run or overwritten here.
#
#   A. legacy_1295   1031 ABOG + 264 ABU, primary-cert reconciliation
#                    -> PUBLISHED frozen SGS projection (read, not recomputed)
#   B. active_2023   mufflyaccess v3.0.0 board_certified_active / national (1306)
#   C. roster_2025   2025 roster snapshot (1339)
#
# B and C are re-run with cliff's OWN age-structured recurrence (wc_project) on
# each cohort's real age distribution, holding the published model parameters
# constant: 64 annual entrants at age 34, the fully-observable age-band retirement
# hazards, horizon = 4. This isolates the effect of the baseline choice.
#
# Writes ONLY to scripts/urps_baseline_scenarios/. Does NOT modify
# data/workforce_projections_consolidated.csv.
# ==============================================================================
find_root <- function() {
  if (requireNamespace("here", quietly = TRUE)) return(here::here())
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) { if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
                   p <- dirname(d); if (identical(p, d)) break; d <- p }
  getwd()
}
root  <- find_root()
sdir  <- file.path(root, "scripts", "urps_baseline_scenarios")
ages  <- utils::read.csv(file.path(sdir, "urps_cohort_ages_v3.0.0.csv"), stringsAsFactors = FALSE)

# ---- published model parameters (same as the frozen projection / shiny engine) ----
ENTRANTS <- 64L        # mean of GRAD_URPS c(61,66,63,66) OB/GYN+urology completers AY2020-24
ENTRY    <- 34L
HORIZON  <- 4L
MC_SEED  <- 20260718L  # matches manuscript_WORKFORCE_CLIFF.Rmd / shiny bootstrap seed
MC_DRAWS <- 4000L
# fully-observable age-band retirement hazards = events / person-years (2016-2021, primary)
BAND_LABELS <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
BAND_EV <- c(13.058, 2.853, 3.508, 4.002, 5.192, 4.388, 0)
BAND_PY <- c(3854, 973, 811, 488, 221, 53, 3)
HAZ     <- ifelse(BAND_PY > 0, BAND_EV / BAND_PY, 0)
band_of <- function(age) cut(age, breaks = c(-Inf,45,50,55,60,65,70,Inf), right = FALSE,
                             labels = BAND_LABELS)
haz_for <- function(age) { h <- HAZ[match(as.character(band_of(age)), BAND_LABELS)]; h[is.na(h)] <- 0; h }

# ---- cliff's deterministic age-structured recurrence (mirrors wc_project) ----
project_det <- function(age, n, entrants = ENTRANTS, horizon = HORIZON, entry = ENTRY) {
  dep <- 0
  for (h in seq_len(horizon)) {
    hz  <- haz_for(age); dep <- dep + sum(n * hz)
    sv  <- n * (1 - hz); a2 <- age + 1L
    ix  <- match(entry, a2)
    if (is.na(ix)) { a2 <- c(a2, entry); sv <- c(sv, entrants) } else sv[ix] <- sv[ix] + entrants
    age <- a2; n <- sv
  }
  list(projected = sum(n), departures = dep)
}
# stochastic replicate: retirements ~ Binomial(count, band hazard) each year
project_mc <- function(age, n) {
  for (h in seq_len(HORIZON)) {
    hz  <- haz_for(age); ret <- stats::rbinom(length(n), size = n, prob = hz)
    sv  <- n - ret; a2 <- age + 1L; ix <- match(ENTRY, a2)
    if (is.na(ix)) { a2 <- c(a2, ENTRY); sv <- c(sv, ENTRANTS) } else sv[ix] <- sv[ix] + ENTRANTS
    age <- a2; n <- sv
  }
  sum(n)
}
run_scenario <- function(age, n) {
  det <- project_det(age, n)
  set.seed(MC_SEED)
  fin <- vapply(seq_len(MC_DRAWS), function(i) project_mc(age, as.integer(n)), numeric(1))
  base <- sum(n); avg_ret <- det$departures / HORIZON
  list(baseline = base, projected = det$projected,
       sd = stats::sd(fin), lo = unname(stats::quantile(fin, .025)),
       hi = unname(stats::quantile(fin, .975)),
       pct_change = 100 * (det$projected - base) / base,
       avg_annual_retirements = avg_ret, replacement_ratio = ENTRANTS / avg_ret)
}

# ---- A. legacy 1295: reproduce from the FROZEN published record (do not re-run) ----
frozen <- utils::read.csv(file.path(root, "data", "workforce_projections_consolidated.csv"),
                          stringsAsFactors = FALSE)
u <- frozen[frozen$subspecialty_abbrev == "URPS", ]
stopifnot(nrow(u) == 1L)
legacy <- list(baseline = as.integer(u$baseline_2025), projected = as.numeric(u$projected_2029),
               sd = as.numeric(u$sd_2029), lo = as.numeric(u$ci95_lower), hi = as.numeric(u$ci95_upper),
               pct_change = as.numeric(u$percent_change),
               avg_annual_retirements = as.numeric(u$avg_annual_retirements),
               replacement_ratio = as.numeric(u$replacement_ratio))

# ---- B, C: re-run the engine on the real cohort age distributions ----
active <- run_scenario(ages$age, ages$n_active_2023)
roster <- run_scenario(ages$age, ages$n_roster_2025)

row <- function(id, basis, source, s) data.frame(
  scenario = id, cohort_basis = basis, source = source,
  baseline_2023 = s$baseline, projected_2029 = round(s$projected, 1),
  ci95_lower = round(s$lo), ci95_upper = round(s$hi), sd_2029 = round(s$sd, 2),
  pct_change = round(s$pct_change, 2), avg_annual_retirements = round(s$avg_annual_retirements, 2),
  replacement_ratio = round(s$replacement_ratio, 2), stringsAsFactors = FALSE)

out <- rbind(
  row("A_legacy", "primary-cert reconciliation (1031 ABOG + 264 ABU)",
      "PUBLISHED frozen SGS projection (not re-run)", legacy),
  row("B_active_2023", "URPS-subspecialty-cert active (mufflyaccess v3.0.0)",
      "engine re-run on the real 2023-active age distribution", active),
  row("C_roster_2025", "2025 roster snapshot (full identified cohort)",
      "engine re-run on the real roster age distribution", roster))

csv_path <- file.path(sdir, "urps_baseline_scenarios_v3.0.0.csv")
utils::write.csv(out, csv_path, row.names = FALSE)

# ---- fail-closed: the frozen projection must be untouched ----
FROZEN_LEGACY_BASELINE <- 1295L  # ssot-ok: legacy frozen SGS projection cohort
stopifnot("frozen projection baseline changed!" = as.integer(u$baseline_2025) == FROZEN_LEGACY_BASELINE,
          "frozen projection endpoint changed!" = abs(as.numeric(u$projected_2029) - 1505.367) < 0.01)

cat(sprintf("wrote %s\n", csv_path))
print(out[, c("scenario","baseline_2023","projected_2029","pct_change",
              "avg_annual_retirements","replacement_ratio")], row.names = FALSE)
