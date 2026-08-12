#!/usr/bin/env Rscript
# Table 1: URPS physician characteristics, ABU vs ABOG pathway, in-model cohort.
# Emits a tidy CSV. Continuous: median [IQR], Wilcoxon. Categorical: n (%),
# chi-square (Fisher when any expected cell < 5). Coverage = % non-missing.
suppressPackageStartupMessages({ library(data.table) })
source("R/in_model_baseline.R")   # SSOT: inmodel() active-baseline cohort filter
a <- fread("data/abu_all_urps_ENRICHED_2026-07-22.csv",  colClasses=list(character="npi"))
b <- fread("data/abog_all_urps_ENRICHED_2026-07-22.csv", colClasses=list(character="npi"))
a <- a[inmodel(in_model_baseline)]; b <- b[inmodel(in_model_baseline)]

# COHORT (2026-07-23, PI decision): the full identified active cohort is 1,339
# (ABU 308 + ABOG 1,031). No one is dropped for a missing certification year;
# Table 1 describes all 1,339. The projection is being brought up to the same
# 1,339 by aging the 6 cert-year-less ABU from an alternative source, so the
# table and the projection share one cohort number.
a[, path := "ABU"]; b[, path := "ABOG"]
d <- rbindlist(list(a, b), fill = TRUE)
nA <- nrow(a); nB <- nrow(b); nT <- nrow(d)

# ── normalizers ──────────────────────────────────────────────────────────────
norm_cred <- function(x){ u <- toupper(gsub("[^A-Za-z]","",x))
  fifelse(grepl("DO", u) & !grepl("DODO", u) & grepl("^D?O|DO", u) & grepl("DO", u), "DO",
  fifelse(grepl("MD|MBBS|MBCHB", u), "MD", "Other")) }
# simpler robust degree: DO if contains D.O token, else MD if MD/MBBS, else Other
deg <- function(x){ u <- toupper(x)
  fifelse(grepl("D\\.?O\\.?($|[^A-Z])", u) | u %in% c("DO","D.O","D.O."), "DO",
  fifelse(grepl("M\\.?D|MBBS|MBCHB", u), "MD", "Other")) }
d[, degree := deg(credential)]
d[, female := fifelse(gender=="F","Female", fifelse(gender=="M","Male", NA_character_))]
d[, img := fifelse(img_us=="IMG","IMG", fifelse(img_us=="US","US", NA_character_))]
d[, sole := fifelse(sole_proprietor=="Y","Yes", fifelse(sole_proprietor=="N","No", NA_character_))]
d[, rural3 := fifelse(rurality %in% c("Urban","Suburban","Rural"), rurality, NA_character_)]
d[, multisite := fifelse(is.na(n_dac_practice_locations), NA_character_,
                         fifelse(n_dac_practice_locations>=2,"Yes","No"))]
d[, secspec := fifelse(n_secondary_specialties>0,"Yes","No")]
d[, hpsa := fifelse(is.na(pip_in_designated_hpsa), NA_character_,
                    fifelse(pip_in_designated_hpsa %in% c(TRUE,"TRUE"),"Yes","No"))]
d[, solo_county := fifelse(is.na(n_other_urps_county), NA_character_,
                           fifelse(n_other_urps_county==0,"Yes","No"))]
# procedure-signature flags (logical TRUE/FALSE/NA) -> Yes/No/NA for addbin
.yn <- function(x) fifelse(is.na(x), NA_character_, fifelse(x %in% c(TRUE,"TRUE","true"),"Yes","No"))
for (.c in c("did_cystoscopy_2024","did_bladder_botox_2024","did_upper_tract_2024",
             "did_prolapse_repair_2024","did_pessary_2024","did_hospital_care_2024"))
  d[, (.c) := .yn(get(.c))]

# ── stat helpers ─────────────────────────────────────────────────────────────
fmtp <- function(p) fifelse(is.na(p),"—", fifelse(p<0.001,"<0.001", sprintf("%.3f", p)))
cat_p <- function(v){ g <- d$path[!is.na(d[[v]])]; x <- d[[v]][!is.na(d[[v]])]
  tb <- table(g, x); if (nrow(tb)<2 || ncol(tb)<2) return(NA_real_)
  ex <- suppressWarnings(chisq.test(tb)$expected)
  if (any(ex<5)) suppressWarnings(fisher.test(tb, simulate.p.value=TRUE, B=1e4)$p.value)
  else suppressWarnings(chisq.test(tb)$p.value) }
cont_p <- function(v){ x<-suppressWarnings(as.numeric(d[[v]])); g<-d$path
  ok<-!is.na(x); if(length(unique(g[ok]))<2) return(NA_real_)
  suppressWarnings(wilcox.test(x[ok]~g[ok])$p.value) }
