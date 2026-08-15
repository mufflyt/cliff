# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# workforce_cliff_engine.R — SINGLE SOURCE OF TRUTH for the workforce-cliff
# hazard/projection machinery. Every sensitivity script and rebuild_ssot_revised.R
# sources this instead of copy-pasting the constants + band_counts() + project().
# Behavior is byte-identical to the machinery previously duplicated across scripts;
# each consumer was re-run and its output CSV diffed to confirm no change.
#
# Exposed constants: WC_BANDS, WC_BAND_LABELS, WC_WIN, WC_AGE_AT_CERT, WC_HORIZON,
#   WC_ENTRY_AGE, WC_REF_YEAR, WC_YEAR0, WC_SUBS, WC_SUBS_FULL, WC_GRAD, WC_ENTRANTS,
#   WC_ENTRANTS_NRMP, WC_PRIMARY, WC_OBS_END, and the input paths (WC_COHORT_CSV etc.).
# Exposed functions: wc_band_of(), wc_load_cohort(), wc_load_abu_ages(),
#   wc_active_ages(), wc_band_counts(), wc_haz_for(), wc_project(), wc_duckdb_path().
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({library(readr); library(dplyr)})

# ---- constants (verbatim from rebuild_ssot_revised.R) ----------------------
source(here::here("R", "workforce_constants.R"), local = TRUE)   # canonical WORKFORCE_PROJECTION_HORIZON_YEARS
WC_BANDS       <- c(0, 45, 50, 55, 60, 65, 70, Inf)
WC_BAND_LABELS <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
WC_WIN         <- c(2016L, 2021L)
WC_AGE_AT_CERT <- 30L
WC_HORIZON     <- WORKFORCE_PROJECTION_HORIZON_YEARS   # SSOT: shared with the data contract
WC_ENTRY_AGE   <- WORKFORCE_ENTRY_AGE   # SSOT: shared entry age (workforce_constants.R)
WC_REF_YEAR    <- WORKFORCE_REFERENCE_YEAR   # SSOT: shared reference / latest-data year (workforce_constants.R)
WC_YEAR0       <- PROJECTION_BASELINE_YEAR   # SSOT: shared projection baseline (workforce_constants.R)
WC_OBS_END     <- WORKFORCE_OBSERVED_END_YEAR   # SSOT: shared observation-confirmable end (workforce_constants.R)
# WC_SUBS / WC_SUBS_FULL are the canonical subspecialty mappings, now defined in
# R/workforce_constants.R (sourced above) so both the engine and manuscript lineages share them.
WC_GRAD      <- list(GO = c(70,73,78,79), URPS = c(61,66,63,66), MIGS = c(47,50,45,47))
WC_ENTRANTS  <- sapply(WC_GRAD, mean)
WC_ENTRANTS_NRMP <- c(URPS = 74L, GO = 88L, MIGS = 51L)
WC_PRIMARY   <- c("GO", "URPS")

# ---- input paths: resolved via config/cliff_paths.yml (#5) ------------------
# ONE config entry per input (env override > path > fallback). Replaces the
# 29-42 hardcoded absolute paths that were scattered across scripts. The resolver
# now lives in R/wc_path.R so the upstream scripts can source it standalone.
source(here::here("R", "wc_path.R"))
WC_COHORT_CSV  <- wc_path("cohort_csv")
WC_ABU_CW      <- wc_path("abu_crosswalk")
WC_ABU_NN      <- wc_path("abu_net_new")
# wc_duckdb_path() is provided by the sourced R/wc_path.R (line above) — do not redefine it here.

#' Assign an age to its workforce age-band label
#'
#' Bucket one or more physician ages into the study age bands using the canonical
#' breakpoints `WC_BANDS` and labels `WC_BAND_LABELS` (right-open intervals, so an
#' age equal to a breakpoint falls in the upper band).
#'
#' @param age Numeric vector of ages in years.
#' @return A character vector of `WC_BAND_LABELS` values the same length as `age`
#'   (`"<45"`, `"45-49"`, ..., `"70+"`); `NA` for ages outside the band range.
#' @seealso `WC_BANDS`, `WC_BAND_LABELS`; guarded by
#'   `tests/testthat/test-ssot-age-bands.R`.
#' @examples
#' \dontrun{ wc_band_of(c(42, 47, 71)) }   # "<45" "45-49" "70+"
wc_band_of <- function(age) as.character(cut(age, breaks = WC_BANDS, labels = WC_BAND_LABELS, right = FALSE))

