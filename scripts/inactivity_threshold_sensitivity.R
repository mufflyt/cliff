#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Reviewer #9: inactivity-DURATION sensitivity (2 vs 3 vs 4 years), distinct from
# the calendar-window sensitivity. A departure event is re-derived from Medicare
# Part B clinical activity: for required inactivity T years, a physician whose last
# Part B active year is L is classified as departed in year L+1 (first-inactive)
# ONLY if the T-year absence is fully observable (L + T <= 2023); otherwise the exit
# is right-censored (treated as still active). Only the age-band hazard changes with
# T; the active baseline and entrant counts are held at the primary values, so the
# three columns isolate the effect of the inactivity threshold.
#
# NOTE: this isolates the Part B inactivity signal, so the T=3 column is not expected
# to reproduce the multi-source consensus primary ratio (5.6) exactly; the three T
# values are internally comparable and answer whether the conclusion depends on the
# required inactivity duration. Reuses the verbatim rebuild_ssot_revised.R machinery.
#   OUTPUT: cliff/data/inactivity_threshold_sensitivity.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({library(DBI); library(duckdb); library(readr); library(dplyr); library(here)})


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
    stop(sprintf("[%s] monorepo input not found:\n  %s", "inactivity_threshold_sensitivity", p), call. = FALSE)
  p
}

BANDS <- c(0,45,50,55,60,65,70,Inf); BAND_LABELS <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
WIN <- c(2016L,2021L); AGE_AT_CERT <- 30L; HORIZON <- 4L; ENTRY_AGE <- 34L; REF_YEAR <- 2024L; OBS_END <- 2023L
band_of <- function(age) as.character(cut(age, breaks=BANDS, labels=BAND_LABELS, right=FALSE))
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")
GRAD <- list(GO=c(70,73,78,79), URPS=c(61,66,63,66)); ENTRANTS <- sapply(GRAD, mean)
PRIMARY <- c("GO","URPS")

# ---- cohort (verbatim) -----------------------------------------------------
coh <- read_csv(iso("manuscript", "tables", "table1_physician_characteristics.csv"),
                show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)],
            cert_year=as.integer(cert_year), ret=as.logical(is_retired_for_cohorting),
            age=as.integer(age_approx)) %>%
  distinct(npi,.keep_all=TRUE) %>% filter(!is.na(ab))

