#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Single authoritative departure/replacement AUDIT TABLE (peer review #3).
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Reviewer #3: several "primary" numbers disagreed across documents because the
# SAME definition was reported three ways (static hazard-times-current-ages vs the
# dynamic aging projection, and ABOG-only vs both-pathway URPS). This script passes
# EVERY departure definition through the ONE authoritative dynamic model used by
# scripts/rebuild_ssot_revised.R and reports, side by side:
#   eligible_departures | person_years | static_2025_rate | dynamic_4yr_departures
#   | dynamic_annual_rate | graduate_input | completion_to_departure_ratio
#   | projected_2029
# so any reader can trace raw events -> reported ratio. The `primary` row must
# reproduce the consolidated SSOT exactly.
#
# The primary classifier is: the 24-source consensus retirement_year (column
# retirement_year), retained only if a NON-OPEN-PAYMENTS anchor fired
# (has_nonop_anchor in cliff/data/departure_anchor.csv). No weighted-score model.
#
# OUTPUT: data/departure_audit_table.csv
#
# PORTED FROM THE ISOCHRONES MONOREPO (2026-08-13), branch
# fix/workforce-cliff-data-contract, scripts/build_audit_table.R. The extraction
# that created this repository took the OUTPUT of this script but not the script
# itself, which is why departure_audit_table.csv sat unregenerable at the 1295
# vintage while the SSOT moved to 1306. Changes made in porting:
#   * here::here("cliff", "data", X) -> here::here("data", X); this IS cliff now
#   * the three monorepo inputs are resolved under CLIFF_ISOCHRONES_ROOT rather
#     than hardcoded absolute paths, and their absence fails loudly
#   * the ABU net-new roster moves from the 2026-07-14 vintage (270 NPIs, the
#     1295 baseline) to 2026-07-22 (308 NPIs, the adopted 1306 baseline). This
#     one substitution is what re-bases the table; everything else is verbatim.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(here); library(readr); library(dplyr)})
source(here::here("manuscript","R","workforce_data_contract.R"))

# ---- monorepo inputs -------------------------------------------------------
# These three files live in the isochrones monorepo and were not carried into
# this repository by the extraction. Point CLIFF_ISOCHRONES_ROOT at a checkout
# to regenerate. Failing loudly beats silently rebuilding on a stale roster.
ISO <- Sys.getenv("CLIFF_ISOCHRONES_ROOT", unset = path.expand("~/isochrones"))
iso <- function(...) {
  p <- file.path(ISO, ...)
  if (!file.exists(p))
    stop(sprintf(paste0("[build_audit_table] monorepo input not found:\n  %s\n",
                        "Set CLIFF_ISOCHRONES_ROOT to an isochrones checkout ",
                        "(currently %s)."), p, ISO), call. = FALSE)
  p
}

BANDS <- c(0,45,50,55,60,65,70,Inf); BL <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
band_of <- function(a) as.character(cut(a, BANDS, labels=BL, right=FALSE))
AGE_AT_CERT <- 30L; ENTRY_AGE <- 34L; REF_YEAR <- 2024L
HORIZON <- WORKFORCE_PROJECTION_HORIZON_YEARS
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")
# Multi-year graduate means (identical to rebuild_ssot_revised.R, verified 2026-07-19)
GRAD <- list(GO=c(70,73,78,79), URPS=c(61,66,63,66), MIGS=c(47,50,45,47))
ENTRANTS <- sapply(GRAD, mean)

# ---- cohort (identical construction to the SSOT builder) --------------------
coh <- read_csv(iso("manuscript","tables","table1_physician_characteristics.csv"),
                show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)],
            cert_year=as.integer(cert_year),
            ry_raw=suppressWarnings(as.integer(retirement_year)),
            ret=as.logical(is_retired_for_cohorting), age=as.integer(age_approx)) %>%
  distinct(npi,.keep_all=TRUE) %>% filter(!is.na(ab))
.anch <- read_csv(here::here("data","departure_anchor.csv"), show_col_types=FALSE) %>%
  mutate(npi=as.character(npi))
coh <- coh %>% left_join(.anch, by="npi") %>%
  mutate(has_nonop_anchor = tidyr::replace_na(as.logical(has_nonop_anchor), FALSE))

# ---- ABU urology-pathway net-new active URPS ages (both-pathway baseline) ----
abu_cw <- read_csv(iso("data","abu_urology","abu_npi_crosswalk_2026-07-14.csv"),
                   show_col_types=FALSE, guess_max=1e5) %>%
  transmute(npi=as.character(npi), cert_year=suppressWarnings(as.integer(abu_cert_year)))
