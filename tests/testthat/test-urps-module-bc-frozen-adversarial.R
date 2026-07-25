# Semantic + adversarial tests for the FROZEN URPS Module B+C (2026-07-23).
#
# Two layers:
#  (1) SEMANTIC invariants must hold on the real frozen outputs.
#  (2) ADVERSARIAL saboteurs: each invariant checker must FAIL on deliberately
#      broken data, proving the check has teeth and is not vacuously true.
# Plus a Hall-of-Shame value regression so the audited numbers cannot silently
# drift, and terminology guards for the three frozen labeling corrections.

library(testthat); suppressPackageStartupMessages(library(data.table))

.here <- function(p) {
  # Resolve under either the isochrones layout (data/...) or the standalone
  # cliff repo layout (data/...), searched up to a few parent directories.
  cands <- unique(c(p, sub("^cliff/", "", p)))
  for (r in c(".", "..", "../..", "../../..")) for (q in cands)
    if (file.exists(file.path(r, q))) return(file.path(r, q))
  p
}
FROZEN <- fread(.here("data/urps_module_bc_FROZEN_2026-07-23.csv"), colClasses=list(character="code"))
PROV   <- fread(.here("data/urps_module_bc_FROZEN_provenance_2026-07-23.csv"))
CORR   <- fread(.here("data/urps_module_bc_corrected_summary_2026-07-23.csv"), colClasses=list(character="code"))
SCRIPT <- readLines(.here("scripts/urps_module_bc_FROZEN_2026-07-23.R"))

# ---- reusable invariant checkers (shared by real + saboteur tests) ----------
inv_shares_bounded        <- function(d) all(d$observable_share>=0 & d$observable_share<=1 &
                                              d$calibrated_national_share>=0 & d$calibrated_national_share<=1)
inv_calibrated_le_observ  <- function(d) all(d$calibrated_national_share <= d$observable_share + 1e-9)
inv_suppression_monotonic <- function(d) all(d$geography_national_all >= d$provider_visible_all)
inv_calib_le_geography    <- function(d) all(d$national_calibrated_primary <= d$geography_national_all)
inv_primary_frac_bounded  <- function(d) all(d$psps_primary_fraction>=0 & d$psps_primary_fraction<=1)
inv_modifier_accounting   <- function(d) all((d$psps_allowed_primary+d$psps_assistant+d$psps_cosurgeon+
                                              d$psps_team+d$psps_other) == d$psps_allowed_all)
inv_numerator_visible     <- function(d) all(d$urps_visible_all <= d$provider_visible_all)
inv_denominator_identity  <- function(d) all(abs(d$national_calibrated_primary -
                                              round(d$geography_national_all*d$psps_primary_fraction)) <= 1)

# ============================================================================
test_that("semantic invariants hold on the frozen outputs", {
  expect_equal(nrow(FROZEN), 4L)
  expect_setequal(FROZEN$code, c("57288","57282","51728","52287"))
  expect_true(inv_shares_bounded(FROZEN))
  expect_true(inv_calibrated_le_observ(FROZEN),  info="calibrated national must be <= observable (conservative lower bound)")
  expect_true(inv_suppression_monotonic(FROZEN), info="geography national >= provider-visible (suppression recovers volume)")
  expect_true(inv_calib_le_geography(FROZEN))
  expect_true(inv_primary_frac_bounded(FROZEN))
  expect_true(inv_modifier_accounting(FROZEN),   info="primary+assistant+cosurg+team+other must equal all allowed")
  expect_true(inv_numerator_visible(FROZEN))
  expect_true(inv_denominator_identity(FROZEN),  info="N = geography x PSPS primary fraction")
})

test_that("functional codes have primary fraction 1.0; surgical codes < 1.0", {
  expect_equal(FROZEN[code=="51728"]$psps_primary_fraction, 1.0)   # urodynamics: no assistant-at-surgery
  expect_equal(FROZEN[code=="52287"]$psps_primary_fraction, 1.0)   # BOTOX: no assistant-at-surgery
  expect_lt(FROZEN[code=="57288"]$psps_primary_fraction, 1.0)      # sling: assistant present
  expect_lt(FROZEN[code=="57282"]$psps_primary_fraction, 1.0)      # apical: assistant present
})

