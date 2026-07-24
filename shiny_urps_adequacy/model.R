# Canonical URPS effective-adequacy model — SINGLE SOURCE OF TRUTH (Guard 57).
# Sourced by app.R and by tests/testthat/. Every KPI, plot, readout, and
# download in the app derives from project() defined here; the guard suite
# tests project() directly so the app and the tests exercise identical logic.
#
# NOTE on "effective FTE" semantics (see guard suite): effective FTE is an
# age-productivity- and clinical-time-weighted CAPACITY index, normalized so
# effective(2025) == headcount(2025). It is NOT an absolute hours-based FTE
# capped at 1 per physician; a workforce younger than the 2025 age mix can
# therefore exceed headcount. The invariant we assert is effective(2025) ==
# headcount(2025), not effective <= headcount.

suppressPackageStartupMessages(library(data.table))

dpath <- function(f) {
  roots <- c("data", "cliff/shiny_urps_adequacy/data", ".",
             "../data", "../../data", "../../../data", "../../../../data")
  for (r in roots) if (file.exists(file.path(r, f))) return(file.path(r, f))
  f
}

source(dpath("urps_model_data.R"))                                   # URPS_AGES, BAND_*, HAZ_WINDOWS
APC    <- fread(dpath("urps_module_a_age_productivity_2026-07-23.csv"))
DEMAND <- fread(dpath("urps_supply_demand_national_2026-07-23.csv"))

## ── fixed model pieces ───────────────────────────────────────────────────────
N_OBGYN <- 1031; N_URO <- 308; N_TOT <- N_OBGYN + N_URO             # baseline 1,339
OB_BASE_SHARE <- N_OBGYN / N_TOT                                    # 0.770
BASE_YEAR <- 2025L
BANDS <- c(0,45,50,55,60,65,70,Inf)
band_of <- function(age) as.character(cut(age, breaks=BANDS, labels=BAND_LABELS, right=FALSE))
HZ  <- HAZ_WINDOWS[["fully_obs"]]; HZ[is.na(HZ)] <- max(HZ, na.rm=TRUE)
HZ  <- pmin(1, HZ); names(HZ) <- BAND_LABELS   # pmin() strips names -> must re-apply
haz_for <- function(age) { h <- HZ[band_of(age)]; h[is.na(h)] <- max(HZ); pmin(1, h) }
wfun <- function(a) { a <- pmin(pmax(a, min(APC$age)), max(APC$age)); APC$rel_to_peak[match(a, APC$age)] }
count0 <- as.numeric(table(URPS_AGES)); av0 <- as.integer(names(table(URPS_AGES)))
WBAR <- sum(count0 * wfun(av0)) / sum(count0)                       # normalize age-weight avg -> 1
w <- function(a) wfun(a) / WBAR

# Documented default (frozen manuscript) scenario — Guard 63/71 reference.
DEFAULTS <- list(retire=65L, entrants=64L, entry_age=34L, fte_new=0.90,
                 obgyn_share=OB_BASE_SHARE, uro_fte=0.70, haz_mult=1.0,
                 demand_mult=1.0, weight_on=TRUE, end_year=2050L)

MODEL_VERSION <- "1.0"
DATA_THROUGH  <- "2024"

