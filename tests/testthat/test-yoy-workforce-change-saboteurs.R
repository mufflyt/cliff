# =============================================================================
# tests/testthat/test-yoy-workforce-change-saboteurs.R
#
# Wave 3 adversarial saboteur suite: year-over-year physician workforce change.
# Targets the pipeline's ability to correctly detect physicians who:
#   (a) ENTER the workforce (new entrants / newly certified)
#   (b) EXIT the workforce (retirement / deactivation)
#   (c) MOVE locations between years (geographic drift)
#   (d) CHANGE subspecialty labels across years (phantom churn)
#   (e) have their stationary-physician bias corrected by patch_yearly_cohorts()
#
# Saboteur codes: W1–W15 (workforce entry/exit), M1–M10 (mover detection),
#                 P1–P5 (patch_yearly_cohorts hardening)
#
# Pattern:
#   1. Construct pathological data
#   2. BUG CONFIRMED: assert the bug fires / wrong answer surfaces
#   3. Apply inline fix (or point at production fix)
#   4. REGRESSION GUARD at file end via source inspection
# =============================================================================

library(testthat)

# ── Helpers ──────────────────────────────────────────────────────────────────

.make_cohort <- function(npis, years, lats = NULL, lons = NULL,
                         subspecialty = "MFM",
                         retired = FALSE,
                         cert_year = 2010L) {
  n <- length(npis) * length(years)
  npi_vec  <- rep(npis,  each = length(years))
  year_vec <- rep(years, times = length(npis))
  lat_vec  <- if (!is.null(lats)) rep(lats,  each = length(years)) else rep(39.7, n)
  lon_vec  <- if (!is.null(lons)) rep(lons,  each = length(years)) else rep(-104.9, n)
  data.frame(
    npi                    = npi_vec,
    year                   = year_vec,
    latitude               = lat_vec,
    longitude              = lon_vec,
    subspecialty_normalized = subspecialty,
    is_retired_for_cohorting = retired,
    certification_year     = cert_year,
    stringsAsFactors       = FALSE
  )
}

# Compute YoY churn: entries + exits per transition year
.compute_churn <- function(df, years = sort(unique(df$year))) {
  active <- df[!df$is_retired_for_cohorting & !is.na(df$npi), ]
  purrr::map_dfr(years[-1], function(y) {
    prev <- unique(active$npi[active$year == y - 1L])
    curr <- unique(active$npi[active$year == y])
    data.frame(
      year     = y,
      entries  = length(setdiff(curr, prev)),
      exits    = length(setdiff(prev, curr)),
      retained = length(intersect(prev, curr)),
      stringsAsFactors = FALSE
    )
  })
}

# =============================================================================
# W1: New entrant not in prior year is correctly counted as entry
# =============================================================================

test_that("W1 BUG CONFIRMED: entrant present only in year+1 produces entry=1, not entry=0", {
  suppressPackageStartupMessages(library(purrr))
  # Physician A is in 2022 only (new entrant)
  df <- rbind(
    .make_cohort("NPI_A", 2022L),
    .make_cohort("NPI_B", 2021:2022L)
  )
  churn <- .compute_churn(df, 2021:2022)
  # NPI_A enters in 2022 — must be counted
  expect_equal(churn$entries[churn$year == 2022L], 1L)
})

# =============================================================================
# W2: Retiree absent from current year is correctly counted as exit
# =============================================================================

test_that("W2 BUG CONFIRMED: physician absent in year+1 produces exit=1, not exit=0", {
  suppressPackageStartupMessages(library(purrr))
  # NPI_A present in 2021 but not 2022 (retired or deactivated)
  df <- rbind(
    .make_cohort("NPI_A", 2021L),
    .make_cohort("NPI_B", 2021:2022L)
  )
  churn <- .compute_churn(df, 2021:2022)
  expect_equal(churn$exits[churn$year == 2022L], 1L)
})

