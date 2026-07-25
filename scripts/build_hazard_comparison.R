#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Pooled vs unpooled age-band departure hazards (peer review #4 + pooling concern).
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# The authoritative model (rebuild_ssot_revised.R) estimates ONE POOLED age-band
# hazard across GO+URPS+MIGS (to stabilise sparse per-band events) and applies it
# to each cohort's own age distribution. This script makes that transparent: for
# each age band it reports, by subspecialty, the events and person-years and the
# UNPOOLED (subspecialty-specific) hazard, alongside the POOLED hazard actually
# used. It also reports the resulting weighted 2025 departure rate for GO and URPS
# under the pooled vs the unpooled hazard, so a reader can see that the reported
# per-subspecialty rates differ mainly because of age structure, not because the
# hazards themselves were estimated separately.
#
# Primary (non-Open-Payments-anchored) departure definition, window 2016-2021.
# Computed entirely from committed inputs (no signals DB needed).
#
# OUTPUTS:
#   data/hazard_by_band_pooled_vs_unpooled.csv   (events, PY, hazards by band)
#   data/hazard_rate_pooled_vs_unpooled.csv      (weighted rate GO/URPS both ways)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(here); library(readr); library(dplyr)})
BANDS <- c(0,45,50,55,60,65,70,Inf); BL <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
band_of <- function(a) as.character(cut(a, BANDS, labels=BL, right=FALSE))
AGE_AT_CERT <- 30L; REF_YEAR <- 2024L; WIN <- c(2016L,2021L)
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")

coh <- read_csv("/Users/tylermuffly/isochrones/manuscript/tables/table1_physician_characteristics.csv",
                show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)],
            cy=as.integer(cert_year), ry=suppressWarnings(as.integer(retirement_year)),
            ret=as.logical(is_retired_for_cohorting), age=as.integer(age_approx)) %>%
  distinct(npi,.keep_all=TRUE) %>% filter(!is.na(ab))
.anch <- read_csv(here::here("data","departure_anchor.csv"), show_col_types=FALSE)
coh <- coh %>% left_join(mutate(.anch, npi=as.character(npi)), by="npi") %>%
  mutate(ry = ifelse(!is.na(ry) & !has_nonop_anchor, NA_integer_, ry)) %>% select(-has_nonop_anchor)

# person-year / event counts by band, for a chosen set of cohort rows
band_counts <- function(rows){
  do.call(rbind, lapply(rows, function(i){
    cy<-coh$cy[i]; ry<-coh$ry[i]
    if(!is.na(ry)&&(ry<WIN[1]||ry>WIN[2])) ry<-NA_integer_
    y0<-max(WIN[1],cy); y1<-if(is.na(ry)) WIN[2] else min(WIN[2],ry); if(y1<y0) return(NULL)
    yy<-y0:y1; data.frame(band=band_of(yy-cy+AGE_AT_CERT), event=as.integer(!is.na(ry)&yy==ry))})) %>%
    group_by(band) %>% summarise(py=dplyr::n(), ev=sum(event), .groups="drop")
}

# PRIMARY pooled hazard = GO + ABOG-URPS ONLY (MIGS excluded 2026-07-19).
# The MIGS-inclusive pool is reported only as a sensitivity (pooled_incl_migs_*).
pooled <- band_counts(which(coh$ab %in% c("GO","URPS")))
pooled_incl_migs <- band_counts(seq_len(nrow(coh)))
go   <- band_counts(which(coh$ab=="GO"))
urps <- band_counts(which(coh$ab=="URPS"))
migs <- band_counts(which(coh$ab=="MIGS"))
g <- function(bc, b, col) { v <- bc[[col]][match(b, bc$band)]; ifelse(is.na(v), 0, v) }

by_band <- data.frame(band=BL) %>% mutate(
  go_events   = g(go,band,"ev"),   go_py   = g(go,band,"py"),
  urps_events = g(urps,band,"ev"), urps_py = g(urps,band,"py"),
  migs_events = g(migs,band,"ev"), migs_py = g(migs,band,"py"),
  pooled_events = g(pooled,band,"ev"), pooled_py = g(pooled,band,"py"),
  pooled_incl_migs_events = g(pooled_incl_migs,band,"ev"), pooled_incl_migs_py = g(pooled_incl_migs,band,"py"),
  go_hazard_unpooled   = round(ifelse(go_py>0, go_events/go_py, NA), 4),
  urps_hazard_unpooled = round(ifelse(urps_py>0, urps_events/urps_py, NA), 4),
  pooled_hazard        = round(ifelse(pooled_py>0, pooled_events/pooled_py, NA), 4),
  pooled_incl_migs_hazard = round(ifelse(pooled_incl_migs_py>0, pooled_incl_migs_events/pooled_incl_migs_py, NA), 4))
write_csv(by_band, here::here("data","hazard_by_band_pooled_vs_unpooled.csv"))

# weighted 2025 static rate for GO/URPS under pooled vs each cohort's own hazard
haz_for <- function(age, hz){ h<-hz[band_of(age)]; h[is.na(h)]<-max(hz,na.rm=TRUE); pmin(1,h) }
rate_of <- function(sub, hz){
  ages <- coh$age[coh$ab==sub & coh$ret==FALSE & !is.na(coh$age)]
  100*sum(haz_for(ages,hz))/length(ages)
}
HZ_POOLED <- setNames(pooled$ev/pooled$py, pooled$band)
HZ_POOLED_MIGS <- setNames(pooled_incl_migs$ev/pooled_incl_migs$py, pooled_incl_migs$band)
HZ_GO     <- setNames(go$ev/go$py, go$band)
HZ_URPS   <- setNames(urps$ev/urps$py, urps$band)
rate_tbl <- data.frame(
  subspecialty_abbrev = c("GO","URPS"),
  rate_pooled_pct   = c(round(rate_of("GO",HZ_POOLED),2),   round(rate_of("URPS",HZ_POOLED),2)),
  rate_unpooled_pct = c(round(rate_of("GO",HZ_GO),2),       round(rate_of("URPS",HZ_URPS),2)),
  rate_pooled_incl_migs_pct = c(round(rate_of("GO",HZ_POOLED_MIGS),2), round(rate_of("URPS",HZ_POOLED_MIGS),2)))
write_csv(rate_tbl, here::here("data","hazard_rate_pooled_vs_unpooled.csv"))

cat("=== Age-band events / person-years / hazards (pooled vs unpooled) ===\n")
print(by_band, row.names=FALSE)
cat("\n=== Weighted 2025 static departure rate: pooled hazard vs cohort-own hazard ===\n")
print(rate_tbl, row.names=FALSE)
cat(sprintf("\nPooled total events=%d, PY=%d. GO events=%d, URPS events=%d, MIGS events=%d.\n",
            sum(pooled$ev), sum(pooled$py), sum(go$ev), sum(urps$ev), sum(migs$ev)))
cat("Wrote hazard_by_band_pooled_vs_unpooled.csv + hazard_rate_pooled_vs_unpooled.csv\n")