# ---- ADVERSARIAL: each checker must reject broken data --------------------
test_that("saboteur: calibrated share above observable is rejected", {
  bad <- copy(FROZEN); bad$calibrated_national_share[bad$code=="57288"] <- bad$observable_share[bad$code=="57288"] + 0.05
  expect_false(inv_calibrated_le_observ(bad))
})
test_that("saboteur: geography below provider-visible is rejected", {
  bad <- copy(FROZEN); bad$geography_national_all[bad$code=="57288"] <- bad$provider_visible_all[bad$code=="57288"] - 1
  expect_false(inv_suppression_monotonic(bad))
})
test_that("saboteur: share outside [0,1] is rejected", {
  bad <- copy(FROZEN); bad$observable_share[1] <- 1.4
  expect_false(inv_shares_bounded(bad))
})
test_that("saboteur: modifier buckets not summing to all is rejected", {
  bad <- copy(FROZEN); bad$psps_assistant[bad$code=="57288"] <- bad$psps_assistant[bad$code=="57288"] + 100
  expect_false(inv_modifier_accounting(bad))
})
test_that("saboteur: broken denominator identity is rejected", {
  bad <- copy(FROZEN); bad$national_calibrated_primary[1] <- bad$national_calibrated_primary[1] + 500
  expect_false(inv_denominator_identity(bad))
})
test_that("saboteur: primary fraction > 1 is rejected", {
  bad <- copy(FROZEN); bad$psps_primary_fraction[1] <- 1.2
  expect_false(inv_primary_frac_bounded(bad))
})

# ---- terminology guards (the three frozen corrections) ---------------------
# Check the OUTPUTS (data column names + provenance values), not the script
# source: the script legitimately contains the forbidden strings inside
# "NOT '<bad term>'" correction comments and inside the gate-11/12 grepl patterns.
test_that("frozen OUTPUTS use the corrected terminology", {
  # (1) our denominator/numerator are never LABELED unsuppressed
  expect_false(any(grepl("unsuppress", names(FROZEN), ignore.case=TRUE)))
  expect_false(any(grepl("unsuppress", names(PROV),   ignore.case=TRUE)))
  expect_true("national_calibrated_primary" %in% names(FROZEN))   # calibrated, not "unsuppressed"
  expect_true("calibrated_national_share"  %in% names(FROZEN))
  # (2) every SOURCE file is labeled suppressed/redacted in provenance (none is "the unsuppressed denominator")
  expect_true(all(grepl("suppress|redact", PROV$suppression, ignore.case=TRUE)))
  # (3) the frozen script positively asserts the corrected framing
  body <- paste(SCRIPT, collapse="\n")
  expect_true(grepl("public-data-calibrated", body, ignore.case=TRUE))
  expect_true(grepl("large low-volume clinician tail", body, ignore.case=TRUE))  # tail NOT attributed to gen OB/GYN
  expect_true(grepl("MAINTAIN 2024 realized", body))
  # (4) gate 11/12 string-hygiene checks are actually present in the frozen script
  expect_true(grepl("GATE 11", body) || grepl("gate 11", body, ignore.case=TRUE))
})

# ---- provenance completeness (Gate 13) -------------------------------------
test_that("provenance is fully populated for all three files", {
  need <- c("dataset_uuid","version_uuid","distribution_title","api_query","metric","input_sha256","extraction_date")
  expect_true(all(need %in% names(PROV)))
  for (col in need) expect_true(all(nchar(as.character(PROV[[col]]))>0), info=paste("empty provenance:", col))
  expect_true(all(PROV$extraction_date=="2026-07-23"))
})

# ---- baseline FTE identity (Gate 8, corrected module) ----------------------
test_that("confirmed 2024 FTE equals active proceduralists (no inflation by construction)", {
  m <- merge(CORR[,.(code, active=active_urps_npis, fte24=req_fte_confirmed_2024)],
             FROZEN[,.(code)], by="code")
  expect_equal(m$fte24, as.numeric(m$active))
})

# ---- Hall of Shame: audited values must not silently drift ------------------
test_that("frozen calibrated/observable shares match the audited values", {
  s <- FROZEN[code=="57288"]
  expect_equal(s$observable_share,          0.710, tolerance=0.01)   # provider-visible (secondary)
  expect_equal(s$calibrated_national_share, 0.383, tolerance=0.01)   # calibrated national (PRIMARY) - NOT 0.71, NOT 0.47
  expect_equal(s$suppression_recovery_fraction, 0.420, tolerance=0.01)
  a <- FROZEN[code=="57282"]
  expect_equal(a$calibrated_national_share, 0.270, tolerance=0.01)
  expect_true(FROZEN[code=="52287"]$calibrated_national_share < FROZEN[code=="52287"]$observable_share)
})