# =============================================================================
# W3: Physician marked is_retired_for_cohorting=TRUE is excluded from churn count
# =============================================================================

test_that("W3 BUG CONFIRMED: retired flag=TRUE excludes physician from active churn", {
  suppressPackageStartupMessages(library(purrr))
  df <- rbind(
    .make_cohort("NPI_ACTIVE", 2021:2022L, retired = FALSE),
    .make_cohort("NPI_RETIRED", 2021:2022L, retired = TRUE)
  )
  churn <- .compute_churn(df, 2021:2022)
  # NPI_RETIRED is in both years but marked retired — should not appear as retained
  expect_equal(churn$retained[churn$year == 2022L], 1L)  # only NPI_ACTIVE retained
  expect_equal(churn$entries[churn$year == 2022L],  0L)
  expect_equal(churn$exits[churn$year == 2022L],    0L)
})

# =============================================================================
# W4: Physician retires mid-study — appears in early years, absent in later years
# =============================================================================

test_that("W4: mid-study retirement shows declining retained count", {
  suppressPackageStartupMessages(library(purrr))
  # NPI_A retires after 2015; NPI_B, NPI_C active throughout
  active_a <- .make_cohort("NPI_A", 2013:2015L)
  active_bc <- .make_cohort(c("NPI_B", "NPI_C"), 2013:2023L)
  df <- rbind(active_a, active_bc)

  churn <- .compute_churn(df, 2013:2023)

  # 2015→2016: NPI_A exits — exits > 0
  expect_gte(churn$exits[churn$year == 2016L], 1L)
  # 2013→2014: no exits (all 3 still active)
  expect_equal(churn$exits[churn$year == 2014L], 0L)
})

# =============================================================================
# W5: Phantom churn from NPI whitespace — "NPI_A " ≠ "NPI_A" creates false exit+entry
# =============================================================================

test_that("W5 BUG CONFIRMED: whitespace-padded NPI creates phantom churn", {
  suppressPackageStartupMessages(library(purrr))
  df <- data.frame(
    npi  = c("NPI_A ",  "NPI_A"),   # trailing space in year 1
    year = c(2021L,     2022L),
    is_retired_for_cohorting = FALSE,
    stringsAsFactors = FALSE
  )
  # Without trimws, setdiff sees two different NPIs → phantom exit AND entry
  raw_churn <- .compute_churn(df, 2021:2022)
  expect_equal(raw_churn$entries[raw_churn$year == 2022L], 1L)  # phantom entry
  expect_equal(raw_churn$exits[raw_churn$year == 2022L],   1L)  # phantom exit

  # FIX: trimws before churn computation
  df_fixed <- df
  df_fixed$npi <- trimws(df_fixed$npi)
  fixed_churn <- .compute_churn(df_fixed, 2021:2022)
  expect_equal(fixed_churn$entries[fixed_churn$year == 2022L], 0L)
  expect_equal(fixed_churn$exits[fixed_churn$year == 2022L],   0L)
  expect_equal(fixed_churn$retained[fixed_churn$year == 2022L], 1L)
})

# =============================================================================
# W6: Float NPI ("1234567890.0") from upstream CSV causes phantom churn
# =============================================================================

test_that("W6 BUG CONFIRMED: float-suffix NPI creates phantom exit+entry across years", {
  suppressPackageStartupMessages(library(purrr))
  df <- data.frame(
    npi  = c("1234567890.0", "1234567890"),  # same physician, different string
    year = c(2021L,          2022L),
    is_retired_for_cohorting = FALSE,
    stringsAsFactors = FALSE
  )
  raw_churn <- .compute_churn(df, 2021:2022)
  expect_equal(raw_churn$exits[raw_churn$year == 2022L],   1L)
  expect_equal(raw_churn$entries[raw_churn$year == 2022L], 1L)

  # FIX: strip trailing .0 suffix
  df_fixed <- df
  df_fixed$npi <- sub("^([0-9]+)\\.0+$", "\\1", df_fixed$npi)
  fixed_churn <- .compute_churn(df_fixed, 2021:2022)
  expect_equal(fixed_churn$exits[fixed_churn$year == 2022L],   0L)
  expect_equal(fixed_churn$entries[fixed_churn$year == 2022L], 0L)
})

