#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Feminization sensitivity: sex-stratified dynamic projection.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# These subspecialties are feminizing (female share of the cohort by certification
# era: <=2005 33%, 2006-2012 60%, 2013-2018 72%, 2019+ 71%). Women leave clinical
# practice at higher rates than men (hazard ratio ~1.4). We model this by (1)
# splitting the empirical age-band hazard into sex-specific hazards calibrated so
# that female hazard = 1.4 x male hazard and the current-mix average reproduces the
# observed rate, and (2) feeding entrants at the recent-cohort female share (72%),
# so the workforce feminizes over the horizon and its effective departure rate rises.
#
# Compares the feminization scenario with the sex-neutral primary projection.
# OUTPUT: data/feminization_sensitivity.csv + console report.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(readr); library(dplyr); library(here); library(DBI); library(duckdb)})

# PORTED FROM THE ISOCHRONES MONOREPO (2026-08-14), commit 0d8fa3662,
# scripts/feminization_sensitivity.R. Monorepo inputs resolve under
# CLIFF_ISOCHRONES_ROOT; the URPS cohort is re-based onto the v3.0.0 snapshot.
#
# WHAT THIS TABLE IS. The URPS row is deliberately ABOG-PATHWAY ONLY, not the
# both-pathway 1,306 workforce, and the supplement says so: sex is ascertainable
# only for the ABOG-certified cohort (the external ABU roster carries no sex
# field), and the 85% female entrant share is the OB/GYN resident pool that feeds
# the ABOG pathway. Its entrant count is therefore 48 (OB/GYN-sponsored), not the
# both-pathway 64. So this artifact must NOT reconcile to the headline ratio, and
# a guard demanding that would be wrong.
#
# WHAT WAS ACTUALLY STALE. The cohort was the pre-v3.0.0 ABOG count of 1,031,
# while the supplement prose beside the table now reads the v3.0.0 active count
# from the consort flow. The two disagreed by the 4 providers the v3.0.0 active
# gate removes. The URPS rows now come from the snapshot, which carries gender
# for all of them.
ISO <- Sys.getenv("CLIFF_ISOCHRONES_ROOT", unset = path.expand("~/isochrones"))
iso <- function(...) { p <- file.path(ISO, ...)
  if (!file.exists(p)) stop(sprintf("[feminization_sensitivity] input not found:\n  %s", p), call. = FALSE)
  p }
V3_PARQUET <- Sys.getenv("CLIFF_URPS_SNAPSHOT", unset = path.expand(
  "~/mufflyaccess/tests/testthat/fixtures/isochrones-v3.0.0/urps_provider_snapshot.parquet"))

BANDS <- c(0,45,50,55,60,65,70,Inf); BL <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
WIN <- c(2016L,2021L); AGE_AT_CERT <- 30L; HORIZON <- 4L; ENTRY_AGE <- 34L; REF_YEAR <- 2024L
HR_FEMALE <- 1.4           # women's departure hazard ratio vs men
# Entrant female share: subspecialty fellows are drawn from the OB/GYN resident pool,
# which is ~85% female (ACGME 2018-2020). We run both the observed recent-subspecialist
# share (0.72) and the resident-pool share (0.85, the forward-looking upper bound).
ENTRANT_FEMALE_SCENARIOS <- c(recent_subspecialist=0.72, obgyn_resident_pool=0.85)
ENTRANT_FEMALE <- 0.85     # primary feminization input (resident-pool share)
band_of <- function(a) as.character(cut(a, BANDS, labels=BL, right=FALSE))
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")
ENTRANTS <- c(URPS=48, GO=75, MIGS=47)

t <- read_csv(iso("manuscript","tables","table1_physician_characteristics.csv"),
              show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)], cy=as.integer(cert_year),
            ry=suppressWarnings(as.integer(retirement_year)), ret=as.logical(is_retired_for_cohorting),
            age=as.integer(age_approx),
            female=case_when(tolower(gender)%in%c("f","female")~TRUE, tolower(gender)%in%c("m","male")~FALSE, TRUE~NA)) %>%
  filter(!is.na(ab))
# PRIMARY departure definition: require a non-Open-Payments corroborating source.
.anch <- read_csv(here::here("data","departure_anchor.csv"), show_col_types=FALSE)
t <- t %>% left_join(mutate(.anch, npi=as.character(npi)), by="npi") %>%
  mutate(ry = ifelse(!is.na(ry) & !has_nonop_anchor, NA_integer_, ry)) %>% select(-has_nonop_anchor)

# base age-band hazard (mixed sex), 2016-2021
pt <- do.call(rbind, lapply(seq_len(nrow(t)), function(i){
  cy<-t$cy[i]; ry<-t$ry[i]; if(!is.na(ry)&&(ry<WIN[1]||ry>WIN[2])) ry<-NA_integer_
  y0<-max(WIN[1],cy); y1<-if(is.na(ry)) WIN[2] else min(WIN[2],ry); if(y1<y0) return(NULL)
  yy<-y0:y1; data.frame(band=band_of(yy-cy+AGE_AT_CERT), ev=as.integer(!is.na(ry)&yy==ry))}))
