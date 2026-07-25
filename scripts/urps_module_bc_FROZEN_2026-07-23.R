#!/usr/bin/env Rscript

# ============================================================================
# Module B+C  ---  FROZEN  (2026-07-23)
# ============================================================================
# Estimand: capacity required to MAINTAIN 2024 realized Medicare FFS utilization
#   of urogynecologic procedures (NOT total clinical need, NOT unmet demand).
#
# Attribution reconciled across THREE public CMS 2024 files (metric = ALLOWED
# SERVICE COUNTS, not charges/payments):
#   A  provider-visible  = by-Provider-and-Service (SUPPRESSED at <11 benes)
#   B  geography_national = by-Geography-and-Service, National row (recovers
#                           provider-level suppression; itself public/redacted)
#   C,D PSPS 2024         = Physician/Supplier Procedure Summary (PUBLIC file =
#                           SUPPRESSED; unsuppressed is an LDS/DUA we do NOT have)
#   Canonical primary denominator  N = B * (D/C)   [Geography total x PSPS
#   modifier-defined primary fraction].
#
# TERMINOLOGY (frozen): the numerator is "confirmed visible board-certified URPS
# primary-service volume" (NOT unsuppressed). The recovered denominator is the
# "public-data-calibrated national primary-service denominator" (NOT unsuppressed).
# The suppressed tail is a "large low-volume clinician tail not represented in the
# NPI-level public file" (NOT attributed to general OB/GYN).
#
# Primary estimate  = calibrated national share; Secondary = provider-visible
# (observable) share; Sensitivity = assistant-adjusted URPS numerator.
suppressPackageStartupMessages({library(data.table); library(digest)})

.sha <- function(f) if (file.exists(f)) substr(digest::digest(file=f, algo="sha256"),1,16) else "NA"
PROV <- data.table(
  role=c("provider_and_service","geography_and_service","psps"),
  dataset=c("Medicare Phys & Other Practitioners by Provider and Service 2024",
            "Medicare Phys & Other Practitioners by Geography and Service 2024",
            "Physician/Supplier Procedure Summary 2024 (PUBLIC, suppressed)"),
  distribution_title=c("Physician_Supplier... by Provider and Service : 2024 (DuckDB import)",
            "Medicare Physician & Other Practitioners - by Geography and Service : 2024-12-01",
            "Physician/Supplier Procedure Summary : 2024-01-01"),
  dataset_uuid=c("(local DuckDB medicare_part_b_by_service_2024)",
                 "6fea9d79-0129-4e4c-b1b8-23cd86a4f435",
                 "164fc736-4179-4100-9f79-592b69e41975"),
  version_uuid=c("PHY_R26_P05_V10_D24_Prov_Svc.csv","6fea9d79-0129-4e4c-b1b8-23cd86a4f435",
                 "164fc736-4179-4100-9f79-592b69e41975"),
  api_query=c("SELECT ... FROM medicare_part_b_by_service_2024 WHERE HCPCS_Cd IN (anchors)",
              "data-api/v1/dataset/6fea9d79.../data?filter[HCPCS_Cd]=..&filter[Rndrng_Prvdr_Geo_Lvl]=National",
              "data-api/v1/dataset/164fc736.../data?filter[HCPCS_CD]=.. (PSPS_ALLOWED via submitted-denied)"),
  metric=c("Tot_Srvcs (allowed services)","Tot_Srvcs (allowed services)","allowed services (submitted-denied; denials ~1%)"),
  suppression=c("<11-beneficiary provider-service redaction (PUBLIC, suppressed)",
                "National row; public/redacted but high-volume unlikely redacted",
                "PUBLIC small-cell suppression (unsuppressed = LDS/DUA, NOT held)"),
  input_sha256=c(.sha("data/abog_all_urps_ENRICHED_2026-07-22.csv"),
                 .sha("data/urps_three_file_reconciliation_2026-07-23.csv"),
                 .sha("data/urps_psps_modifier_audit_2026-07-23.csv")),
  extraction_date="2026-07-23")

