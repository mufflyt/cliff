#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Rebuild the workforce SSOT: major-revision pass (peer review #1/#4/#5/#9).
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# #4 RIGHT-CENSORING: age-band departure hazards are estimated over the FULLY
#    OBSERVABLE window 2016-2021 (with Medicare/NPPES data to 2023 and a 3-year
#    cessation rule, 2022-2023 exits are unconfirmable and pile up as provisional
#    over-flags). 2016-2019 and 2016-2023 are retained as sensitivities.
# #1 URPS BOTH-PATHWAY: the primary URPS baseline is now the union of the ABOG
#    (OB/GYN) pathway and the ABU (urology) pathway. 270 net-new active
#    urology-pathway urogynecologists (ABU roster, not already ABOG) are added to
#    the 1,031 ABOG-active, giving 1,301. The ACGME graduate count already spans
#    both pathways, so the numerator is unchanged; this makes stock and flow the
#    same population. ABU physicians are assumed to share the ABOG-URPS age-band
#    hazard (same subspecialty); their ages come from ABU certification year.
# #5 MULTI-YEAR INFLOW: entrants are the 4-year ACGME graduate mean (GO 75, URPS
#    48; 2020-21..2023-24), not a single year; MIGS 47 (NRMP/AAGL, unchanged).
# #9 PARAMETER UNCERTAINTY: ci95 columns are a 10,000-iteration bootstrap that
#    propagates (a) age-band hazard uncertainty via a Beta(events+.5, PY-events+.5)
#    posterior per band and (b) year-to-year graduate variability via Normal(mean,
#    sd); seed recorded. This replaces the narrow conditional departure-draw
#    interval (kept as a secondary column sd_2029 basis).
#
# MIGS remains in the table for the contract but is treated as an EXPLORATORY
# focused-practice-designation cohort in the manuscript (not pooled).
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(here); library(readr); library(dplyr)})

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# NRMP single-year-entry BENCHMARK -> data/workforce_projection_benchmark_nrmp.csv
#
# Extracted from isochrones scripts/rebuild_ssot_revised.R, which in the monorepo
# wrote three artifacts from one model run. cliff split the other two into
# scripts/rebuild_ssot_revised.R (the SSOT) and
# scripts/build_departure_window_sensitivity.R (the window sensitivity), but the
# NRMP benchmark block was left behind, so its artifact had no generator here.
# Only the benchmark write is retained below; the other two are suppressed.
#
# The URPS start ages come from the v3.0.0 cohort that defines the adopted 1,306
# baseline, not from the ABU roster reconstruction, which yields the retired
# 1,295 basis. See CLAUDE.md.
ISO <- Sys.getenv("CLIFF_ISOCHRONES_ROOT", unset = path.expand("~/isochrones"))
iso <- function(...) { p <- file.path(ISO, ...)
  if (!file.exists(p)) stop(sprintf("[build_nrmp_benchmark] input not found:\n  %s", p), call. = FALSE)
  p }

source(here::here("manuscript","R","workforce_data_contract.R"))

BANDS <- c(0,45,50,55,60,65,70,Inf); BAND_LABELS <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
WIN <- c(2016L,2021L); WIN_SENS <- list(fully_obs=c(2016L,2021L), drop2=c(2016L,2019L), full=c(2016L,2023L))
AGE_AT_CERT <- 30L; YEAR0 <- 2025L; HORIZON <- WORKFORCE_PROJECTION_HORIZON_YEARS
ENTRY_AGE <- 34L; N_BOOT <- 10000L; SEED <- 20260718L; REF_YEAR <- 2024L
band_of <- function(age) as.character(cut(age, breaks=BANDS, labels=BAND_LABELS, right=FALSE))
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")
SUBS_FULL <- c(URPS="Urogynecology and Reconstructive Pelvic Surgery",
               GO="Gynecologic Oncology", MIGS="Minimally Invasive Gynecologic Surgery")

# #5 multi-year ACGME graduate mean (AY2020-21..2023-24) + SD; MIGS = NRMP/AAGL.
# URPS is the BOTH-PATHWAY completer series (ACGME Data Resource Book Table D.5:
# OB/GYN-sponsored 45,51,47,50 PLUS Urology-sponsored 16,15,16,16), to match the
# both-pathway active stock; GO is single-pathway (OB/GYN). Verified 2026-07-19.
GRAD <- list(GO=c(70,73,78,79), URPS=c(61,66,63,66), MIGS=c(47,50,45,47))  # MIGS = NRMP filled 2022-25
ENTRANTS <- sapply(GRAD, mean); ENT_SD <- sapply(GRAD, sd)
ENTRANTS_NRMP <- c(URPS=74L, GO=88L, MIGS=51L)   # benchmark (NRMP filled, 2026 appointment year;
                                                 # URPS is now the both-pathway "Urology and OB/GYN" match)

# ---- ABOG cohort ----------------------------------------------------------
coh <- read_csv(iso("manuscript", "tables", "table1_physician_characteristics.csv"),
                show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)],
            cert_year=as.integer(cert_year),
            ry=suppressWarnings(as.integer(retirement_year)),
            ret=as.logical(is_retired_for_cohorting), age=as.integer(age_approx)) %>%
  distinct(npi,.keep_all=TRUE) %>% filter(!is.na(ab))

