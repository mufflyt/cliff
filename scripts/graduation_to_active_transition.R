#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Graduation -> active-practice transition function (review point #3).
# The primary model adds fellowship completers to the active board-certified
# stock in their entry year at full weight. This script estimates the OBSERVED
# transition from certification to active practice empirically, links it to the
# projection, and quantifies how much the immediate-entry assumption overstates
# near-term growth.
#
# Empirical transition: among board-certified GO and URPS physicians (cert cohorts
# 2013-2019, >=4 yr follow-up), the cumulative fraction with observed Medicare
# activity by k years after certification, NORMALIZED to eventual activation so it
# measures TIMING, not the Medicare-visibility ceiling (the ~11-16% who never bill
# Medicare reflect non-Medicare panels, not non-entry, and must not be counted as
# non-entrants -- the same visibility caveat as the operative analysis). The raw
# ever-billed ceiling is reported separately.
#
# We then re-project the status-quo workforce applying the timing ramp to entrants
# and compare the 2029 stock with the immediate-entry projection.
#
# OUTPUT: cliff/data/graduation_active_transition.csv
#         cliff/data/graduation_active_transition_projection.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(dplyr); library(tidyr); library(readr); library(here)})


# PORTED FROM THE ISOCHRONES MONOREPO (2026-08-14). The extraction that created
# this repository carried this script's OUTPUT across but not the script, so the
# artifact sat in data/ with nothing able to regenerate it. Changes on porting:
#   * here::here("cliff", "data", X) -> here::here("data", X); this IS cliff now
#   * monorepo inputs resolve under CLIFF_ISOCHRONES_ROOT and fail loudly when
#     absent, rather than being hardcoded absolute paths that would silently
#     rebuild on whatever happened to be there
ISO <- Sys.getenv("CLIFF_ISOCHRONES_ROOT", unset = path.expand("~/isochrones"))
iso <- function(...) {
  p <- file.path(ISO, ...)
  if (!file.exists(p))
    stop(sprintf("[%s] monorepo input not found:\n  %s", "graduation_to_active_transition", p), call. = FALSE)
  p
}

SUBS <- c(GO="Gynecologic Oncology", URPS="Female Pelvic Medicine & Reconstructive Surgery")
KMAX <- 5L; COHORTS <- 2013:2019   # >=4 yr follow-up to 2023

d <- read_csv(iso("manuscript", "tables", "table1_physician_characteristics.csv"),
              show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(ab=names(SUBS)[match(subspecialty,SUBS)],
            cy=as.integer(cert_year),
            fb=suppressWarnings(as.integer(first_billing_year))) %>%
  filter(!is.na(ab))

# --- transition function: cumulative activation by k years since certification ----
trans <- do.call(rbind, lapply(names(SUBS), function(k){
  co <- d %>% filter(ab==k, cy %in% COHORTS)
  ever <- co %>% filter(!is.na(fb))                 # eventual activators (Medicare-visible)
  ceiling_ever <- mean(!is.na(co$fb))               # ever-billed ceiling (visibility, not entry)
  # normalized timing ramp among eventual activators
  f <- vapply(0:KMAX, function(kk) mean((ever$fb - ever$cy) <= kk), numeric(1))
  data.frame(subspecialty_abbrev=k, k=0:KMAX,
             cum_active_fraction=round(f,3),
             ever_billed_ceiling=round(ceiling_ever,3))
}))
write_csv(trans, here::here("data","graduation_active_transition.csv"))

# --- transition-adjusted re-projection ------------------------------------------
# The IMMEDIATE-entry endpoint is anchored to the authoritative SSOT projected_2029
# (so the supplement remains single-source-of-truth consistent); the transition
# ramp is applied as a DEFERRAL computed from the entry-timing model, which is
# independent of the departure model, and subtracted from the SSOT endpoint.
ss <- read_csv(here::here("data","workforce_projections_consolidated.csv"), show_col_types=FALSE)
HORIZON <- 4L
proj <- do.call(rbind, lapply(c("GO","URPS"), function(k){
  base <- ss$baseline_2025[ss$subspecialty_abbrev==k]
  rate <- ss$annual_retirement_rate[ss$subspecialty_abbrev==k]/100
  E    <- ss$annual_entrants[ss$subspecialty_abbrev==k]
  ssot_2029 <- ss$projected_2029[ss$subspecialty_abbrev==k]
  fk   <- trans$cum_active_fraction[trans$subspecialty_abbrev==k]   # length KMAX+1, k=0..KMAX
  marg <- diff(c(0, fk))                                            # marginal activation by year since entry
  # deferral = immediate-entry minus ramped, both from the same deterministic model
  s_imm <- base; s_ramp <- base
  for(t in seq_len(HORIZON)){
    s_imm  <- s_imm*(1-rate) + E
    add <- sum(vapply(seq_len(t), function(j){ idx <- t-j+1; if(idx<=length(marg)) E*marg[idx] else 0 }, numeric(1)))
    s_ramp <- s_ramp*(1-rate) + add
  }
  deferral <- s_imm - s_ramp
  imm_r <- round(ssot_2029); ramp_r <- round(ssot_2029 - deferral)
  data.frame(subspecialty_abbrev=k, baseline=base, annual_entrants=E,
             projected_2029_immediate=imm_r,
             projected_2029_ramped=ramp_r,
             difference=imm_r - ramp_r,   # consistent with the displayed rounded endpoints
             pct_of_growth_deferred=round(100*(imm_r-ramp_r)/(imm_r-base)))
}))
write_csv(proj, here::here("data","graduation_active_transition_projection.csv"))

cat("=== #3 graduation -> active-practice transition function (cert cohorts 2013-2019) ===\n")
print(as.data.frame(trans %>% tidyr::pivot_wider(names_from=k, values_from=cum_active_fraction,
      names_prefix="k=") %>% select(-ever_billed_ceiling) %>% distinct()), row.names=FALSE)
cat("\nEver-billed ceiling (Medicare visibility, NOT entry):",
    paste(sprintf("%s %.0f%%", trans$subspecialty_abbrev[trans$k==0], 100*trans$ever_billed_ceiling[trans$k==0]), collapse=", "), "\n")
cat("\n=== transition-adjusted re-projection ===\n"); print(as.data.frame(proj), row.names=FALSE)
cat("\nWrote graduation_active_transition.csv + _projection.csv\n")