.wc_norm_sex <- function(x) { x <- toupper(trimws(as.character(x)))
  ifelse(substr(x,1,1) %in% c("M","F"), substr(x,1,1), NA_character_) }

#' Load the ABOG cohort, optionally applying the non-Open-Payments departure anchor.
#' Returns npi, ab, cert_year, ry (anchored), ret, age, sex. Identical to the block
#' previously duplicated in each script (plus a harmless `sex` column).
#' @param apply_anchor [logical]: Apply the non-Open-Payments departure anchor.
#' @param here_fn [function]: Path resolver, injectable so a caller outside the source tree can supply its own.
wc_load_cohort <- function(apply_anchor = TRUE, here_fn = here::here) {
  raw <- readr::read_csv(WC_COHORT_CSV, show_col_types = FALSE, guess_max = 1e5)
  for (nm in c("abog_gender", "npi_gender")) if (!nm %in% names(raw)) raw[[nm]] <- NA_character_
  coh <- raw %>%
    filter(subspecialty %in% unname(WC_SUBS), !is.na(cert_year)) %>%
    transmute(npi = as.character(npi), ab = names(WC_SUBS)[match(subspecialty, WC_SUBS)],
              cert_year = as.integer(cert_year), ry = suppressWarnings(as.integer(retirement_year)),
              ret = as.logical(is_retired_for_cohorting), age = as.integer(age_approx),
              sex = dplyr::coalesce(.wc_norm_sex(abog_gender), .wc_norm_sex(npi_gender))) %>%
    distinct(npi, .keep_all = TRUE) %>% filter(!is.na(ab))
  if (apply_anchor) {
    anch <- readr::read_csv(here_fn("data","departure_anchor.csv"), show_col_types = FALSE)
    coh <- coh %>% left_join(mutate(anch, npi = as.character(npi)), by = "npi") %>%
      mutate(ry = ifelse(!is.na(ry) & !has_nonop_anchor, NA_integer_, ry)) %>% select(-has_nonop_anchor)
  }
  coh
}

#' ABU urology-pathway net-new active URPS ages (age from ABU certification year).
wc_load_abu_ages <- function() {
  abu_cw <- readr::read_csv(WC_ABU_CW, show_col_types = FALSE, guess_max = 1e5) %>%
    transmute(npi = as.character(npi), cert_year = suppressWarnings(as.integer(abu_cert_year)))
  abu_nn <- trimws(gsub('"', '', readLines(WC_ABU_NN)))
  abu_nn <- abu_nn[abu_nn != "" & !grepl("npi", abu_nn, ignore.case = TRUE)]
  (abu_cw %>% filter(npi %in% abu_nn, !is.na(cert_year)) %>%
      mutate(age = WC_REF_YEAR - cert_year + WC_AGE_AT_CERT) %>% distinct(npi, .keep_all = TRUE))$age
}

#' Primary active-age vectors per cohort (ret==FALSE + ABU net-new appended to URPS).
#' @param coh [data.frame]: Cohort from `wc_load_cohort()`.
#' @param abu_age [integer]: ABU urology-pathway ages to append for the both-pathway baseline.
wc_active_ages <- function(coh, abu_age = wc_load_abu_ages()) {
  a <- coh %>% filter(ret == FALSE, !is.na(age))
  ages <- split(a$age, a$ab); ages$URPS <- c(ages$URPS, abu_age); ages
}

#' Age-band person-year + event counts over a window (GO+URPS primary rows by default).
#' @param coh [data.frame]: Cohort from `wc_load_cohort()`.
#' @param win [integer(2)]: Observation window, start and end year.
#' @param rows [integer]: Row indices of `coh` to count; defaults to the primary cohorts.
wc_band_counts <- function(coh, win = WC_WIN, rows = which(coh$ab %in% WC_PRIMARY)) {
  do.call(rbind, lapply(rows, function(i) {
    cy <- coh$cert_year[i]; ry <- coh$ry[i]
    if (!is.na(ry) && (ry < win[1] || ry > win[2])) ry <- NA_integer_
    y0 <- max(win[1], cy); y1 <- if (is.na(ry)) win[2] else min(win[2], ry); if (y1 < y0) return(NULL)
    yy <- y0:y1; data.frame(band = wc_band_of(yy - cy + WC_AGE_AT_CERT), event = as.integer(!is.na(ry) & yy == ry))
  })) %>% group_by(band) %>% summarise(py = dplyr::n(), ev = sum(event), .groups = "drop")
}

