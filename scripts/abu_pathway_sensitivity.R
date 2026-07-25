#!/usr/bin/env Rscript
source(here::here("R", "workforce_cliff_engine.R"))   # SSOT: study constants (WC_*) + wc_path()
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# #10: model the ABU (urology-pathway) URPS component separately instead of
# assigning it the ABOG hazard. Produces a supplement sensitivity table:
#   (A) ABOG-only URPS   (baseline 1031, OB/GYN-pathway grads 48, ABOG hazard)
#   (B) both-pathway     (baseline 1295, both-pathway grads 64, ABOG hazard on ABU)
#   (C-E) both-pathway with the ABU subset's departure hazard scaled x0.5 / x1 / x2
# ABU-only standalone hazards are NOT independently estimable from this cohort
# (no linked ABU departure signals), so we bracket the ABU hazard rather than
# assert it. OUTPUT: data/abu_pathway_sensitivity.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(dplyr); library(readr); library(here)})

# Study constants: SSOT = R/workforce_cliff_engine.R (WC_*).
BANDS <- WC_BANDS; BL <- WC_BAND_LABELS
WIN <- WC_WIN; AGE_AT_CERT <- WC_AGE_AT_CERT; REF_YEAR <- WC_REF_YEAR; HORIZON <- WC_HORIZON; ENTRY_AGE <- WC_ENTRY_AGE
band_of <- function(age) as.character(cut(age, BANDS, labels=BL, right=FALSE))

coh <- read_csv(wc_path("cohort_csv"),
                show_col_types=FALSE, guess_max=READ_GUESS_MAX_ROWS) %>%
  filter(subspecialty=="Female Pelvic Medicine & Reconstructive Surgery", !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), cert_year=as.integer(cert_year),
            ry=suppressWarnings(as.integer(retirement_year)),
            ret=as.logical(is_retired_for_cohorting), age=as.integer(age_approx)) %>%
  distinct(npi,.keep_all=TRUE)
# PRIMARY departure definition: require a non-Open-Payments corroborating source.
.anch <- read_csv(here::here("data","departure_anchor.csv"), show_col_types=FALSE)
coh <- coh %>% left_join(mutate(.anch, npi=as.character(npi)), by="npi") %>%
  mutate(ry = ifelse(!is.na(ry) & !has_nonop_anchor, NA_integer_, ry)) %>% select(-has_nonop_anchor)

# ABOG age-band hazard (fully observable window)
bc <- do.call(rbind, lapply(seq_len(nrow(coh)), function(i){
  cy<-coh$cert_year[i]; ry<-coh$ry[i]
  if(!is.na(ry)&&(ry<WIN[1]||ry>WIN[2])) ry<-NA_integer_
  y0<-max(WIN[1],cy); y1<-if(is.na(ry)) WIN[2] else min(WIN[2],ry); if(y1<y0) return(NULL)
  yy<-y0:y1; data.frame(band=band_of(yy-cy+AGE_AT_CERT), event=as.integer(!is.na(ry)&yy==ry))})) %>%
  group_by(band) %>% summarise(py=dplyr::n(), ev=sum(event), .groups="drop")
HAZ <- setNames(bc$ev/bc$py, bc$band)
haz_for <- function(age, mult=1){ h<-HAZ[band_of(age)]*mult; h[is.na(h)]<-max(HAZ,na.rm=TRUE)*mult; pmin(1,h) }

abog_ages <- coh %>% filter(ret==FALSE, !is.na(age)) %>% pull(age)
abu_cw <- read_csv(wc_path("abu_crosswalk"),
                   show_col_types=FALSE, guess_max=READ_GUESS_MAX_ROWS) %>%
  transmute(npi=as.character(npi), cert_year=suppressWarnings(as.integer(abu_cert_year)))
abu_nn <- trimws(gsub('"','', readLines(
  wc_path("abu_net_new"))))
abu_nn <- abu_nn[abu_nn!="" & !grepl("npi", abu_nn, ignore.case=TRUE)]
abu_ages <- abu_cw %>% filter(npi %in% abu_nn, !is.na(cert_year)) %>%
  mutate(age=REF_YEAR-cert_year+AGE_AT_CERT) %>% distinct(npi,.keep_all=TRUE) %>% pull(age)

# dynamic 4-yr projection over sub-populations, each with its own hazard multiplier
project <- function(pops, entrants){
  # pops: list of list(ages=, mult=). Returns avg annual departures over HORIZON.
  total_dep <- 0
  pops <- lapply(pops, function(p) list(ages=as.numeric(p$ages), mult=p$mult))
  ent_ages <- rep(ENTRY_AGE, 0)
  for(t in seq_len(HORIZON)){
    dep_t <- 0
    for(j in seq_along(pops)){
      a <- pops[[j]]$ages; if(!length(a)) next
      h <- haz_for(a, pops[[j]]$mult); d <- sum(h)
      dep_t <- dep_t + d
      surv <- a + 1L                     # age survivors
      # remove expected departures by trimming highest-hazard fraction deterministically
      keep <- rbinom_free(a, h)
      pops[[j]]$ages <- surv[keep]
    }
    # entrants (all ABOG-pathway hazard, mult=1) added to pop 1
    pops[[1]]$ages <- c(pops[[1]]$ages, rep(ENTRY_AGE, entrants))
    total_dep <- total_dep + dep_t
  }
  total_dep/HORIZON
}
# deterministic survivor selection: keep each physician with prob (1-h) via expected-value
# thinning (rank by hazard, remove the top sum(h) by expectation). Use fractional retention.
rbinom_free <- function(a, h){
  # keep all; expected departures handled at the aggregate via hazard sum is complex, so
  # instead remove the ceiling(sum(h)) individuals with highest hazard (conservative, stable)
  n_rm <- min(length(a), round(sum(h)))
  if(n_rm==0) return(rep(TRUE,length(a)))
  ord <- order(h, decreasing=TRUE)
  keep <- rep(TRUE,length(a)); keep[ord[seq_len(n_rm)]] <- FALSE; keep
}

scen <- function(label, pops, entrants, baseline){
  avg_dep <- project(pops, entrants)
  data.frame(scenario=label, baseline=baseline, annual_grads=entrants,
             avg_annual_departures=round(avg_dep,1),
             replacement_ratio=round(entrants/avg_dep,2))
}

out <- bind_rows(
  scen("ABOG-only URPS", list(list(ages=abog_ages, mult=1)), 48, length(abog_ages)),
  scen("Both-pathway (ABU=ABOG hazard)",
       list(list(ages=abog_ages, mult=1), list(ages=abu_ages, mult=1)), 64,
       length(abog_ages)+length(abu_ages)),
  scen("Both-pathway, ABU hazard x0.5",
       list(list(ages=abog_ages, mult=1), list(ages=abu_ages, mult=0.5)), 64,
       length(abog_ages)+length(abu_ages)),
  scen("Both-pathway, ABU hazard x2.0",
       list(list(ages=abog_ages, mult=1), list(ages=abu_ages, mult=2.0)), 64,
       length(abog_ages)+length(abu_ages)))

write_csv(out, here::here("data","abu_pathway_sensitivity.csv"))
cat("=== #10 ABU-pathway sensitivity (URPS) ===\n"); print(as.data.frame(out), row.names=FALSE)
cat(sprintf("\nABOG active URPS=%d, ABU net-new active=%d, both-pathway=%d\n",
            length(abog_ages), length(abu_ages), length(abog_ages)+length(abu_ages)))
cat("Wrote data/abu_pathway_sensitivity.csv\n")