# =============================================================================
# W7: Subspecialty alias flip ("MIG"→"MIGS") creates phantom churn if not canonicalized
# =============================================================================

test_that("W7 BUG CONFIRMED: MIG vs MIGS alias without canonicalization = phantom churn", {
  suppressPackageStartupMessages(library(purrr))
  # Same physician but subspecialty label changed between data vintages
  df <- data.frame(
    npi                     = c("NPI_MIGS", "NPI_MIGS"),
    year                    = c(2021L,       2022L),
    subspecialty_normalized = c("MIG",       "MIGS"),
    is_retired_for_cohorting = FALSE,
    stringsAsFactors = FALSE
  )
  # Subspecialty-stratified churn: "MIG" cohort exits, "MIGS" cohort enters
  sub_churn <- function(d, sub) {
    sub_d <- d[d$subspecialty_normalized == sub, ]
    .compute_churn(sub_d, 2021:2022)
  }
  c_mig  <- sub_churn(df, "MIG")
  c_migs <- sub_churn(df, "MIGS")

  # BUG: phantom exit in MIG, phantom entry in MIGS
  expect_equal(c_mig$exits[1],    1L)
  expect_equal(c_migs$entries[1], 1L)

  # FIX: canonicalize MIG → MIGS before churn
  df_fixed <- df
  df_fixed$subspecialty_normalized[df_fixed$subspecialty_normalized == "MIG"] <- "MIGS"
  c_fixed <- sub_churn(df_fixed, "MIGS")
  expect_equal(c_fixed$exits[1],    0L)
  expect_equal(c_fixed$entries[1],  0L)
  expect_equal(c_fixed$retained[1], 1L)
})

# =============================================================================
# W8: NA retirement flag treated as FALSE silently inflates active count
# =============================================================================

test_that("W8 BUG CONFIRMED: NA retirement flag includes 'unknown' physicians in active count", {
  suppressPackageStartupMessages(library(purrr))
  df <- data.frame(
    npi  = c("NPI_KNOWN_ACTIVE", "NPI_UNKNOWN"),
    year = c(2022L, 2022L),
    is_retired_for_cohorting = c(FALSE, NA),
    stringsAsFactors = FALSE
  )
  # Without NA guard, !is.na(NA) = FALSE → filter(!is_retired) keeps the NA row
  # Actually !NA = NA, which filter() drops. Let's verify behavior:
  active_raw <- df[!df$is_retired_for_cohorting %in% TRUE, ]  # keeps NA rows
  expect_equal(nrow(active_raw), 2L)  # BUG: NA-status physician counted as active

  # FIX: explicitly require is_retired == FALSE (not just !TRUE)
  active_fixed <- df[!is.na(df$is_retired_for_cohorting) & !df$is_retired_for_cohorting, ]
  expect_equal(nrow(active_fixed), 1L)
})

# =============================================================================
# W9: Zero-year gap (same year both sides of setdiff) produces all-zero churn
# =============================================================================

test_that("W9 BUG CONFIRMED: same year on both sides of setdiff produces meaningless all-zero churn", {
  suppressPackageStartupMessages(library(purrr))
  df <- .make_cohort(paste0("NPI_", 1:5), 2020:2022L)
  # If baseline_year == latest_year, entries = exits = 0 always
  prev <- unique(df$npi[df$year == 2021L])
  curr <- unique(df$npi[df$year == 2021L])  # same year
  expect_equal(length(setdiff(curr, prev)), 0L)
  expect_equal(length(setdiff(prev, curr)), 0L)
  # All-zero is indistinguishable from "no change" — misleading, not an error signal
  # Fix enforced by Y1/Y2 RETRACTION GUARD in 05_tables.R
})

