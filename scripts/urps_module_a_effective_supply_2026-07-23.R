#!/usr/bin/env Rscript
# Module A, step 2 (FINISH): convert projected HEADCOUNT supply to procedure-
# equivalent EFFECTIVE-supply FTEs by weighting each projected physician-year by
# the within-physician age-productivity curve (Module A step 1). Then the
# like-for-like adequacy vs the aging-driven (women 65+) demand.
#   effective_supply(t) = sum_age count(age,t) * w(age),  w normalized so the
#   2025 workforce averages 1.0 => effective(2025) == headcount(2025).
# Headcount overstates capacity because older urogynecologists operate less.
suppressPackageStartupMessages({library(data.table)})
source("shiny_urps_scenarios/urps_model_data.R")  # URPS_AGES, BAND_EV/PY, BAND_LABELS

## ── age-productivity weight w(age), from Module A step 1 (clamped at ends) ───
apc <- fread("data/urps_module_a_age_productivity_2026-07-23.csv")   # age, rel_to_peak
wfun <- function(a){ a <- pmin(pmax(a, min(apc$age)), max(apc$age)); apc$rel_to_peak[match(a, apc$age)] }

## ── age-tracked supply projection 2025-2050 (same engine as the SSOT) ───────
BANDS <- c(0,45,50,55,60,65,70,Inf)
band_of <- function(age) as.character(cut(age,breaks=BANDS,labels=BAND_LABELS,right=FALSE))
hz <- {ev<-BAND_EV[["fully_obs"]]; py<-BAND_PY[["fully_obs"]]; hh<-ifelse(py>0,ev/py,NA); hh[is.na(hh)]<-max(hh,na.rm=T); hh<-pmin(1,hh); names(hh)<-BAND_LABELS; hh}
haz_for <- function(age,hz){h<-hz[band_of(age)]; h[is.na(h)]<-max(hz,na.rm=T); pmin(1,h)}
HORIZON <- 25L; ENTRANTS <- 64; ENTRY_AGE <- 34L
count0 <- table(URPS_AGES); av0 <- as.integer(names(count0)); count0 <- as.numeric(count0)
# normalize w so the 2025 distribution averages 1.0
wbar <- sum(count0*wfun(av0))/sum(count0); w <- function(a) wfun(a)/wbar
project_eff <- function(hzv){
  av <- av0; count <- count0; rows <- list()
  for (k in 0:HORIZON){ yr <- 2025L+k
    rows[[length(rows)+1]] <- data.table(YEAR=yr, headcount=round(sum(count)),
                                         effective=round(sum(count*w(av)),1),
                                         mean_age=round(sum(count*av)/sum(count),1))
    hzz <- haz_for(av,hzv); sv <- count*(1-hzz)
    av2 <- av+1L; ix <- match(ENTRY_AGE,av2)
    if (is.na(ix)){av2<-c(av2,ENTRY_AGE); sv<-c(sv,ENTRANTS)} else sv[ix]<-sv[ix]+ENTRANTS
    av <- av2; count <- sv }
  rbindlist(rows)
}
# PRIMARY (2026-07-23, PI decision): RETIREMENT AT AGE 65 (hard departure at 65).
hz_r65 <- hz; hz_r65["65-69"] <- 1.0; hz_r65["70+"] <- 1.0
sup <- project_eff(hz_r65)
# comparison: observed hazard (urogynecologists work past 65 as currently observed)
supObs <- project_eff(hz)
sup[, `:=`(headcount_obshazard=supObs$headcount, effective_obshazard=supObs$effective, mean_age_obshazard=supObs$mean_age)]

## ── demand driver (women 65+) + adequacy ────────────────────────────────────
dem <- fread("data/urps_supply_demand_national_2026-07-23.csv")[, .(YEAR, women_65plus)]
d <- merge(sup, dem, by="YEAR")
b <- d[YEAR==2025]
d[, headcount_index := round(100*headcount/b$headcount,1)]
d[, effective_index := round(100*effective/b$effective,1)]
d[, women65_index   := round(100*women_65plus/b$women_65plus,1)]
d[, eff_per_100k_w65 := round(1e5*effective/women_65plus,2)]
d[, head_per_100k_w65:= round(1e5*headcount/women_65plus,2)]
# adequacy = growth of supply relative to growth of the aging-driven demand (2025=1.00)
d[, adequacy_headcount := round((headcount/b$headcount)/(women_65plus/b$women_65plus),3)]
d[, adequacy_effective := round((effective/b$effective)/(women_65plus/b$women_65plus),3)]
fwrite(d, "data/urps_module_a_effective_supply_2026-07-23.csv")
cat("Wrote data/urps_module_a_effective_supply_2026-07-23.csv\n\n")
print(d[YEAR %in% c(2025,2030,2035,2040,2045,2050),
        .(YEAR, headcount, effective, mean_age, eff_per_100k_w65,
          adeq_head=adequacy_headcount, adeq_eff=adequacy_effective)])
cat(sprintf("\n2025->2050: headcount %+.0f%%, EFFECTIVE supply %+.0f%%, women65 %+.0f%%\n",
    d[YEAR==2050]$headcount_index-100, d[YEAR==2050]$effective_index-100, d[YEAR==2050]$women65_index-100))
cat(sprintf("Effective-FTE gap at 2050: %.0f FTE (%.0f%% of headcount); mean age %.1f -> %.1f\n",
    d[YEAR==2050]$headcount-d[YEAR==2050]$effective, 100*d[YEAR==2050]$effective/d[YEAR==2050]$headcount,
    b$mean_age, d[YEAR==2050]$mean_age))
cat(sprintf("Adequacy 2050: headcount %.2f vs EFFECTIVE %.2f (both 2025=1.00)\n",
    d[YEAR==2050]$adequacy_headcount, d[YEAR==2050]$adequacy_effective))
cat(sprintf("Near-term EFFECTIVE adequacy trough: %.2f in %d (dips below parity as the mid-career cohort ages toward retirement)\n",
    min(d$adequacy_effective), d[which.min(adequacy_effective)]$YEAR))
cat("(PRIMARY = retirement at age 65)\n")
# comparison: observed hazard (works past 65)
dO <- merge(sup[,.(YEAR,effective_obshazard)], dem, by="YEAR"); bO <- dO[YEAR==2025]
dO[, adeq_eff_obs := round((effective_obshazard/bO$effective_obshazard)/(women_65plus/bO$women_65plus),3)]
cat(sprintf("COMPARISON (observed hazard, works past 65): effective 2050 = %d (retire65=%d); adequacy 2050 %.2f (retire65 %.2f)\n",
    round(d[YEAR==2050]$effective_obshazard), round(d[YEAR==2050]$effective),
    dO[YEAR==2050]$adeq_eff_obs, d[YEAR==2050]$adequacy_effective))