# ---- Part B last-active year per cohort NPI -------------------------------
db <- "/Volumes/MufflySamsung 1/DuckDB/nber_my_duckdb.duckdb"
if(!file.exists(db)) db <- "/Volumes/MufflySamsung/DuckDB/nber_my_duckdb.duckdb"
con <- dbConnect(duckdb::duckdb(), db, read_only=TRUE)
duckdb::duckdb_register(con, "coh_npi", data.frame(npi=coh$npi))
pb <- dbGetQuery(con, "SELECT CAST(a.npi AS VARCHAR) npi, a.last_active_year_part_b L
                       FROM credentials.part_b_activity a JOIN coh_npi c ON CAST(a.npi AS VARCHAR)=c.npi")
dbDisconnect(con, shutdown=TRUE)
coh <- coh %>% left_join(pb, by="npi")
message(sprintf("[#9] %d cohort NPIs; %d (%.0f%%) have Part B activity (median last-active %d)",
                nrow(coh), sum(!is.na(coh$L)), 100*mean(!is.na(coh$L)), median(coh$L, na.rm=TRUE)))

# ---- ABU net-new active URPS ages (verbatim) -------------------------------
abu_cw <- read_csv(iso("data", "abu_urology", "abu_npi_crosswalk_2026-07-14.csv"),
                   show_col_types=FALSE, guess_max=1e5) %>%
  transmute(npi=as.character(npi), cert_year=suppressWarnings(as.integer(abu_cert_year)))
abu_nn <- trimws(gsub('"','', readLines(iso("data", "abu_urology", "abu_fpmrs_net_new_npis_active_2026-07-14.txt"))))
abu_nn <- abu_nn[abu_nn!="" & !grepl("npi", abu_nn, ignore.case=TRUE)]
abu_age <- (abu_cw %>% filter(npi %in% abu_nn, !is.na(cert_year)) %>%
              mutate(age=REF_YEAR-cert_year+AGE_AT_CERT) %>% distinct(npi,.keep_all=TRUE))$age

# active age vectors (primary baseline, held fixed across T)
ages <- split((coh %>% filter(ret==FALSE, !is.na(age)))$age, (coh %>% filter(ret==FALSE, !is.na(age)))$ab)
ages$URPS <- c(ages$URPS, abu_age)

# ---- hazard + projection machinery (verbatim) ------------------------------
band_counts <- function(rows){
  do.call(rbind, lapply(rows, function(i){
    cy<-coh$cert_year[i]; ry<-coh$ry[i]
    if(!is.na(ry)&&(ry<WIN[1]||ry>WIN[2])) ry<-NA_integer_
    y0<-max(WIN[1],cy); y1<-if(is.na(ry)) WIN[2] else min(WIN[2],ry); if(y1<y0) return(NULL)
    yy<-y0:y1; data.frame(band=band_of(yy-cy+AGE_AT_CERT), event=as.integer(!is.na(ry)&yy==ry))})) %>%
    group_by(band) %>% summarise(py=dplyr::n(), ev=sum(event), .groups="drop")
}
haz_for <- function(age, hz){ h<-hz[band_of(age)]; h[is.na(h)]<-max(hz,na.rm=TRUE); pmin(1,h) }
project <- function(a, entrants, hz){
  count<-table(a); av<-as.integer(names(count)); count<-as.numeric(count); dep<-0
  for(h in seq_len(HORIZON)){ hzz<-haz_for(av,hz); dep<-dep+sum(count*hzz); sv<-count*(1-hzz)
    av2<-av+1L; ix<-match(ENTRY_AGE,av2)
    if(is.na(ix)){av2<-c(av2,ENTRY_AGE); sv<-c(sv,entrants)} else sv[ix]<-sv[ix]+entrants
    av<-av2; count<-sv }
  list(active_2029=sum(count), departures_4yr=dep)
}

# ---- per-threshold: re-derive events, recompute hazard + ratio -------------
res <- do.call(rbind, lapply(c(2L,3L,4L), function(T){
  # departure event only if the T-year absence is fully observable by 2023
  coh$ry <<- ifelse(!is.na(coh$L) & (coh$L + T <= OBS_END), coh$L + 1L, NA_integer_)
  bc <- band_counts(which(coh$ab %in% PRIMARY)); HAZ <- setNames(bc$ev/bc$py, bc$band)
  do.call(rbind, lapply(PRIMARY, function(k){
    d <- project(ages[[k]], ENTRANTS[[k]], HAZ); avg <- d$departures_4yr/HORIZON
    ev_k <- sum(!is.na(coh$ry) & coh$ab==k & coh$ry>=WIN[1] & coh$ry<=WIN[2])
    data.frame(subspecialty_abbrev=k, threshold_years=T,
               n_events_in_window=ev_k,
               departure_rate_pct=round(100*avg/length(ages[[k]]),2),
               avg_annual_departures=round(avg,1),
               replacement_ratio=round(ENTRANTS[[k]]/avg,2),
               assessment=ifelse(ENTRANTS[[k]]/avg>=1.2,"Adequate",ifelse(ENTRANTS[[k]]/avg>=0.8,"Marginal","Insufficient")),
               stringsAsFactors=FALSE)
  }))
}))
res <- res[order(res$subspecialty_abbrev, res$threshold_years),]
write_csv(res, here("data","inactivity_threshold_sensitivity.csv"))
cat("\n#9 INACTIVITY-THRESHOLD SENSITIVITY (Part B activity, primary cohorts):\n"); print(res)
cat("\nDONE\n")