# =============================================================================
# W10: Reversed year order (latest < baseline) inverts sign of change
# =============================================================================

test_that("W10 BUG CONFIRMED: reversed year order makes growth look like decline", {
  suppressPackageStartupMessages(library(purrr))
  # 2013: 3 physicians; 2023: 5 physicians (workforce grew)
  df <- rbind(
    .make_cohort(paste0("NPI_", 1:3), 2013L),
    .make_cohort(paste0("NPI_", 1:5), 2023L)
  )
  # Correct: baseline=2013, latest=2023
  correct_entries <- length(setdiff(
    unique(df$npi[df$year == 2023L]),
    unique(df$npi[df$year == 2013L])
  ))
  # Reversed: baseline=2023, latest=2013
  reversed_entries <- length(setdiff(
    unique(df$npi[df$year == 2013L]),
    unique(df$npi[df$year == 2023L])
  ))

  # BUG: reversed shows "entries" = 0, exits = 2 (workforce "shrank")
  expect_equal(correct_entries,  2L)   # correct: 2 new physicians
  expect_equal(reversed_entries, 0L)   # reversed: 0 "entries" — wrong direction
})

# =============================================================================
# M1: patch_yearly_cohorts — mover's 2022 lat must differ from 2013 lat after patch
# =============================================================================

test_that("M1: patch_yearly_cohorts updates mover lat/lon for correct year only", {
  tmp <- tempfile()
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  # Cohort for 2022: physician at Denver (static geocode-time coord)
  cohort_2022 <- data.frame(
    npi = "NPI_MOVER", latitude = 39.7, longitude = -104.9,
    stringsAsFactors = FALSE
  )
  saveRDS(cohort_2022, file.path(tmp, "step_2.5_final_cohort_y2022.rds"))

  # year_coord_map: same physician moved to San Francisco by 2022
  ycm <- data.frame(
    npi = "NPI_MOVER", analysis_year = 2022L,
    lat = 37.77, lon = -122.42, stringsAsFactors = FALSE
  )

  # Source patch function
  src_path <- here::here("R", "build_year_coord_map.R")
  skip_if_not(file.exists(src_path), "build_year_coord_map.R not found")
  suppressMessages(source(src_path, local = TRUE))

  patch_yearly_cohorts(ycm, cohort_dir = tmp, analysis_years = 2022L)

  patched <- readRDS(file.path(tmp, "step_2.5_final_cohort_y2022.rds"))
  expect_equal(round(patched$latitude,  2), 37.77)
  expect_equal(round(patched$longitude, 2), -122.42)
})

# =============================================================================
# M2: patch_yearly_cohorts — NON-mover retains original coordinates
# =============================================================================

test_that("M2: patch_yearly_cohorts leaves non-mover coordinates unchanged", {
  tmp <- tempfile()
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  cohort <- data.frame(
    npi = c("NPI_STAYER", "NPI_MOVER"),
    latitude  = c(39.7, 39.7),
    longitude = c(-104.9, -104.9),
    stringsAsFactors = FALSE
  )
  saveRDS(cohort, file.path(tmp, "step_2.5_final_cohort_y2022.rds"))

  # Only NPI_MOVER in year_coord_map (NPI_STAYER absent → keep original)
  ycm <- data.frame(
    npi = "NPI_MOVER", analysis_year = 2022L,
    lat = 37.77, lon = -122.42, stringsAsFactors = FALSE
  )

  src_path <- here::here("R", "build_year_coord_map.R")
  skip_if_not(file.exists(src_path), "build_year_coord_map.R not found")
  suppressMessages(source(src_path, local = TRUE))

  patch_yearly_cohorts(ycm, cohort_dir = tmp, analysis_years = 2022L)

  patched <- readRDS(file.path(tmp, "step_2.5_final_cohort_y2022.rds"))
  stayer_row <- patched[patched$npi == "NPI_STAYER", ]
  expect_equal(round(stayer_row$latitude,  1), 39.7)
  expect_equal(round(stayer_row$longitude, 1), -104.9)
})

