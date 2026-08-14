#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Reviewer #5: the 2025 active baseline is ESTIMATED, carried forward from admin
# data ending 2023-2024. This decomposes each cohort's estimated 2025 active stock
# by how recently it is administratively supported (Medicare Part B last-active year)
# and reports a baseline-lag ratio range:
#   directly_supported  Part B active in 2023 (the latest admin year)
#   carried_fwd_1_2yr    last Part B active 2021-2022 (short lag)
#   carried_fwd_3plus    last Part B active <= 2020 (long lag; most uncertain)
#   presumed_entrant     recent certificant (cert year >= 2022) with no Part B yet
#   no_admin_history     no Part B activity and not a recent certificant
# Baseline-lag sensitivity: recompute the completion-to-departure ratio after
# removing the long-lag (>=3yr carried-forward) physicians from the active stock
# (treating them as already departed), the most adverse plausible baseline error.
# Reuses verbatim rebuild_ssot_revised.R machinery.
#   OUTPUT: cliff/data/baseline_lag_decomposition.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({library(DBI); library(duckdb); library(readr); library(dplyr); library(here)})

# Ported from the isochrones monorepo (2026-08-13). Monorepo inputs resolve under
# CLIFF_ISOCHRONES_ROOT and fail loudly if absent; the ABU net-new roster is the
# 2026-07-22 vintage (308 NPIs, the adopted 1,306 baseline), not 2026-07-14 (270).
ISO <- Sys.getenv("CLIFF_ISOCHRONES_ROOT", unset = path.expand("~/isochrones"))
iso <- function(...) {
  p <- file.path(ISO, ...)
  if (!file.exists(p))
    stop(sprintf("[baseline_lag_decomposition] monorepo input not found:\n  %s", p), call. = FALSE)
  p
}

BANDS <- c(0,45,50,55,60,65,70,Inf); BAND_LABELS <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
WIN <- c(2016L,2021L); AGE_AT_CERT <- 30L; HORIZON <- 4L; ENTRY_AGE <- 34L; REF_YEAR <- 2024L; ADMIN_END <- 2023L
band_of <- function(age) as.character(cut(age, breaks=BANDS, labels=BAND_LABELS, right=FALSE))
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")
GRAD <- list(GO=c(70,73,78,79), URPS=c(61,66,63,66)); ENTRANTS <- sapply(GRAD, mean); PRIMARY <- c("GO","URPS")

coh <- read_csv(iso("manuscript","tables","table1_physician_characteristics.csv"), show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)], cert_year=as.integer(cert_year),
            ry=suppressWarnings(as.integer(retirement_year)), ret=as.logical(is_retired_for_cohorting), age=as.integer(age_approx)) %>%
  distinct(npi,.keep_all=TRUE) %>% filter(!is.na(ab))
.anch <- read_csv(here("data","departure_anchor.csv"), show_col_types=FALSE)
coh <- coh %>% left_join(mutate(.anch, npi=as.character(npi)), by="npi") %>%
  mutate(ry=ifelse(!is.na(ry) & !has_nonop_anchor, NA_integer_, ry)) %>% select(-has_nonop_anchor)

db <- "/Volumes/MufflySamsung 1/DuckDB/nber_my_duckdb.duckdb"; if(!file.exists(db)) db <- "/Volumes/MufflySamsung/DuckDB/nber_my_duckdb.duckdb"
con <- dbConnect(duckdb::duckdb(), db, read_only=TRUE); duckdb::duckdb_register(con, "coh_npi", data.frame(npi=coh$npi))
pb <- dbGetQuery(con, "SELECT CAST(a.npi AS VARCHAR) npi, a.last_active_year_part_b L FROM credentials.part_b_activity a JOIN coh_npi c ON CAST(a.npi AS VARCHAR)=c.npi")
dbDisconnect(con, shutdown=TRUE)
coh <- coh %>% left_join(pb, by="npi")

# ---- URPS cohort membership: the v3.0.0 snapshot, not a roster reconstruction --
# The adopted 1,306 baseline is ABOG 1,027 + ABU net-new 279, and that membership
# is defined by the isochrones v3.0.0 provider snapshot's active_2023 gate.
# Rebuilding it from the monorepo rosters gives 1,031 + 302 = 1,333: it keeps the
# 4 ABOG providers the active gate drops, and excludes only 6 ABU NPIs for a
# missing certification year where the snapshot excludes 29. Those are exactly
# the consort_cohort_flow removals (removed_inactive 4; abu_excluded_nocert 29),
# so the snapshot is the authority on WHO is active. This script's contribution
# is the administrative-lag categorisation of that cohort, not its definition.
V3_PARQUET <- Sys.getenv("CLIFF_URPS_SNAPSHOT", unset = path.expand(
  "~/mufflyaccess/tests/testthat/fixtures/isochrones-v3.0.0/urps_provider_snapshot.parquet"))
if (!file.exists(V3_PARQUET))
  stop(sprintf(paste0("[baseline_lag_decomposition] v3.0.0 provider snapshot not found:\n  %s\n",
                      "Set CLIFF_URPS_SNAPSHOT to the isochrones-v3.0.0 parquet."),
               V3_PARQUET), call. = FALSE)