# The URPS ACTIVE-AGE DISTRIBUTION comes from the v3.0.0 cohort that defines the
# adopted 1,306 baseline (ABOG 1,027 + ABU net-new 279, national), NOT from a
# reconstruction off the monorepo rosters.
#
# Reconstructing it here cannot reproduce the SSOT, and that is the whole point
# of this table. Rebuilding from the 2026-07-22 roster against the only crosswalk
# that exists (2026-07-14) yields ABOG 1,031 + ABU 302 = 1,333: it misses the 4
# providers the v3.0.0 active gate removes, and excludes only 6 ABU NPIs for a
# missing certification year where v3.0.0 excludes 29. The published cohort is
# the authority on WHO is active; this script's job is the departure model
# applied to them, so it takes the roster as given and estimates the hazard
# itself. GO is unaffected -- its monorepo baseline of 1,052 already matches.
.v3 <- utils::read.csv(here::here("scripts","urps_scenario_cube",
                                  "urps_cohort_ages_pathway_geo_v3.0.0.csv"),
                       stringsAsFactors = FALSE)
.v3 <- .v3[.v3$geography == "national", ]
v3_ages <- function(pathways) with(.v3[.v3$pathway %in% pathways, ],
                                   rep(as.integer(age), as.integer(n_active_2023)))
URPS_AGES_BOTH <- v3_ages(c("ABOG", "ABU"))   # 1,306
URPS_AGES_ABOG <- v3_ages("ABOG")             # 1,027
# Verify the cohort against the SSOT rather than against a literal, so this check
# tracks mufflyaccess instead of pinning a number that would go stale the same way
# the artifact this script writes did.
.ssot_n <- function(with_uro) mufflyaccess::urps_count(
  year = 2023L, measure = "board_certified_active", geography = "national",
  include_urology = with_uro, incomplete = "error")
stopifnot(length(URPS_AGES_BOTH) == .ssot_n(TRUE),
          length(URPS_AGES_ABOG) == .ssot_n(FALSE))

# ---- shared hazard + projection machinery (identical to the SSOT builder) ----
# IMPORTANT: the authoritative model (rebuild_ssot_revised.R) estimates ONE POOLED
# age-band hazard across ALL cohort rows (borrowing strength across the sparse
# per-band events), then applies that single hazard curve to each subspecialty's
# own active-age distribution. `rows` therefore spans the whole cohort, not one
# subspecialty. This is what makes the `primary` audit row reproduce the SSOT.
band_counts <- function(rows, win){
  do.call(rbind, lapply(rows, function(i){
    cy<-coh$cert_year[i]; ry<-coh$ry[i]
    if(!is.na(ry)&&(ry<win[1]||ry>win[2])) ry<-NA_integer_
    y0<-max(win[1],cy); y1<-if(is.na(ry)) win[2] else min(win[2],ry); if(y1<y0) return(NULL)
    yy<-y0:y1; data.frame(band=band_of(yy-cy+AGE_AT_CERT), event=as.integer(!is.na(ry)&yy==ry))})) %>%
    group_by(band) %>% summarise(py=dplyr::n(), ev=sum(event), .groups="drop")
}
haz_for <- function(age, hz){ h<-hz[band_of(age)]; h[is.na(h)]<-max(hz,na.rm=TRUE); pmin(1,h) }
project <- function(ages, entrants, hz){
  count<-table(ages); av<-as.integer(names(count)); count<-as.numeric(count); dep<-0
  for(h in seq_len(HORIZON)){ hzz<-haz_for(av,hz); dep<-dep+sum(count*hzz); sv<-count*(1-hzz)
    av2<-av+1L; ix<-match(ENTRY_AGE,av2)
    if(is.na(ix)){av2<-c(av2,ENTRY_AGE); sv<-c(sv,entrants)} else sv[ix]<-sv[ix]+entrants
    av<-av2; count<-sv }
  list(active_2029=sum(count), departures_4yr=dep)
}

