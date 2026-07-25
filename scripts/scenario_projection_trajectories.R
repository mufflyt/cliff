#!/usr/bin/env Rscript
source(here::here("R", "wc_path.R"))
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Scenario-based workforce projection trajectories (2025-2029) for Figure 1A,
# following the fixed-entrant scenario design of Shah et al. (uveitis forecast):
#   conservative = 70% of the recent graduate mean (practice-conversion floor)
#   status-quo   = recent four-year ACGME graduate mean (the primary projection)
#   optimistic   = NRMP positions-filled benchmark
# Individual-level Monte Carlo (Beta-posterior age-band hazards + stochastic
# departures + Normal graduate draws) yields per-year median and 95% bands. This
# reuses the SSOT model inputs so the status-quo median lands on projected_2029.
#
# OUTPUT: data/scenario_projection_trajectories.csv
#   subspecialty_abbrev, subspecialty, scenario, year, median, lo, hi, entrants
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(dplyr); library(readr); library(here)})
set.seed(20260718L)

BANDS <- c(0,45,50,55,60,65,70,Inf); BL <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
band_of <- function(a) as.character(cut(a, BANDS, labels=BL, right=FALSE))
WIN <- c(2016L,2021L); AGE_AT_CERT <- 30L; ENTRY_AGE <- 34L; REF_YEAR <- 2024L
YEAR0 <- 2025L; HORIZON <- 4L; N_BOOT <- 2000L
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")
SUBS_FULL <- c(URPS="Urogynecology and Reconstructive Pelvic Surgery",
               GO="Gynecologic Oncology", MIGS="Minimally Invasive Gynecologic Surgery")
GRAD <- list(GO=c(70,73,78,79), URPS=c(61,66,63,66), MIGS=c(47,50,45,47))
NRMP <- c(GO=88, URPS=74, MIGS=51)

# ---- cohort (ABOG) + ABU net-new for URPS -------------------------------------
coh <- read_csv(wc_path("cohort_csv"),
                show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)],
            cert_year=as.integer(cert_year), ry=suppressWarnings(as.integer(retirement_year)),
            ret=as.logical(is_retired_for_cohorting), age=as.integer(age_approx)) %>%
  distinct(npi,.keep_all=TRUE) %>% filter(!is.na(ab))
# PRIMARY departure definition: require a non-Open-Payments corroborating source.
.anch <- read_csv(here::here("data","departure_anchor.csv"), show_col_types=FALSE)
coh <- coh %>% left_join(mutate(.anch, npi=as.character(npi)), by="npi") %>%
  mutate(ry = ifelse(!is.na(ry) & !has_nonop_anchor, NA_integer_, ry)) %>% select(-has_nonop_anchor)

# pooled age-band hazard life table (matches SSOT): events + person-years per band
bc <- do.call(rbind, lapply(seq_len(nrow(coh)), function(i){
  cy<-coh$cert_year[i]; ry<-coh$ry[i]
  if(!is.na(ry)&&(ry<WIN[1]||ry>WIN[2])) ry<-NA_integer_
  y0<-max(WIN[1],cy); y1<-if(is.na(ry)) WIN[2] else min(WIN[2],ry); if(y1<y0) return(NULL)
  yy<-y0:y1; data.frame(band=band_of(yy-cy+AGE_AT_CERT), event=as.integer(!is.na(ry)&yy==ry))})) %>%
  group_by(band) %>% summarise(py=dplyr::n(), ev=sum(event), .groups="drop")
HAZ_EV <- setNames(bc$ev, bc$band); HAZ_PY <- setNames(bc$py, bc$band)
bands_all <- BL

active <- coh %>% filter(ret==FALSE, !is.na(age))
ages_by <- split(active$age, active$ab)
abu_cw <- read_csv(wc_path("abu_crosswalk"),
                   show_col_types=FALSE, guess_max=1e5) %>%
  transmute(npi=as.character(npi), cert_year=suppressWarnings(as.integer(abu_cert_year)))
abu_nn <- trimws(gsub('"','', readLines(
  wc_path("abu_net_new"))))
abu_nn <- abu_nn[abu_nn!="" & !grepl("npi", abu_nn, ignore.case=TRUE)]
abu_ages <- abu_cw %>% filter(npi %in% abu_nn, !is.na(cert_year)) %>%
  mutate(age=REF_YEAR-cert_year+AGE_AT_CERT) %>% distinct(npi,.keep_all=TRUE) %>% pull(age)
