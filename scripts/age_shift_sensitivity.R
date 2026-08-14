#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Age-shift sensitivity (reviewer #19), run through the ONE authoritative model.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Age is certification-anchored (cert_year + 30) and validation shows a ~2-year
# underestimate. Because age-band hazards rise nonlinearly, a +2 or +4 year shift
# can move physicians across band boundaries. We recompute the replacement ratio
# with all ages shifted +0/+2/+4, applied to BOTH the POOLED age-band hazard life
# table and the active-age distribution (and the entry age), using the primary
# (non-Open-Payments-anchored) departure definition and the SAME pooled dynamic
# projection as scripts/rebuild_ssot_revised.R. The +0 row therefore reproduces the
# consolidated SSOT exactly; only the shift perturbs it. (The ratios are NOT
# restated here: the 7.35/5.83 pair this comment used to name was a third vintage
# matching neither the artifact nor the SSOT. Read them from the SSOT.)
# Reviewer #3: every sensitivity passes through the identical dynamic model.
#
# OUTPUT: cliff/data/age_shift_sensitivity.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(dplyr); library(readr); library(here)})
source(here::here("manuscript","R","workforce_data_contract.R"))

# Ported from the isochrones monorepo (2026-08-13). Same treatment as
# scripts/build_audit_table.R: monorepo inputs resolve under
# CLIFF_ISOCHRONES_ROOT, and the URPS active-age distribution comes from the
# v3.0.0 cohort that DEFINES the adopted 1,306 baseline rather than from a
# roster reconstruction, which cannot reproduce it (see that script's header).
ISO <- Sys.getenv("CLIFF_ISOCHRONES_ROOT", unset = path.expand("~/isochrones"))
iso <- function(...) { p <- file.path(ISO, ...)
  if (!file.exists(p)) stop(sprintf("[age_shift_sensitivity] input not found:\n  %s", p), call. = FALSE)
  p }
.v3 <- utils::read.csv(here::here("scripts","urps_scenario_cube",
                                  "urps_cohort_ages_pathway_geo_v3.0.0.csv"),
                       stringsAsFactors = FALSE)
.v3 <- .v3[.v3$geography == "national", ]
URPS_AGES <- with(.v3, rep(as.integer(age), as.integer(n_active_2023)))
stopifnot(length(URPS_AGES) == mufflyaccess::urps_count(
  year = 2023L, measure = "board_certified_active", geography = "national",
  include_urology = TRUE, incomplete = "error"))
BANDS <- c(0,45,50,55,60,65,70,Inf); BL <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
band_of <- function(a) as.character(cut(a, BANDS, labels=BL, right=FALSE))
WIN <- c(2016L,2021L); AGE_AT_CERT <- 30L; ENTRY_AGE <- 34L; REF_YEAR <- 2024L
HORIZON <- WORKFORCE_PROJECTION_HORIZON_YEARS
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")
GRAD <- list(GO=c(70,73,78,79), URPS=c(61,66,63,66), MIGS=c(47,50,45,47)); ENTRANTS <- sapply(GRAD, mean)

coh <- read_csv(iso("manuscript","tables","table1_physician_characteristics.csv"),
                show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)],
            cy=as.integer(cert_year), ry=suppressWarnings(as.integer(retirement_year)),
            ret=as.logical(is_retired_for_cohorting), age=as.integer(age_approx)) %>%
  distinct(npi,.keep_all=TRUE) %>% filter(!is.na(ab))
.anch <- read_csv(here::here("data","departure_anchor.csv"), show_col_types=FALSE)
coh <- coh %>% left_join(mutate(.anch, npi=as.character(npi)), by="npi") %>%
  mutate(ry = ifelse(!is.na(ry) & !has_nonop_anchor, NA_integer_, ry)) %>% select(-has_nonop_anchor)

# ABU both-pathway active ages
abu_cw <- read_csv("/Users/tylermuffly/isochrones/data/abu_urology/abu_npi_crosswalk_2026-07-14.csv",
                   show_col_types=FALSE, guess_max=1e5) %>%
  transmute(npi=as.character(npi), cert_year=suppressWarnings(as.integer(abu_cert_year)))
