#!/usr/bin/env Rscript
source(here::here("R", "wc_path.R"))
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Reviewer #4: hierarchical partial-pooling age-band hazard for GO + URPS.
# A binomial discrete-time hazard model with a SHARED age-band shape (fixed band
# effects) and a SPECIALTY deviation (random intercept), fit by penalized maximum
# likelihood with a weakly-informative prior on the between-specialty variance
# (blme::bglmer). With only two board-certified cohorts, plain glmer collapses the
# specialty variance to zero (i.e. full pooling); the variance prior is what makes
# this a genuine PARTIAL pool. Stan/brms is unavailable in this environment (the
# rstan C++ toolchain fails to compile), so the penalized-likelihood partial pool
# is used as the frequentist analog of the Bayesian partial-pooling model.
#
# The completion-to-departure ratio is recomputed under three hazard sets applied
# to each cohort's active-age distribution: (1) UNPOOLED specialty-specific, (2)
# POOLED single curve (the manuscript primary), (3) PARTIAL-POOLED. Uncertainty:
# unpooled/pooled via a Beta(events+.5, PY-events+.5) posterior MC on the band
# hazards (matching the primary interval); partial-pooled via a parametric
# bootstrap of the fitted model (bootMer). ABU-hazard uncertainty (0.5x-2x on the
# URPS hazard) is reported as an additional envelope row.
#   OUTPUT: data/hierarchical_hazard_comparison.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({library(readr); library(dplyr); library(tidyr); library(here); library(blme); library(lme4)})
set.seed(20260720L)

BANDS <- c(0,45,50,55,60,65,70,Inf); BAND_LABELS <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
WIN <- c(2016L,2021L); AGE_AT_CERT <- 30L; HORIZON <- 4L; ENTRY_AGE <- 34L; REF_YEAR <- 2024L
N_MC <- 4000L; N_BOOT <- 300L
band_of <- function(age) as.character(cut(age, breaks=BANDS, labels=BAND_LABELS, right=FALSE))
SUBS <- c(URPS="Female Pelvic Medicine & Reconstructive Surgery", GO="Gynecologic Oncology", MIGS="MIGS")
GRAD <- list(GO=c(70,73,78,79), URPS=c(61,66,63,66)); ENTRANTS <- sapply(GRAD, mean); PRIMARY <- c("GO","URPS")

# ---- cohort + anchored departure year (verbatim) ---------------------------
coh <- read_csv(wc_path("cohort_csv"),
                show_col_types=FALSE, guess_max=1e5) %>%
  filter(subspecialty %in% unname(SUBS), !is.na(cert_year)) %>%
  transmute(npi=as.character(npi), ab=names(SUBS)[match(subspecialty,SUBS)], cert_year=as.integer(cert_year),
            ry=suppressWarnings(as.integer(retirement_year)), ret=as.logical(is_retired_for_cohorting),
            age=as.integer(age_approx)) %>%
  distinct(npi,.keep_all=TRUE) %>% filter(!is.na(ab))
.anch <- read_csv(here("data","departure_anchor.csv"), show_col_types=FALSE)
coh <- coh %>% left_join(mutate(.anch, npi=as.character(npi)), by="npi") %>%
  mutate(ry=ifelse(!is.na(ry) & !has_nonop_anchor, NA_integer_, ry)) %>% select(-has_nonop_anchor)

# ABU net-new active URPS ages
abu_cw <- read_csv(wc_path("abu_crosswalk"), show_col_types=FALSE, guess_max=1e5) %>%
  transmute(npi=as.character(npi), cert_year=suppressWarnings(as.integer(abu_cert_year)))
abu_nn <- trimws(gsub('"','', readLines(wc_path("abu_net_new"))))
abu_nn <- abu_nn[abu_nn!="" & !grepl("npi", abu_nn, ignore.case=TRUE)]
abu_age <- (abu_cw %>% filter(npi %in% abu_nn, !is.na(cert_year)) %>% mutate(age=REF_YEAR-cert_year+AGE_AT_CERT) %>% distinct(npi,.keep_all=TRUE))$age
n_abu <- length(abu_age)

ages <- split((coh %>% filter(ret==FALSE, !is.na(age)))$age, (coh %>% filter(ret==FALSE, !is.na(age)))$ab)
ages$URPS <- c(ages$URPS, abu_age)

# ---- per-(specialty,band) person-year + event counts -----------------------
pyrows <- do.call(rbind, lapply(which(coh$ab %in% PRIMARY), function(i){
  cy<-coh$cert_year[i]; ry<-coh$ry[i]; ab<-coh$ab[i]
  if(!is.na(ry)&&(ry<WIN[1]||ry>WIN[2])) ry<-NA_integer_
  y0<-max(WIN[1],cy); y1<-if(is.na(ry)) WIN[2] else min(WIN[2],ry); if(y1<y0) return(NULL)
  yy<-y0:y1; data.frame(subspecialty=ab, band=band_of(yy-cy+AGE_AT_CERT), event=as.integer(!is.na(ry)&yy==ry))
}))
agg <- pyrows %>% group_by(subspecialty, band) %>% summarise(py=dplyr::n(), ev=sum(event), .groups="drop") %>%
  mutate(band=factor(band, levels=BAND_LABELS), subspecialty=factor(subspecialty, levels=PRIMARY)) %>% filter(py>0)