#' Per-band hazard lookup (missing bands filled with the max, capped at 1).
#' @param age [numeric]: Ages to look the hazard up for.
#' @param hz [numeric]: Named age-band hazard vector.
wc_haz_for <- function(age, hz) { h <- hz[wc_band_of(age)]; h[is.na(h)] <- max(hz, na.rm = TRUE); pmin(1, h) }

#' Deterministic age-structured projection. Returns list(active_2029, departures_4yr).
#' `age_shift` shifts the retirement-hazard curve along age: at age `a` a provider
#' faces the hazard of age `a - age_shift`, so a NEGATIVE age_shift retires people
#' earlier (they face an older age's hazard). Default `0L` is byte-identical to the
#' original engine. This is the lever mufflyaccess's scenario dictionary calls
#' `retirement_shift_years` (pass it straight through).
#' @param ages [numeric]: Active-age distribution at the projection start.
#' @param entrants [numeric]: Annual entrants added at the entry age.
#' @param hz [numeric]: Named age-band hazard vector.
#' @param horizon [integer]: Projection horizon in years.
#' @param age_shift [integer]: Shift of the retirement-hazard curve along age; negative retires earlier.
wc_project <- function(ages, entrants, hz, horizon = WC_HORIZON, age_shift = 0L) {
  count <- table(ages); av <- as.integer(names(count)); count <- as.numeric(count); dep <- 0
  for (h in seq_len(horizon)) {
    hzz <- wc_haz_for(av - age_shift, hz); dep <- dep + sum(count * hzz); sv <- count * (1 - hzz)
    av2 <- av + 1L; ix <- match(WC_ENTRY_AGE, av2)
    if (is.na(ix)) { av2 <- c(av2, WC_ENTRY_AGE); sv <- c(sv, entrants) } else sv[ix] <- sv[ix] + entrants
    av <- av2; count <- sv
  }
  list(active_2029 = sum(count), departures_4yr = dep)
}

#' Per-year projection PATH -- the same recurrence as wc_project(), but recording
#' each projected year instead of only the endpoint. Returns a data.frame with one
#' row per year: `step` (1..horizon), `active` (headcount after that year's exits +
#' entrants), `entrants`, `departures` (exits that year). By construction the final
#' `active` equals wc_project()$active_2029 and `sum(departures)` equals
#' wc_project()$departures_4yr for the same inputs (asserted in
#' test-wc-engine-equivalence.R); it just exposes the intermediate years the
#' projection contract needs. `age_shift` behaves exactly as in wc_project().
#' @param ages [numeric]: Active-age distribution at the projection start.
#' @param entrants [numeric]: Annual entrants added at the entry age.
#' @param hz [numeric]: Named age-band hazard vector.
#' @param horizon [integer]: Projection horizon in years.
#' @param age_shift [integer]: Shift of the retirement-hazard curve along age; negative retires earlier.
wc_project_trajectory <- function(ages, entrants, hz, horizon = WC_HORIZON, age_shift = 0L) {
  count <- table(ages); av <- as.integer(names(count)); count <- as.numeric(count)
  out <- vector("list", horizon)
  for (h in seq_len(horizon)) {
    hzz <- wc_haz_for(av - age_shift, hz); dep_h <- sum(count * hzz); sv <- count * (1 - hzz)
    av2 <- av + 1L; ix <- match(WC_ENTRY_AGE, av2)
    if (is.na(ix)) { av2 <- c(av2, WC_ENTRY_AGE); sv <- c(sv, entrants) } else sv[ix] <- sv[ix] + entrants
    av <- av2; count <- sv
    out[[h]] <- data.frame(step = h, active = sum(count), entrants = entrants, departures = dep_h)
  }
  do.call(rbind, out)
}

