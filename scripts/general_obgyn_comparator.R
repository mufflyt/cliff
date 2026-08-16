#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# TIER-3: GENERAL OB/GYN comparator + classifier-validation cohort.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# PURPOSE (per PI, not a workforce projection): apply the SAME departure
# classifier to a large, well-defined general OB/GYN population as an external
# benchmark and validation cohort. The key diagnostic is the AGE-AT-DEPARTURE
# distribution: if general OB/GYNs also show implausibly young departures, the
# young-departure signal is a classifier/age-proxy artifact; if it is confined to
# MIGS, it points to a MIGS-specific designation/denominator problem.
#
# NOT POOLED: general OB/GYNs are reported as a separate comparator cohort; the
# subspecialty-specific empirical rates remain the primary model inputs. HRSA
# groups OB/GYN broadly and warns category rates misestimate individual
# specialties, so we keep the cohorts distinct.
#
# APPLES-TO-APPLES AGE: all four cohorts use ONE independent age source, the
# Medicare DAC (Physician Compare) graduation year, with age = year - Grd_yr +
# AGE_AT_GRAD. This deliberately replaces the certification-anchored proxy used
# in the primary model so the MIGS age-37 finding can be re-examined on a common,
# subspecialty-neutral footing.
#
# COHORTS (subspecialty is defined by ABOG board certification, NOT by the DAC/CMS
# specialty code, which lumps all OB/GYN subspecialists under generic
# "OBSTETRICS/GYNECOLOGY" -- CLAUDE.md #16):
#   General OB/GYN = DAC pri_spec generic "OBSTETRICS/GYNECOLOGY", excluding EVERY
#                    ABOG-certified subspecialist (all seven subspecialties in the
#                    ABOG cohort file). DAC specialty is used only to define the
#                    generalist universe and to supply graduation year.
#   GO / URPS / MIGS = the manuscript's ABOG subspecialist cohort.
# DEPARTURE = credentials.retirement_consensus.is_retired_final with
#             retirement_year_final in the 2016-2023 observation window.
#
# OUTPUT: cliff/data/general_obgyn_comparator.csv + console report.
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
    stop(sprintf("[%s] monorepo input not found:\n  %s", "general_obgyn_comparator", p), call. = FALSE)
  p
}

WIN <- c(2016L, 2023L); AGE_AT_GRAD <- 27L   # median US med-school graduation age
HG_SCRAPE_YEAR <- 2026L                       # Healthgrades checkpoint timestamp (2026-02)
COHORT <- iso("manuscript", "tables", "table1_physician_characteristics.csv")
HG_DIR <- iso("data", "healthgrades")

# resolve the NBER DuckDB (handle macOS " 1" mount drift)
db <- NA_character_
source(here::here("R", "wc_path.R"))   # wc_path()/wc_duckdb_path(): registered external inputs
db <- wc_duckdb_path()   # config/cliff_paths.yml: primary + mount-drift fallback
if (is.na(db)) stop("NBER DuckDB not mounted; cannot build the general OB/GYN comparator.")

con <- dbConnect(duckdb::duckdb(), db, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE))

DAC <- "doctors_and_clinicians_12_2023_DAC_NationalDownloadableFile_csv_7"