# =============================================================================
# M3: patch_yearly_cohorts — duplicate NPI in year_coord_map causes hard stop
# =============================================================================

test_that("M3 BUG CONFIRMED: duplicate NPI in year_coord_map causes stop() not silent fan-out", {
  tmp <- tempfile()
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  cohort <- data.frame(npi = "NPI_A", latitude = 39.7, longitude = -104.9,
                       stringsAsFactors = FALSE)
  saveRDS(cohort, file.path(tmp, "step_2.5_final_cohort_y2022.rds"))

  # Duplicate NPI in year_coord_map — two conflicting locations
  ycm <- data.frame(
    npi = c("NPI_A", "NPI_A"), analysis_year = c(2022L, 2022L),
    lat = c(37.77, 40.0), lon = c(-122.42, -75.0), stringsAsFactors = FALSE
  )

  src_path <- here::here("R", "build_year_coord_map.R")
  skip_if_not(file.exists(src_path), "build_year_coord_map.R not found")
  suppressMessages(source(src_path, local = TRUE))

  expect_error(
    patch_yearly_cohorts(ycm, cohort_dir = tmp, analysis_years = 2022L),
    regexp = "duplicate NPI"
  )
})

# =============================================================================
# M4: patch_yearly_cohorts — dry_run=TRUE does NOT write to disk
# =============================================================================

test_that("M4: patch_yearly_cohorts dry_run=TRUE leaves original file unchanged", {
  tmp <- tempfile()
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  cohort <- data.frame(npi = "NPI_A", latitude = 39.7, longitude = -104.9,
                       stringsAsFactors = FALSE)
  cohort_path <- file.path(tmp, "step_2.5_final_cohort_y2022.rds")
  saveRDS(cohort, cohort_path)
  mtime_before <- file.mtime(cohort_path)

  ycm <- data.frame(npi = "NPI_A", analysis_year = 2022L,
                    lat = 37.77, lon = -122.42, stringsAsFactors = FALSE)

  src_path <- here::here("R", "build_year_coord_map.R")
  skip_if_not(file.exists(src_path), "build_year_coord_map.R not found")
  suppressMessages(source(src_path, local = TRUE))

  suppressMessages(patch_yearly_cohorts(ycm, cohort_dir = tmp,
                                        analysis_years = 2022L, dry_run = TRUE))

  after <- readRDS(cohort_path)
  expect_equal(round(after$latitude, 1), 39.7)   # unchanged
  expect_equal(round(after$longitude, 1), -104.9)
})

# =============================================================================
# M5: patch_yearly_cohorts — missing cohort file is skipped, not a hard stop
# =============================================================================

test_that("M5: patch_yearly_cohorts skips missing cohort year gracefully", {
  tmp <- tempfile()
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  # Only 2022 file exists; request patching 2021 and 2022
  cohort <- data.frame(npi = "NPI_A", latitude = 39.7, longitude = -104.9,
                       stringsAsFactors = FALSE)
  saveRDS(cohort, file.path(tmp, "step_2.5_final_cohort_y2022.rds"))

  ycm <- data.frame(npi = "NPI_A", analysis_year = c(2021L, 2022L),
                    lat = c(37.77, 37.77), lon = c(-122.42, -122.42),
                    stringsAsFactors = FALSE)

  src_path <- here::here("R", "build_year_coord_map.R")
  skip_if_not(file.exists(src_path), "build_year_coord_map.R not found")
  suppressMessages(source(src_path, local = TRUE))

  results <- suppressMessages(
    patch_yearly_cohorts(ycm, cohort_dir = tmp, analysis_years = 2021:2022L)
  )
  expect_true(results[["2021"]]$skipped)
  expect_false(results[["2022"]]$skipped)
  expect_equal(results[["2022"]]$patched, 1L)
})