#' Per-year AGE COMPOSITION -- the same recurrence as wc_project() / _trajectory(),
#' but recording the full (age, n) distribution after each projected year rather
#' than only the aggregate. Returns a long data.frame(step, age, n). The per-step
#' `sum(n)` equals wc_project_trajectory()$active exactly (asserted in
#' test-wc-engine-additions.R); it exposes the age structure an age-weighted
#' clinical-FTE calculation needs. `age_shift` behaves exactly as in wc_project().
#' @param ages [numeric]: Active-age distribution at the projection start.
#' @param entrants [numeric]: Annual entrants added at the entry age.
#' @param hz [numeric]: Named age-band hazard vector.
#' @param horizon [integer]: Projection horizon in years.
#' @param age_shift [integer]: Shift of the retirement-hazard curve along age; negative retires earlier.
wc_project_ages <- function(ages, entrants, hz, horizon = WC_HORIZON, age_shift = 0L) {
  count <- table(ages); av <- as.integer(names(count)); count <- as.numeric(count)
  out <- vector("list", horizon)
  for (h in seq_len(horizon)) {
    hzz <- wc_haz_for(av - age_shift, hz); sv <- count * (1 - hzz)
    av2 <- av + 1L; ix <- match(WC_ENTRY_AGE, av2)
    if (is.na(ix)) { av2 <- c(av2, WC_ENTRY_AGE); sv <- c(sv, entrants) } else sv[ix] <- sv[ix] + entrants
    av <- av2; count <- sv
    out[[h]] <- data.frame(step = h, age = av, n = count)
  }
  do.call(rbind, out)
}

#' Per-provider (individual-level) stochastic MICROSIMULATION of the same projection.
#'
#' `wc_project()` above is an expected-value recurrence: it collapses the individual
#' ages to a count vector and removes the fraction `count * hazard` each year. This
#' function instead carries EACH provider as an individual and, every year, draws a
#' Bernoulli departure per provider from their age-band hazard, ages the survivors,
#' and adds a stochastic cohort of entrants (Poisson mean = `entrants`). Repeated
#' `n_sims` times it yields the full sampling distribution of the 2029 workforce, with
#' individual (aleatory) uncertainty the aggregate model cannot express.
#'
#' Reduction guarantee (the "is it real, and is it right" check): because
#' `E[Bernoulli(h)] = h` and `E[Poisson(entrants)] = entrants`, the MEAN of this
#' microsimulation converges to `wc_project()`'s deterministic `active_2029`. The
#' regression test `test-wc-project-micro.R` asserts they agree within Monte Carlo
#' error, so the per-provider engine is a true refinement of (not a departure from)
#' the validated aggregate model. Pass `stochastic_entry = FALSE` for deterministic
#' entry (round(entrants)/yr) when isolating departure variance.
#'
#' @param ages Integer vector of individual provider ages (one element per provider),
#'   e.g. an element of `wc_active_ages()`.
#' @param entrants Mean annual entrants (fellowship completers).
#' @param hz Named age-band hazard vector (as consumed by [wc_haz_for()]).
#' @param horizon Projection years (default [WC_HORIZON]).
#' @param n_sims Number of individual-level realizations (default 2000).
#' @param seed RNG seed for reproducibility.
#' @param stochastic_entry If TRUE (default) entrants ~ Poisson(entrants) each year;
#'   if FALSE, exactly `round(entrants)` enter each year.
#' @return list: `active_2029` (mean), `active_sd`, `active_ci` (2.5/97.5 pct),
#'   `departures_4yr` (mean), and the raw `active_draws` / `departures_draws`.
#' @family workforce-projection
#' @export
wc_project_micro <- function(ages, entrants, hz, horizon = WC_HORIZON,
                             n_sims = 2000L, seed = 1L, stochastic_entry = TRUE) {
  stopifnot(length(ages) > 0)
  ages <- as.integer(ages[!is.na(ages)])
  if (!is.null(seed)) set.seed(seed)   # seed = NULL lets a caller (e.g. the MC loop) own the RNG stream
  active <- integer(n_sims); deps <- integer(n_sims)
  for (s in seq_len(n_sims)) {
    a <- ages; dep <- 0L
    for (h in seq_len(horizon)) {
      hz_a  <- wc_haz_for(a, hz)                       # per-provider hazard
      leave <- stats::runif(length(a)) < hz_a          # Bernoulli departure per provider
      dep   <- dep + sum(leave)
      a     <- a[!leave] + 1L                          # survivors age one year
      n_new <- if (stochastic_entry) stats::rpois(1L, entrants) else as.integer(round(entrants))
      if (n_new > 0L) a <- c(a, rep.int(WC_ENTRY_AGE, n_new))
    }
    active[s] <- length(a); deps[s] <- dep
  }
  list(active_2029    = mean(active),
       active_sd      = stats::sd(active),
       active_ci      = unname(stats::quantile(active, c(0.025, 0.975))),
       departures_4yr = mean(deps),
       active_draws   = active,
       departures_draws = deps)
}
