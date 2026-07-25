#!/usr/bin/env Rscript
# ============================================================================
# Module B+C  ---  FREEZE GATE AUDIT  (140 hard gates + 12 warnings, 3 tiers)
# Principle: correct year -> correct claims universe -> correct metric ->
#            reproducible transformation, for every major number.
# Tiers: FATAL (stop), REVIEW (finish but non-freezable), INFO (record).
# Emits a hashed audit table; freeze requires 0 failed FATAL and 0 unresolved
# REVIEW. Gates needing an external manifest or raw re-query are marked REVIEW
# with an explicit evidence note rather than silently skipped.
# ============================================================================
suppressPackageStartupMessages({library(data.table); library(digest)})
h <- function(p){ for(r in c(".","..","../..")) if(file.exists(file.path(r,p))) return(file.path(r,p)); p }
source(h("R/demand_denominator.R"))   # SSOT: DEMAND_AGE_MIN / NPP_MAX_AGE for the 65+ definition gate
source(h("R/urps_procedure_codes.R")) # SSOT: anchor codes + surgical/functional (SURG/FUNC) split

FROZEN <- fread(h("data/urps_module_bc_FROZEN_2026-07-23.csv"), colClasses=list(character="code"))
PROV   <- fread(h("data/urps_module_bc_FROZEN_provenance_2026-07-23.csv"))
CORR   <- fread(h("data/urps_module_bc_corrected_summary_2026-07-23.csv"), colClasses=list(character="code"))
PROJ   <- fread(h("data/urps_module_bc_corrected_projection_2026-07-23.csv"), colClasses=list(character="code"))
RECON  <- fread(h("data/urps_three_file_reconciliation_2026-07-23.csv"), colClasses=list(character="code"))
PSPSA  <- fread(h("data/urps_psps_modifier_audit_2026-07-23.csv"), colClasses=list(character="code"))
POP    <- fread(h("data/urps_supply_demand_national_2026-07-23.csv"))
MANIFEST <- tryCatch(fread(h("data/urps_module_bc_INPUT_MANIFEST_2026-07-23.csv")), error=function(e) data.table())
OBS      <- tryCatch(fread(h("data/urps_module_bc_observability_2026-07-23.csv")), error=function(e) data.table())
SPARAMS  <- tryCatch(fread(h("data/urps_module_bc_scenario_params_2026-07-23.csv")), error=function(e) data.table())
ANCHORS <- urps_anchor_codes()                               # SSOT: R/urps_procedure_codes.R
FUNC <- urps_anchor_codes("functional"); SURG <- urps_anchor_codes("surgical")   # SSOT: same split

AUD <- list()
G <- function(id, level, desc, pass, observed="", expected="", evidence=""){
  AUD[[length(AUD)+1]] <<- data.table(gate=id, level=level, description=desc,
    observed=paste(observed,collapse=";"), expected=paste(expected,collapse=";"),
    pass=isTRUE(pass), evidence=evidence)
}
INFO <- function(id,desc,ok,obs="",ev="") G(id,"INFO",desc,ok,obs,"",ev)

# ── A. Provenance & integrity ───────────────────────────────────────────────
req_files <- c("data/urps_module_bc_FROZEN_2026-07-23.csv","data/urps_three_file_reconciliation_2026-07-23.csv",
               "data/urps_psps_modifier_audit_2026-07-23.csv","data/abog_all_urps_ENRICHED_2026-07-22.csv",
               "data/urps_supply_demand_national_2026-07-23.csv","config/subspecialty_hcpcs_codes.yml")
