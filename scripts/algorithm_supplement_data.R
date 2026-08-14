#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Generate departure-algorithm supplement data: leave-one-source-out (LOSO)
# and the per-cohort CONSORT-style derivation flow (peer review).
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# LOSO: for each departed physician, which of the six sources fired
# (credentials.retirement_signals_pivot has_* flags); 'sole_support' = departures
# that would be lost if that source were removed (it was the only firing signal).
# CONSORT: certified/designated -> NPI-matched -> active-in-practice -> removed
# (deceased / inactive) -> final active baseline, per cohort (URPS both-pathway).
#
# Writes cliff/data/loso_source_contribution.csv and cliff/data/consort_cohort_flow.csv
# so the supplement renders without the external DuckDB.
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
    stop(sprintf("[%s] monorepo input not found:\n  %s", "algorithm_supplement_data", p), call. = FALSE)
  p
}

SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")
coh <- read_csv(iso("manuscript", "tables", "table1_physician_characteristics.csv"),
                show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)],
            departed=as.logical(is_retired_for_cohorting),
            deceased=as.logical(deceased)) %>%
  distinct(npi,.keep_all=TRUE)

# --- LOSO from the signals pivot --------------------------------------------
db <- NA_character_
for (c in c("/Volumes/MufflySamsung/DuckDB/nber_my_duckdb.duckdb",
            "/Volumes/MufflySamsung 1/DuckDB/nber_my_duckdb.duckdb")) if (file.exists(c)) { db<-c; break }