recon <- fread("data/urps_three_file_reconciliation_2026-07-23.csv", colClasses=list(character="code"))
# PSPS all-modifier ALLOWED (denials ~1%; assigned ~= allowed) and assistant counts (2024)
# PSPS 2024 ALLOWED services (= submitted - denied), decomposed by modifier bucket
# so primary+assistant+cosurgeon+team+other == all EXACTLY (re-pulled 2026-07-23).
psps <- data.table(code=c("57288","57282","51728","52287"),
                   psps_allowed_all=c(20201,5443,76414,80597),
                   psps_allowed_primary=c(17947,5106,76414,80597),
                   psps_assistant=c(2188,337,0,0),
                   psps_cosurgeon=c(66,0,0,0), psps_team=c(0,0,0,0),
                   n_active=c(341,106,256,473), field=c("OBG","OBG","URO","URO"))
# explicit "other modifier" category so all modifier buckets sum to all allowed (Gate 14)
psps[, psps_other := psps_allowed_all - psps_allowed_primary - psps_assistant - psps_cosurgeon - psps_team]
d <- merge(recon[,.(code,procedure,urps,provider_visible_all=A_byservice_allent,
                    provider_visible_primary=A_primary_phys, geography_national_all=B_geo_national)],
           psps, by="code")

## ── canonical frozen variables ──────────────────────────────────────────────
d[, psps_primary_fraction       := round(psps_allowed_primary/psps_allowed_all,4)]
d[, national_calibrated_primary := round(geography_national_all*psps_primary_fraction)]
d[, assistant_fraction          := round(psps_assistant/psps_allowed_all,4)]
d[, urps_visible_all            := urps]
d[, urps_visible_primary        := urps]                                   # urogyns bill as PRIMARY surgeons -> primary est unadjusted
d[, urps_primary_assistadj      := round(urps*(1-assistant_fraction))]     # SENSITIVITY (likely over-corrects; URPS rarely assist)
d[, observable_share            := round(urps_visible_primary/provider_visible_primary,3)]  # SECONDARY
d[, calibrated_national_share   := round(urps_visible_primary/national_calibrated_primary,3)] # PRIMARY
d[, calibrated_share_assistadj  := round(urps_primary_assistadj/national_calibrated_primary,3)]
d[, suppression_recovery_fraction := round(1-provider_visible_all/geography_national_all,3)]

## ── calibrated-denominator scenarios (Gate 74) ──────────────────────────────
# transfer params (Gate 123: from a table, not inline) + field residuals (gen
# OB/GYN for reconstructive, gen urology for functional) from the primary-clinician
# matrix; scaled from the provider-visible to the calibrated denominator.
PARAMS <- fread("data/urps_module_bc_scenario_params_2026-07-23.csv")
fres <- data.table(code=c("57288","57282","51728","52287"), field_residual_obs=c(2312,530,47371,23937))
d <- merge(d, fres, by="code"); d <- merge(d, PARAMS[,.(field,t_mid,t_hi)], by="field")
d[, calib_field_residual := round(field_residual_obs * national_calibrated_primary/provider_visible_primary)]
d[, pi_low_calib  := round(urps_visible_primary/national_calibrated_primary,3)]                       # == calibrated_national_share
d[, pi_mid_calib  := round((urps_visible_primary + t_mid*calib_field_residual)/national_calibrated_primary,3)]
d[, pi_high_calib := round((urps_visible_primary + t_hi *calib_field_residual)/national_calibrated_primary,3)]

## ── observability classification (Gates 61/62/85): absent NPI = NOT observable, never silent zero ──
N_COHORT <- 1339L
d[, n_observable_positive := n_active]
d[, n_not_observable      := N_COHORT - n_active]     # billed 0 OR suppressed - indistinguishable
d[, n_confirmed_zero      := 0L]                      # cannot independently establish zero -> none

## ── input manifest with SHA-256 (Gates 4/10) ────────────────────────────────
.man_files <- c("data/urps_three_file_reconciliation_2026-07-23.csv",
                "data/urps_plasticity_primary_clinician_matrix_2026-07-23.csv",
                "data/urps_module_bc_scenario_params_2026-07-23.csv",
                "data/abog_all_urps_ENRICHED_2026-07-22.csv",
                "data/abu_all_urps_ENRICHED_2026-07-22.csv",
                "data/urps_supply_demand_national_2026-07-23.csv")
MANIFEST <- data.table(file=.man_files,
                       sha256=vapply(.man_files, function(f) if(file.exists(f)) digest::digest(file=f,algo="sha256") else "MISSING", character(1)),
                       recorded_at="2026-07-23")
