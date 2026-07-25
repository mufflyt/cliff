#!/usr/bin/env Rscript
source(here::here("R", "wc_path.R"))
# URPS national SUPPLY vs DEMAND projection, 2025-2050.
#   DEMAND: U.S. Census 2023 National Population Projections (mid series), female
#     population by age x year, x age-specific PFD prevalence (Nygaard 2008,
#     JAMA; NHANES symptomatic >=1 pelvic floor disorder). Headline denominator
#     = women 65+.
#   SUPPLY: the study workforce engine (URPS active-age distribution + partial-
#     pooled age-band departure hazard + 64 entrants/yr at age 34), projected
#     forward from the 1,339 active baseline.
suppressPackageStartupMessages({library(data.table)})
# census NPP files resolved via npp_projection_path() (R/demand_denominator.R)
source("shiny_urps_scenarios/urps_model_data.R")  # URPS_AGES, BAND_EV, BAND_PY, BAND_LABELS

## ── DEMAND: Census female population by age band, per year (mid + low/high) ──
agecols <- sprintf("POP_%d", 0:100)
# age-specific PFD prevalence (Nygaard 2008 JAMA, NHANES; >=1 symptomatic PFD)
source(here::here("R","pfd_prevalence.R"))   # SSOT: age-specific PFD prevalence (Nygaard 2008)
source(here::here("R","demand_denominator.R"))   # SSOT: DEMAND_INDEX_BASE_YEAR (reporting index base)
source(here::here("R","units.R"))                # SSOT: RATE_PER_100K
prev <- pfd_prevalence_by_age
pw <- prev(0:100)
demand_series <- function(file){
  fem <- npp_total_female(fread(file))   # SSOT: total-female NPP rows (R/demand_denominator.R)
  fem[, {pop <- as.numeric(.SD)
    list(women_65plus=sum(pop[66:101]), women_40plus=sum(pop[41:101]), women_with_pfd=sum(pop*pw))},
    by=YEAR, .SDcols=agecols]
}
dm <- demand_series(npp_projection_path("mid"))
dl <- demand_series(npp_projection_path("low"))
dh <- demand_series(npp_projection_path("hi"))
demand <- dm[dl[,.(YEAR,w65_lo=women_65plus,pfd_lo=women_with_pfd)], on="YEAR"][
              dh[,.(YEAR,w65_hi=women_65plus,pfd_hi=women_with_pfd)], on="YEAR"]

## ── SUPPLY: project the workforce engine forward ────────────────────────────
BANDS <- c(0,45,50,55,60,65,70,Inf)
band_of <- function(age) as.character(cut(age,breaks=BANDS,labels=BAND_LABELS,right=FALSE))
hz <- {ev<-BAND_EV[["fully_obs"]]; py<-BAND_PY[["fully_obs"]]; h<-ifelse(py>0,ev/py,NA); h[is.na(h)]<-max(h,na.rm=T); h<-pmin(1,h); names(h)<-BAND_LABELS; h}  # re-name AFTER pmin (pmin strips names)
haz_for <- function(age,hz){h<-hz[band_of(age)]; h[is.na(h)]<-max(hz,na.rm=T); pmin(1,h)}
project <- function(ages, entrants, hz, horizon, entry_age=34L){
  count<-table(ages); av<-as.integer(names(count)); count<-as.numeric(count)
  traj<-numeric(horizon+1); traj[1]<-sum(count)
  for(h in seq_len(horizon)){ hzz<-haz_for(av,hz); sv<-count*(1-hzz)
    av2<-av+1L; ix<-match(entry_age,av2)
    if(is.na(ix)){av2<-c(av2,entry_age); sv<-c(sv,entrants)} else sv[ix]<-sv[ix]+entrants
    av<-av2; count<-sv; traj[h+1]<-sum(count) }
  traj }