## ── the projection (canonical) ───────────────────────────────────────────────
# Returns one row per projected year 2025..end_year with headcount, effective,
# mean_age, sd_age, demand, indices, adequacy, capacity gap (>0 = shortage).
project <- function(retire_age, entrants, entry_age, fte_new, obgyn_share,
                    uro_fte, haz_mult, demand_mult, weight_on, end_year) {
  ages <- av0; nb <- count0; nn <- rep(0, length(count0))          # base vs new cohorts
  base_blend <- OB_BASE_SHARE*1.0 + (1-OB_BASE_SHARE)*uro_fte      # baseline pathway blend (fixed 77/23)
  new_blend  <- obgyn_share*1.0   + (1-obgyn_share)*uro_fte        # entrant pathway blend
  rows <- vector("list", end_year-BASE_YEAR+1); k <- 0
  for (yr in BASE_YEAR:end_year) {
    wv  <- if (weight_on) w(ages) else rep(1, length(ages))
    hc  <- sum(nb)+sum(nn); cnt <- nb+nn; ma <- sum(ages*cnt)/hc
    eff <- sum(wv*nb)*base_blend + sum(wv*nn)*new_blend*fte_new
    k <- k+1; rows[[k]] <- data.table(YEAR=yr, headcount=hc, effective=eff,
                                      mean_age=ma, sd_age=sqrt(sum(cnt*(ages-ma)^2)/hc))
    h <- pmin(1, haz_for(ages)*haz_mult); h[ages >= retire_age] <- 1
    nb <- nb*(1-h); nn <- nn*(1-h)
    ages <- ages+1L; ix <- match(entry_age, ages)
    if (is.na(ix)) { ages<-c(ages,entry_age); nb<-c(nb,0); nn<-c(nn,entrants) }
    else nn[ix] <- nn[ix]+entrants
  }
  d <- rbindlist(rows)
  d <- merge(d, DEMAND[, .(YEAR, w65=women_65plus)], by="YEAR")
  b <- d[YEAR==BASE_YEAR]
  d[, dem_growth := 1 + (w65/b$w65 - 1)*demand_mult]
  d[, `:=`(hc_index=100*headcount/b$headcount, eff_index=100*effective/b$effective,
           dem_index=100*dem_growth,
           adeq_hc=(headcount/b$headcount)/dem_growth,
           adeq_eff=(effective/b$effective)/dem_growth)]
  # Capacity gap, ASSUMING 2025 supply-demand BALANCE:
  # demand-equivalent effective FTE = effective(2025) x demand growth; gap = required - supplied.
  d[, req_fte  := b$effective * dem_growth]
  d[, shortfall := req_fte - effective]              # >0 = capacity gap (shortage of effective FTE)
  d[, demand := req_fte]                             # alias: demand-equivalent effective FTE
  d[, capacity_gap := shortfall]                     # alias: canonical name
  validate_scenario_projection(d)                    # hard-fail on any identity violation
  attr(d, "scenario_fp") <- scenario_fp(list(retire=retire_age, entrants=entrants, entry_age=entry_age,
    fte_new=fte_new, obgyn_share=obgyn_share, uro_fte=uro_fte, haz_mult=haz_mult,
    demand_mult=demand_mult, weight_on=weight_on, end_year=end_year))
  d[]
}

# Convenience: run project() from a named list (the DEFAULTS shape).
project_from <- function(p) project(p$retire, p$entrants, p$entry_age, p$fte_new,
  p$obgyn_share, p$uro_fte, p$haz_mult, p$demand_mult, p$weight_on, p$end_year)

## ── consistency guard: hard-fail on the canonical algebraic identities ───────
## Called at the end of project(); every projection object is validated, so no
## downstream output can display a value that violates these relationships.
validate_scenario_projection <- function(d, tol = 1e-8) {
  yrs <- d$YEAR
  if (anyDuplicated(yrs))                         stop("SSOT: duplicated projection years")
  if (!all(BASE_YEAR:max(yrs) %in% yrs))          stop("SSOT: missing projection years")
  num <- c("headcount","effective","mean_age","sd_age","w65","dem_growth",
           "eff_index","hc_index","dem_index","adeq_eff","adeq_hc","req_fte","shortfall")
  for (col in num) { v <- d[[col]]
    if (any(is.na(v)) || any(!is.finite(v)))      stop(paste("SSOT: NA/non-finite in", col)) }
  if (any(d$headcount < -tol) || any(d$effective < -tol)) stop("SSOT: negative workforce")
  b <- d[YEAR==BASE_YEAR]
  if (max(abs(c(b$eff_index,b$hc_index,b$dem_index)-100)) > 1e-6) stop("SSOT: 2025 index != 100")
  # demand-equivalent = req_fte; supply = effective
  if (any(abs(d$shortfall - (d$req_fte - d$effective)) > tol))    stop("SSOT: gap != demand_eff - supply_eff")
  if (any(abs(d$adeq_eff  - d$effective/d$req_fte)     > tol))    stop("SSOT: adequacy != supply/demand")
  if (any(abs(d$eff_index - 100*d$effective/b$effective) > 1e-6)) stop("SSOT: supply_index identity")
  if (any(abs(d$dem_index - 100*d$req_fte/b$req_fte)     > 1e-6)) stop("SSOT: demand_index identity")
  if (!all(sign(round(d$shortfall,6)) == sign(round(1-d$adeq_eff,9)))) stop("SSOT: gap sign != (adequacy<1)")
  invisible(TRUE)
}