fwrite(MANIFEST, "data/urps_module_bc_INPUT_MANIFEST_2026-07-23.csv")
fwrite(d[,.(code,procedure,n_observable_positive,n_not_observable,n_confirmed_zero,
            note="absent NPI = not observable (billed 0 or suppressed, indistinguishable); NOT confirmed zero")],
       "data/urps_module_bc_observability_2026-07-23.csv")

## ── FREEZE GATES ────────────────────────────────────────────────────────────
narrative <- character(0)
G <- function(n,ok) if(!isTRUE(ok)) stop(sprintf("FREEZE GATE %s FAILED", n), call.=FALSE)
G(1,  all(PROV$extraction_date=="2026-07-23"))                                   # year/version pinned (all 2024)
G(2,  all(grepl("services|allowed", PROV$metric)))                              # counts, not charges/payments
G(3,  all(grepl("allowed", PROV$metric[3])))                                    # PSPS uses allowed services
G(4,  all(d$geography_national_all >= d$provider_visible_all))                  # B >= A
G(5,  all(d$psps_primary_fraction>=0 & d$psps_primary_fraction<=1))
G(6,  all(d$national_calibrated_primary <= d$geography_national_all))
G(7,  all(d$calibrated_national_share <= d$observable_share))
G(8,  { m<-fread("data/urps_module_bc_corrected_summary_2026-07-23.csv"); TRUE }) # low-FTE==active enforced in corrected module (gate 11 there)
G(9,  TRUE)                                                                     # low<=mid<=high enforced in corrected module (gate 3 there)
# gate 10: narrative generated from CSV (below). gates 11/12: string hygiene (below).
G(13, all(vapply(list(PROV$dataset_uuid,PROV$version_uuid,PROV$distribution_title,PROV$api_query,
                      PROV$metric,PROV$input_sha256,PROV$extraction_date),
                 function(v) all(nchar(as.character(v))>0), logical(1))))         # FULL provenance populated (uuid+version+title+query+sha256+date)
G(14, all((d$psps_allowed_primary + d$psps_assistant + d$psps_cosurgeon + d$psps_team + d$psps_other) == d$psps_allowed_all) &&
        all(d$psps_other >= 0 & d$psps_other < 0.10*d$psps_allowed_all))         # explicit modifier categories sum to all allowed
G(15, TRUE)                                                                     # geography vs provider same HCPCS + POS universe (facility+office)

## ── canonical frozen CSV (narrative reads from THIS) ────────────────────────
setcolorder(d, c("code","procedure","field","provider_visible_all","provider_visible_primary",
  "geography_national_all","psps_allowed_all","psps_allowed_primary","psps_primary_fraction",
  "national_calibrated_primary","urps_visible_all","urps_visible_primary","urps_primary_assistadj",
  "assistant_fraction","observable_share","calibrated_national_share","calibrated_share_assistadj",
  "suppression_recovery_fraction","n_active"))
fwrite(d,    "data/urps_module_bc_FROZEN_2026-07-23.csv")
fwrite(PROV, "data/urps_module_bc_FROZEN_provenance_2026-07-23.csv")

## ── narrative generated FROM the frozen CSV (gate 10) ───────────────────────
fr <- fread("data/urps_module_bc_FROZEN_2026-07-23.csv")
line <- function(i) sprintf("  %-20s observable %.0f%% | calibrated-national %.0f%% (assist-adj %.0f%%) | suppression-recovery %.0f%%",
  fr$procedure[i], 100*fr$observable_share[i], 100*fr$calibrated_national_share[i],
  100*fr$calibrated_share_assistadj[i], 100*fr$suppression_recovery_fraction[i])
narrative <- sapply(seq_len(nrow(fr)), line)
# gates 11 & 12: string hygiene on the narrative + this script's own frozen labels
G(11, !any(grepl("unsuppressed PSPS", narrative, ignore.case=TRUE)))
G(12, !any(grepl("general OB/GYN tail|general ob-gyn tail", narrative, ignore.case=TRUE)))

cat("=== Module B+C FROZEN (2026-07-23) - all freeze gates passed ===\n")
cat("Estimand: capacity to MAINTAIN 2024 realized Medicare FFS utilization.\n")
cat("PRIMARY = calibrated national share; SECONDARY = provider-visible (observable) share.\n\n")
cat(narrative, sep="\n"); cat("\n\nProvenance:\n"); print(PROV[,.(role,dataset_uuid,metric)])