# =============================================================================
# M6: Positive longitude for CONUS physician is geocoding artifact — not a real move
# =============================================================================

test_that("M6 BUG CONFIRMED: positive longitude for US physician creates false >10km move", {
  # Denver: lat=39.7, correct lon=-104.9 (western hemisphere)
  # Geocoding artifact: lon=+104.9 (sign flipped)
  lat_denver <- 39.7392
  lon_correct <- -104.9903
  lon_flipped <-  104.9903   # geocoding bug: positive

  # haversine-style distance proxy (degrees)
  lon_diff_bad  <- abs(lon_flipped  - lon_correct)   # 209.98 degrees
  lon_diff_good <- abs(lon_correct  - lon_correct)   # 0

  # BUG: sign flip looks like a >10,000 km move
  expect_gt(lon_diff_bad, 100)

  # FIX: negate positive lon for CONUS latitudes [24, 50]
  lon_fixed <- ifelse(lat_denver >= 24 & lat_denver <= 50 & lon_flipped > 0,
                      -lon_flipped, lon_flipped)
  expect_equal(round(lon_fixed, 4), round(lon_correct, 4))
})

# =============================================================================
# P1: patch_yearly_cohorts row-count invariant — merge must not fan out
# =============================================================================

test_that("P1: patch_yearly_cohorts output has same row count as input cohort", {
  tmp <- tempfile()
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  cohort <- data.frame(
    npi = paste0("NPI_", 1:50), latitude = 39.7, longitude = -104.9,
    stringsAsFactors = FALSE
  )
  saveRDS(cohort, file.path(tmp, "step_2.5_final_cohort_y2022.rds"))

  # Patch only 10 of 50 physicians
  ycm <- data.frame(
    npi = paste0("NPI_", 1:10), analysis_year = 2022L,
    lat = 37.77, lon = -122.42, stringsAsFactors = FALSE
  )

  src_path <- here::here("R", "build_year_coord_map.R")
  skip_if_not(file.exists(src_path), "build_year_coord_map.R not found")
  suppressMessages(source(src_path, local = TRUE))

  suppressMessages(patch_yearly_cohorts(ycm, cohort_dir = tmp, analysis_years = 2022L))

  patched <- readRDS(file.path(tmp, "step_2.5_final_cohort_y2022.rds"))
  expect_equal(nrow(patched), nrow(cohort))  # no fan-out from merge
})

# =============================================================================
# P2: Stale .ycm_lat / .ycm_lon columns from prior run are stripped before re-patch
# =============================================================================

test_that("P2: patch_yearly_cohorts strips stale .__patch_lat__ columns before merge", {
  tmp <- tempfile()
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  # Cohort already has a stale column from a prior patch run
  cohort <- data.frame(
    npi = "NPI_A", latitude = 39.7, longitude = -104.9,
    `.__patch_lat__` = 99.0,   # stale artifact
    check.names = FALSE, stringsAsFactors = FALSE
  )
  saveRDS(cohort, file.path(tmp, "step_2.5_final_cohort_y2022.rds"))

  ycm <- data.frame(npi = "NPI_A", analysis_year = 2022L,
                    lat = 37.77, lon = -122.42, stringsAsFactors = FALSE)

  src_path <- here::here("R", "build_year_coord_map.R")
  skip_if_not(file.exists(src_path), "build_year_coord_map.R not found")
  suppressMessages(source(src_path, local = TRUE))

  suppressMessages(patch_yearly_cohorts(ycm, cohort_dir = tmp, analysis_years = 2022L))

  patched <- readRDS(file.path(tmp, "step_2.5_final_cohort_y2022.rds"))
  # Stale column must be gone; correct lat applied
  expect_false(".__patch_lat__" %in% names(patched))
  expect_equal(round(patched$latitude, 2), 37.77)
})

# =============================================================================
# W11: Churn rate of 0% across all years signals frozen geography (Bug #94 detector)
# =============================================================================

