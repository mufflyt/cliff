#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Two prespecified reviewer sensitivities for the workforce-cliff manuscript.
# Reuses the EXACT machinery of scripts/rebuild_ssot_revised.R (verbatim
# constants + project()) so the "primary" columns reconcile to the SSOT
# (GO baseline 1,052 / URPS 1,295 / GO ratio ~7.11) before anything is varied.
#
#  #3  CONSISTENT-DEFINITION BASELINE.  The primary 2025 active stock uses the
#      multi-source cohorting gate (is_retired_for_cohorting), while departures
#      require a non-Open-Payments anchor. This recomputes the 2025 active stock
#      under the SAME anchored departure rule (active = not departed under the
#      anchored rule by 2025) and reruns the dynamic model, so stock and flow
#      share one definition.  -> cliff/data/consistent_definition_baseline_sensitivity.csv
#
#  #2  AGE-SPECIFIC MORTALITY.  Board-confirmed deaths are blocked (obituary
#      pipeline). As the reviewer's "at minimum" ask, layer expected age- and
#      sex-specific mortality (SSA Period Life Table, 2020, 2023 Trustees Report)
#      onto the active stock and add it to the departure numerator, showing the
#      effect on departure count, rate, ratio, and the 2029 projection. General-
#      population q(x) OVER-states physician mortality (healthy-worker effect), so
#      this is a conservative upper bound on the missed-death correction.
#      -> cliff/data/mortality_sensitivity.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({library(here); library(readr); library(dplyr)})


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
    stop(sprintf("[%s] monorepo input not found:\n  %s", "build_reviewer_sensitivities", p), call. = FALSE)
  p
}

# ---- constants (verbatim from rebuild_ssot_revised.R) ----------------------
BANDS <- c(0,45,50,55,60,65,70,Inf); BAND_LABELS <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
WIN <- c(2016L,2021L); AGE_AT_CERT <- 30L; YEAR0 <- 2025L
HORIZON <- 4L; ENTRY_AGE <- 34L; REF_YEAR <- 2024L
band_of <- function(age) as.character(cut(age, breaks=BANDS, labels=BAND_LABELS, right=FALSE))
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")
GRAD <- list(GO=c(70,73,78,79), URPS=c(61,66,63,66), MIGS=c(47,50,45,47))
ENTRANTS <- sapply(GRAD, mean)
PRIMARY <- c("GO","URPS")   # manuscript primary cohorts (MIGS exploratory)

COHORT_CSV <- iso("manuscript", "tables", "table1_physician_characteristics.csv")
stopifnot(file.exists(COHORT_CSV))

# ---- cohort + anchored departure year (verbatim) ---------------------------
norm_sex <- function(x){ x <- toupper(trimws(as.character(x)))
  ifelse(substr(x,1,1) %in% c("M","F"), substr(x,1,1), NA_character_) }
raw <- read_csv(COHORT_CSV, show_col_types=FALSE, guess_max=1e5)
coh <- raw %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)],
            cert_year=as.integer(cert_year),
            ry=suppressWarnings(as.integer(retirement_year)),
            ret=as.logical(is_retired_for_cohorting), age=as.integer(age_approx),
            sex=coalesce(norm_sex(abog_gender), norm_sex(npi_gender))) %>%
  distinct(npi,.keep_all=TRUE) %>% filter(!is.na(ab))

.anch <- read_csv(here::here("data","departure_anchor.csv"), show_col_types=FALSE)
coh <- coh %>% left_join(mutate(.anch, npi=as.character(npi)), by="npi") %>%
  mutate(ry = ifelse(!is.na(ry) & !has_nonop_anchor, NA_integer_, ry)) %>% select(-has_nonop_anchor)

# ---- ABU urology-pathway net-new active URPS (verbatim) --------------------
abu_cw <- read_csv(iso("data", "abu_urology", "abu_npi_crosswalk_2026-07-14.csv"),
                   show_col_types=FALSE, guess_max=1e5) %>%
  transmute(npi=as.character(npi), cert_year=suppressWarnings(as.integer(abu_cert_year)))
abu_nn <- trimws(gsub('"','', readLines(
  iso("data", "abu_urology", "abu_fpmrs_net_new_npis_active_2026-07-14.txt"))))