# PRIMARY departure definition: require a non-Open-Payments corroborating source
# (scripts/departure_anchor.R). Open-Payments-only "departures" are nulled so they
# do not enter the hazard life table. Baseline (is_retired_for_cohorting) unchanged.
.anch <- read_csv(here::here("data","departure_anchor.csv"), show_col_types=FALSE)
coh <- coh %>% left_join(mutate(.anch, npi=as.character(npi)), by="npi") %>%
  mutate(ry = ifelse(!is.na(ry) & !has_nonop_anchor, NA_integer_, ry)) %>% select(-has_nonop_anchor)

# ---- #1 ABU urology-pathway net-new active URPS (age from ABU cert year) ----
abu_cw <- read_csv(iso("data", "abu_urology", "abu_npi_crosswalk_2026-07-14.csv"),
                   show_col_types=FALSE, guess_max=1e5) %>%
  transmute(npi=as.character(npi), cert_year=suppressWarnings(as.integer(abu_cert_year)))
abu_nn <- trimws(gsub('"','', readLines(
  iso("data", "abu_urology", "abu_fpmrs_net_new_npis_active_2026-07-14.txt"))))
abu_nn <- abu_nn[abu_nn!="" & !grepl("npi", abu_nn, ignore.case=TRUE)]
abu_age <- abu_cw %>% filter(npi %in% abu_nn, !is.na(cert_year)) %>%
  mutate(age = REF_YEAR - cert_year + AGE_AT_CERT) %>% distinct(npi,.keep_all=TRUE)
message(sprintf("[#1] ABU net-new active URPS: %d NPIs, %d with cert year (median age %.0f)",
                length(abu_nn), nrow(abu_age), median(abu_age$age)))

# ---- age-band hazard life table over a window -------------------------------
# PRIMARY hazard pools GO + ABOG-URPS ONLY. MIGS is exploratory and noncomparable
# (cohort ascertainment, certification status, graduate numerator), so its events
# do NOT enter the primary hazard (reviewer decision 2026-07-19). MIGS is still
# projected by applying this GO+URPS hazard to its own age distribution, and a
# MIGS-inclusive hazard is reported only as a sensitivity (Appendix S6b).
band_counts <- function(win, rows=which(coh$ab %in% c("GO","URPS"))){
  do.call(rbind, lapply(rows, function(i){
    cy<-coh$cert_year[i]; ry<-coh$ry[i]
    if(!is.na(ry)&&(ry<win[1]||ry>win[2])) ry<-NA_integer_
    y0<-max(win[1],cy); y1<-if(is.na(ry)) win[2] else min(win[2],ry); if(y1<y0) return(NULL)
    yy<-y0:y1; data.frame(band=band_of(yy-cy+AGE_AT_CERT), event=as.integer(!is.na(ry)&yy==ry))})) %>%
    group_by(band) %>% summarise(py=dplyr::n(), ev=sum(event), .groups="drop")
}
bc <- band_counts(WIN)
HAZ <- setNames(bc$ev/bc$py, bc$band)
haz_for <- function(age, hz=HAZ){ h<-hz[band_of(age)]; h[is.na(h)]<-max(hz,na.rm=TRUE); pmin(1,h) }

# ---- active age vectors (URPS = ABOG + ABU net-new) ------------------------
active <- coh %>% filter(ret==FALSE, !is.na(age))
start_ages <- split(active$age, active$ab)
# v3.0.0 both-pathway baseline (1,027 ABOG + 279 ABU net-new = 1,306)
.v3 <- utils::read.csv(here::here("scripts", "urps_scenario_cube",
                                  "urps_cohort_ages_pathway_geo_v3.0.0.csv"),
                       stringsAsFactors = FALSE)
.v3 <- .v3[.v3$geography == "national", ]
start_ages$URPS <- rep(as.integer(.v3$age), as.integer(.v3$n_active_2023))
stopifnot(length(start_ages$URPS) == mufflyaccess::urps_count(
  year = 2023L, measure = "board_certified_active", geography = "national",
  include_urology = TRUE, incomplete = "error"))

# ---- dynamic projection (deterministic given hazards + entrants) -----------
project <- function(ages, entrants, hz=HAZ){
  count<-table(ages); av<-as.integer(names(count)); count<-as.numeric(count); dep<-0
  for(h in seq_len(HORIZON)){ hzz<-haz_for(av,hz); dep<-dep+sum(count*hzz); sv<-count*(1-hzz)
    av2<-av+1L; ix<-match(ENTRY_AGE,av2)
    if(is.na(ix)){av2<-c(av2,ENTRY_AGE); sv<-c(sv,entrants)} else sv[ix]<-sv[ix]+entrants
    av<-av2; count<-sv }
  list(active_2029=sum(count), departures_4yr=dep)
}