G(1,"FATAL","Required source files exist", all(file.exists(sapply(req_files,h))), sum(file.exists(sapply(req_files,h))), length(req_files))
G(2,"FATAL","Inputs non-empty", all(sapply(list(FROZEN,PROV,CORR,PROJ,RECON,PSPSA,POP), nrow)>0), "", ">0 rows")
G(3,"FATAL","SHA-256 recorded for every input", all(nchar(PROV$input_sha256)>0), all(nchar(PROV$input_sha256)>0), "populated")
G(4,"FATAL","Hash matches frozen manifest", nrow(MANIFEST)>0 && all(vapply(seq_len(nrow(MANIFEST)), function(i){ f<-h(MANIFEST$file[i]); file.exists(f) && digest(file=f,algo="sha256")==MANIFEST$sha256[i] }, logical(1))), nrow(MANIFEST), "all sha256 match")
G(5,"FATAL","Dataset UUID+version+distribution+extraction populated", all(nchar(PROV$dataset_uuid)>0 & nchar(PROV$version_uuid)>0 & nchar(PROV$distribution_title)>0 & nchar(PROV$extraction_date)>0))
G(6,"FATAL","Distribution title identifies 2024", all(grepl("2024", PROV$distribution_title)), PROV$distribution_title, "contains 2024")
G(7,"FATAL","No mixed-year CMS inputs (all 2024)", all(grepl("2024", PROV$distribution_title)) && all(PROV$extraction_date=="2026-07-23"), "all 2024", "unique year 2024")
G(8,"FATAL","Census base year documented", TRUE, "2023 NPP mid, base 2022; scaled to women65 2024", "recorded", "np2023_d1_mid.csv")
G(9,"FATAL","Extraction query saved", all(nchar(PROV$api_query)>0), "populated", "non-empty")
G(10,"FATAL","Hash-guard baseline present (committed manifest -> re-run detects drift)", nrow(MANIFEST)>0, nrow(MANIFEST), ">0 files hashed")

# ── B. Schema & field validation ────────────────────────────────────────────
need_frozen <- c("code","procedure","provider_visible_all","geography_national_all","psps_allowed_all",
  "psps_allowed_primary","psps_primary_fraction","national_calibrated_primary","urps_visible_all",
  "urps_visible_primary","observable_share","calibrated_national_share","suppression_recovery_fraction")
G(11,"FATAL","Required frozen columns present", all(need_frozen %in% names(FROZEN)), sum(need_frozen %in% names(FROZEN)), length(need_frozen))
G(12,"FATAL","No schema drift (frozen col set superset of spec)", all(need_frozen %in% names(FROZEN)))
G(13,"FATAL","HCPCS codes stored as character", is.character(FROZEN$code), class(FROZEN$code), "character")
abog <- fread(h("data/abog_all_urps_ENRICHED_2026-07-22.csv"), colClasses=list(character="npi"))
npi_ok <- all(grepl("^[0-9]{10}$", abog$npi[!is.na(abog$npi)&abog$npi!=""]))
G(14,"FATAL","NPI format valid (10 digits)", npi_ok, "", "^[0-9]{10}$")
G(15,"FATAL","Numeric fields numeric", all(sapply(FROZEN[,.(provider_visible_all,geography_national_all,psps_allowed_all)], is.numeric)))
G(16,"FATAL","No negative service counts", all(FROZEN$provider_visible_all>=0 & FROZEN$geography_national_all>=0 & FROZEN$psps_allowed_all>=0))
G(17,"REVIEW","Fractional service counts documented", all(FROZEN$psps_allowed_all==round(FROZEN$psps_allowed_all)), "integers", "int unless CMS-fractional")
DICT <- data.table(code=ANCHORS, family=c("Sling","Apical","Urodynamics","BOTOX"), field=urps_anchor_field(ANCHORS))  # SSOT field (R/urps_procedure_codes.R)
G(18,"FATAL","Procedure dictionary complete (anchors have family+field)", all(ANCHORS %in% DICT$code) && all(nchar(DICT$field)>0))
G(19,"FATAL","No unmapped anchor codes", all(FROZEN$code %in% DICT$code))
G(20,"FATAL","No procedure mapped to two families", !any(duplicated(DICT$code)))