## ── scenario fingerprint: identical inputs -> identical string ───────────────
## Includes every model-changing input + model/data version (Guard: fingerprint
## covers all inputs). A change to any one flips the fingerprint.
scenario_fp <- function(p) paste(
  sprintf("retire=%s", p$retire), sprintf("entrants=%s", p$entrants),
  sprintf("entry_age=%s", p$entry_age), sprintf("fte_new=%.2f", p$fte_new),
  sprintf("obgyn=%.3f", p$obgyn_share), sprintf("uro_fte=%.2f", p$uro_fte),
  sprintf("haz=%.2f", p$haz_mult), sprintf("demand=%.2f", p$demand_mult),
  sprintf("weight=%s", p$weight_on), sprintf("end=%s", p$end_year),
  sprintf("mv=%s", MODEL_VERSION), sprintf("dv=%s", DATA_THROUGH), sep="|")

`%||%` <- function(a, b) if (is.null(a)) b else a

## Reference = EXACT equality with the frozen defaults on every model-changing input.
is_reference_scenario <- function(params, defaults = DEFAULTS) {
  keys <- c("retire","entrants","entry_age","fte_new","obgyn_share","uro_fte",
            "haz_mult","demand_mult","weight_on","end_year")
  isTRUE(all.equal(params[keys], defaults[keys], check.attributes=FALSE))
}

## ── ONE canonical summary object: every narrative/KPI value derives from here ─
## Built from the canonical projection table; no output recomputes these.
scenario_summary <- function(d, params, defaults = DEFAULTS) {
  H <- params$end_year
  e <- d[YEAR==H]; b <- d[YEAR==BASE_YEAR]; i <- which.min(d$adeq_eff)
  list(
    horizon             = H,
    effective_end       = e$effective,
    headcount_end       = e$headcount,
    eff_growth_pct      = 100*(e$effective/b$effective - 1),
    hc_growth_pct       = 100*(e$headcount/b$headcount - 1),
    dem_growth_pct      = 100*(e$demand/b$demand - 1),
    adequacy_end        = e$adeq_eff,
    met_pct             = round(100*e$adeq_eff),
    capacity_gap_end    = e$capacity_gap,       # >0 = shortfall
    capacity_margin_end = -e$capacity_gap,      # >0 = above requirement
    trough_year         = d$YEAR[i],
    trough_value        = d$adeq_eff[i],
    trough_pct          = round(100*d$adeq_eff[i]),
    mean_age_end        = e$mean_age,
    sd_age_end          = e$sd_age,
    # patient-level translation (per literature: report per-100k + patient consequence,
    # not an abstract FTE gap). Load per FTE grows by 1/adequacy.
    per100k_2025        = 1e5 * b$headcount / b$w65,          # urogynecologists per 100k women 65+
    per100k_end         = 1e5 * e$headcount / e$w65,
    women_per_efte_2025 = b$w65 / b$effective,               # women 65+ per effective FTE
    women_per_efte_end  = e$w65 / e$effective,
    load_increase_pct   = 100*((e$w65/e$effective)/(b$w65/b$effective) - 1),
    is_reference        = is_reference_scenario(params, defaults),
    fingerprint         = attr(d, "scenario_fp") %||% scenario_fp(params))
}