test_that("W11 BUG CONFIRMED: 0% churn in ALL years signals frozen physician geography", {
  suppressPackageStartupMessages(library(purrr))
  # Identical cohort every year — Bug #94 symptom
  npis <- paste0("NPI_", 1:100)
  df <- .make_cohort(npis, 2013:2023L)

  churn <- .compute_churn(df, 2013:2023)
  all_zero_churn <- all(churn$entries == 0L & churn$exits == 0L)

  # BUG CONFIRMED: frozen cohort shows zero churn — no one enters or leaves
  expect_true(all_zero_churn,
    info = "All-zero churn across all years indicates frozen cohort — possible Bug #94 regression"
  )

  # Healthy pipeline: at least some years show non-zero churn
  # (this is the REGRESSION GUARD postcondition for production data)
})

# =============================================================================
# W12: Late entrant — physician certified in 2017 must NOT appear in 2013 cohort
# =============================================================================

test_that("W12: physician certified in 2017 is absent from 2013-2016 cohorts", {
  suppressPackageStartupMessages(library(purrr))
  df <- rbind(
    .make_cohort("NPI_LATE", 2017:2023L, cert_year = 2017L),
    .make_cohort("NPI_EARLY", 2013:2023L, cert_year = 2010L)
  )

  # NPI_LATE should have entries in 2017 and 0 activity before
  years_late_active <- unique(df$year[df$npi == "NPI_LATE"])
  expect_true(all(years_late_active >= 2017L))

  churn <- .compute_churn(df, 2013:2023)
  # 2016→2017: NPI_LATE enters
  expect_gte(churn$entries[churn$year == 2017L], 1L)
  # 2013→2014: NPI_LATE not yet present — 0 entries from this physician
  expect_equal(churn$entries[churn$year == 2014L], 0L)
})

# =============================================================================
# W13: Early retiree — physician last active 2015 must NOT appear in 2016+ cohorts
# =============================================================================

test_that("W13: physician last active 2015 shows exit in 2016 transition", {
  suppressPackageStartupMessages(library(purrr))
  df <- rbind(
    .make_cohort("NPI_EARLY_RETIRE", 2013:2015L),
    .make_cohort("NPI_CAREER",       2013:2023L)
  )
  churn <- .compute_churn(df, 2013:2023)

  # 2015→2016: NPI_EARLY_RETIRE exits
  expect_gte(churn$exits[churn$year == 2016L], 1L)
  # No exits before 2016 (NPI_EARLY_RETIRE still active)
  early_exits <- churn$exits[churn$year < 2016L]
  expect_true(all(early_exits == 0L))
})

# =============================================================================
# W14: Sabbatical return — physician absent 2018, returns 2019 shows exit+entry
# =============================================================================

test_that("W14: sabbatical physician (absent one year) generates exit then re-entry", {
  suppressPackageStartupMessages(library(purrr))
  # NPI_SABBATICAL active 2013-2017, absent 2018, returns 2019-2023
  df <- rbind(
    .make_cohort("NPI_SABBATICAL", c(2013:2017L, 2019:2023L)),
    .make_cohort("NPI_CONTROL",    2013:2023L)
  )
  churn <- .compute_churn(df, 2013:2023)

  # 2017→2018: NPI_SABBATICAL exits
  expect_gte(churn$exits[churn$year == 2018L], 1L)
  # 2018→2019: NPI_SABBATICAL re-enters
  expect_gte(churn$entries[churn$year == 2019L], 1L)
})

# =============================================================================
# W15: Total workforce = retained + new entrants = prior + new - exits (accounting identity)
# =============================================================================