abu_nn <- abu_nn[abu_nn!="" & !grepl("npi", abu_nn, ignore.case=TRUE)]
abu_age <- abu_cw %>% filter(npi %in% abu_nn, !is.na(cert_year)) %>%
  mutate(age = REF_YEAR - cert_year + AGE_AT_CERT) %>% distinct(npi,.keep_all=TRUE)

# RE-BASED ONTO v3.0.0. The roster reconstruction above is the pre-migration
# path and yields the retired 1,295 baseline. The adopted 1,306 baseline is
# defined by the v3.0.0 cohort, so take the URPS active ages from it: the ABOG
# side replaces coh's URPS rows and the ABU net-new side replaces abu_age.
.v3 <- utils::read.csv(here::here("scripts", "urps_scenario_cube",
                                  "urps_cohort_ages_pathway_geo_v3.0.0.csv"),
                       stringsAsFactors = FALSE)
.v3 <- .v3[.v3$geography == "national", ]
.v3_ages <- function(pw) with(.v3[.v3$pathway == pw, ],
                              rep(as.integer(age), as.integer(n_active_2023)))
V3_ABOG <- .v3_ages("ABOG")
abu_age <- data.frame(age = .v3_ages("ABU"))
stopifnot(length(V3_ABOG) + nrow(abu_age) == mufflyaccess::urps_count(
  year = 2023L, measure = "board_certified_active", geography = "national",
  include_urology = TRUE, incomplete = "error"))

# ---- age-band hazard (verbatim, GO+URPS only) ------------------------------
band_counts <- function(win, rows=which(coh$ab %in% PRIMARY)){
  do.call(rbind, lapply(rows, function(i){
    cy<-coh$cert_year[i]; ry<-coh$ry[i]
    if(!is.na(ry)&&(ry<win[1]||ry>win[2])) ry<-NA_integer_
    y0<-max(win[1],cy); y1<-if(is.na(ry)) win[2] else min(win[2],ry); if(y1<y0) return(NULL)
    yy<-y0:y1; data.frame(band=band_of(yy-cy+AGE_AT_CERT), event=as.integer(!is.na(ry)&yy==ry))})) %>%
    group_by(band) %>% summarise(py=dplyr::n(), ev=sum(event), .groups="drop")
}
bc <- band_counts(WIN); HAZ <- setNames(bc$ev/bc$py, bc$band)
haz_for <- function(age, hz=HAZ){ h<-hz[band_of(age)]; h[is.na(h)]<-max(hz,na.rm=TRUE); pmin(1,h) }

# ---- dynamic projection (verbatim) -----------------------------------------
project <- function(ages, entrants, hz=HAZ){
  count<-table(ages); av<-as.integer(names(count)); count<-as.numeric(count); dep<-0
  for(h in seq_len(HORIZON)){ hzz<-haz_for(av,hz); dep<-dep+sum(count*hzz); sv<-count*(1-hzz)
    av2<-av+1L; ix<-match(ENTRY_AGE,av2)
    if(is.na(ix)){av2<-c(av2,ENTRY_AGE); sv<-c(sv,entrants)} else sv[ix]<-sv[ix]+entrants
    av<-av2; count<-sv }
  list(active_2029=sum(count), departures_4yr=dep)
}
ratio_of <- function(k, ages){ d<-project(ages, ENTRANTS[[k]]); ENTRANTS[[k]]/(d$departures_4yr/HORIZON) }

# ---- baseline age vectors: PRIMARY vs CONSISTENT-DEFINITION -----------------
ages_primary <- split((coh %>% filter(ret==FALSE, !is.na(age)))$age,
                      (coh %>% filter(ret==FALSE, !is.na(age)))$ab)
ages_primary$URPS <- c(V3_ABOG, abu_age$age)

# #3 consistent: active in 2025 = NOT departed under the anchored rule by 2025
consistent <- coh %>% filter((is.na(ry) | ry > YEAR0), !is.na(age))
ages_consist <- split(consistent$age, consistent$ab)
ages_consist$URPS <- c(V3_ABOG, abu_age$age)   # ABU net-new carry (no departure signal)