abu_nn <- trimws(gsub('"','', readLines(
  "/Users/tylermuffly/isochrones/data/abu_urology/abu_fpmrs_net_new_npis_active_2026-07-14.txt")))
abu_nn <- abu_nn[abu_nn!="" & !grepl("npi", abu_nn, ignore.case=TRUE)]
ABU_AGES <- abu_cw %>% filter(npi %in% abu_nn, !is.na(cert_year)) %>%
  mutate(age=REF_YEAR-cert_year+AGE_AT_CERT) %>% distinct(npi,.keep_all=TRUE) %>% pull(age)

haz_for <- function(age, hz){ h<-hz[band_of(age)]; h[is.na(h)]<-max(hz,na.rm=TRUE); pmin(1,h) }
project <- function(ages, entrants, hz, entry_age){
  count<-table(ages); av<-as.integer(names(count)); count<-as.numeric(count); dep<-0
  for(h in seq_len(HORIZON)){ hzz<-haz_for(av,hz); dep<-dep+sum(count*hzz); sv<-count*(1-hzz)
    av2<-av+1L; ix<-match(entry_age,av2)
    if(is.na(ix)){av2<-c(av2,entry_age); sv<-c(sv,entrants)} else sv[ix]<-sv[ix]+entrants
    av<-av2; count<-sv }
  list(active_2029=sum(count), departures_4yr=dep)
}

# POOLED age-band hazard over GO + ABOG-URPS ONLY (MIGS excluded from the primary
# hazard; reviewer decision 2026-07-19), with all ages shifted by `shift`.
pooled_haz <- function(shift){
  bc <- do.call(rbind, lapply(which(coh$ab %in% c("GO","URPS")), function(i){
    cy<-coh$cy[i]; ry<-coh$ry[i]
    if(!is.na(ry)&&(ry<WIN[1]||ry>WIN[2])) ry<-NA_integer_
    y0<-max(WIN[1],cy); y1<-if(is.na(ry)) WIN[2] else min(WIN[2],ry); if(y1<y0) return(NULL)
    yy<-y0:y1; data.frame(band=band_of(yy-cy+AGE_AT_CERT+shift), event=as.integer(!is.na(ry)&yy==ry))})) %>%
    group_by(band) %>% summarise(py=dplyr::n(), ev=sum(event), .groups="drop")
  setNames(bc$ev/bc$py, bc$band)
}

out <- do.call(rbind, lapply(c(0L,2L,4L), function(s){
  hz <- pooled_haz(s)
  do.call(rbind, lapply(c("GO","URPS"), function(sub){
    ci <- coh$ab==sub
    ages <- coh$age[ci & coh$ret==FALSE & !is.na(coh$age)]
    # URPS baseline from the v3.0.0 SSOT cohort; GO keeps the monorepo cohort,
    # whose 1,052 already reproduces the SSOT.
    if(sub=="URPS") ages <- URPS_AGES
    ages <- ages + s
    d <- project(ages, ENTRANTS[[sub]], hz, ENTRY_AGE + s)
    avg <- d$departures_4yr/HORIZON; ent <- round(ENTRANTS[[sub]])
    data.frame(subspecialty_abbrev=sub, age_shift_years=s,
               departure_rate_pct=round(100*avg/length(ages),2),
               avg_annual_departures=round(avg,1),
               replacement_ratio=round(ent/avg,2))
  }))
}))
write_csv(out, here::here("data","age_shift_sensitivity.csv"))
cat("=== #19 age-shift sensitivity (primary anchored def, pooled dynamic model) ===\n")
print(as.data.frame(out), row.names=FALSE)
.ssot <- utils::read.csv(here::here("data","workforce_projections_consolidated.csv"),
                         stringsAsFactors = FALSE)
cat(sprintf("\n(+0 row must reproduce SSOT: GO %.2f, URPS %.2f)\nWrote data/age_shift_sensitivity.csv\n",
            .ssot$replacement_ratio[.ssot$subspecialty_abbrev == "GO"],
            .ssot$replacement_ratio[.ssot$subspecialty_abbrev == "URPS"]))
