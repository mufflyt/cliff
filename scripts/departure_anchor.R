#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Non-Open-Payments departure anchor (reviewer #2 construct-validity fix).
# The published classifier let a single Open Payments (industry-payment)
# cessation classify a departure (config min_sources_required = 1). Because
# stopping industry payments is not a validated indicator of leaving practice,
# the PRIMARY departure definition now requires corroboration by at least one
# claims / prescribing / enrollment / certification signal (Medicare Part B or D,
# NPPES deactivation, or ABMS certification lapse). Open Payments becomes a
# supporting-only signal and can no longer solely classify a departure.
#
# This script writes, for every cohort NPI, whether a non-Open-Payments departure
# source fired (has_nonop_anchor). Downstream hazard code nulls the consensus
# departure year for NPIs that fail the anchor (Open-Payments-only departures),
# removing those likely-false-positive events from the life table. The baseline
# active workforce (is_retired_for_cohorting) is a separate gate and is unchanged.
#
# OUTPUT: cliff/data/departure_anchor.csv (npi, has_nonop_anchor)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(DBI); library(duckdb); library(dplyr); library(readr); library(here)})
SUBS <- c(GO="Gynecologic Oncology", URPS="Female Pelvic Medicine & Reconstructive Surgery", MIGS="MIGS")

coh <- read_csv("/Users/tylermuffly/isochrones/manuscript/tables/table1_physician_characteristics.csv",
                show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi)) %>% distinct()

db <- "/Volumes/MufflySamsung 1/DuckDB/nber_my_duckdb.duckdb"
if(!file.exists(db)) db <- "/Volumes/MufflySamsung/DuckDB/nber_my_duckdb.duckdb"
con <- dbConnect(duckdb::duckdb(), db, read_only=TRUE)
duckdb::duckdb_register(con, "coh_npi", data.frame(npi=coh$npi))
sig <- dbGetQuery(con, "SELECT CAST(p.npi AS VARCHAR) npi,
                        (COALESCE(p.has_medicare_part_b,FALSE) OR COALESCE(p.has_medicare_part_d,FALSE)
                         OR COALESCE(p.has_nppes_deactivation,FALSE) OR COALESCE(p.has_abms_cert_lapse,FALSE)) has_nonop_anchor
                        FROM credentials.retirement_signals_pivot p
                        JOIN coh_npi c ON CAST(p.npi AS VARCHAR)=c.npi")
dbDisconnect(con, shutdown=TRUE)

out <- coh %>% left_join(sig, by="npi") %>%
  mutate(has_nonop_anchor = tidyr::replace_na(as.logical(has_nonop_anchor), FALSE))
write_csv(out, here::here("cliff","data","departure_anchor.csv"))
cat(sprintf("Departure anchor: %d cohort NPIs; %d (%.0f%%) have a non-Open-Payments anchor.\n",
            nrow(out), sum(out$has_nonop_anchor), 100*mean(out$has_nonop_anchor)))
cat("Wrote cliff/data/departure_anchor.csv\n")
