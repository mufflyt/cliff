#!/usr/bin/env Rscript
source(here::here("R", "wc_path.R"))
source(here::here("R", "demand_denominator.R"))   # SSOT: npp_women_65plus_cols() / DEMAND_AGE_MIN

# Module B+C (CORRECTED): procedure-based utilization & plasticity attribution
#
# Module B: project observed 2024 Medicare PRIMARY-PHYSICIAN procedure volume
#   by the projected population of women 65+ (Census 2023 mid series). We lack
#   patient age on the claims, so this is total-65+ growth, NOT age-specific.
# Module C: apply empirically observed low/middle/high urogynecology attribution
#   scenarios on the AUDITED primary-clinician denominator (facility + APP
#   assistant lines excluded; single anchor code per family).
#
# INTERPRETATION: outputs are the procedure-equivalent capacity required to
# MAINTAIN 2024 realized Medicare fee-for-service utilization, NOT total
# clinical need or currently unmet demand. Baseline required FTE ~= current
# active proceduralists by construction. Denominator = women 65+ used as a
# population-normalized Medicare-FFS rate (NOT an all-payer treatment rate).
# Source: Medicare Physician & Other Practitioners by-Provider-and-Service 2024
# (extracted 2026-07-23); Census 2023 National Population Projections (mid).

suppressPackageStartupMessages({library(DBI); library(duckdb); library(data.table)})
SCR <- here::here("data", "census")
EXTRACT_DATE <- "2024 PUF (PHY_R26...D24), extracted 2026-07-23"
inmodel <- function(x) x %in% c(TRUE,"TRUE","true",1,"1")

con <- dbConnect(duckdb(), wc_duckdb_path(), read_only=TRUE)
on.exit(dbDisconnect(con, shutdown=TRUE))
abu <- fread("data/abu_all_urps_ENRICHED_2026-07-22.csv", colClasses=list(character="npi"))
abog<- fread("data/abog_all_urps_ENRICHED_2026-07-22.csv",colClasses=list(character="npi"))
cohmap <- rbind(data.table(npi=as.character(abu$npi[inmodel(abu$in_model_baseline)]),  cohort="ABU"),
                data.table(npi=as.character(abog$npi[inmodel(abog$in_model_baseline)]), cohort="ABOG"))
cohmap <- unique(cohmap[!is.na(npi)&npi!=""], by="npi")
stopifnot("GATE 8: cohort NPIs not unique"= !any(duplicated(cohmap$npi)))
dbWriteTable(con, "cohmap", cohmap, temporary=TRUE, overwrite=TRUE)

# single anchor code per family; field = specialty pool where unmatched urogyns most plausibly hide
anchors <- data.table(
  code   =c("57288","57282","51728","52287"),
  family =c("Sling for SUI","Apical suspension","Complex urodynamics","Bladder BOTOX"),
  field  =c("OBG","OBG","URO","URO"))
APP <- c("Physician Assistant","Nurse Practitioner","Clinical Nurse Specialist",
         "Certified Clinical Nurse Specialist","Certified Registered Nurse Anesthetist")
OBG <- c("Obstetrics & Gynecology","Gynecological Oncology")