# --- DAC: NPI -> graduation year (broad OB/GYN, so subspecialists who self-report
# as generic OB/GYN OR as gyn-onc still get a grad year) + a generic-code flag
# that (with ABOG below) defines the generalist universe.
dac <- dbGetQuery(con, sprintf('
  SELECT CAST("NPI" AS VARCHAR) npi,
         MIN(TRY_CAST("Grd_yr" AS INTEGER)) grad_year,
         MAX(CASE WHEN UPPER(pri_spec)=%s THEN 1 ELSE 0 END) is_generic
  FROM "%s"
  WHERE UPPER(pri_spec) LIKE %s OR UPPER(pri_spec) LIKE %s
  GROUP BY 1', "'OBSTETRICS/GYNECOLOGY'", DAC, "'%GYN%'", "'%OBSTETRIC%'"))
dac$grad_year <- ifelse(!is.na(dac$grad_year) & dac$grad_year >= 1950 & dac$grad_year <= 2020,
                        dac$grad_year, NA_integer_)

# --- classifier output (departure) -------------------------------------------
cons <- dbGetQuery(con, "SELECT CAST(npi AS VARCHAR) npi,
                          is_retired_final, retirement_year_final
                          FROM credentials.retirement_consensus") %>%
  mutate(is_retired_final = as.logical(is_retired_final),
         retirement_year_final = suppressWarnings(as.integer(retirement_year_final)))

# --- ABOG subspecialist cohort: subspecialty is defined by ABOG certification -
# ALL seven ABOG subspecialties (the full cohort file) are the exclusion set for
# generalists; the three surgical ones are labelled for the comparator.
abog <- read_csv(COHORT, show_col_types=FALSE, guess_max=1e5) %>%
  transmute(npi=as.character(npi), subspecialty,
            react=as.logical(is_reactivated),
            departed_cohort=as.logical(is_retired_for_cohorting)) %>%
  distinct(npi, .keep_all=TRUE)
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery",
          GO="Gynecologic Oncology", MIGS="MIGS")
coh <- abog %>% filter(subspecialty %in% unname(SUBS)) %>%
  transmute(npi, cohort=names(SUBS)[match(subspecialty,SUBS)])
abog_all_npi <- unique(abog$npi)   # every ABOG-certified subspecialist

# --- assemble the four cohorts ----------------------------------------------
gen <- dac %>%
  filter(is_generic == 1, !npi %in% abog_all_npi) %>%  # generic OB/GYN, not ABOG-subspecialist
  transmute(npi, cohort = "General OB/GYN")

# --- Healthgrades ACTUAL age for the subspecialists (no generalist scrape) ----
# est_age is Healthgrades' reconciled physician age at scrape (2026-02); it is a
# real profile age (corr with years-in-practice ~0.9, not a pure transform), a
# better age source than the certification/graduation proxy. Used only for the
# ABOG subspecialists, who are the ones Healthgrades covers.
hg <- do.call(rbind, lapply(c("migs","urogyn","gyn_onc"), function(s){
  x <- tryCatch(readRDS(file.path(HG_DIR, sprintf("%s_healthgrades_checkpoint.rds", s))), error=function(e) NULL)
  if (is.null(x) || is.null(x$physicians)) return(NULL)
  p <- x$physicians
  data.frame(npi=as.character(p$npi),
             hg_age=suppressWarnings(as.numeric(p$est_age)), stringsAsFactors=FALSE)
})) %>% filter(!is.na(npi), !is.na(hg_age), hg_age>=25, hg_age<=95) %>%
  distinct(npi, .keep_all=TRUE)

# Keep every physician for the departure RATE (age is optional, joined below;
# generalists without a DAC grad year still count in the rate denominator).
people <- bind_rows(coh, gen) %>%
  left_join(dac %>% select(npi, grad_year), by="npi") %>%
  left_join(cons, by="npi") %>%
  left_join(abog %>% select(npi, react), by="npi") %>%
  left_join(hg, by="npi") %>%
  distinct(npi, cohort, .keep_all = TRUE)

# --- departure flag within the observation window ---------------------------
people$departed <- people$is_retired_final %in% TRUE &
  !is.na(people$retirement_year_final) &
  people$retirement_year_final >= WIN[1] & people$retirement_year_final <= WIN[2]
# two age-at-departure estimates:
#   grad-year (all four cohorts, single common source for the benchmark comparison)
#   Healthgrades real age (subspecialists only; back-dated to the departure year)
people$age_grad <- ifelse(people$departed,
  people$retirement_year_final - people$grad_year + AGE_AT_GRAD, NA_real_)
people$age_hg <- ifelse(people$departed & !is.na(people$hg_age),
  people$hg_age - (HG_SCRAPE_YEAR - people$retirement_year_final), NA_real_)
# primary age = Healthgrades where available (subspecialists), else graduation year
people$age_at_departure <- ifelse(!is.na(people$age_hg), people$age_hg, people$age_grad)

# --- metrics per cohort ------------------------------------------------------
# annual departure rate via a person-year life table over WIN: each physician
# contributes years from WIN_lo to min(WIN_hi, retirement) (full window if active),
# and one departure event if departed in-window.
py_row <- function(dep, ry) {
  y1 <- if (dep && !is.na(ry)) min(WIN[2], ry) else WIN[2]
  max(0L, y1 - WIN[1] + 1L)
}
CO <- c("General OB/GYN","GO","URPS","MIGS")
q <- function(v,p) if(length(v)) as.integer(quantile(v,p)) else NA
res <- lapply(CO, function(k){
  d <- people[people$cohort==k, ]
  n <- nrow(d)
  py <- sum(mapply(py_row, d$departed, d$retirement_year_final))
  ev <- sum(d$departed)
  aad  <- d$age_at_departure[d$departed & !is.na(d$age_at_departure)]   # HG-preferred
  aadg <- d$age_grad[d$departed & !is.na(d$age_grad)]                    # grad-year only
  data.frame(
    cohort = k, n = n,
    annual_departure_rate_pct = round(100*ev/py, 2),
    departures = ev,
    age_source = if(k=="General OB/GYN") "graduation year" else "Healthgrades",
    median_departure_age = if(length(aad)) median(aad) else NA,
    p25 = q(aad,.25), p75 = q(aad,.75),
    pct_departures_before_50 = if(length(aad)) round(100*mean(aad<50),1) else NA,
    median_age_gradyear = if(length(aadg)) median(aadg) else NA,   # single-source cross-check
    reentry_pct = round(100*mean(d$react, na.rm=TRUE), 2),
    stringsAsFactors = FALSE)
})
tab <- do.call(rbind, res)

cat("=== GENERAL OB/GYN comparator + classifier validation cohort ===\n")
cat(sprintf("Age: Healthgrades real age for ABOG subspecialists; graduation year (grad+%d) for\n",AGE_AT_GRAD))
cat("General OB/GYN (no Healthgrades scrape). 'median_age_gradyear' is the single-source\n")
cat(sprintf("(graduation-year) cross-check for all four cohorts. Window %d-%d.\n\n", WIN[1], WIN[2]))
print(as.data.frame(tab), row.names = FALSE)

write_csv(tab, here::here("data","general_obgyn_comparator.csv"))
cat("\nWrote cliff/data/general_obgyn_comparator.csv\n")
mig<-tab[tab$cohort=="MIGS",]; gen<-tab[tab$cohort=="General OB/GYN",]
cat(sprintf("\nDIAGNOSTIC (MIGS age-37 finding):\n  MIGS median departure age = %s (Healthgrades) / %s (graduation-year);\n  General OB/GYN = %s (graduation-year), %s%% before 50.\n  A young signal in the large generalist cohort implicates the classifier/estimand,\n  not a MIGS-specific defect.\n",
    mig$median_departure_age, mig$median_age_gradyear, gen$median_departure_age, gen$pct_departures_before_50))