HORIZON <- 2050-2025
ENTRANTS <- mean(GRAD_URPS)   # SSOT: URPS entrant inflow = mean of the ACGME graduate counts (matches module_a, iter7); never hardcode 64
supply_mid <- project(URPS_AGES, ENTRANTS, hz, HORIZON)
# Monte Carlo the departure hazard (Beta posterior on the age-band events/PY,
# matching the app's interval method) -> a distribution of supply trajectories.
set.seed(20260723L)
ev <- BAND_EV[["fully_obs"]]; py <- BAND_PY[["fully_obs"]]
N <- 2000L
mc <- matrix(NA_real_, nrow=N, ncol=HORIZON+1)
for (i in seq_len(N)) {
  hb <- stats::rbeta(length(ev), ev+0.5, pmax(py-ev,0)+0.5)
  hb[py==0] <- max(hb[py>0], na.rm=TRUE); hb <- pmin(1,hb); names(hb) <- BAND_LABELS
  mc[i,] <- project(URPS_AGES, ENTRANTS, hb, HORIZON)
}
supply <- data.table(YEAR=PROJECTION_BASELINE_YEAR:DEMAND_HORIZON_END_YEAR, supply=round(supply_mid),
                     supply_lo=round(apply(mc,2,quantile,0.025)),
                     supply_hi=round(apply(mc,2,quantile,0.975)))

## ── Combine + metrics ───────────────────────────────────────────────────────
sd <- merge(supply, demand, by="YEAR")
sd[, urogyn_per_100k_w65    := round(RATE_PER_100K*supply/women_65plus, 2)]
sd[, per100k_lo := round(RATE_PER_100K*supply_lo/w65_hi, 2)]     # worst case: low supply / high demand
sd[, per100k_hi := round(RATE_PER_100K*supply_hi/w65_lo, 2)]     # best case:  high supply / low demand
sd[, women_pfd_per_urogyn   := round(women_with_pfd/supply)]
# index vs mid-2025 baseline (bands share the same denominator so the fan is honest)
b <- sd[YEAR==DEMAND_INDEX_BASE_YEAR]   # SSOT: reporting index base (R/demand_denominator.R)
sd[, supply_index    := round(100*supply/b$supply,1)]
sd[, supply_lo_index := round(100*supply_lo/b$supply,1)]
sd[, supply_hi_index := round(100*supply_hi/b$supply,1)]
sd[, w65_index    := round(100*women_65plus/b$women_65plus,1)]
sd[, w65_lo_index := round(100*w65_lo/b$women_65plus,1)]
sd[, w65_hi_index := round(100*w65_hi/b$women_65plus,1)]
sd[, pfd_index    := round(100*women_with_pfd/b$women_with_pfd,1)]
sd[, pfd_lo_index := round(100*pfd_lo/b$women_with_pfd,1)]
sd[, pfd_hi_index := round(100*pfd_hi/b$women_with_pfd,1)]

fwrite(sd, "data/urps_supply_demand_national_2026-07-23.csv")
cat("Wrote data/urps_supply_demand_national_2026-07-23.csv\n\n")
show <- sd[YEAR %in% seq(PROJECTION_BASELINE_YEAR, DEMAND_HORIZON_END_YEAR, 5L)]
print(show[, .(YEAR, supply, women_65plus=round(women_65plus/1e6,1),
               women_with_pfd=round(women_with_pfd/1e6,1),
               per_100k_w65=urogyn_per_100k_w65, pfd_per_urogyn=women_pfd_per_urogyn,
               supply_idx=supply_index, w65_idx=w65_index)])
cat(sprintf("\n2025->2050: supply %+.0f%%, women 65+ %+.0f%%, women with PFD %+.0f%%\n",
    sd[YEAR==DEMAND_HORIZON_END_YEAR]$supply_index-100, sd[YEAR==DEMAND_HORIZON_END_YEAR]$w65_index-100, sd[YEAR==DEMAND_HORIZON_END_YEAR]$pfd_index-100))
cat(sprintf("Urogynecologists per 100k women 65+: %.1f (2025) -> %.1f (2050)\n",
    sd[YEAR==DEMAND_INDEX_BASE_YEAR]$urogyn_per_100k_w65, sd[YEAR==DEMAND_HORIZON_END_YEAR]$urogyn_per_100k_w65))