H <- pt %>% group_by(band) %>% summarise(py=n(), ev=sum(ev), .groups="drop") %>% mutate(h=ev/py) %>% { setNames(.$h,.$band) }
hbase <- function(age){ v<-H[band_of(age)]; v[is.na(v)]<-max(H,na.rm=TRUE); v }

# sex-stratified dynamic projection on a fixed age grid; survivors age +1 each year
# (shift up), then entrants are injected at ENTRY_AGE with the feminizing sex mix.
AGES <- 25:100
project_sex <- function(ages, female, entrants, sex_specific, ef){
  d <- data.frame(age=ages, female=female) %>% filter(!is.na(female))
  fem_share_active <- mean(d$female)
  cF <- as.numeric(table(factor(d$age[d$female], levels=AGES)))
  cM <- as.numeric(table(factor(d$age[!d$female], levels=AGES)))
  # calibrate sex hazards so mix-average == base and h_F = HR * h_M (share = active female share)
  hb <- hbase(AGES)
  hM <- if (sex_specific) pmin(1, hb/(1+(HR_FEMALE-1)*fem_share_active)) else pmin(1,hb)
  hF <- if (sex_specific) pmin(1, HR_FEMALE*hM) else pmin(1,hb)
  dep <- 0
  for(y in seq_len(HORIZON)){
    dep <- dep + sum(cF*hF) + sum(cM*hM)
    sF <- cF*(1-hF); sM <- cM*(1-hM)
    cF <- c(0, sF[-length(sF)]); cM <- c(0, sM[-length(sM)])   # age +1 (shift up the grid)
    ix <- match(ENTRY_AGE, AGES)
    cF[ix] <- cF[ix] + entrants*ef
    cM[ix] <- cM[ix] + entrants*(1-ef)
  }
  list(active_2029=sum(cF)+sum(cM), departures_4yr=dep, fem_share_active=fem_share_active)
}

active <- t %>% filter(ret==FALSE, !is.na(age))

# Re-base the URPS rows onto the v3.0.0 ABOG-pathway active cohort. GO and MIGS
# are not in this snapshot (it is URPS-only) and keep the monorepo cohort; GO's
# baseline of 1,052 already matches the SSOT.
if (!file.exists(V3_PARQUET))
  stop(sprintf(paste0("[feminization_sensitivity] v3.0.0 snapshot not found:\n  %s\n",
                      "Set CLIFF_URPS_SNAPSHOT."), V3_PARQUET), call. = FALSE)
.con <- DBI::dbConnect(duckdb::duckdb())
v3 <- DBI::dbGetQuery(.con, sprintf(
  "SELECT age_proxy_from_cert age, gender FROM read_parquet(%s)
    WHERE active_2023 AND board_pathway = 'ABOG'", shQuote(V3_PARQUET)))
DBI::dbDisconnect(.con, shutdown = TRUE)
stopifnot(nrow(v3) == mufflyaccess::urps_count(
  year = 2023L, measure = "board_certified_active", geography = "national",
  include_urology = FALSE, incomplete = "error"))
active <- dplyr::bind_rows(
  active[active$ab != "URPS", c("ab", "age", "female")],
  data.frame(ab = "URPS", age = as.integer(v3$age),
             female = dplyr::case_when(toupper(trimws(v3$gender)) == "F" ~ TRUE,
                                       toupper(trimws(v3$gender)) == "M" ~ FALSE,
                                       TRUE ~ NA),
             stringsAsFactors = FALSE))
res <- do.call(rbind, lapply(names(SUBS), function(k){
  d <- active[active$ab==k,]
  base <- nrow(d %>% filter(!is.na(female)))
  neu <- project_sex(d$age, d$female, ENTRANTS[[k]], sex_specific=FALSE, ef=0.72)
  scen <- lapply(ENTRANT_FEMALE_SCENARIOS, function(ef)
    project_sex(d$age, d$female, ENTRANTS[[k]], sex_specific=TRUE, ef=ef))
  data.frame(subspecialty_abbrev=k, active_female_pct=round(100*neu$fem_share_active,1), baseline=base,
    ratio_sexneutral=round(ENTRANTS[[k]]/(neu$departures_4yr/HORIZON),2),
    ratio_fem_entrants72=round(ENTRANTS[[k]]/(scen$recent_subspecialist$departures_4yr/HORIZON),2),
    ratio_fem_entrants85=round(ENTRANTS[[k]]/(scen$obgyn_resident_pool$departures_4yr/HORIZON),2),
    pct_change_fem85=round(100*(scen$obgyn_resident_pool$active_2029-base)/base,1))
}))
write_csv(res, here::here("data","feminization_sensitivity.csv"))

cat(sprintf("Feminization sensitivity (female HR %.1f; entrant female share 72%% obs. subspecialist and 85%% OB/GYN resident pool)\n\n", HR_FEMALE))
print(as.data.frame(res), row.names=FALSE)
cat("\nAll cohorts above replacement at 85% female entrants:", all(res$ratio_fem_entrants85>1.05), "\n")
cat("Wrote data/feminization_sensitivity.csv\n")
