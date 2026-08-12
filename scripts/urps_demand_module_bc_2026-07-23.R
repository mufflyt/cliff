#!/usr/bin/env Rscript
source(here::here("R", "wc_path.R"))
source(here::here("R", "demand_denominator.R"))   # SSOT: npp_women_65plus_cols() / DEMAND_AGE_MIN
source(here::here("R", "in_model_baseline.R"))    # SSOT: inmodel() active-baseline cohort filter
# ACS Module B (procedure-based demand) + C (empirical plasticity/attribution)
# for urogynecology, national, 2025-2050.
#   B: observed 2024 Medicare volume per core service -> per-capita rate on women
#      65+ -> projected with Census 2023 female-65+ population.
#   C: urogyn-attributable share = fraction of each service currently performed by
#      our board-certified cohort (EMPIRICAL), with low/mid/high scenarios.
#   Required FTE = attributable demand / observed procedures-per-active-urogyn
#      (demand and productivity both on the Medicare basis, so the all-payer
#      undercount largely cancels in the adequacy ratio).
suppressPackageStartupMessages({library(DBI); library(duckdb); library(data.table)})
# census NPP files resolved via npp_projection_path() (R/demand_denominator.R)
sq <- function(v) paste0("(", paste0("'", v, "'", collapse=","), ")")

con <- dbConnect(duckdb(), wc_duckdb_path(), read_only=TRUE)
on.exit(dbDisconnect(con, shutdown=TRUE))
abu <- fread("data/abu_all_urps_ENRICHED_2026-07-22.csv", colClasses=list(character="npi"))
abog<- fread("data/abog_all_urps_ENRICHED_2026-07-22.csv",colClasses=list(character="npi"))
coh <- unique(c(as.character(abu$npi[inmodel(abu$in_model_baseline)]),
                as.character(abog$npi[inmodel(abog$in_model_baseline)])))
dbWriteTable(con, "coh", data.frame(npi=coh), temporary=TRUE, overwrite=TRUE)

grp <- list(
  sling       = "57288",
  prolapse    = c("57240","57250","57260","57265","57267","57282","57283","57284","57285"),
  urodynamics = c("51728","51729","51784","51741","51797","51798","51785","51726","51727"),
  oab_botox   = "52287",
  pessary     = c("57160","A4562"),
  neuromod    = c("64561","64581","64585","64590"))

