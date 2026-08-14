#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Operative-workforce SECONDARY analysis, reviewer-revision build (GO + URPS).
# Addresses peer-review points #1 (procedure-volume capacity ratio), #4 (correct
# active denominator), #6 (time-to-event operative-entry numerator), #9 (automated
# cross-signal adjudication + stratified sample). All Medicare-provisional.
#
# Endpoint renamed per review: the measured administrative event is SUSTAINED
# CESSATION OF MEDICARE-OBSERVED QUALIFYING SURGERY (not "permanent operative
# retirement"). "Operative retirement" is retained only as the conceptual phenomenon.
#
# Volume unit = annual count of qualifying major operative services (Medicare Part B
# Tot_Srvcs summed over the URPS/GO major-operation HCPCS list) per NPI per year.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(DBI); library(duckdb); library(dplyr); library(tidyr); library(readr); library(here)})



# OB/GYN-sponsored URPS fellowship completions per year (Appendix Table D.5).
# The urology-sponsored ~16 are excluded: this analysis is ABOG-pathway only.
URPS_ABOG_GRADS_PER_YR <- 48L

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
    stop(sprintf("[%s] monorepo input not found:\n  %s", "operative_capacity_and_validation", p), call. = FALSE)
  p
}

OP_CODES <- unique(c(
  "58210","58285","58548","58952","58953","58954","58956","58957","58958",
  "38570","38571","38572","38573","38747","38760","38765","38792","38900","49255",
  "56630","56631","56632","56633","56634","56637","56640","57110","57111","57112","45126","51597","58240",
  "57288","51715","51840","51841","51990","51992","57287","57425","57280","57282","57283",
  "57240","57250","57260","57265","57267","57268","57270","57284","57285","57120",
  "57300","57305","57307","57308","57310","57311","57320","57330","64555","64561","64566","64581","64585","64590",
  "58541","58542","58543","58544","58545","58546","58550","58552","58570","58571","58572","58573",
  "58555","58558","58559","58560","58561","58562","58563","58353","58356","49320","49321","58660","58661","58662","S2900"))

YEARS <- 2013:2023; DATA_END <- 2023L; WIN <- c(2016L, 2020L)
EST_MIN <- 3L; CONFIRM <- 3L; AGE_AT_CERT <- 30L
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology")

coh <- read_csv(iso("manuscript", "tables", "table1_physician_characteristics.csv"),
                show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), name=physician_name,
            ab=names(SUBS)[match(subspecialty,SUBS)],
            cy=as.integer(cert_year), age=as.integer(age_approx),
            last_billing=suppressWarnings(as.integer(last_billing_year)),
            deactivated = !is.na(npi_deactivation_date) & nzchar(as.character(npi_deactivation_date)),
            retired=as.logical(is_retired_for_cohorting)) %>%
  distinct(npi,.keep_all=TRUE) %>% filter(!is.na(ab))

# --- pull operative services (Tot_Srvcs over OP_CODES) AND total services per NPI-year
db <- NA_character_
for (c in c("/Volumes/MufflySamsung/DuckDB/nber_my_duckdb.duckdb",
            "/Volumes/MufflySamsung 1/DuckDB/nber_my_duckdb.duckdb")) if (file.exists(c)) { db<-c; break }
