#!/usr/bin/env Rscript
# FORMALIZED into mufflyt/cliff from an ephemeral session scratchpad (2026-07-24).
# Large public inputs are fetched by scripts/download_enrichment_inputs.sh
# (HRSA HPSA polygons + CMS Medicare CY2024 PUF) into data/enrichment_inputs/,
# overridable via the MEDICARE_2024_CSV / HPSA_SHP env vars.
# Refresh per-physician Medicare procedure activity to CY2024 (latest CMS PUF,
# PHY_R26_P05_V10_D24_Prov_Svc.csv, released 2026-05). Queries the downloaded
# CSV directly via DuckDB read_csv_auto (no write to the shared database).
# Adds *_2024 columns alongside the *_2023 ones and prints the ABU vs ABOG split
# for the manuscript update. Same lower-bound caveats (Medicare FFS only; CMS
# suppresses provider-code cells <11 services).
suppressPackageStartupMessages({library(DBI); library(duckdb); library(data.table); library(yaml)})
source(here::here("R", "in_model_baseline.R"))   # SSOT: inmodel() active-baseline cohort filter

CSV <- Sys.getenv("MEDICARE_2024_CSV", unset = here::here("data","enrichment_inputs","medicare_prov_svc_2024.csv"))
stopifnot(file.exists(CSV))
codes <- vapply(yaml::read_yaml("config/subspecialty_hcpcs_codes.yml")$
                female_pelvic_medicine_reconstructive_surgery$codes,
                function(x) as.character(x$code), character(1))

abu  <- fread("data/abu_all_urps_ENRICHED_2026-07-22.csv",  colClasses=list(character="npi"))
abog <- fread("data/abog_all_urps_ENRICHED_2026-07-22.csv", colClasses=list(character="npi"))
npis <- unique(c(as.character(abu$npi), as.character(abog$npi))); npis <- npis[!is.na(npis)&npis!=""]

con <- dbConnect(duckdb(), ":memory:"); on.exit(dbDisconnect(con, shutdown=TRUE))
dbExecute(con, sprintf("CREATE VIEW svc AS SELECT * FROM read_csv_auto('%s', ALL_VARCHAR=TRUE)", CSV))
# confirm expected columns exist
cols <- dbListFields(con, "svc")
npi_c <- grep("Rndrng_NPI", cols, value=TRUE)[1]; hc_c <- grep("HCPCS_Cd", cols, value=TRUE)[1]
srv_c <- grep("Tot_Srvcs", cols, value=TRUE)[1]; ben_c <- grep("Tot_Benes", cols, value=TRUE)[1]
cat(sprintf("CY2024 CSV columns resolved: %s / %s / %s / %s\n", npi_c, hc_c, srv_c, ben_c))
dbWriteTable(con, "coh", data.frame(npi=npis), overwrite=TRUE)
dbWriteTable(con, "fpcodes", data.frame(code=codes), overwrite=TRUE)

agg <- as.data.table(dbGetQuery(con, sprintf("
  SELECT CAST(s.%s AS VARCHAR) npi,
    CAST(SUM(CASE WHEN s.%s='57288' THEN TRY_CAST(s.%s AS DOUBLE) ELSE 0 END) AS INT) slings_medicare_2024,
    COUNT(DISTINCT CASE WHEN f.code IS NOT NULL THEN s.%s END) urogyn_procedures_2024,
    CAST(SUM(CASE WHEN f.code IS NOT NULL THEN TRY_CAST(s.%s AS DOUBLE) ELSE 0 END) AS INT) urogyn_services_2024
  FROM svc s LEFT JOIN fpcodes f ON s.%s=f.code
  WHERE CAST(s.%s AS VARCHAR) IN (SELECT npi FROM coh)
  GROUP BY 1", npi_c, hc_c, srv_c, hc_c, srv_c, hc_c, npi_c)))

add <- function(df, path) {
  df <- as.data.table(df); df[, npi := as.character(npi)]
  df <- merge(df, agg, by="npi", all.x=TRUE)
  for (c in c("slings_medicare_2024","urogyn_procedures_2024","urogyn_services_2024"))
    df[is.na(get(c)), (c) := 0L]
  df[, did_urogyn_surgery_2024 := urogyn_procedures_2024 > 0]
  fwrite(df, path); df
}
abu2  <- add(abu,  "data/abu_all_urps_ENRICHED_2026-07-22.csv")
abog2 <- add(abog, "data/abog_all_urps_ENRICHED_2026-07-22.csv")

# ---- pathway split for the manuscript sentence (computed from rosters) ----
summ <- function(df,lab){ s<-df[inmodel(in_model_baseline)]
  cat(sprintf("%s in-model n=%d: did urogyn surgery %.0f%%; did slings %.0f%% (%d surgeons, %d slings); median urogyn services %d\n",
      lab, nrow(s), 100*mean(s$did_urogyn_surgery_2024), 100*mean(s$slings_medicare_2024>0),
      sum(s$slings_medicare_2024>0), sum(s$slings_medicare_2024),
      as.integer(median(s$urogyn_services_2024)))) }
cat("\n=== CY2024 ===\n"); summ(abu2,"ABU"); summ(abog2,"ABOG")
cat(sprintf("TOTAL slings 2024: %d by %d surgeons\n",
    sum(abu2[inmodel(in_model_baseline)]$slings_medicare_2024)+sum(abog2[inmodel(in_model_baseline)]$slings_medicare_2024),
    sum(abu2[inmodel(in_model_baseline)]$slings_medicare_2024>0)+sum(abog2[inmodel(in_model_baseline)]$slings_medicare_2024>0)))