pctcell <- function(sub, cond){ n<-sum(cond[sub],na.rm=TRUE); den<-sum(!is.na(cond[sub]))
  sprintf("%d (%.1f%%)", n, 100*n/den) }
medcell <- function(sub, x){ v<-x[sub]; v<-v[!is.na(v)]
  if(!length(v)) return("—"); sprintf("%.1f [%.1f, %.1f]", median(v), quantile(v,.25), quantile(v,.75)) }

rows <- list()
addbin <- function(label, var, yes="Yes"){ cond<-d[[var]]==yes
  cov<-100*mean(!is.na(d[[var]]))
  rows[[length(rows)+1]] <<- data.table(Characteristic=label,
    ABU=pctcell(d$path=="ABU",cond), ABOG=pctcell(d$path=="ABOG",cond),
    Overall=pctcell(rep(TRUE,nT),cond), P=fmtp(cat_p(var)), Coverage=sprintf("%.0f%%",cov)) }
addcont <- function(label, var){ x<-suppressWarnings(as.numeric(d[[var]])); cov<-100*mean(!is.na(x))
  rows[[length(rows)+1]] <<- data.table(Characteristic=label,
    ABU=medcell(d$path=="ABU",x), ABOG=medcell(d$path=="ABOG",x),
    Overall=medcell(rep(TRUE,nT),x), P=fmtp(cont_p(var)), Coverage=sprintf("%.0f%%",cov)) }
addcat <- function(label, var){ p<-fmtp(cat_p(var)); cov<-100*mean(!is.na(d[[var]]))
  rows[[length(rows)+1]] <<- data.table(Characteristic=label, ABU="", ABOG="", Overall="",
    P=p, Coverage=sprintf("%.0f%%",cov))
  for(lv in sort(unique(d[[var]][!is.na(d[[var]])]))){ cond<-d[[var]]==lv
    rows[[length(rows)+1]] <<- data.table(Characteristic=paste0("   ",lv),
      ABU=pctcell(d$path=="ABU",cond), ABOG=pctcell(d$path=="ABOG",cond),
      Overall=pctcell(rep(TRUE,nT),cond), P="", Coverage="") } }

addbin("Female, n (%)", "female", "Female")
addcont("Estimated age, years, median [IQR]", "age_from_grad_year")
addcat("Degree, n (%)", "degree")
addbin("International medical graduate, n (%)", "img", "IMG")
addcont("Practice organization size (Medicare group members), median [IQR]", "group_size")
addbin("Multi-site practice (≥2 locations), n (%)", "multisite", "Yes")
addbin("Sole proprietor, n (%)", "sole", "Yes")
addcat("Rurality, n (%)", "rural3")
addbin("Practices in a designated primary-care HPSA, n (%)", "hpsa", "Yes")
addbin("Only urogynecologist in county, n (%)", "solo_county", "Yes")
addcont("Practice-area ADI (score; higher = more deprived), median [IQR]", "adi")
addcont("Practice-area SVI (0-1; higher = more vulnerable), median [IQR]", "svi")
addcont("Local insurer market HHI, median [IQR]", "hhi")

# ── Medicare practice signature (2024; among Medicare-present) ──
addbin("Cystoscopy, n (%)", "did_cystoscopy_2024", "Yes")
addbin("Bladder chemodenervation (BOTOX), n (%)", "did_bladder_botox_2024", "Yes")
addbin("Upper urinary tract / kidney stones, n (%)", "did_upper_tract_2024", "Yes")
addbin("Vaginal prolapse repair, n (%)", "did_prolapse_repair_2024", "Yes")
addbin("Pessary fitting, n (%)", "did_pessary_2024", "Yes")
addbin("Hospital admission care, n (%)", "did_hospital_care_2024", "Yes")
addcont("Total Medicare services (2024), median [IQR]", "medicare_services_2024")

# ── Patient panel (Medicare Part D 2023) ──
addcont("Female Part D beneficiaries (%), median [IQR]", "partd_pct_female_benes_2023")
addcont("Part D beneficiary age, years, median [IQR]", "partd_bene_avg_age_2023")

tab <- rbindlist(rows)
setnames(tab, c("ABU","ABOG","Overall"),
         c(sprintf("ABU (n=%d)",nA), sprintf("ABOG (n=%d)",nB), sprintf("Overall (n=%d)",nT)))
out <- "data/table1_urps_characteristics_2026-07-23.csv"
fwrite(tab, out)
cat("Wrote", out, "\n\n")
print(tab, nrow=100)