## ── contract validator: hard-fail if the SUMMARY disagrees with the projection ─
## Catches stale labels/KPIs/ranges/downloads even when every number is itself
## algebraically correct — the failure mode from the screenshots.
validate_scenario_contract <- function(projection_tbl, params, summary_vals,
                                       defaults = DEFAULTS, tol = 1e-8) {
  d <- projection_tbl
  req <- c("YEAR","headcount","effective","demand","hc_index","eff_index","dem_index",
           "adeq_eff","capacity_gap","mean_age","sd_age")
  miss <- setdiff(req, names(d)); if (length(miss)) stop(paste("contract: missing cols:", paste(miss, collapse=", ")))
  if (anyDuplicated(d$YEAR))          stop("contract: duplicated years")
  if (!all(diff(d$YEAR) == 1L))       stop("contract: non-consecutive years")
  if (max(d$YEAR) != params$end_year) stop("contract: horizon != selected end_year")
  for (col in setdiff(req, "YEAR")) if (any(!is.finite(d[[col]]))) stop(paste("contract: non-finite in", col))
  if (any(d$headcount < -tol) || any(d$effective < -tol)) stop("contract: negative workforce")
  if (any(d$demand <= 0))             stop("contract: demand <= 0")
  # NOTE: 'effective <= headcount' is deliberately NOT enforced — effective FTE is an
  # age-productivity index normalized to 2025=headcount, so a younger-than-2025 workforce
  # can exceed headcount. Enforcing it would false-fail valid scenarios (see guard suite).
  b <- d[YEAR==BASE_YEAR]
  if (max(abs(c(b$hc_index,b$eff_index,b$dem_index)-100)) > 1e-6) stop("contract: baseline index != 100")
  if (any(abs(d$adeq_eff - d$eff_index/d$dem_index) > tol))       stop("contract: adequacy != eff_index/dem_index")
  if (abs(b$adeq_eff - 1) > tol)      stop("contract: baseline adequacy != 1")
  if (abs(b$capacity_gap) > tol)      stop("contract: baseline gap != 0")
  sign_ok <- all((d$adeq_eff < 1-tol & d$capacity_gap > -tol) |
                 (d$adeq_eff > 1+tol & d$capacity_gap <  tol) |
                 (abs(d$adeq_eff-1) <= tol & abs(d$capacity_gap) <= tol))
  if (!sign_ok)                       stop("contract: capacity-gap sign disagrees with adequacy")
  # the DISPLAYED summary must match the projection horizon row + trough + label + fingerprint
  e <- d[YEAR==params$end_year]; i <- which.min(d$adeq_eff)
  if (summary_vals$trough_year != d$YEAR[i])                      stop("contract: displayed trough year inconsistent")
  if (abs(summary_vals$trough_value - d$adeq_eff[i]) > tol)       stop("contract: displayed trough value inconsistent")
  if (abs(summary_vals$adequacy_end - e$adeq_eff) > tol)          stop("contract: displayed terminal adequacy inconsistent")
  if (abs(summary_vals$effective_end - e$effective) > tol)       stop("contract: displayed terminal effective inconsistent")
  if (abs(summary_vals$capacity_gap_end - e$capacity_gap) > tol) stop("contract: displayed terminal gap inconsistent")
  if (!identical(summary_vals$is_reference, is_reference_scenario(params, defaults))) stop("contract: reference/custom label incorrect")
  if (!identical(summary_vals$fingerprint, attr(d,"scenario_fp") %||% scenario_fp(params))) stop("contract: summary fingerprint != projection fingerprint")
  invisible(TRUE)
}