.v3con <- dbConnect(duckdb::duckdb())
v3 <- dbGetQuery(.v3con, sprintf(
  "SELECT CAST(npi AS VARCHAR) npi, board_pathway, cert_year, age_proxy_from_cert age
     FROM read_parquet(%s) WHERE active_2023", shQuote(V3_PARQUET)))
dbDisconnect(.v3con, shutdown = TRUE)
stopifnot(sum(v3$board_pathway == "ABOG") == 1027L,
          sum(v3$board_pathway == "ABU_NET_NEW") == 279L)
# ABU net-new are treated as directly-supported recent certificants, as before.
abu_age <- as.integer(v3$age[v3$board_pathway == "ABU_NET_NEW"])

haz_for <- function(age, hz){ h<-hz[band_of(age)]; h[is.na(h)]<-max(hz,na.rm=TRUE); pmin(1,h) }
band_counts <- function(rows){
  do.call(rbind, lapply(rows, function(i){ cy<-coh$cert_year[i]; ry<-coh$ry[i]; if(!is.na(ry)&&(ry<WIN[1]||ry>WIN[2])) ry<-NA_integer_
    y0<-max(WIN[1],cy); y1<-if(is.na(ry)) WIN[2] else min(WIN[2],ry); if(y1<y0) return(NULL)
    yy<-y0:y1; data.frame(band=band_of(yy-cy+AGE_AT_CERT), event=as.integer(!is.na(ry)&yy==ry))})) %>%
    group_by(band) %>% summarise(py=dplyr::n(), ev=sum(event), .groups="drop") }
bc <- band_counts(which(coh$ab %in% PRIMARY)); HAZ <- setNames(bc$ev/bc$py, bc$band)
project <- function(a, E){ count<-table(a); av<-as.integer(names(count)); count<-as.numeric(count); dep<-0
  for(h in seq_len(HORIZON)){ hzz<-haz_for(av,HAZ); dep<-dep+sum(count*hzz); sv<-count*(1-hzz)
    av2<-av+1L; ix<-match(ENTRY_AGE,av2); if(is.na(ix)){av2<-c(av2,ENTRY_AGE); sv<-c(sv,E)} else sv[ix]<-sv[ix]+E; av<-av2; count<-sv }
  dep/HORIZON }

# GO keeps the monorepo cohort: its 1,052 baseline already reproduces the SSOT.
# URPS ABOG-pathway rows come from the v3.0.0 snapshot (1,027), with their Part B
# lag looked up for the same categorisation, so the decomposition is computed over
# exactly the cohort the adopted baseline is defined on.
act_go <- coh %>% filter(ab == "GO", ret == FALSE, !is.na(age)) %>%
  transmute(ab, age = as.integer(age), cert_year = as.integer(cert_year), L)
v3_abog <- v3[v3$board_pathway == "ABOG", ]
.con2 <- dbConnect(duckdb::duckdb(), db, read_only = TRUE)
duckdb::duckdb_register(.con2, "v3_npi", data.frame(npi = v3_abog$npi))
pb2 <- dbGetQuery(.con2, paste(
  "SELECT CAST(a.npi AS VARCHAR) npi, a.last_active_year_part_b L",
  "FROM credentials.part_b_activity a JOIN v3_npi c ON CAST(a.npi AS VARCHAR)=c.npi"))
dbDisconnect(.con2, shutdown = TRUE)
act_urps <- v3_abog %>%
  left_join(pb2, by = "npi") %>%
  transmute(ab = "URPS", age = as.integer(age), cert_year = as.integer(cert_year), L)
act <- bind_rows(act_go, act_urps)
stopifnot(sum(act$ab == "URPS") == 1027L)
act$cat <- with(act, ifelse(!is.na(L) & L==ADMIN_END, "directly_supported",
                     ifelse(!is.na(L) & L>=ADMIN_END-2, "carried_fwd_1_2yr",
                     ifelse(!is.na(L), "carried_fwd_3plus",
                     ifelse(cert_year>=2022, "presumed_entrant", "no_admin_history")))))

out <- do.call(rbind, lapply(PRIMARY, function(k){
  a <- act[act$ab==k, ]
  ages_full <- if(k=="URPS") c(a$age, abu_age) else a$age
  ages_trim <- if(k=="URPS") c(a$age[a$cat!="carried_fwd_3plus"], abu_age) else a$age[a$cat!="carried_fwd_3plus"]
  ratio_full <- ENTRANTS[[k]]/project(ages_full, ENTRANTS[[k]])
  ratio_trim <- ENTRANTS[[k]]/project(ages_trim, ENTRANTS[[k]])
  tab <- table(factor(a$cat, levels=c("directly_supported","carried_fwd_1_2yr","carried_fwd_3plus","presumed_entrant","no_admin_history")))
  data.frame(subspecialty_abbrev=k,
             directly_supported=as.integer(tab["directly_supported"]),
             carried_fwd_1_2yr=as.integer(tab["carried_fwd_1_2yr"]),
             carried_fwd_3plus=as.integer(tab["carried_fwd_3plus"]),
             presumed_entrant=as.integer(tab["presumed_entrant"]),
             no_admin_history=as.integer(tab["no_admin_history"]),
             abu_net_new=if(k=="URPS") length(abu_age) else 0L,
             baseline_total=length(ages_full),
             ratio_primary=round(ratio_full,2),
             ratio_lag_trimmed=round(ratio_trim,2), stringsAsFactors=FALSE)
}))
write_csv(out, here("data","baseline_lag_decomposition.csv"))
cat("\n#5 BASELINE-LAG DECOMPOSITION:\n"); print(out, row.names=FALSE)
cat("\nDONE\n")