vol <- rbindlist(lapply(names(grp), function(g){
  cds <- sq(grp[[g]])
  q <- function(extra) dbGetQuery(con, sprintf(
    "SELECT CAST(SUM(Tot_Srvcs) AS INT) n, SUM(Tot_Srvcs*Avg_Mdcr_Alowd_Amt) usd
     FROM medicare_part_b_by_service_2024 WHERE HCPCS_Cd IN %s %s", cds, extra))
  natl <- q(""); cohv <- q("AND CAST(Rndrng_NPI AS VARCHAR) IN (SELECT npi FROM coh)")
  data.table(service=g, national_2024=natl$n, cohort_2024=cohv$n, count_share=cohv$n/natl$n,
             national_usd=natl$usd, cohort_usd=cohv$usd, usd_share=cohv$usd/natl$usd)
}))
n_proc <- dbGetQuery(con, sprintf("SELECT COUNT(DISTINCT CAST(Rndrng_NPI AS VARCHAR)) n FROM medicare_part_b_by_service_2024 WHERE CAST(Rndrng_NPI AS VARCHAR) IN (SELECT npi FROM coh) AND HCPCS_Cd IN %s", sq(unlist(grp))))$n
usd_per_fte <- sum(vol$cohort_usd)/n_proc   # work-unit (allowed-$) throughput per procedurally-active urogyn

cat("== Core urogyn services, Medicare 2024 (Module C: empirical attribution) ==\n")
print(vol[, .(service, national_2024, cohort_2024, urogyn_share=round(count_share,3),
              natl_work_usd_M=round(national_usd/1e6,1), urogyn_work_share=round(usd_share,3))])
cat(sprintf("Procedurally-active urogyns: %d; work-units (allowed $) per FTE: $%s\n\n",
    n_proc, format(round(usd_per_fte), big.mark=",")))

## ── Women 65+ per year (Census 2023 mid) + supply from prior model ──────────
fem <- npp_total_female(fread(npp_projection_path("mid")))   # SSOT: total-female NPP rows + path (R/demand_denominator.R)
w65 <- fem[, .(women65 = rowSums(.SD)), by=YEAR, .SDcols=npp_women_65plus_cols()]
w65_2024 <- w65[YEAR==DEMAND_REBASE_YEAR]$women65   # SSOT: demographic rebase year (R/demand_denominator.R)
supply <- fread("data/urps_supply_demand_national_2026-07-23.csv")[, .(YEAR, supply, supply_lo, supply_hi)]

## ── Module B: project each service, Module C: attribute + scenarios ─────────
yrs <- PROJECTION_BASELINE_YEAR:DEMAND_HORIZON_END_YEAR   # SSOT horizon span (R/demand_denominator.R)
proj <- data.table(YEAR=yrs, women65=w65[match(yrs,YEAR)]$women65)
proj[, growth := women65/w65_2024]
# Module C attribution-plasticity SCENARIOS (SSOT for this file): multiply each service's observed urogyn
# share by these factors. mid=1.0 (as-observed), low/high = +/-20% sensitivity on the attributable share.
# ONE definition drives BOTH the procedure-count projection and the required-FTE loop below, so the two can
# never disagree. The three values are distinct scenarios (do NOT collapse); the +/-0.2 is a deliberate band.
URPS_ATTRIB_MULT <- c(mid = 1.0, low = 0.8, high = 1.2)
stopifnot(identical(names(URPS_ATTRIB_MULT), c("mid","low","high")),
          URPS_ATTRIB_MULT[["mid"]] == 1.0,
          URPS_ATTRIB_MULT[["low"]] < URPS_ATTRIB_MULT[["mid"]],
          URPS_ATTRIB_MULT[["high"]] > URPS_ATTRIB_MULT[["mid"]])
# urogyn-attributable PROCEDURE COUNT (reporting) and WORK ($, for FTE), scaled by 65+ growth
attr_proc <- function(mult) round(sum(vol$national_2024*pmin(vol$count_share*mult,1))*proj$growth)
attr_work <- function(mult)       sum(vol$national_usd*pmin(vol$usd_share*mult,1))*proj$growth
proj[, urogyn_procedures_mid := attr_proc(URPS_ATTRIB_MULT[["mid"]])]
proj[, urogyn_procedures_low := attr_proc(URPS_ATTRIB_MULT[["low"]])]
proj[, urogyn_procedures_high:= attr_proc(URPS_ATTRIB_MULT[["high"]])]
# required FTE = attributable WORK ($) / work-per-FTE  (both Medicare $, so all-payer bias largely cancels)
for (s in c("mid","low","high")){
  m <- URPS_ATTRIB_MULT[[s]]
  proj[[paste0("required_fte_",s)]] <- round(attr_work(m)/usd_per_fte)
}
# adequacy = supply / required (mid supply vs mid demand; plus bounds)
proj <- merge(proj, supply, by="YEAR")
proj[, adequacy_mid  := round(supply/required_fte_mid,2)]
proj[, adequacy_low  := round(supply_lo/required_fte_high,2)]   # worst: low supply / high demand
proj[, adequacy_high := round(supply_hi/required_fte_low,2)]    # best:  high supply / low demand

fwrite(proj, "data/urps_demand_module_bc_2026-07-23.csv")
cat("Wrote data/urps_demand_module_bc_2026-07-23.csv\n\n")
show <- proj[YEAR %in% seq(PROJECTION_BASELINE_YEAR, DEMAND_HORIZON_END_YEAR, 5L)]
print(show[, .(YEAR, women65_M=round(women65/1e6,1), urogyn_procedures_mid, required_fte_mid, supply,
               adequacy=adequacy_mid, adeq_band=paste0(adequacy_low,"-",adequacy_high))])
cat(sprintf("\nRequired urogyn FTEs (mid): %d (2025) -> %d (2050); supply %d -> %d\n",
    proj[YEAR==2025]$required_fte_mid, proj[YEAR==DEMAND_HORIZON_END_YEAR]$required_fte_mid,
    proj[YEAR==2025]$supply, proj[YEAR==DEMAND_HORIZON_END_YEAR]$supply))
cat(sprintf("Adequacy (supply/required, mid): %.2f (2025) -> %.2f (2050); 2050 band %.2f-%.2f\n",
    proj[YEAR==2025]$adequacy_mid, proj[YEAR==DEMAND_HORIZON_END_YEAR]$adequacy_mid,
    proj[YEAR==DEMAND_HORIZON_END_YEAR]$adequacy_low, proj[YEAR==DEMAND_HORIZON_END_YEAR]$adequacy_high))
saveRDS(list(vol=vol, usd_per_fte=usd_per_fte, n_proc=n_proc), "data/urps_module_bc_meta_2026-07-23.rds")