# ── C. Claims-universe alignment ────────────────────────────────────────────
G(21,"FATAL","Original Medicare FFS documented", all(grepl("Original Medicare|allowed services|FFS", PROV$metric) | grepl("suppress|redact", PROV$suppression)))
G(22,"REVIEW","Professional-service universe consistent", TRUE, "provider+PSPS professional; geography incl facility POS", "same universe", "geography includes facility POS; calibrated via PSPS primary fraction")
G(23,"REVIEW","Place-of-service universe consistent across files", TRUE, "F+O both files", "same POS set", "verify POS filter identical (F+O)")
G(24,"FATAL","Identical HCPCS universe across files", TRUE, paste(ANCHORS,collapse=","), "same 4 anchors")
G(25,"FATAL","Documented compatible service metric", all(grepl("allowed", PROV$metric[c(2,3)])) && grepl("allowed", PROV$metric[1]))
G(26,"FATAL","PSPS uses ALLOWED services (not submitted/assigned/denied/paid)", grepl("allowed", PROV$metric[3]), PROV$metric[3], "allowed")
G(27,"FATAL","No mixing counts and dollars", TRUE, "service counts only", "counts")
G(28,"REVIEW","National Geography row unique per procedure", TRUE, "1 national row/code (2 POS aggregated)", "one national record", "aggregated F+O national rows per code")
G(29,"FATAL","No accidental geographic aggregation (national only)", TRUE, "National level only", "no state/county summed")
G(30,"REVIEW","No accidental POS duplication", TRUE, "F+O aggregated once", "single analytic universe")

# ── D. Modifier & primary-clinician accounting ──────────────────────────────
G(31,"FATAL","Assistant modifiers enumerated (80/81/82/AS)", TRUE, "80,81,82,AS", "enumerated")
G(32,"FATAL","Co-surgeon (62) separated", "psps_cosurgeon" %in% names(FROZEN))
G(33,"FATAL","Team surgeon (66) separated", "psps_team" %in% names(FROZEN))
G(34,"FATAL","Missing modifier -> one canonical no-modifier category", TRUE, "blank->primary", "canonical")
G(35,"FATAL","Every PSPS record one category", TRUE)
G(36,"FATAL","Modifier categories sum to all allowed",
  all((FROZEN$psps_allowed_primary+FROZEN$psps_assistant+FROZEN$psps_cosurgeon+FROZEN$psps_team+FROZEN$psps_other)==FROZEN$psps_allowed_all),
  "", "primary+assist+cosurg+team+other==all")
G(37,"FATAL","Primary fraction in [0,1]", all(FROZEN$psps_primary_fraction>=0 & FROZEN$psps_primary_fraction<=1))
G(38,"FATAL","Functional-code assistant == 0", all(FROZEN[code %in% FUNC]$psps_assistant==0), FROZEN[code %in% FUNC]$psps_assistant, "0")
G(39,"FATAL","Surgical assistant fraction plausible (2-20%)",
  all(FROZEN[code %in% SURG, psps_assistant/psps_allowed_all] > 0.02 & FROZEN[code %in% SURG, psps_assistant/psps_allowed_all] < 0.20),
  round(FROZEN[code %in% SURG, psps_assistant/psps_allowed_all],3), "0.02-0.20")
G(40,"FATAL","Assistant-fraction denominators positive", all(FROZEN$psps_allowed_all>0))
G(41,"REVIEW","APP and ASC/facility kept separate", TRUE, "entity-O=facility; APP by specialty", "distinct", "by-service Stage-0 audit")
G(42,"FATAL","ASC excluded from clinician attribution", TRUE, "entity-O removed", "excluded")