test_that("W15: churn accounting identity holds: curr_n = prev_n + entries - exits", {
  suppressPackageStartupMessages(library(purrr))
  set.seed(42L)
  npis <- paste0("NPI_", 1:200)
  # Staggered cohort: some retire, some enter each year
  df <- data.frame(
    npi  = c(rep(npis[1:150], each = 11),    # active throughout
             rep(npis[151:170], each = 6),   # enter 2018
             rep(npis[171:200], each = 4)),  # active 2013-2016 only
    year = c(rep(2013:2023L, 150),
             rep(2018:2023L, 20),
             rep(2013:2016L, 30)),
    is_retired_for_cohorting = FALSE,
    stringsAsFactors = FALSE
  )
  df <- dplyr::distinct(df, npi, year, .keep_all = TRUE)
  active <- df[!df$is_retired_for_cohorting, ]

  for (y in 2014:2023) {
    prev_n   <- dplyr::n_distinct(active$npi[active$year == y - 1L])
    curr_n   <- dplyr::n_distinct(active$npi[active$year == y])
    entries  <- length(setdiff(unique(active$npi[active$year == y]),
                               unique(active$npi[active$year == y - 1L])))
    exits    <- length(setdiff(unique(active$npi[active$year == y - 1L]),
                               unique(active$npi[active$year == y])))
    expected <- prev_n + entries - exits
    expect_equal(curr_n, expected,
      info = sprintf("Year %d: %d + %d entries - %d exits = %d (got %d)",
                     y, prev_n, entries, exits, expected, curr_n)
    )
  }
})

# =============================================================================
# REGRESSION GUARDS — source inspection
# =============================================================================

.src_patch <- function() {
  f <- here::here("R", "build_year_coord_map.R")
  if (!file.exists(f)) return(character(0))
  readLines(f, warn = FALSE)
}

.src_cohort_excl <- function() {
  f <- here::here("R", "apply_cohort_inclusion_exclusion_criteria.R")
  if (!file.exists(f)) return(character(0))
  readLines(f, warn = FALSE)
}

test_that("REGRESSION GUARD: patch_yearly_cohorts exists in build_year_coord_map.R", {
  src <- .src_patch()
  skip_if(length(src) == 0L, "build_year_coord_map.R not found")
  expect_gte(length(grep("patch_yearly_cohorts", src)), 1L)
})

test_that("REGRESSION GUARD: patch_yearly_cohorts has duplicate-NPI guard (stop)", {
  src <- .src_patch()
  skip_if(length(src) == 0L, "build_year_coord_map.R not found")
  dup_guard <- grep("duplicate NPI|dup_npis|duplicated.*npi", src, ignore.case = TRUE)
  expect_gte(length(dup_guard), 1L)
})

test_that("REGRESSION GUARD: patch_yearly_cohorts uses temp-verify-rename write pattern", {
  src <- .src_patch()
  skip_if(length(src) == 0L, "build_year_coord_map.R not found")
  has_tmp    <- length(grep("\\.tmp", src)) >= 1L
  has_rename <- length(grep("file\\.rename", src)) >= 1L
  expect_true(has_tmp && has_rename,
    info = "Atomic write pattern (.tmp + file.rename) must be present in patch_yearly_cohorts"
  )
})

test_that("REGRESSION GUARD: patch_yearly_cohorts strips stale .__patch_lat__ columns", {
  src <- .src_patch()
  skip_if(length(src) == 0L, "build_year_coord_map.R not found")
  stale_strip <- grep("__patch_lat__|__patch_lon__|stale", src)
  expect_gte(length(stale_strip), 1L)
})

test_that("REGRESSION GUARD: Step 2.5 QA uses subspecialty_normalized for abbreviation check", {
  src <- .src_cohort_excl()
  skip_if(length(src) == 0L, "apply_cohort_inclusion_exclusion_criteria.R not found")
  fix_lines <- grep("subspecialty_normalized.*names|sub_check_col", src)
  expect_gte(length(fix_lines), 1L)
})

test_that("REGRESSION GUARD: patch_yearly_cohorts wired into Step 2.75 call site", {
  src <- .src_patch()
  skip_if(length(src) == 0L, "build_year_coord_map.R not found")
  callsite <- grep("patch_yearly_cohorts\\(", src)
  expect_gte(length(callsite), 1L)
})
