#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# TEMPORAL BACK-TEST of the dynamic departure model (peer review).
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Freeze the active cohort at an earlier base year, roll it forward with the
# age-band departure-hazard model, and compare the PROJECTED number still active
# to the OBSERVED number still active. This tests the whole model (the dynamic
# stock-flow mechanics plus the age-band hazards), not a single component.
#
# CLOSED-COHORT design: we track only the physicians active at the base year and
# apply pure survival (no entrants), so the test isolates the departure process
# and is not confounded by graduate-inflow assumptions. Observed survival comes
# from each physician's classified retirement_year.
#
# Two hazard sources:
#   (1) CALIBRATION: hazards from the full observable window 2016-2021, applied to
#       the 2016 cohort, compared with observed active counts 2017-2021 (goodness
#       of fit of the age-band model to the cohort's actual depletion).
#   (2) OUT-OF-SAMPLE: hazards TRAINED on 2016-2019, cohort frozen at 2019, projected
#       to 2020-2021, compared with observed (a true forward test). Departures are
#       too sparse before 2019 to train on an earlier window.
#
# OUTPUT: cliff/data/temporal_backtest.csv + console report.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(readr); library(dplyr); library(here)})


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
    stop(sprintf("[%s] monorepo input not found:\n  %s", "temporal_backtest", p), call. = FALSE)
  p
}

BANDS <- c(0,45,50,55,60,65,70,Inf); BL <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
AGE_AT_CERT <- 30L
band_of <- function(age) as.character(cut(age, breaks=BANDS, labels=BL, right=FALSE))
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")

coh <- read_csv(iso("manuscript", "tables", "table1_physician_characteristics.csv"),
                show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)],
            cy=as.integer(cert_year), ry=suppressWarnings(as.integer(retirement_year))) %>%
  distinct(npi, .keep_all=TRUE) %>% filter(!is.na(ab))

# ---- age-band hazards over a training window (person-year life table) -------
haz_train <- function(win){
  pt <- do.call(rbind, lapply(seq_len(nrow(coh)), function(i){
    cy<-coh$cy[i]; ry<-coh$ry[i]
    if(!is.na(ry)&&(ry<win[1]||ry>win[2])) ry<-NA_integer_
    y0<-max(win[1],cy); y1<-if(is.na(ry)) win[2] else min(win[2],ry); if(y1<y0) return(NULL)
    yy<-y0:y1; data.frame(band=band_of(yy-cy+AGE_AT_CERT), ev=as.integer(!is.na(ry)&yy==ry))}))
  h <- pt %>% group_by(band) %>% summarise(py=n(), ev=sum(ev), .groups="drop") %>% mutate(h=ev/py)
  setNames(h$h, h$band)
}
haz_for <- function(age, hz){ v<-hz[band_of(age)]; v[is.na(v)]<-max(hz,na.rm=TRUE); pmin(1,v) }

# ---- observed vs predicted closed-cohort survival --------------------------
# base cohort = active at BASE (cert<=BASE, not departed by BASE)
backtest <- function(base, targets, hz, subs=names(SUBS)){
  do.call(rbind, lapply(subs, function(k){
    c0 <- coh %>% filter(ab==k, cy<=base, is.na(ry) | ry>base)
    age0 <- base - c0$cy + AGE_AT_CERT
    do.call(rbind, lapply(targets, function(Tt){
      obs <- sum(is.na(c0$ry) | c0$ry > Tt)                    # observed still-active at T
      # predicted survival: age the base cohort forward applying hazards each year
      cnt <- rep(1, length(age0)); ag <- age0
      for(y in seq_len(Tt-base)){ cnt <- cnt*(1-haz_for(ag,hz)); ag <- ag+1L }
      pred <- sum(cnt)
      data.frame(subspecialty_abbrev=k, base=base, target=Tt,
                 n_base=length(age0), observed_active=obs, predicted_active=round(pred,1),
                 error=round(pred-obs,1), pct_error=round(100*(pred-obs)/obs,1))
    }))
  }))
}

# (1) CALIBRATION: full-window hazards, 2016 cohort, targets 2017-2021
hz_full <- haz_train(c(2016L,2021L))
cal <- backtest(2016L, 2017:2021, hz_full)

# (2) OUT-OF-SAMPLE: train 2016-2019, freeze 2019, project 2020-2021
hz_1619 <- haz_train(c(2016L,2019L))
oos <- backtest(2019L, 2020:2021, hz_1619)

out <- bind_rows(cbind(mode="calibration_2016_2021haz", cal),
                 cbind(mode="oos_train2016_2019", oos))
write_csv(out, here::here("data","temporal_backtest.csv"))

cat("=== (1) CALIBRATION back-test: 2016 cohort survival, full-window hazards ===\n")
cat("(predicted vs observed number of the 2016-active cohort still active at year T)\n\n")
for(k in names(SUBS)){
  d <- cal %>% filter(subspecialty_abbrev==k)
  cat(sprintf("%-5s (n_base %d):\n", k, d$n_base[1]))
  for(i in seq_len(nrow(d))) cat(sprintf("   %d: observed %d  predicted %.0f  (%+.1f%%)\n",
        d$target[i], d$observed_active[i], d$predicted_active[i], d$pct_error[i]))
}
cat("\n=== (2) OUT-OF-SAMPLE: hazards trained 2016-2019, 2019 cohort -> 2020-2021 ===\n\n")
for(k in names(SUBS)){
  d <- oos %>% filter(subspecialty_abbrev==k)
  cat(sprintf("%-5s (n_base %d):\n", k, d$n_base[1]))
  for(i in seq_len(nrow(d))) cat(sprintf("   %d: observed %d  predicted %.0f  (%+.1f%%)\n",
        d$target[i], d$observed_active[i], d$predicted_active[i], d$pct_error[i]))
}
cat("\nMean absolute pct error (calibration):", round(mean(abs(cal$pct_error)),1),
    "%% | (out-of-sample):", round(mean(abs(oos$pct_error)),1), "%%\n")
cat("Wrote cliff/data/temporal_backtest.csv\n")