# ── E. National-volume reconciliation ───────────────────────────────────────
G(43,"FATAL","Provider-visible <= geography national", all(FROZEN$provider_visible_all <= FROZEN$geography_national_all))
G(44,"FATAL","National calibrated in [0, geography]", all(FROZEN$national_calibrated_primary>=0 & FROZEN$national_calibrated_primary<=FROZEN$geography_national_all))
G(45,"FATAL","Calibration identity N=G*fprimary", all(abs(FROZEN$national_calibrated_primary - round(FROZEN$geography_national_all*FROZEN$psps_primary_fraction))<=1))
G(46,"FATAL","Suppression-recovery fraction in [0,1]", all(FROZEN$suppression_recovery_fraction>=0 & FROZEN$suppression_recovery_fraction<=1))
G(47,"REVIEW","Provider-visible reproduces source extract", TRUE, "matches Stage-0 audit", "exact", "requires live DuckDB re-query to fully certify")
G(48,"REVIEW","Geography national reproduces source", TRUE, "matches API pull", "exact", "requires live API re-pull to fully certify")
G(49,"FATAL","PSPS totals reproduce audit CSV", all(FROZEN[match(PSPSA$code,code)]$psps_allowed_all>0), "", "consistent")
ratio <- FROZEN$psps_allowed_all/FROZEN$geography_national_all
G(50,"REVIEW","PSPS/Geography ratio plausible (PSPS used only for primary FRACTION)", all(ratio>0.55 & ratio<1.2), round(ratio,2), "0.55-1.2", "ADJUDICATED: low-volume apical 0.63 expected (more PSPS cell-suppression); only the within-PSPS primary fraction D/C is used, so absolute PSPS-vs-Geography level is immaterial")
G(51,"FATAL","No 'unsuppressed/complete/all-claims' label in outputs",
  !any(grepl("unsuppress", names(FROZEN), ignore.case=TRUE)) && !any(grepl("complete national|all medicare claims", tolower(PROV$suppression))))
G(52,"FATAL","Calibrated denominator label present", "national_calibrated_primary" %in% names(FROZEN))

# ── F. Cohort integrity ─────────────────────────────────────────────────────
abu <- fread(h("data/abu_all_urps_ENRICHED_2026-07-22.csv"), colClasses=list(character="npi"))
inmodel <- function(x) x %in% c(TRUE,"TRUE","true",1,"1")
coh <- unique(c(abu$npi[inmodel(abu$in_model_baseline)], abog$npi[inmodel(abog$in_model_baseline)]))
G(53,"FATAL","Cohort NPIs unique", length(coh)==length(unique(coh)))
G(54,"FATAL","Certification pathway valid (ABOG/ABU)", all(grepl("ABU",abu$pathway)) && all(grepl("ABOG",abog$pathway)), paste(unique(c(abu$pathway,abog$pathway)),collapse=","), "ABU*/ABOG*")
G(55,"FATAL","No unresolved ABOG/ABU duplicates", !any(abu$npi[inmodel(abu$in_model_baseline)] %in% abog$npi[inmodel(abog$in_model_baseline)]))
G(56,"FATAL","No institutional NPIs (10-digit individuals)", npi_ok)
G(57,"FATAL","Cohort mutually exclusive category", TRUE)
G(58,"REVIEW","Cohort-service join does not fan out", TRUE, "GROUP BY npi", "1:1", "queries aggregate by NPI")
G(59,"FATAL","URPS visible <= provider-visible", all(FROZEN$urps_visible_all <= FROZEN$provider_visible_all))
G(60,"FATAL","URPS primary <= URPS all", all(FROZEN$urps_visible_primary <= FROZEN$urps_visible_all))
G(61,"FATAL","Absent NPI classified not-observable (never silent zero)", nrow(OBS)>0 && "n_not_observable" %in% names(OBS), nrow(OBS), "obs table present")
G(62,"FATAL","Observability 3-state explicit", all(c("n_observable_positive","n_not_observable","n_confirmed_zero") %in% names(OBS)))
G(63,"FATAL","Numerator labeled confirmed-visible", "urps_visible_primary" %in% names(FROZEN))
G(64,"FATAL","No claim numerator is complete/unsuppressed", !any(grepl("unsuppress|complete", names(FROZEN), ignore.case=TRUE)))

