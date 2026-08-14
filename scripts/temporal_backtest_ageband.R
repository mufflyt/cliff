#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Reviewer #10: age-band granularity for the temporal back-test. The aggregate
# closed-cohort back-test (scripts/temporal_backtest.R) is extended by stratifying
# the observed-vs-predicted 2016->2021 survival comparison by the physician's age
# band at base (2016), so the calibration is shown WITHIN each age band, not just
# in aggregate. Board-certified primary cohorts (GO + ABOG-URPS) only; ABU net-new
# urogynecologists are not in the historical back-test cohort (no pre-2024 roster),
# a limitation noted in the caption.
#   OUTPUT: cliff/data/temporal_backtest_ageband.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({library(readr); library(dplyr); library(here)})


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
    stop(sprintf("[%s] monorepo input not found:\n  %s", "temporal_backtest_ageband", p), call. = FALSE)
  p
}

BANDS <- c(0,45,50,55,60,65,70,Inf); BL <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
AGE_AT_CERT <- 30L; BASE <- 2016L; TARGET <- 2021L
band_of <- function(age) as.character(cut(age, breaks=BANDS, labels=BL, right=FALSE))
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")
PRIMARY <- c("GO","URPS")

coh <- read_csv(iso("manuscript", "tables", "table1_physician_characteristics.csv"), show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)],
            cy=as.integer(cert_year), ry=suppressWarnings(as.integer(retirement_year))) %>%
  distinct(npi,.keep_all=TRUE) %>% filter(!is.na(ab))

haz_train <- function(win){
  pt <- do.call(rbind, lapply(seq_len(nrow(coh)), function(i){
    cy<-coh$cy[i]; ry<-coh$ry[i]; if(!is.na(ry)&&(ry<win[1]||ry>win[2])) ry<-NA_integer_
    y0<-max(win[1],cy); y1<-if(is.na(ry)) win[2] else min(win[2],ry); if(y1<y0) return(NULL)
    yy<-y0:y1; data.frame(band=band_of(yy-cy+AGE_AT_CERT), ev=as.integer(!is.na(ry)&yy==ry))}))
  h <- pt %>% group_by(band) %>% summarise(py=dplyr::n(), ev=sum(ev), .groups="drop") %>% mutate(h=ev/py)
  setNames(h$h, h$band)
}
haz_for <- function(age, hz){ v<-hz[band_of(age)]; v[is.na(v)]<-max(hz,na.rm=TRUE); pmin(1,v) }
hz <- haz_train(c(2016L,2021L))

# per (specialty, base-year age band): observed vs predicted still-active at TARGET
out <- do.call(rbind, lapply(PRIMARY, function(k){
  c0 <- coh %>% filter(ab==k, cy<=BASE, is.na(ry) | ry>BASE)
  age0 <- BASE - c0$cy + AGE_AT_CERT; bnd0 <- band_of(age0)
  do.call(rbind, lapply(BL, function(b){
    ix <- which(bnd0==b); if(length(ix)==0) return(NULL)
    obs <- sum(is.na(c0$ry[ix]) | c0$ry[ix] > TARGET)
    cnt <- rep(1, length(ix)); ag <- age0[ix]
    for(y in seq_len(TARGET-BASE)){ cnt <- cnt*(1-haz_for(ag,hz)); ag <- ag+1L }
    pred <- sum(cnt)
    data.frame(subspecialty_abbrev=k, age_band=b, n_base=length(ix),
               observed_active=obs, predicted_active=round(pred,1),
               error=round(pred-obs,1),
               pct_error=ifelse(obs>0, round(100*(pred-obs)/obs,1), NA_real_),
               stringsAsFactors=FALSE)
  }))
}))
out$age_band <- factor(out$age_band, levels=BL); out <- out[order(out$subspecialty_abbrev, out$age_band),]
write_csv(out, here("data","temporal_backtest_ageband.csv"))
cat(sprintf("\n#10 AGE-BAND BACK-TEST (2016 cohort -> 2021; max |pct_error| = %.1f%%):\n", max(abs(out$pct_error), na.rm=TRUE)))
print(out, row.names=FALSE); cat("\nDONE\n")