# ---- #9 parameter-uncertainty bootstrap ------------------------------------
# Per iteration: Beta posterior for each band hazard + Normal graduate draw.
boot_ci <- function(ages, k){
  set.seed(SEED + match(k, names(SUBS)))
  bands <- names(HAZ)
  a <- setNames(bc$ev[match(bands, bc$band)] + 0.5, bands)
  b <- setNames(bc$py[match(bands, bc$band)] - bc$ev[match(bands, bc$band)] + 0.5, bands)
  out <- numeric(N_BOOT)
  for(i in seq_len(N_BOOT)){
    hz <- setNames(rbeta(length(bands), a, b), bands)
    # #21: graduate output by EMPIRICAL RESAMPLING of the observed annual counts
    # (integer, no distributional assumption), not a Normal fit to four values.
    ent <- sample(GRAD[[k]], 1)
    out[i] <- project(ages, ent, hz)$active_2029
  }
  c(sd=sd(out), lo=quantile(out,.025,names=FALSE), hi=quantile(out,.975,names=FALSE))
}

build_row <- function(k){
  ages <- start_ages[[k]]; base <- length(ages)
  d <- project(ages, ENTRANTS[[k]]); avg_dep <- d$departures_4yr/HORIZON
  ci <- boot_ci(ages, k); ratio <- ENTRANTS[[k]]/avg_dep
  data.frame(subspecialty=SUBS_FULL[[k]], subspecialty_abbrev=k,
    baseline_2025=base, projected_2029=d$active_2029,
    sd_2029=ci[["sd"]], ci95_lower=ci[["lo"]], ci95_upper=ci[["hi"]],
    percent_change=100*(d$active_2029-base)/base,
    annual_retirement_rate=100*avg_dep/base,
    avg_annual_retirements=avg_dep, annual_entrants=round(ENTRANTS[[k]]),
    replacement_ratio=ratio, replacement_assessment=classify_replacement(ratio),
    fellowship_total_4yr=round(ENTRANTS[[k]])*HORIZON,
    total_retirements_4yr=round(d$departures_4yr), stringsAsFactors=FALSE)
}
primary <- do.call(rbind, lapply(names(SUBS), build_row))
# annual_entrants is rounded for display; recompute ratio/projection from the rounded
# value so the fail-closed contract identities hold exactly.
primary <- primary %>% mutate(
  replacement_ratio = annual_entrants/avg_annual_retirements,
  replacement_assessment = classify_replacement(replacement_ratio),
  projected_2029 = baseline_2025 + HORIZON*(annual_entrants - avg_annual_retirements),
  percent_change = 100*(projected_2029-baseline_2025)/baseline_2025)
primary <- primary[match(WORKFORCE_SUBSPECIALTIES, primary$subspecialty_abbrev),]
validate_workforce_data(primary, source_hint="rebuild_ssot_revised.R")
# ===== CANONICAL SSOT WRITER =====
# This is the ONE authoritative writer of workforce_projections_consolidated.csv.
# The other variants (rebuild_ssot_final.R, rebuild_ssot_dynamic_acgme.R) fail closed
# unless WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE=1; rebuild_ssot_from_nrmp.R only reads.
# (this repo generates that artifact elsewhere: see scripts/rebuild_ssot_revised.R
#  and scripts/build_departure_window_sensitivity.R)

# ---- window sensitivity (departure rate by observation window) -------------
# #7: every alternative departure definition (here, observation window) passes
# through the SAME dynamic model; report the dynamic replacement ratio, not a
# static graduates/(baseline*rate) ratio.
wsens <- do.call(rbind, lapply(names(WIN_SENS), function(nm){
  bcw <- band_counts(WIN_SENS[[nm]]); hzw <- setNames(bcw$ev/bcw$py, bcw$band)
  do.call(rbind, lapply(names(SUBS), function(k){
    ages <- start_ages[[k]]
    rate <- 100*sum(haz_for(ages,hzw))/length(ages)
    d <- project(ages, ENTRANTS[[k]], hzw)
    ratio <- ENTRANTS[[k]]/(d$departures_4yr/HORIZON)
    data.frame(window=paste(WIN_SENS[[nm]],collapse="-"), label=nm,
               subspecialty_abbrev=k, rate=round(rate,2),
               dynamic_ratio=round(ratio,2),
               assessment=classify_replacement(ratio))}))}))
# (this repo generates that artifact elsewhere: see scripts/rebuild_ssot_revised.R
#  and scripts/build_departure_window_sensitivity.R)

# ---- NRMP benchmark (single-year entry) ------------------------------------
bench <- do.call(rbind, lapply(names(SUBS), function(k){
  d<-project(start_ages[[k]], ENTRANTS_NRMP[[k]]); avg<-d$departures_4yr/HORIZON
  data.frame(subspecialty_abbrev=k, nrmp_entrants=ENTRANTS_NRMP[[k]],
    projected_2029_nrmp=round(d$active_2029,1), replacement_ratio_nrmp=round(ENTRANTS_NRMP[[k]]/avg,2),
    percent_change_nrmp=round(100*(d$active_2029-length(start_ages[[k]]))/length(start_ages[[k]]),1),
    assessment_nrmp=classify_replacement(ENTRANTS_NRMP[[k]]/avg))}))
write_csv(bench, here::here("data","workforce_projection_benchmark_nrmp.csv"))