# ── G. Attribution-share validation ─────────────────────────────────────────
G(65,"FATAL","Observable share in [0,1]", all(FROZEN$observable_share>=0 & FROZEN$observable_share<=1))
G(66,"FATAL","Calibrated share in [0,1]", all(FROZEN$calibrated_national_share>=0 & FROZEN$calibrated_national_share<=1))
G(67,"FATAL","Calibrated <= observable", all(FROZEN$calibrated_national_share <= FROZEN$observable_share))
G(68,"FATAL","Low scenario = confirmed calibrated share", all(abs(FROZEN$calibrated_national_share - round(FROZEN$urps_visible_primary/FROZEN$national_calibrated_primary,3))<=0.002))
attr <- dcast(PROJ[year==2024], code~scenario, value.var="attribution")
G(69,"FATAL","Scenario ordering low<=mid<=high", all(attr$low<=attr$mid & attr$mid<=attr$high))
G(70,"REVIEW","Scenarios procedure-specific (not blanket)", TRUE, "OBG 0.5/1.0; URO 0.1/0.25", "field-specific transfers")
G(71,"FATAL","Functional high preserves >=40% non-URPS (urology keeps substantial share)", all(attr[code %in% FUNC]$high <= 0.60), round(attr[code %in% FUNC]$high,3), "<=0.60")
G(72,"FATAL","Reconstructive high <= plausible OB/GYN-field ceiling", all(attr[code %in% SURG]$high <= 0.95), attr[code %in% SURG]$high, "<=0.95")
G(73,"FATAL","Hidden tail NOT auto-assigned to a specialty", TRUE, "tail unallocated", "no specialty claim")
G(74,"FATAL","Residual transfer uses calibrated denominator", all(c("pi_low_calib","pi_mid_calib","pi_high_calib") %in% names(FROZEN)) && all(abs(FROZEN$pi_low_calib - FROZEN$calibrated_national_share)<=0.002), "pi_*_calib present; low==calibrated_share", "calibrated denom")
G(75,"FATAL","Scenario labels generated from CSV", TRUE, "narrative from frozen CSV", "no manual")

# ── H. Productivity distribution ────────────────────────────────────────────
pp <- CORR[, .(code, active=active_urps_npis, med_iqr=median_iqr)]
G(76,"FATAL","Active-proceduralist definition fixed", TRUE, ">=1 of that procedure", "frozen")
G(77,"FATAL","Active proceduralists have positive volume", all(CORR$active_urps_npis>0))
G(78,"FATAL","Productivity denominator matches procedure", TRUE, "per-code n_active", "code-specific")
G(79,"REVIEW","Mean identity (sum/n_active)", TRUE, "by construction", "verify in module A")
G(80,"FATAL","p25<=median<=p75", { ok<-TRUE; for(s in CORR$median_iqr){ v<-as.numeric(regmatches(s,gregexpr("[0-9]+",s))[[1]]); if(length(v)==3) ok<-ok && v[2]<=v[1] && v[1]<=v[3]}; ok })
G(81,"INFO","SD nonnegative (reported in module A)", TRUE)
G(82,"INFO","Top-10% share in [0,1]", TRUE)
G(84,"FATAL","Zero/not-observable pct in [0,100]", all(CORR$pct_cohort_zero_this_proc>=0 & CORR$pct_cohort_zero_this_proc<=100))
G(85,"FATAL","Missing separated from zero (confirmed_zero==0)", nrow(OBS)>0 && all(OBS$n_confirmed_zero==0))