if (is.na(db)) stop("NBER DuckDB not mounted.")
con <- dbConnect(duckdb::duckdb(), db, read_only=TRUE)
# credentials.retirement_signals_pivot is a derived intermediate that is NOT in
# the available database; only the long-format credentials.retirement_signals_unified
# and the per-source tables are. Reconstructed here as the wide form of that long
# table: signal_source takes exactly the values these has_* columns name, so the
# mapping is one-to-one. BOOL_OR is required, not cosmetic -- abms_cert_lapse has
# 4,740 rows over 4,643 NPIs. source_count_unified is the distinct firing-source
# count. Identical to the reconstruction in scripts/build_audit_table.R.
piv <- dbGetQuery(con, "
  SELECT CAST(npi AS VARCHAR) npi,
         BOOL_OR(signal_source = 'abms_cert_lapse')    AS has_abms_cert_lapse,
         BOOL_OR(signal_source = 'nppes_deactivation') AS has_nppes_deactivation,
         BOOL_OR(signal_source = 'open_payments')      AS has_open_payments,
         BOOL_OR(signal_source = 'medicare_part_d')    AS has_medicare_part_d,
         BOOL_OR(signal_source = 'medicare_part_b')    AS has_medicare_part_b,
         COUNT(DISTINCT signal_source)                 AS source_count_unified
    FROM credentials.retirement_signals_unified
   GROUP BY 1")
dbDisconnect(con, shutdown=TRUE)

dep <- coh %>% filter(departed) %>% inner_join(piv, by="npi")
SRC <- c(has_abms_cert_lapse="ABMS MOC lapse (priority 1)",
         has_nppes_deactivation="NPPES deactivation (priority 2)",
         has_open_payments="Open Payments cessation (priority 3)",
         has_medicare_part_d="Medicare Part D cessation (priority 5)",
         has_medicare_part_b="Medicare Part B cessation (priority 6)")
loso <- do.call(rbind, lapply(names(SRC), function(s){
  fired <- sum(dep[[s]] %in% TRUE)
  sole  <- sum(dep[[s]] %in% TRUE & dep$source_count_unified==1)
  data.frame(source=SRC[[s]], n_departures_supported=fired,
             pct_of_departures=round(100*fired/nrow(dep),1),
             sole_support_lost_if_removed=sole,
             pct_lost_if_removed=round(100*sole/nrow(dep),1))
}))
write_csv(loso, here::here("data","loso_source_contribution.csv"))

# --- CONSORT-style cohort flow ----------------------------------------------
# ABOG pathway per cohort (table1 is already NPI-matched and CONUS-filtered).
flow <- coh %>% group_by(ab) %>% summarise(
  certified_matched = n(),
  removed_deceased = sum(deceased %in% TRUE),
  removed_inactive = sum(departed %in% TRUE & !(deceased %in% TRUE)),
  active_baseline = sum(departed %in% FALSE), .groups="drop")
# URPS both-pathway. The recovered version of this script hardcoded the
# pre-v3.0.0 pair (abu_active_total 270; abu_active_aged 264) and derived the
# ABOG side from the monorepo cohort, which reproduces the RETIRED 1,295
# baseline: 1,135 matched, 104 inactive, 1,031 active, +264 = 1,295. It also
# never emitted abu_identified / abu_excluded_nocert / abu_included, so the
# committed artifact came from a later version that is in neither repository.
#
# The adopted 1,306 baseline is defined by the isochrones v3.0.0 provider
# snapshot's active_2023 gate, and the whole URPS row is derivable from it:
# ABOG 1,027 active + 4 inactive = 1,031 matched; ABU 279 active + 29 without a
# usable certification year = 308 identified; 1,027 + 279 = 1,306. GO and MIGS
# keep the monorepo cohort, which already matches the SSOT.
V3_PARQUET <- Sys.getenv("CLIFF_URPS_SNAPSHOT", unset = path.expand(
  "~/mufflyaccess/tests/testthat/fixtures/isochrones-v3.0.0/urps_provider_snapshot.parquet"))
if (!file.exists(V3_PARQUET))
  stop(sprintf("[algorithm_supplement_data] v3.0.0 snapshot not found:\n  %s", V3_PARQUET), call. = FALSE)
.c <- dbConnect(duckdb::duckdb())
v3 <- dbGetQuery(.c, sprintf(
  "SELECT board_pathway, active_2023, COUNT(*) n FROM read_parquet(%s) GROUP BY 1,2",
  shQuote(V3_PARQUET)))
dbDisconnect(.c, shutdown = TRUE)
vn <- function(pw, act) { v <- v3$n[v3$board_pathway == pw & v3$active_2023 == act]; if (!length(v)) 0L else as.integer(v) }
abog_active <- vn("ABOG", TRUE);       abog_inactive <- vn("ABOG", FALSE)
abu_active  <- vn("ABU_NET_NEW", TRUE); abu_nocert   <- vn("ABU_NET_NEW", FALSE)
stopifnot(abog_active + abu_active == mufflyaccess::urps_count(
  year = 2023L, measure = "board_certified_active", geography = "national",
  include_urology = TRUE, incomplete = "error"))

is_urps <- flow$ab == "URPS"
flow$certified_matched[is_urps] <- abog_active + abog_inactive
flow$removed_inactive[is_urps]  <- abog_inactive
flow$active_baseline[is_urps]   <- abog_active
flow$abu_net_new_active <- ifelse(is_urps, abu_active + abu_nocert, 0L)
flow$active_baseline_final <- ifelse(is_urps, abog_active + abu_active, flow$active_baseline)
flow$abu_identified       <- ifelse(is_urps, abu_active + abu_nocert, 0L)
flow$abu_excluded_nocert  <- ifelse(is_urps, abu_nocert, 0L)
flow$abu_included         <- ifelse(is_urps, abu_active, 0L)
write_csv(flow, here::here("data","consort_cohort_flow.csv"))

cat("=== Leave-one-source-out (departed physicians) ===\n")
cat("Departed matched in pivot:", nrow(dep), "of", sum(coh$departed),
    "| median sources per departure:", median(dep$source_count_unified, na.rm=TRUE), "\n\n")
print(as.data.frame(loso), row.names=FALSE)
cat("\n=== CONSORT cohort flow ===\n")
print(as.data.frame(flow), row.names=FALSE)
cat("\nSpecialty inactivity thresholds (config/retirement_specialty_thresholds.yml):",
    "default 3 y; Gynecologic Oncology 4 y; MIGS 4 y; URPS -> default 3 y.\n")
cat("Wrote loso_source_contribution.csv and consort_cohort_flow.csv\n")