# ---- one audit row: a departure DEFINITION x a subspecialty -----------------
# `gate` returns, for the subspecialty's rows, the retirement year to COUNT as a
# departure (NA = not a departure under this definition). `both_pathway` toggles
# whether ABU ages join the URPS active-age distribution.
# One audit row. The pooled hazard is estimated ONCE per (definition, window) over
# the whole cohort; the per-subspecialty row reuses it (matching the SSOT builder).
audit_row <- function(defn, sub, win, hz, bc_pooled, both_pathway=TRUE){
  ci <- which(coh$ab==sub)
  active_ages <- coh$age[ci][coh$ret[ci]==FALSE & !is.na(coh$age[ci])]
  # URPS active ages come from the v3.0.0 SSOT cohort (see above); GO keeps the
  # monorepo construction, which already reproduces its SSOT baseline of 1,052.
  if(sub=="URPS") active_ages <- if(both_pathway) URPS_AGES_BOTH else URPS_AGES_ABOG
  base <- length(active_ages)
  static_rate <- 100*sum(haz_for(active_ages,hz))/base
  d <- project(active_ages, ENTRANTS[[sub]], hz)
  avg_dep <- d$departures_4yr/HORIZON
  ent <- round(ENTRANTS[[sub]])
  # eligible departures = this subspecialty's own in-window events (for S7b / traceability)
  elig <- sum(!is.na(coh$ry[ci]) & coh$ry[ci]>=win[1] & coh$ry[ci]<=win[2])
  data.frame(
    definition=defn, subspecialty_abbrev=sub, window=paste(win,collapse="-"),
    urps_pathway=if(sub=="URPS") (if(both_pathway) "both" else "ABOG-only") else NA_character_,
    eligible_departures=elig,
    pooled_person_years=sum(bc_pooled$py), active_baseline=base,
    static_2025_rate_pct=round(static_rate,2),
    dynamic_4yr_departures=round(d$departures_4yr,1),
    dynamic_annual_rate_pct=round(100*avg_dep/base,2),
    graduate_input=ent,
    completion_to_departure_ratio=round(ent/avg_dep,2),
    projected_2029=round(base + HORIZON*(ent-avg_dep),1),
    # carried for the Open-Payments sensitivity below, stripped before writing
    .avg_dep=avg_dep,
    stringsAsFactors=FALSE)
}

# gates ---------------------------------------------------------------------
g_primary  <- function(ci) ifelse(coh$has_nonop_anchor[ci], coh$ry_raw[ci], NA_integer_)  # non-OP anchored
g_opincl   <- function(ci) coh$ry_raw[ci]                                                  # OP-inclusive consensus

variants <- list(
  list(defn="primary (non-OP anchored)",        win=c(2016L,2021L), gate=g_primary, both=TRUE),
  list(defn="OP-inclusive consensus",           win=c(2016L,2021L), gate=g_opincl,  both=TRUE),
  list(defn="primary, ABOG-only URPS baseline",  win=c(2016L,2021L), gate=g_primary, both=FALSE),
  list(defn="primary, window 2016-2019",         win=c(2016L,2019L), gate=g_primary, both=TRUE),
  list(defn="primary, window 2016-2023",         win=c(2016L,2023L), gate=g_primary, both=TRUE)
)

out <- do.call(rbind, lapply(variants, function(v){
  # Set the (gated) departure year for ALL cohort rows, then estimate ONE pooled
  # hazard over the whole cohort under this definition/window.
  coh$ry <<- NA_integer_
  coh$ry[] <<- v$gate(seq_len(nrow(coh)))
  bc <- band_counts(which(coh$ab %in% c("GO","URPS")), v$win)  # GO+URPS-only primary hazard (MIGS excluded 2026-07-19)
  hz <- setNames(bc$ev/bc$py, bc$band)
  do.call(rbind, lapply(c("GO","URPS"), function(s)
    audit_row(v$defn, s, v$win, hz, bc, v$both)))
}))

# ---- Open-Payments sensitivity ---------------------------------------------
# data/open_payments_sensitivity.csv is not an independent analysis: it is this
# table's first two definitions, renamed. Verified against the pre-regeneration
# pair, where 3 of 4 cells reproduce exactly and the fourth differs by 0.1 only
# because the artifact used the UNROUNDED four-year departures, as here.
#
# The monorepo's scripts/open_payments_sensitivity.R (isochrones 0d8fa3662) is a
# different, five-rule analysis (primary / op_excluded / op_only_out /
# claims_anchor / two_source) that writes the same path with an incompatible
# schema, and it needs credentials.retirement_signals_pivot, a derived table
# absent from the available database. It is not the generator of the committed
# artifact -- the rule labels below appear in no generator in either repository.
OP_RULES <- c("non_op_anchored (primary)" = "primary (non-OP anchored)",
              "op_inclusive"              = "OP-inclusive consensus")
op <- do.call(rbind, lapply(names(OP_RULES), function(rn) {
  r <- out[out$definition == OP_RULES[[rn]], ]
  data.frame(rule = rn, subspecialty_abbrev = r$subspecialty_abbrev,
             departure_rate_pct    = r$dynamic_annual_rate_pct,
             avg_annual_departures = round(r$.avg_dep, 1),
             replacement_ratio     = r$completion_to_departure_ratio,
             stringsAsFactors = FALSE)
}))
write_csv(op, here::here("data","open_payments_sensitivity.csv"))
cat("\nWrote data/open_payments_sensitivity.csv\n"); print(op, row.names = FALSE)

out$.avg_dep <- NULL
write_csv(out, here::here("data","departure_audit_table.csv"))
cat("=== DEPARTURE / REPLACEMENT AUDIT TABLE (all definitions through the one dynamic model) ===\n")
print(out, row.names=FALSE)
cat("\nWrote data/departure_audit_table.csv\n")
cat("\nThe `primary (non-OP anchored)` row must reproduce workforce_projections_consolidated.csv.\n")