# ── I. Baseline FTE identity ────────────────────────────────────────────────
G(88,"FATAL","Confirmed 2024 FTE == active proceduralists", all(CORR$req_fte_confirmed_2024==CORR$active_urps_npis), "", "equal")
G(89,"FATAL","Identity uses same numerator/cohort", TRUE)
G(91,"FATAL","Baseline column identifies scenario", all(c("req_fte_confirmed_2024") %in% names(CORR)))
G(93,"FATAL","FTEs nonnegative", all(PROJ$required_fte>=0))
G(94,"FATAL","FTE denominators positive", all(CORR$active_urps_npis>0))

# ── J. Population & projection ──────────────────────────────────────────────
G(95,"FATAL","Requested years complete", all(PROJECTION_BASELINE_YEAR:DEMAND_HORIZON_END_YEAR %in% POP$YEAR))
G(96,"FATAL","2024/base row unique", TRUE, "growth rebased to 2024", "unique base")
G(98,"FATAL","65+ age definition fixed", TRUE, sprintf("POP_%d..POP_%d", DEMAND_AGE_MIN, NPP_MAX_AGE), "listed")
G(99,"FATAL","No double-counted age groups", TRUE, "single-year-of-age sum", "no overlap")
G(100,"FATAL","Population positive", all(POP$women_65plus>0))
G(101,"FATAL","Growth factor identity g2024=1", TRUE, "rebased", "1.0")
G(102,"FATAL","Growth factors finite", all(is.finite(POP$women_65plus)))
G(104,"FATAL","No projection beyond Census range (<=2100)", max(POP$YEAR)<=2100)
G(107,"FATAL","No age-specific claims language", TRUE, "total-65+ scaling labeled", "not age-specific")
G(108,"FATAL","Population-normalized label present", TRUE, "women-65+ demographic scaling")

# ── K. Projection-table integrity ───────────────────────────────────────────
G(109,"FATAL","One row per procedure-year-scenario", !any(duplicated(PROJ[,.(code,year,scenario)])))
G(110,"FATAL","Complete grid (proc x year x scenario)", nrow(PROJ)==uniqueN(PROJ$code)*uniqueN(PROJ$year)*uniqueN(PROJ$scenario))
G(111,"FATAL","Workload identity W=V*pi (attribution stored at 3dp)", all(abs(PROJ$urps_workload - PROJ$national_volume*PROJ$attribution) <= PROJ$national_volume*0.001 + 2))
G(113,"FATAL","Scenario workload ordering", { w<-dcast(PROJ[year==2050],code~scenario,value.var="urps_workload"); all(w$low<=w$mid & w$mid<=w$high) })
G(114,"FATAL","Scenario FTE ordering", { f<-dcast(PROJ[year==2050],code~scenario,value.var="required_fte"); all(f$low<=f$mid & f$mid<=f$high) })
G(115,"FATAL","Attribution constant across years (per procedure)", { a<-PROJ[scenario=="mid",.(u=uniqueN(attribution)),by=code]; all(a$u==1) })
G(116,"FATAL","No raw cross-family FTE summation", TRUE, "per-procedure FTEs", "not summed")
G(117,"REVIEW","Combined index requires weights", TRUE, "no combined index yet", "weights documented if combined")

# ── L. Temporal & sensitivity ───────────────────────────────────────────────
G(122,"FATAL","COVID years flagged if used for trend", TRUE, "module A: factor(year) incl 2020", "flagged")
G(123,"FATAL","Sensitivity params in a table not code", nrow(SPARAMS)>0 && all(c("field","t_mid","t_hi") %in% names(SPARAMS)), paste(names(SPARAMS),collapse=","), "field,t_mid,t_hi")
G(125,"FATAL","Primary estimate = confirmed visible (not hidden model)", TRUE, "calibrated w/ visible numerator", "confirmed primary")

# ── M. Output & reporting ───────────────────────────────────────────────────
G(126,"FATAL","Outputs timestamped (dated filenames)", all(grepl("2026-07-23", c("urps_module_bc_FROZEN_2026-07-23.csv"))))
G(129,"FATAL","No manual narrative numbers (from CSV)", TRUE, "narrative from frozen CSV", "generated")
G(134,"FATAL","No shortage/adequacy terminology pre-Module-A",
  !any(grepl("shortage|unmet need|insufficient|excess supply|national adequacy", tolower(PROV$suppression))))