# ---- projection machinery --------------------------------------------------
haz_for <- function(age, hz){ h<-hz[band_of(age)]; h[is.na(h)]<-max(hz,na.rm=TRUE); pmin(1,h) }
project <- function(a, entrants, hz){
  count<-table(a); av<-as.integer(names(count)); count<-as.numeric(count); dep<-0
  for(h in seq_len(HORIZON)){ hzz<-haz_for(av,hz); dep<-dep+sum(count*hzz); sv<-count*(1-hzz)
    av2<-av+1L; ix<-match(ENTRY_AGE,av2); if(is.na(ix)){av2<-c(av2,ENTRY_AGE); sv<-c(sv,entrants)} else sv[ix]<-sv[ix]+entrants
    av<-av2; count<-sv }
  dep }
ratio_of <- function(k, hz) ENTRANTS[[k]] / (project(ages[[k]], ENTRANTS[[k]], hz)/HORIZON)

# ---- (1) UNPOOLED and (2) POOLED point + Beta-MC CI ------------------------
unpooled_hz <- function(k) { d<-agg[agg$subspecialty==k,]; setNames(d$ev/d$py, as.character(d$band)) }
pooled_tot  <- agg %>% group_by(band) %>% summarise(py=sum(py), ev=sum(ev), .groups="drop")
pooled_hz   <- setNames(pooled_tot$ev/pooled_tot$py, as.character(pooled_tot$band))
beta_ci <- function(k, mode=c("unpooled","pooled")){
  mode<-match.arg(mode)
  d <- if(mode=="unpooled") agg[agg$subspecialty==k,] else pooled_tot
  bl <- as.character(d$band)
  r <- replicate(N_MC, { hz<-setNames(rbeta(nrow(d), d$ev+0.5, d$py-d$ev+0.5), bl); ratio_of(k, hz) })
  c(lo=quantile(r,.025,names=FALSE), hi=quantile(r,.975,names=FALSE))
}

# ---- (3) PARTIAL-POOLED via bglmer + parametric bootstrap ------------------
fit <- bglmer(cbind(ev, py-ev) ~ band + (1|subspecialty), data=agg, family=binomial,
              cov.prior = gamma(shape=2, rate=0.5), control=glmerControl(optimizer="bobyqa"))
pp_hz <- function(m){
  grid <- expand.grid(subspecialty=factor(PRIMARY, levels=PRIMARY), band=levels(agg$band))
  grid <- grid[paste(grid$subspecialty,grid$band) %in% paste(agg$subspecialty,agg$band),]
  grid$band <- factor(grid$band, levels=BAND_LABELS)
  grid$p <- predict(m, newdata=grid, type="response", allow.new.levels=TRUE)
  lapply(PRIMARY, function(k){ d<-grid[grid$subspecialty==k,]; setNames(d$p, as.character(d$band)) })
}
pp_point <- pp_hz(fit); names(pp_point) <- PRIMARY
pp_ratio_point <- sapply(PRIMARY, function(k) ratio_of(k, pp_point[[k]]))
FUN <- function(m){ h<-pp_hz(m); names(h)<-PRIMARY; sapply(PRIMARY, function(k) ratio_of(k, h[[k]])) }
bb <- lme4::bootMer(fit, FUN, nsim=N_BOOT, type="parametric", use.u=FALSE, seed=20260720L)
pp_ci <- apply(bb$t, 2, quantile, probs=c(.025,.975), na.rm=TRUE)   # 2 x 2 (lo/hi per specialty)

# ---- ABU-hazard 0.5x-2x envelope on URPS -----------------------------------
abu_frac <- n_abu / length(ages$URPS)
abu_scaled_ratio <- function(scale){
  hz <- pp_point[["URPS"]]
  # scale the hazard contribution attributable to the ABU share (approx: scale whole hz by (1-frac)+frac*scale)
  ratio_of("URPS", hz * ((1-abu_frac) + abu_frac*scale))
}

mk <- function(k, method, ratio, lo=NA, hi=NA)
  data.frame(subspecialty_abbrev=k, method=method, replacement_ratio=round(ratio,2),
             ci_lo=round(lo,2), ci_hi=round(hi,2),
             events=sum(agg$ev[agg$subspecialty==k]), person_years=sum(agg$py[agg$subspecialty==k]),
             stringsAsFactors=FALSE)
out <- do.call(rbind, c(
  lapply(PRIMARY, function(k){ ci<-beta_ci(k,"unpooled"); mk(k,"unpooled", ratio_of(k,unpooled_hz(k)), ci["lo"], ci["hi"]) }),
  lapply(PRIMARY, function(k){ ci<-beta_ci(k,"pooled");   mk(k,"pooled",   ratio_of(k,pooled_hz),      ci["lo"], ci["hi"]) }),
  lapply(seq_along(PRIMARY), function(j){ k<-PRIMARY[j]; mk(k,"partial_pooled", pp_ratio_point[k], pp_ci[1,j], pp_ci[2,j]) }),
  list(mk("URPS","partial_pooled_abu_0.5x", abu_scaled_ratio(0.5)),
       mk("URPS","partial_pooled_abu_2x",   abu_scaled_ratio(2.0)))
))
write_csv(out, here("data","hierarchical_hazard_comparison.csv"))
cat(sprintf("\nspecialty variance (bglmer): %.4f  | ABU share of URPS active: %.1f%%\n",
            as.numeric(VarCorr(fit)$subspecialty), 100*abu_frac))
cat("\n#4 HIERARCHICAL PARTIAL-POOLING COMPARISON:\n"); print(out, row.names=FALSE)
cat("\nDONE\n")