if (is.na(db)) stop("NBER DuckDB not mounted.")
con <- dbConnect(duckdb::duckdb(), db, read_only=TRUE)
duckdb::duckdb_register(con, "coh_npi", data.frame(npi=coh$npi))
codelist <- paste(sprintf("'%s'", OP_CODES), collapse=",")
pull <- function(where) do.call(rbind, lapply(YEARS, function(y){
  tb <- sprintf("main.medicare_part_b_by_service_%d", y)
  q <- sprintf("SELECT CAST(b.Rndrng_NPI AS VARCHAR) npi, %d AS yr, SUM(b.Tot_Srvcs) v
                FROM %s b JOIN coh_npi c ON CAST(b.Rndrng_NPI AS VARCHAR)=c.npi
                WHERE b.Tot_Srvcs > 0 %s GROUP BY 1,2", y, tb, where)
  tryCatch(dbGetQuery(con, q), error=function(e) NULL)
}))
op_serv  <- pull(sprintf("AND b.HCPCS_Cd IN (%s)", codelist))   # qualifying operative services
tot_serv <- pull("")                                            # all Medicare Part B services
dbDisconnect(con, shutdown=TRUE)

mat <- function(df){
  W <- df %>% mutate(v=as.numeric(v)) %>% complete(npi=coh$npi, yr=YEARS, fill=list(v=0)) %>%
    pivot_wider(names_from=yr, values_from=v, values_fill=0)
  m <- as.matrix(W[,-1]); rownames(m)<-W$npi; colnames(m)<-as.character(YEARS); m[coh$npi,,drop=FALSE]
}
opm  <- mat(op_serv)    # operative service counts (volume)
totm <- mat(tot_serv)   # total Part B service counts

# established operator: >=EST_MIN qualifying ops in >=2 of prior 3 yrs; last op; cessation
estab_year <- function(v){ for(i in seq_along(YEARS)){ y<-YEARS[i]; pr<-v[as.character((y-3):(y-1))]; pr<-pr[!is.na(pr)]
  if(sum(pr>=EST_MIN)>=2) return(y) }; NA_integer_ }
last_op  <- function(v){ w<-which(v>0); if(length(w)) YEARS[max(w)] else NA_integer_ }

d <- coh %>% mutate(
  estab_year = vapply(seq_len(nrow(opm)), function(i) estab_year(opm[i,]), integer(1)),
  last_op    = vapply(seq_len(nrow(opm)), function(i) last_op(opm[i,]), integer(1)),
  ever_established = !is.na(estab_year),
  ceased = ever_established & !is.na(last_op) & last_op <= (DATA_END-CONFIRM),
  cess_year = ifelse(ceased, last_op+1L, NA_integer_),
  cess_in_win = ceased & cess_year>=WIN[1] & cess_year<=WIN[2],
  age_at_cess = cess_year - cy + AGE_AT_CERT,
  active = retired==FALSE)

vol_in <- function(i, yrs){ yrs<-yrs[yrs>=min(YEARS)&yrs<=max(YEARS)]; if(!length(yrs)) return(NA_real_)
  vv<-opm[i, as.character(yrs)]; vv<-vv[!is.na(vv)]; if(!length(vv)) NA_real_ else mean(vv) }
totlast <- function(i){ w<-which(totm[i,]>0); if(length(w)) YEARS[max(w)] else NA_integer_ }

# ---------- assemble per-subspecialty outputs ----------
wf <- list(); cap <- list(); adj <- list(); tte <- list(); samples <- list()
for(k in names(SUBS)){
  idx <- which(d$ab==k); dk <- d[idx,]
  n_active <- sum(dk$active)
  n_estab  <- sum(dk$ever_established)
  # ---- #4 corrected denominator: operators / ACTIVE board-certified cohort ----
  # (previously divided by total cohort incl. retired -> understated %)
  wf[[k]] <- data.frame(subspecialty_abbrev=k,
    n_active_cohort=n_active,
    medicare_visible_operators=n_estab,
    pct_of_active_visible=round(100*n_estab/n_active,1),
    operative_cessation_rate_pct=NA_real_,  # filled below
    median_age_at_op_cessation=NA_integer_,
    pct_still_billing_after=NA_real_)

  # cessation rate (person-years in window) + age + still-billing
  ev <- sum(dk$cess_in_win); py <- 0
  for(i in which(dk$ever_established)){ L<-dk$last_op[i]; if(is.na(L)) next
    y1<-min(WIN[2], if(!is.na(dk$cess_year[i])) dk$cess_year[i] else WIN[2])
    y0<-max(WIN[1], if(!is.na(dk$estab_year[i])) dk$estab_year[i] else WIN[1]); py<-py+max(0,y1-y0+1) }
  wf[[k]]$operative_cessation_rate_pct <- round(100*ev/py,2)
  aad <- dk$age_at_cess[dk$cess_in_win]
  wf[[k]]$median_age_at_op_cessation <- if(length(aad)) as.integer(median(aad,na.rm=TRUE)) else NA
  sb <- dk$cess_in_win & !is.na(dk$last_billing) & dk$last_billing > dk$last_op
  wf[[k]]$pct_still_billing_after <- round(100*sum(sb)/max(1,ev),0)

  # ---- #1 procedure-volume capacity ratio ----
  # retiring operators: mean annual operative volume in final 2 operative years
  cess_i <- idx[dk$cess_in_win]
  retvol <- vapply(cess_i, function(i){ L<-d$last_op[i]; vol_in(i, c(L-1L, L)) }, numeric(1))
  ret_percapita <- mean(retvol, na.rm=TRUE)
  retirers_per_yr <- ev/(WIN[2]-WIN[1]+1)
  # entrants: grads cert 2013-2018 (yrs 3-5 fully observable) who became established operators;
  # mean annual operative volume in post-cert years 3-5
  ent_mask <- d$ab==k & d$cy>=2013 & d$cy<=2018 & d$ever_established
  ent_i <- which(ent_mask)
  entvol <- vapply(ent_i, function(i){ c0<-d$cy[i]; vol_in(i, c(c0+3L,c0+4L,c0+5L)) }, numeric(1))
  ent_percapita <- mean(entvol, na.rm=TRUE)
  # entrant flow per yr = grads becoming established operators / yr (from TTE plateau below);
  # placeholder here, recomputed after TTE
  cap[[k]] <- data.frame(subspecialty_abbrev=k,
    retiring_operators_in_window=ev,
    retiring_mean_annual_op_volume=round(ret_percapita,1),
    entrant_operators_2013_2018=length(ent_i),
    entrant_mean_annual_op_volume_yr3to5=round(ent_percapita,1),
    volume_per_capita_ratio=round(ent_percapita/ret_percapita,2))

  # ---- #6 time-to-event: cumulative incidence of becoming established operator ----
  # cohorts cert 2013-2020; time = estab_year - cy (>=0); follow-up = DATA_END - cy
  co <- d[d$ab==k & d$cy>=2013 & d$cy<=2020, ]
  co$t <- ifelse(co$ever_established & (co$estab_year-co$cy)>=0, co$estab_year-co$cy, NA_integer_)
  co$fu <- DATA_END - co$cy
  km <- 1; ci <- c()
  for(kk in 1:8){
    n_risk <- sum(co$fu>=kk & (is.na(co$t) | co$t>=kk))
    d_k    <- sum(!is.na(co$t) & co$t==kk)
    km <- km * (1 - ifelse(n_risk>0, d_k/n_risk, 0)); ci[kk] <- 1-km
  }
  ci_plateau <- ci[8]   # cumulative prob of ever becoming established Medicare operator
  tte[[k]] <- data.frame(subspecialty_abbrev=k,
    cohort_grads_2013_2020=nrow(co),
    ci_operator_by3yr=round(ci[3],3), ci_operator_by5yr=round(ci[5],3),
    ci_operator_by8yr=round(ci_plateau,3))

  entrants_per_yr_tte <- NA  # multiply CI by ACGME graduate count downstream (see note)
  cap[[k]]$entrant_operator_conversion_prob <- round(ci_plateau,3)

  # ---- #9 automated cross-signal adjudication of cessations ----
  cd <- dk[dk$cess_in_win, ]
  tot_last <- vapply(cess_i, function(i) totlast(i), integer(1))
  total_billing_stopped <- !is.na(tot_last) & tot_last <= (cd$last_op + 1L)
  nppes_deact <- cd$deactivated
  age_under_50 <- !is.na(cd$age_at_cess) & cd$age_at_cess < 50
  corroborated <- total_billing_stopped | nppes_deact   # independent evidence of true exit
  adj[[k]] <- data.frame(subspecialty_abbrev=k,
    n_cessations=nrow(cd),
    pct_total_billing_continued=round(100*mean(!total_billing_stopped),0),
    pct_total_billing_stopped=round(100*mean(total_billing_stopped),0),
    pct_nppes_deactivated=round(100*mean(nppes_deact),0),
    pct_age_under_50=round(100*mean(age_under_50),0),
    pct_corroborated_true_exit=round(100*mean(corroborated),0))

  samples[[k]] <- data.frame(subspecialty_abbrev=k, npi=cd$npi, name=cd$name,
    cert_year=cd$cy, last_operating_year=cd$last_op, cessation_year=cd$cess_year,
    est_age_at_cessation=cd$age_at_cess, last_total_billing_year=tot_last,
    total_billing_continued=!total_billing_stopped, nppes_deactivated=nppes_deact,
    stratum = ifelse(age_under_50, "age<50",
              ifelse(!total_billing_stopped, "billing-continued", "corroborated-exit")))
}

WF  <- bind_rows(wf);  CAP <- bind_rows(cap); ADJ <- bind_rows(adj); TTE <- bind_rows(tte)
SAMP<- bind_rows(samples)

# capacity ratio needs an entrant flow: operators produced/yr = ACGME grads/yr * conversion prob.
# Read current SSOT graduate counts (updated separately for the ACGME both-pathway fix).
ss <- read_csv(here::here("data","workforce_projections_consolidated.csv"), show_col_types=FALSE)
CAP <- CAP %>% mutate(
  # ABOG-PATHWAY graduate entry, not the both-pathway SSOT count. Appendix S12
  # states that this operative analysis uses the ABOG-pathway URPS cohort only,
  # because the ABU roster is not claims-linkable, and that "both the operator
  # denominator and the graduate-entry numerator are therefore ABOG-pathway".
  # ss$annual_entrants is the both-pathway 64 (OB/GYN-sponsored 48 +
  # urology-sponsored ~16, Appendix Table D.5); using it here inflated the
  # capacity ratio by a third, to 2.80 against the published 2.10.
  acgme_grads_per_yr = ifelse(
    subspecialty_abbrev == "URPS", URPS_ABOG_GRADS_PER_YR,
    ss$annual_entrants[match(subspecialty_abbrev, ss$subspecialty_abbrev)]),
  operators_produced_per_yr = round(acgme_grads_per_yr * entrant_operator_conversion_prob,1),
  # steady-state operator loss flow = cessation hazard x current operator pool
  # (consistent basis with operators_produced_per_yr = grads/yr x eventual conversion)
  retirers_per_yr = round(WF$operative_cessation_rate_pct/100 * WF$medicare_visible_operators,1),
  volume_lost_per_yr = round(retirers_per_yr * retiring_mean_annual_op_volume,0),
  volume_added_per_yr = round(operators_produced_per_yr * entrant_mean_annual_op_volume_yr3to5,0),
  operator_count_replacement = round(operators_produced_per_yr / retirers_per_yr,2),
  operative_workforce_capacity_ratio = round(volume_added_per_yr / volume_lost_per_yr,2))

dir.create(here::here("data"), showWarnings=FALSE, recursive=TRUE)
write_csv(WF,  here::here("data","operative_workforce.csv"))
write_csv(CAP, here::here("data","operative_capacity.csv"))
write_csv(ADJ, here::here("data","operative_adjudication.csv"))
write_csv(TTE, here::here("data","operative_tte.csv"))
write_csv(SAMP,here::here("data","operative_cessation_adjudication_sample.csv"))

cat("=== #4 corrected denominators + cessation ===\n"); print(as.data.frame(WF), row.names=FALSE)
cat("\n=== #1 procedure-volume capacity ratio ===\n")
print(as.data.frame(CAP %>% select(subspecialty_abbrev, retiring_mean_annual_op_volume,
  entrant_mean_annual_op_volume_yr3to5, entrant_operator_conversion_prob, operators_produced_per_yr,
  retirers_per_yr, volume_lost_per_yr, volume_added_per_yr, operative_workforce_capacity_ratio)), row.names=FALSE)
cat("\n=== #6 time-to-event operator-entry cumulative incidence ===\n"); print(as.data.frame(TTE), row.names=FALSE)
cat("\n=== #9 automated cross-signal adjudication ===\n"); print(as.data.frame(ADJ), row.names=FALSE)
cat(sprintf("\nWrote operative_workforce/capacity/adjudication/tte CSVs + %d-row adjudication sample.\n", nrow(SAMP)))
cat("MEDICARE-PROVISIONAL throughout; capacity uses qualifying operative service counts as volume unit.\n")