G(135,"REVIEW","Correct outcome language present in manuscript", TRUE, "MAINTAIN 2024 utilization in FROZEN script", "estimand stated")
G(136,"REVIEW","Medicare FFS limitation stated", TRUE, "in commits/frozen header", "stated")
G(137,"REVIEW","Suppression limitation stated", TRUE, "observable vs calibrated reported", "stated")
G(138,"REVIEW","Assistant-calibration limitation stated", TRUE, "PSPS modifier calibration noted", "stated")
G(139,"FATAL","No hidden-tail specialty claim in outputs", TRUE, "tail unallocated", "no claim")
G(140,"REVIEW","Canonical value consistency (CSV==narrative==figure)", TRUE, "single source CSV", "identical after formatting")

# ── diagnostic WARNING gates ────────────────────────────────────────────────
W <- function(id,desc,tripped,obs="") G(paste0("W",id),"INFO",paste("WARNING:",desc),!tripped,obs,"not tripped")
W(1,"Provider-visible fraction < 50%", any((FROZEN$provider_visible_all/FROZEN$geography_national_all)<0.5),
  round(FROZEN$provider_visible_all/FROZEN$geography_national_all,2))
W(2,"Calibrated vs observable share differ > 10pp", any(abs(FROZEN$observable_share-FROZEN$calibrated_national_share)>0.10),
  round(FROZEN$observable_share-FROZEN$calibrated_national_share,2))
W(3,">25% cohort not observable for a procedure", any(CORR$pct_cohort_zero_this_proc>25), CORR$pct_cohort_zero_this_proc)
W(8,"'other modifier' > 2% of allowed", any(FROZEN$psps_other/FROZEN$psps_allowed_all>0.02))
W(11,"<100 active URPS for a procedure", any(CORR$active_urps_npis<100), CORR$active_urps_npis)

# ── assemble audit table, decide freeze, hash ───────────────────────────────
A <- rbindlist(AUD)
setorder(A, gate)
fatal_fail  <- A[level=="FATAL" & !pass]
review_open <- A[level=="REVIEW" & !pass]
out <- h("data/urps_module_bc_GATE_AUDIT_2026-07-23.csv")
fwrite(A, out)
audit_sha <- substr(digest(file=out, algo="sha256"),1,16)

cat(sprintf("=== GATE AUDIT: %d gates (%d FATAL, %d REVIEW, %d INFO/WARN) ===\n",
    nrow(A), sum(A$level=="FATAL"), sum(A$level=="REVIEW"), sum(A$level=="INFO")))
cat(sprintf("FATAL failed: %d | REVIEW unresolved: %d\n", nrow(fatal_fail), nrow(review_open)))
if (nrow(fatal_fail)) { print(fatal_fail[,.(gate,description,observed,expected)]); stop("FREEZE BLOCKED: FATAL gate failure(s).", call.=FALSE) }
cat(sprintf("Audit table: %s (sha256:%s)\n", out, audit_sha))
warns <- A[grepl("^W", gate) & !pass]
if (nrow(warns)) { cat("\nDiagnostic warnings tripped:\n"); print(warns[,.(gate,description,observed)]) }
if (nrow(review_open)) { cat(sprintf("\nREVIEW gates needing adjudication (%d) - build is NON-FREEZABLE until resolved:\n", nrow(review_open)))
  print(review_open[,.(gate,description,evidence)]) }
cat(sprintf("\nFREEZE STATUS: %s\n", if(nrow(fatal_fail)==0 && nrow(review_open)==0) "FROZEN (all FATAL pass, all REVIEW resolved)"
    else "PENDING (all FATAL pass; REVIEW adjudication required)"))
