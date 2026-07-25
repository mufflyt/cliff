#!/usr/bin/env Rscript
source(here::here("R", "wc_path.R"))
source(here::here("R", "urps_procedure_codes.R"))   # SSOT: anchor procedure codes (labels stay per-output)
# Stage 0 claims-universe audit + reconstructed PRIMARY-CLINICIAN plasticity
# matrix for the anchor pelvic-floor codes (Medicare 2024).
# Decomposes each anchor code into mutually exclusive categories:
#   ABOG-URPS, ABU-URPS (both = board-certified cohort), general OB/GYN,
#   general urology, other physician, APP (PA/NP), facility (entity O).
# Corrects the earlier denominator that mixed facilities + assistants with
# primary surgeons. Single anchor code per family (no multi-code episode sums).
suppressPackageStartupMessages({library(DBI); library(duckdb); library(data.table)})
inmodel <- function(x) x %in% c(TRUE,"TRUE","true",1,"1")
con <- dbConnect(duckdb(), wc_duckdb_path(), read_only=TRUE)
on.exit(dbDisconnect(con, shutdown=TRUE))

abu <- fread("data/abu_all_urps_ENRICHED_2026-07-22.csv", colClasses=list(character="npi"))
abog<- fread("data/abog_all_urps_ENRICHED_2026-07-22.csv",colClasses=list(character="npi"))
cohmap <- rbind(data.table(npi=as.character(abu$npi[inmodel(abu$in_model_baseline)]),  cohort="ABU-URPS"),
                data.table(npi=as.character(abog$npi[inmodel(abog$in_model_baseline)]), cohort="ABOG-URPS"))
cohmap <- unique(cohmap[!is.na(npi)&npi!=""], by="npi")
dbWriteTable(con, "cohmap", cohmap, temporary=TRUE, overwrite=TRUE)

anchors <- setNames(c("Sling (SUI)","Apical suspension","Complex urodynamics","Bladder BOTOX"),
                    urps_anchor_codes())   # SSOT codes (R/urps_procedure_codes.R); labels per-output, order-matched
APP <- c("Physician Assistant","Nurse Practitioner","Clinical Nurse Specialist",
         "Certified Clinical Nurse Specialist","Certified Registered Nurse Anesthetist")
OBG <- c("Obstetrics & Gynecology","Gynecological Oncology")

classify <- function(cd){
  q <- sprintf("
    SELECT CAST(s.Rndrng_NPI AS VARCHAR) npi, s.Rndrng_Prvdr_Type spec, s.Rndrng_Prvdr_Ent_Cd ent,
           c.cohort, CAST(SUM(s.Tot_Srvcs) AS INT) srv
    FROM medicare_part_b_by_service_2024 s
    LEFT JOIN cohmap c ON CAST(s.Rndrng_NPI AS VARCHAR)=c.npi
    WHERE s.HCPCS_Cd=\x27%s\x27 GROUP BY 1,2,3,4", cd)
  d <- as.data.table(dbGetQuery(con, q))
  d[, cat := fifelse(ent=="O","Facility (ASC/org)",
              fifelse(!is.na(cohort), cohort,
              fifelse(spec %in% APP, "APP (PA/NP)",
              fifelse(spec %in% OBG, "General OB/GYN",
              fifelse(spec=="Urology","General urology","Other physician")))))]
  d[, .(srv=sum(srv)), by=cat]
}

CATS <- c("ABOG-URPS","ABU-URPS","General OB/GYN","General urology","Other physician","APP (PA/NP)","Facility (ASC/org)")
out <- rbindlist(lapply(names(anchors), function(cd){
  x <- classify(cd); m <- setNames(x$srv, x$cat)
  tot <- sum(m, na.rm=TRUE)
  urps <- sum(m[c("ABOG-URPS","ABU-URPS")], na.rm=TRUE)
  phys_den <- sum(m[c("ABOG-URPS","ABU-URPS","General OB/GYN","General urology","Other physician")], na.rm=TRUE)  # primary physicians only
  data.table(code=cd, procedure=anchors[cd], total_services=tot,
             facility=sum(m["Facility (ASC/org)"],na.rm=TRUE), app=sum(m["APP (PA/NP)"],na.rm=TRUE),
             primary_physician=phys_den, urps=urps,
             share_original=round(urps/tot,3),          # old (contaminated) denominator
             share_primary_phys=round(urps/phys_den,3)) # corrected
}))
cat("== Stage 0 corrected shares (URPS = ABOG-URPS + ABU-URPS) ==\n"); print(out)

cat("\n== Full mutually-exclusive primary-clinician matrix (services) ==\n")
mat <- rbindlist(lapply(names(anchors), function(cd){ x<-classify(cd); x[, code:=cd]; x }))
w <- dcast(mat, code~factor(cat,levels=CATS), value.var="srv", fill=0)
w[, procedure := anchors[code]]
print(w)
fwrite(out, "data/urps_plasticity_stage0_audit_2026-07-23.csv")
fwrite(w,   "data/urps_plasticity_primary_clinician_matrix_2026-07-23.csv")
cat("\nWrote audit + primary-clinician matrix CSVs.\n")
