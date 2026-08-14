#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Validate the certification-anchored ESTIMATED age against two external age
# sources (peer review): Healthgrades profile age and Medicare-graduation-year age.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Proxy: estimated age = reference_year - certification_year + 30 (age_approx).
# References: (a) Healthgrades est_age (real profile age, ABOG subspecialists);
#             (b) Medicare DAC graduation year -> grad_year + 27.
# Reports, per source: mean error (SD), median absolute error (p25-p75),
# Pearson correlation, and the share placed in the same 5-year age band.
#
# OUTPUT: cliff/data/age_proxy_validation.csv + console report.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(DBI); library(duckdb); library(dplyr); library(readr); library(here)})


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
    stop(sprintf("[%s] monorepo input not found:\n  %s", "age_proxy_validation", p), call. = FALSE)
  p
}

REF_YEAR <- 2024L; HG_SCRAPE <- 2026L; AGE_AT_GRAD <- 27L
BANDS <- c(0,45,50,55,60,65,70,Inf)
band <- function(a) cut(a, BANDS, right=FALSE)
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")

coh <- read_csv(iso("manuscript", "tables", "table1_physician_characteristics.csv"),
                show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS)) %>%
  transmute(npi=as.character(npi), proxy_age=as.integer(age_approx)) %>%
  filter(!is.na(proxy_age)) %>% distinct(npi,.keep_all=TRUE)

# Healthgrades real age
HG_DIR <- iso("data", "healthgrades")
hg <- do.call(rbind, lapply(c("migs","urogyn","gyn_onc"), function(s){
  x <- tryCatch(readRDS(file.path(HG_DIR, sprintf("%s_healthgrades_checkpoint.rds",s))), error=function(e) NULL)
  if (is.null(x)||is.null(x$physicians)) return(NULL)
  data.frame(npi=as.character(x$physicians$npi),
             hg_age=suppressWarnings(as.numeric(x$physicians$est_age)))
})) %>% filter(!is.na(npi), !is.na(hg_age), hg_age>=25, hg_age<=95) %>% distinct(npi,.keep_all=TRUE)

# DAC graduation-year age
db <- NA_character_
for (c in c("/Volumes/MufflySamsung/DuckDB/nber_my_duckdb.duckdb",
            "/Volumes/MufflySamsung 1/DuckDB/nber_my_duckdb.duckdb")) if (file.exists(c)) { db<-c; break }
if (is.na(db)) stop("NBER DuckDB not mounted.")
con <- dbConnect(duckdb::duckdb(), db, read_only=TRUE)
dac <- dbGetQuery(con, "SELECT CAST(\"NPI\" AS VARCHAR) npi, MIN(TRY_CAST(\"Grd_yr\" AS INTEGER)) grad_year
                        FROM \"doctors_and_clinicians_12_2023_DAC_NationalDownloadableFile_csv_7\"
                        WHERE UPPER(pri_spec) LIKE '%GYN%' OR UPPER(pri_spec) LIKE '%OBSTETRIC%' GROUP BY 1")
dbDisconnect(con, shutdown=TRUE)
dac <- dac %>% filter(!is.na(grad_year), grad_year>=1950, grad_year<=2020) %>%
  mutate(grad_age = REF_YEAR - grad_year + AGE_AT_GRAD)

m <- coh %>%
  left_join(hg, by="npi") %>%
  # back-date Healthgrades current age to the reference year for a like comparison
  mutate(hg_age_ref = hg_age - (HG_SCRAPE - REF_YEAR)) %>%
  left_join(dac %>% select(npi, grad_age), by="npi")

metrics <- function(proxy, ref){
  ok <- !is.na(proxy) & !is.na(ref); p<-proxy[ok]; r<-ref[ok]; e<-p-r
  data.frame(n=length(p), mean_error=round(mean(e),2), sd_error=round(sd(e),2),
             median_abs_error=round(median(abs(e)),1),
             p25_abs=round(quantile(abs(e),.25),1), p75_abs=round(quantile(abs(e),.75),1),
             correlation=round(cor(p,r),3),
             pct_same_band=round(100*mean(band(p)==band(r)),1))
}
out <- bind_rows(
  cbind(reference="Healthgrades profile age", metrics(m$proxy_age, m$hg_age_ref)),
  cbind(reference="Medicare graduation-year age", metrics(m$proxy_age, m$grad_age)))
write_csv(out, here::here("data","age_proxy_validation.csv"))

cat("=== Certification-anchored estimated age vs external references ===\n")
cat("Proxy = reference_year - cert_year + 30 (age_approx); reference_year =", REF_YEAR, "\n\n")
print(as.data.frame(out), row.names=FALSE)
cat("\nCoverage: Healthgrades", sum(!is.na(m$hg_age_ref)), "of", nrow(m),
    "| graduation-year", sum(!is.na(m$grad_age)), "of", nrow(m), "\n")
cat("Wrote cliff/data/age_proxy_validation.csv\n")