# ============================================================================
# (#3) CONSISTENT-DEFINITION BASELINE SENSITIVITY
# ============================================================================
b3 <- do.call(rbind, lapply(PRIMARY, function(k){
  bp <- length(ages_primary[[k]]); bc3 <- length(ages_consist[[k]])
  pp <- project(ages_primary[[k]], ENTRANTS[[k]]); pc <- project(ages_consist[[k]], ENTRANTS[[k]])
  data.frame(subspecialty_abbrev=k,
    baseline_primary=bp, baseline_consistent=bc3,
    baseline_delta=bc3-bp, baseline_pct_change=round(100*(bc3-bp)/bp,1),
    ratio_primary=round(ENTRANTS[[k]]/(pp$departures_4yr/HORIZON),2),
    ratio_consistent=round(ENTRANTS[[k]]/(pc$departures_4yr/HORIZON),2),
    projected_2029_primary=round(pp$active_2029), projected_2029_consistent=round(pc$active_2029),
    stringsAsFactors=FALSE)
}))
attr(b3,"provenance") <- sprintf("consistent-definition (anchored) 2025 baseline; anchor=cliff/data/departure_anchor.csv; %s",
                                 format(Sys.time()))
write_csv(b3, here::here("data","consistent_definition_baseline_sensitivity.csv"))
cat("\n#3 CONSISTENT-DEFINITION BASELINE (reconcile primary to SSOT):\n"); print(b3)

# ============================================================================
# (#2) AGE-SPECIFIC MORTALITY SENSITIVITY
# ============================================================================
LT_PATH <- here::here("data","ssa_period_life_table_2020.csv")
stopifnot(file.exists(LT_PATH))
lt <- read_csv(LT_PATH, comment="#", show_col_types=FALSE)
qx_of <- function(age, sex){
  age <- pmin(pmax(age, min(lt$age)), max(lt$age))
  m <- lt$male_qx[match(age, lt$age)]; f <- lt$female_qx[match(age, lt$age)]
  ifelse(is.na(sex), (m+f)/2, ifelse(sex=="M", m, f))   # unknown sex -> blended
}
# active ABOG rows with sex + age (primary baseline definition)
act <- coh %>% filter(ret==FALSE, !is.na(age))
# ABU net-new: sex unknown -> urology is predominantly male; use male q(x) (conservative, higher mortality)
abu_rows <- data.frame(ab="URPS", age=abu_age$age, sex="M")
act2 <- bind_rows(act %>% select(ab, age, sex), abu_rows)
act2$qx <- qx_of(act2$age, act2$sex)

b2 <- do.call(rbind, lapply(PRIMARY, function(k){
  ages <- ages_primary[[k]]
  d <- project(ages, ENTRANTS[[k]]); avg_dep <- d$departures_4yr/HORIZON
  exp_deaths <- sum(act2$qx[act2$ab==k])                      # expected deaths/yr in active stock
  # mortality-augmented age-band hazard: add band-mean q(x) to each band hazard
  bq <- tapply(act2$qx[act2$ab==k], band_of(act2$age[act2$ab==k]), mean)
  HAZ_m <- HAZ; for(bn in names(HAZ_m)) if(!is.na(bq[bn])) HAZ_m[bn] <- pmin(1, HAZ_m[bn] + bq[bn])
  dm <- project(ages, ENTRANTS[[k]], HAZ_m)
  data.frame(subspecialty_abbrev=k, n_active=length(ages),
    departures_primary=round(avg_dep,1),
    expected_mortality_per_yr=round(exp_deaths,1),
    departures_adj_all_missed=round(avg_dep+exp_deaths,1),
    departures_adj_half_missed=round(avg_dep+0.5*exp_deaths,1),
    rate_primary_pct=round(100*avg_dep/length(ages),2),
    rate_adj_all_pct=round(100*(avg_dep+exp_deaths)/length(ages),2),
    ratio_primary=round(ENTRANTS[[k]]/avg_dep,2),
    ratio_adj_all_missed=round(ENTRANTS[[k]]/(avg_dep+exp_deaths),2),
    ratio_adj_half_missed=round(ENTRANTS[[k]]/(avg_dep+0.5*exp_deaths),2),
    projected_2029_primary=round(d$active_2029),
    projected_2029_mortality_adj=round(dm$active_2029),
    stringsAsFactors=FALSE)
}))
attr(b2,"provenance") <- sprintf("SSA Period Life Table 2020; sex-specific q(x); ABU=male; %s", format(Sys.time()))
write_csv(b2, here::here("data","mortality_sensitivity.csv"))
cat("\n#2 AGE-SPECIFIC MORTALITY SENSITIVITY:\n"); print(b2)
cat("\nDONE\n")