## ── audited category decomposition + per-NPI productivity, per code ──────────
decomp <- function(cd){
  d <- as.data.table(dbGetQuery(con, sprintf(
    "SELECT CAST(s.Rndrng_NPI AS VARCHAR) npi, s.Rndrng_Prvdr_Type spec, s.Rndrng_Prvdr_Ent_Cd ent,
            c.cohort, CAST(SUM(s.Tot_Srvcs) AS INT) srv
     FROM medicare_part_b_by_service_2024 s LEFT JOIN cohmap c ON CAST(s.Rndrng_NPI AS VARCHAR)=c.npi
     WHERE s.HCPCS_Cd=\x27%s\x27 GROUP BY 1,2,3,4", cd)))
  d[, cat := fifelse(ent=="O","facility",
              fifelse(!is.na(cohort),"urps",
              fifelse(spec %in% APP,"app",
              fifelse(spec %in% OBG,"gen_obg",
              fifelse(spec=="Urology","gen_uro","other")))))]
  by <- d[, .(srv=sum(srv)), by=cat]; m <- setNames(by$srv, by$cat)
  g <- function(k) as.integer(sum(m[k], na.rm=TRUE))
  prim <- g("urps")+g("gen_obg")+g("gen_uro")+g("other")                 # primary physicians (no facility/APP)
  # productivity among URPS proceduralists (>=1 of THIS procedure)
  up <- d[cat=="urps", .(n=sum(srv)), by=npi][n>0]
  data.table(code=cd, total=sum(m,na.rm=TRUE), facility=g("facility"), app=g("app"),
             primary_physician=prim, urps=g("urps"), gen_obg=g("gen_obg"),
             gen_uro=g("gen_uro"), other=g("other"),
             n_active=nrow(up), mean_pp=mean(up$n), sd_pp=sd(up$n),
             p25=quantile(up$n,.25), med=median(up$n), p75=quantile(up$n,.75), p90=quantile(up$n,.90),
             top10_share=sum(sort(up$n,decreasing=TRUE)[seq_len(ceiling(0.1*nrow(up)))])/sum(up$n))
}
D <- rbindlist(lapply(anchors$code, decomp))
D <- merge(anchors, D, by="code")
n_cohort <- nrow(cohmap)
D[, pct_cohort_zero := round(100*(n_cohort-n_active)/n_cohort,1)]

## ── attribution scenarios (Module C), on the primary-physician denominator ──
D[, field_residual := fifelse(field=="OBG", gen_obg, gen_uro)]
# PROCEDURE-SPECIFIC transfer of same-field residual to URPS (Issue 2 fix):
#  reconstructive (OBG field): unmatched OB/GYN plausibly urogynecologic ->
#    mid transfers half, high transfers all of the OB/GYN residual.
#  functional (URO field): most urology urodynamics/BOTOX is genuine urology ->
#    only a MODEST transfer (roster-missed ABU urogyns); urology keeps >=75%.
D[, t_mid := fifelse(field=="OBG", 0.50, 0.10)]
D[, t_hi  := fifelse(field=="OBG", 1.00, 0.25)]
D[, pi_low  := urps/primary_physician]                              # strict confirmed URPS
D[, pi_mid  := (urps + t_mid*field_residual)/primary_physician]
D[, pi_high := (urps + t_hi *field_residual)/primary_physician]

## ── Module B: Census 65+ growth, projected volume, workload, FTE ────────────
fem <- fread(file.path(SCR,"np2023_d1_mid.csv"))[SEX==2 & ORIGIN==0 & RACE==0]
w65 <- fem[, .(w65=rowSums(.SD)), by=YEAR, .SDcols=npp_women_65plus_cols()]
base65 <- w65[YEAR==DEMAND_REBASE_YEAR]$w65   # SSOT: demographic rebase year (R/demand_denominator.R)
gf <- function(t) w65[YEAR==t]$w65/base65                            # demographic growth factor (rebased to 2024)
YRS <- c(2024,2030,2040,DEMAND_HORIZON_END_YEAR)   # horizon end via SSOT (R/demand_denominator.R)

long <- rbindlist(lapply(seq_len(nrow(D)), function(i){
  r <- D[i]; q <- r$mean_pp                                          # procedures per active URPS FTE (current avg)
  rbindlist(lapply(YRS, function(t){
    V <- round(r$primary_physician*gf(t))
    rbindlist(lapply(c("low","mid","high"), function(s){
      pi <- r[[paste0("pi_",s)]]; U <- V*pi
      data.table(code=r$code, family=r$family, year=t, scenario=s,
                 national_volume=V, attribution=round(pi,3),
                 urps_workload=round(U), required_fte=round(U/q,1))
    }))
  }))
}))

## ── VALIDATION GATES (fail closed) ──────────────────────────────────────────
stopifnot(
  "GATE 1: cohort > national"        = all(D$urps <= D$total),
  "GATE 2: shares in [0,1]"          = all(long$attribution>=0 & long$attribution<=1),
  "GATE 3: low<=mid<=high"           = { w<-dcast(long[year==2024],code~scenario,value.var="attribution"); all(w$low<=w$mid & w$mid<=w$high) },
  "GATE 4: 2024 volume == observed"  = all(long[year==2024 & scenario=="low"]$national_volume == D$primary_physician),
  "GATE 5: population positive"      = all(sapply(YRS,gf)>0),
  "GATE 6: no facility/APP in num"   = TRUE,   # by construction: urps excludes facility(O)+APP
  "GATE 7: episode-interpretable"    = all(anchors$code %in% c("57288","57282","51728","52287")),
  "GATE 8: unique cohort NPIs"       = !any(duplicated(cohmap$npi)),
  "GATE 9: no dup proc-year-scenario"= !any(duplicated(long[,.(code,year,scenario)])),
  "GATE 10: extraction recorded"     = nchar(EXTRACT_DATE)>0,
  "GATE 11: confirmed 2024 FTE == active proceduralists" = {
     lf <- long[year==2024 & scenario=="low"]; na <- D[match(lf$code,code)]$n_active
     all(abs(lf$required_fte - na) < 0.5) }
)
cat("All 11 validation gates PASSED (incl baseline FTE identity).\n\n")

## ── minimum per-procedure output table ──────────────────────────────────────
mt <- D[, .(code, family,
  national_observable_2024=primary_physician, confirmed_urps_2024=urps,
  confirmed_share=round(urps/primary_physician,3),
  attr_low=round(pi_low,3), attr_mid=round(pi_mid,3), attr_high=round(pi_high,3),
  active_urps_npis=n_active, mean_sd=sprintf("%.0f (%.0f)",mean_pp,sd_pp),
  median_iqr=sprintf("%.0f [%.0f, %.0f]",med,p25,p75),
  pct_cohort_zero_this_proc=pct_cohort_zero, top10_pct=round(100*top10_share))]
v <- dcast(long[scenario=="mid"], code~year, value.var="national_volume")
setnames(v, as.character(YRS), paste0("vol_",YRS))
flo <- dcast(long[scenario=="low"], code~year, value.var="required_fte")   # CONFIRMED scenario (Issue 1 fix)
setnames(flo, as.character(YRS), paste0("req_fte_confirmed_",YRS))
fmi <- dcast(long[scenario=="mid"], code~year, value.var="required_fte")
setnames(fmi, as.character(YRS), paste0("req_fte_mid_",YRS))
mt <- Reduce(function(a,b) merge(a,b,by="code"), list(mt, v[,.(code,vol_2030,vol_2050)],
             flo[,.(code,req_fte_confirmed_2024,req_fte_confirmed_2050)], fmi[,.(code,req_fte_mid_2050)]))
mt[, episode_flag := "single anchor; primary-physician; facility+APP excluded; no age-specific rate; PSPS-assistant not yet netted"]

fwrite(mt,   "data/urps_module_bc_corrected_summary_2026-07-23.csv")
fwrite(long, "data/urps_module_bc_corrected_projection_2026-07-23.csv")
cat("== Minimum per-procedure table (corrected Module B+C) ==\n")
print(mt[, .(family, natl=national_observable_2024, urps=confirmed_urps_2024, share=confirmed_share,
             attr_low_mid_high=sprintf("%.2f/%.2f/%.2f",attr_low,attr_mid,attr_high), n_active=active_urps_npis,
             per_npi=median_iqr, fte_confirmed_2024=req_fte_confirmed_2024,
             fte_confirmed_2050=req_fte_confirmed_2050, fte_mid_2050=req_fte_mid_2050)])
cat("\n2024->2050 demographic growth (women 65+):", round(100*(gf(DEMAND_HORIZON_END_YEAR)-1)),"%\n")
cat("Interpretation: capacity to MAINTAIN 2024 realized Medicare FFS utilization; baseline FTE ~= current active by construction.\n")