ages_by$URPS <- c(ages_by$URPS, abu_ages)

# ---- individual-level Monte Carlo projection ----------------------------------
# ent_vec is the per-projection-year (2026..2029) entrant mean, so a scenario can
# apply a training lag (the optimistic NRMP scenario only takes effect once the
# matched fellows would complete the 3-year fellowship, review point #4).
FELLOWSHIP_YEARS <- 3L
project_mc <- function(ages0, ent_vec, ent_sd){
  M <- matrix(NA_real_, N_BOOT, HORIZON+1)
  for(b in seq_len(N_BOOT)){
    hz <- vapply(bands_all, function(bd){
      e<-HAZ_EV[bd]; p<-HAZ_PY[bd]; if(is.na(e)) e<-0; if(is.na(p)||p==0) return(NA_real_)
      rbeta(1, e+0.5, p-e+0.5)}, numeric(1)); names(hz)<-bands_all
      hzmax <- max(hz, na.rm=TRUE)
    ages <- ages0; M[b,1] <- length(ages)
    for(t in seq_len(HORIZON)){
      h <- hz[band_of(ages)]; h[is.na(h)] <- hzmax
      keep <- rbinom(length(ages),1,pmin(1,h))==0
      ages <- ages[keep] + 1L
      e <- max(0L, as.integer(round(rnorm(1, ent_vec[t], ent_sd))))
      ages <- c(ages, rep(ENTRY_AGE, e))
      M[b,t+1] <- length(ages)
    }
  }
  data.frame(year=YEAR0+0:HORIZON,
             median=apply(M,2,median),
             lo=apply(M,2,quantile,0.025),
             hi=apply(M,2,quantile,0.975))
}

# NRMP is the 2026 appointment-year match. Matched fellows enter the workforce only
# after completing their fellowship, whose length differs by pathway: the urology
# URPS fellowship is 2 years, the obstetrics-gynecology URPS fellowship is 3 years,
# and Gynecologic Oncology is 3 years. The optimistic scenario therefore realizes the
# NRMP-fill output pathway by pathway as each cohort completes. Status-quo and NRMP
# graduate output split into obstetrics-gynecology + urology components for URPS.
GRAD_SPLIT  <- list(GO=list(obg=75, uro=0), URPS=list(obg=48, uro=16), MIGS=list(obg=47, uro=0))
NRMP_SPLIT  <- list(GO=list(obg=88, uro=0), URPS=list(obg=56, uro=18), MIGS=list(obg=51, uro=0))
LEN_OBG <- 3L; LEN_URO <- 2L; MATCH_YR <- 2026L
opt_component <- function(nrmp_c, grad_c, len, Y) if (Y >= MATCH_YR + len) nrmp_c else grad_c
out <- do.call(rbind, lapply(names(SUBS), function(k){
  gmean <- mean(GRAD[[k]]); gsd <- sd(GRAD[[k]]); a0 <- ages_by[[k]]
  opt_vec <- vapply(YEAR0 + seq_len(HORIZON), function(Y)
    opt_component(NRMP_SPLIT[[k]]$obg, GRAD_SPLIT[[k]]$obg, LEN_OBG, Y) +
    opt_component(NRMP_SPLIT[[k]]$uro, GRAD_SPLIT[[k]]$uro, LEN_URO, Y), numeric(1))
  scen <- list(conservative=rep(0.70*gmean, HORIZON),
               `status-quo`=rep(gmean, HORIZON),
               optimistic=opt_vec)
  do.call(rbind, lapply(names(scen), function(s){
    tr <- project_mc(a0, scen[[s]], gsd)
    data.frame(subspecialty_abbrev=k, subspecialty=unname(SUBS_FULL[k]),
               scenario=s, tr, entrants=round(scen[[s]][HORIZON],1))
  }))
}))

write_csv(out, here::here("data","scenario_projection_trajectories.csv"))
cat("=== scenario projection trajectories (2029 endpoints) ===\n")
print(out %>% filter(year==2029) %>%
        transmute(subspecialty_abbrev, scenario, entrants,
                  y2029=round(median), lo=round(lo), hi=round(hi)) %>% as.data.frame(), row.names=FALSE)
cat("\nWrote data/scenario_projection_trajectories.csv\n")
