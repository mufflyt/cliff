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
WC_BANDS       <- c(0, 45, 50, 55, 60, 65, 70, Inf)
WC_BAND_LABELS <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
WC_WIN         <- c(2016L, 2021L)
WC_AGE_AT_CERT <- 30L
WC_HORIZON     <- 4L
WC_ENTRY_AGE   <- 34L
WC_REF_YEAR    <- 2024L
WC_YEAR0       <- 2025L
WC_OBS_END     <- 2023L
WC_SUBS      <- c(URPS = "Female Pelvic Medicine & Reconstructive Surgery", GO = "Gynecologic Oncology", MIGS = "MIGS")
WC_SUBS_FULL <- c(URPS = "Urogynecology and Reconstructive Pelvic Surgery", GO = "Gynecologic Oncology", MIGS = "Minimally Invasive Gynecologic Surgery")
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
wc_duckdb_path <- function() wc_path("signals_duckdb")

wc_band_of <- function(age) as.character(cut(age, breaks = WC_BANDS, labels = WC_BAND_LABELS, right = FALSE))

.wc_norm_sex <- function(x) { x <- toupper(trimws(as.character(x)))
  ifelse(substr(x,1,1) %in% c("M","F"), substr(x,1,1), NA_character_) }

#' Load the ABOG cohort, optionally applying the non-Open-Payments departure anchor.
#' Returns npi, ab, cert_year, ry (anchored), ret, age, sex. Identical to the block
#' previously duplicated in each script (plus a harmless `sex` column).
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
wc_active_ages <- function(coh, abu_age = wc_load_abu_ages()) {
  a <- coh %>% filter(ret == FALSE, !is.na(age))
  ages <- split(a$age, a$ab); ages$URPS <- c(ages$URPS, abu_age); ages
}

#' Age-band person-year + event counts over a window (GO+URPS primary rows by default).
wc_band_counts <- function(coh, win = WC_WIN, rows = which(coh$ab %in% WC_PRIMARY)) {
  do.call(rbind, lapply(rows, function(i) {
    cy <- coh$cert_year[i]; ry <- coh$ry[i]
    if (!is.na(ry) && (ry < win[1] || ry > win[2])) ry <- NA_integer_
    y0 <- max(win[1], cy); y1 <- if (is.na(ry)) win[2] else min(win[2], ry); if (y1 < y0) return(NULL)
    yy <- y0:y1; data.frame(band = wc_band_of(yy - cy + WC_AGE_AT_CERT), event = as.integer(!is.na(ry) & yy == ry))
  })) %>% group_by(band) %>% summarise(py = dplyr::n(), ev = sum(event), .groups = "drop")
}

#' Per-band hazard lookup (missing bands filled with the max, capped at 1).
wc_haz_for <- function(age, hz) { h <- hz[wc_band_of(age)]; h[is.na(h)] <- max(hz, na.rm = TRUE); pmin(1, h) }

#' Deterministic age-structured projection. Returns list(active_2029, departures_4yr).
wc_project <- function(ages, entrants, hz, horizon = WC_HORIZON) {
  count <- table(ages); av <- as.integer(names(count)); count <- as.numeric(count); dep <- 0
  for (h in seq_len(horizon)) {
    hzz <- wc_haz_for(av, hz); dep <- dep + sum(count * hzz); sv <- count * (1 - hzz)
    av2 <- av + 1L; ix <- match(WC_ENTRY_AGE, av2)
    if (is.na(ix)) { av2 <- c(av2, WC_ENTRY_AGE); sv <- c(sv, entrants) } else sv[ix] <- sv[ix] + entrants
    av <- av2; count <- sv
  }
  list(active_2029 = sum(count), departures_4yr = dep)
}
