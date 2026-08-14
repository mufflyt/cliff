#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Open Payments construct-validity sensitivity (reviewer #2 major point).
# The departure classifier is heavily driven by cessation of Open Payments
# reporting, which is not a validated indicator of leaving clinical practice.
# We recompute the empirical age-band departure hazard, the weighted departure
# rate, and the headcount replacement ratio under alternative source-inclusion
# rules, using the per-NPI per-source signals in credentials.retirement_signals_pivot.
#
# Rules (a departure in 2016-2021 is COUNTED only if it survives the rule):
#   primary     : any classified departure (consensus)
#   op_excluded : a non-Open-Payments source must have fired
#   op_only_out : drop departures whose ONLY firing source is Open Payments
#   claims_anchor: require a claims/enrollment/certification source
#                  (Part B, Part D, NPPES, or ABMS)
#   two_source  : require >= 2 concordant firing sources
#
# Because Open-Payments cessation tends to OVER-count departures, excluding it
# removes events and RAISES the ratio; the test is whether the conclusion holds.
# Departure year is held at the consensus year; only inclusion changes.
#
# OUTPUT: cliff/data/open_payments_sensitivity.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(DBI); library(duckdb); library(dplyr); library(readr); library(here)})

# Ported from the isochrones monorepo (2026-08-13). Monorepo inputs resolve under
# CLIFF_ISOCHRONES_ROOT. The baseline and entrant counts already come from the
# SSOT below, so this script re-bases automatically; only the paths needed fixing.
ISO <- Sys.getenv("CLIFF_ISOCHRONES_ROOT", unset = path.expand("~/isochrones"))
iso <- function(...) { p <- file.path(ISO, ...)
  if (!file.exists(p)) stop(sprintf("[open_payments_sensitivity] input not found:\n  %s", p), call. = FALSE)
  p }

BANDS <- c(0,45,50,55,60,65,70,Inf); BL <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
band_of <- function(a) as.character(cut(a, BANDS, labels=BL, right=FALSE))
WIN <- c(2016L,2021L); AGE_AT_CERT <- 30L
SUBS <- c(GO="Gynecologic Oncology", URPS="Female Pelvic Medicine & Reconstructive Surgery")

ss <- read_csv(here::here("data","workforce_projections_consolidated.csv"), show_col_types=FALSE)
coh <- read_csv(iso("manuscript","tables","table1_physician_characteristics.csv"),
                show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)],
            cy=as.integer(cert_year), ry=suppressWarnings(as.integer(retirement_year)),
            ret=as.logical(is_retired_for_cohorting), age=as.integer(age_approx)) %>%
  distinct(npi,.keep_all=TRUE) %>% filter(!is.na(ab))

# per-source firing flags
db <- "/Volumes/MufflySamsung 1/DuckDB/nber_my_duckdb.duckdb"
if(!file.exists(db)) db <- "/Volumes/MufflySamsung/DuckDB/nber_my_duckdb.duckdb"
con <- dbConnect(duckdb::duckdb(), db, read_only=TRUE)
duckdb::duckdb_register(con, "coh_npi", data.frame(npi=coh$npi))
sig <- dbGetQuery(con, "SELECT CAST(p.npi AS VARCHAR) npi, p.has_open_payments op, p.has_medicare_part_b pb,
                        p.has_medicare_part_d pd, p.has_nppes_deactivation nppes, p.has_abms_cert_lapse abms,
                        p.source_count_unified nsrc
                        FROM credentials.retirement_signals_pivot p
                        JOIN coh_npi c ON CAST(p.npi AS VARCHAR)=c.npi")
dbDisconnect(con, shutdown=TRUE)
for(cc in c("op","pb","pd","nppes","abms")) sig[[cc]] <- as.logical(sig[[cc]])
d <- coh %>% left_join(sig, by="npi")
# firing-source count among the departure sources (exclude age, medicaid handled as anchor-neutral)
d$nfire <- rowSums(cbind(d$op, d$pb, d$pd, d$nppes, d$abms), na.rm=TRUE)

# rule -> keep a classified departure?
rules <- list(
  primary      = function(x) TRUE,
  op_excluded  = function(x) (x$pb|x$pd|x$nppes|x$abms) %in% TRUE,
  op_only_out  = function(x) !((x$op %in% TRUE) & (x$nfire<=1)),
  claims_anchor= function(x) (x$pb|x$pd|x$nppes|x$abms) %in% TRUE,
  two_source   = function(x) (x$nfire>=2) %in% TRUE)

haz_rate <- function(dep_flag, sub){
  ci <- d$ab==sub
  # life table over WIN: person-years per band; events at ry if departure kept
  rows <- which(ci)
  pyb <- setNames(numeric(length(BL)), BL); evb <- setNames(numeric(length(BL)), BL)
  for(i in rows){
    cy<-d$cy[i]; ry<-d$ry[i]
    keep_dep <- !is.na(ry) & ry>=WIN[1] & ry<=WIN[2] & isTRUE(dep_flag[i])
    ry_eff <- if(keep_dep) ry else NA_integer_
    y0<-max(WIN[1],cy); y1<-if(is.na(ry_eff)) WIN[2] else min(WIN[2],ry_eff); if(y1<y0) next
    for(y in y0:y1){ b<-band_of(y-cy+AGE_AT_CERT); pyb[b]<-pyb[b]+1
      if(!is.na(ry_eff)&&y==ry_eff) evb[b]<-evb[b]+1 }
  }
  H <- evb/pyb; H[is.na(H)] <- 0
  hf <- function(age){ v<-H[band_of(age)]; v[is.na(v)]<-max(H,na.rm=TRUE); v }
  active <- d[ci & d$ret==FALSE & !is.na(d$age), ]
  100*sum(hf(active$age))/nrow(active)
}

out <- do.call(rbind, lapply(names(rules), function(rn){
  do.call(rbind, lapply(c("GO","URPS"), function(sub){
    keep <- vapply(seq_len(nrow(d)), function(i) isTRUE(rules[[rn]](d[i,])), logical(1))
    rate <- haz_rate(keep, sub)
    base <- ss$baseline_2025[ss$subspecialty_abbrev==sub]
    ent  <- ss$annual_entrants[ss$subspecialty_abbrev==sub]
    avg_dep <- rate/100*base
    data.frame(rule=rn, subspecialty_abbrev=sub, departure_rate_pct=round(rate,2),
               avg_annual_departures=round(avg_dep,1),
               replacement_ratio=round(ent/avg_dep,2))
  }))
}))
write_csv(out, here::here("data","open_payments_sensitivity.csv"))
cat("=== Open Payments construct-validity sensitivity ===\n"); print(as.data.frame(out), row.names=FALSE)
cat("\nWrote cliff/data/open_payments_sensitivity.csv\n")
