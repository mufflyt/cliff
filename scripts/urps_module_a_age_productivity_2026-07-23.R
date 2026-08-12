#!/usr/bin/env Rscript
source(here::here("R", "wc_path.R"))
source(here::here("R", "workforce_constants.R"))   # SSOT: WORKFORCE_OBSERVED_START_YEAR (2013)
source(here::here("R", "in_model_baseline.R"))     # SSOT: inmodel() active-baseline cohort filter
# Module A, step 1: within-physician AGE-PRODUCTIVITY curve for URPS, 2013-2024.
# Panel: each cohort NPI x year -> urogyn procedure WORKLOAD (allowed $, a work
# proxy) across the 89 FPMRS-defining codes. Model:
#   log(Y_it + 1) ~ ns(age) + factor(year) + (1|npi)
# The physician random/fixed effect isolates how the SAME physician's Medicare
# workload changes with age (ACS "declining capacity before formal retirement"),
# net of calendar-year shocks (COVID 2020). Medicare FFS only; allowed-$ weighted.
suppressPackageStartupMessages({library(DBI); library(duckdb); library(data.table); library(yaml); library(splines); library(lme4)})
codes <- vapply(yaml::read_yaml("config/subspecialty_hcpcs_codes.yml")$
                female_pelvic_medicine_reconstructive_surgery$codes, function(x) as.character(x$code), character(1))

con <- dbConnect(duckdb(), wc_duckdb_path(), read_only=TRUE)
on.exit(dbDisconnect(con, shutdown=TRUE))
abu <- fread("data/abu_all_urps_ENRICHED_2026-07-22.csv", colClasses=list(character="npi"))
abog<- fread("data/abog_all_urps_ENRICHED_2026-07-22.csv",colClasses=list(character="npi"))
# age in 2024 (graduation-year age; certification-proxy fallback) -> birth year
ages <- rbind(abu[inmodel(in_model_baseline), .(npi=as.character(npi), age24=fifelse(!is.na(age_from_grad_year),as.numeric(age_from_grad_year),as.numeric(age_proxy_from_cert)))],
              abog[inmodel(in_model_baseline),.(npi=as.character(npi), age24=fifelse(!is.na(age_from_grad_year),as.numeric(age_from_grad_year),as.numeric(age_proxy_from_cert)))])
ages <- unique(ages[!is.na(age24)], by="npi"); ages[, birth := WORKFORCE_REFERENCE_YEAR-age24]   # SSOT: age reckoned as-of the reference year
dbWriteTable(con, "coh", ages[,.(npi,birth)], temporary=TRUE, overwrite=TRUE)

## ── build the panel: cohort x year urogyn workload (allowed $) ───────────────
cds <- paste0("(", paste0("'", codes, "'", collapse=","), ")")
yrs <- WORKFORCE_OBSERVED_START_YEAR:WORKFORCE_REFERENCE_YEAR   # SSOT: observed start .. latest-Medicare/reference year (distinct from the 2023 study-scope end)
panel <- rbindlist(lapply(yrs, function(y){
  t <- paste0("medicare_part_b_by_service_", y)
  if (!(t %in% dbListTables(con))) return(NULL)
  as.data.table(dbGetQuery(con, sprintf("
    SELECT CAST(s.Rndrng_NPI AS VARCHAR) npi, %d AS year,
           SUM(s.Tot_Srvcs*s.Avg_Mdcr_Alowd_Amt) work_usd, CAST(SUM(s.Tot_Srvcs) AS INT) procs
    FROM %s s JOIN coh c ON CAST(s.Rndrng_NPI AS VARCHAR)=c.npi
    WHERE s.HCPCS_Cd IN %s GROUP BY 1,2", y, t, cds)))
}))
panel <- merge(panel, ages[,.(npi,birth)], by="npi")
panel[, age := year-birth]
panel <- panel[age>=30 & age<=80 & work_usd>0]
panel[, lY := log(work_usd+1)]
cat(sprintf("Panel: %d physician-years, %d physicians, years %d-%d\n",
            nrow(panel), uniqueN(panel$npi), min(panel$year), max(panel$year)))

## ── fit within-physician age curve ──────────────────────────────────────────
m <- lmer(lY ~ ns(age, df=4) + factor(year) + (1|npi), data=panel, REML=FALSE)
grid <- data.table(age=35:75, year=2019L)                     # hold year fixed (pre-COVID reference)
grid[, pred_lY := predict(m, newdata=grid, re.form=NA)]
grid[, work_usd := exp(pred_lY)-1]
peak <- grid[which.max(work_usd)]
grid[, rel_to_peak := round(work_usd/peak$work_usd,3)]
cat(sprintf("\nPeak urogyn Medicare workload at age %d ($%s allowed/yr).\n", peak$age, format(round(peak$work_usd),big.mark=",")))
cat("Relative workload by age (fraction of peak, within-physician, year-adjusted):\n")
for (a in c(35,40,45,50,55,60,65,70,75)) cat(sprintf("  age %d: %.2f\n", a, grid[age==a]$rel_to_peak))
# calendar-year (COVID) effects
ye <- data.table(year=yrs); ye[, eff := c(0, fixef(m)[grep("factor\\(year\\)", names(fixef(m)))])]
cat(sprintf("\n2020 (COVID) calendar effect vs 2013: %.2f log-points (%.0f%% workload)\n",
            ye[year==2020]$eff, 100*exp(ye[year==2020]$eff)))
fwrite(grid[,.(age,rel_to_peak,work_usd=round(work_usd))], "data/urps_module_a_age_productivity_2026-07-23.csv")
cat("\nWrote data/urps_module_a_age_productivity_2026-07-23.csv\n")
