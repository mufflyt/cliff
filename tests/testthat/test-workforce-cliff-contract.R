# =============================================================================
# Workforce Cliff — Data Contract: Adversarial + Semantic Tests
# =============================================================================
#
# Guards the workforce-cliff manuscript against the failure that silently
# published zeros: an all-zero / "Unknown" / wrong-shape / self-inconsistent
# workforce-projection table reaching the render undetected.
#
#   * ADVERSARIAL tests  — feed the validator deliberately broken tables and
#                          assert it STOPS (fail-loud), one perturbation each.
#   * SEMANTIC tests     — assert the frozen authoritative table (cliff/data)
#                          satisfies the domain arithmetic that ties the
#                          columns together, and that the accessor helpers
#                          return domain-correct values.
#
# Source of truth under test: data/workforce_projections_consolidated.csv
# Contract under test:        manuscript/R/workforce_data_contract.R
#
# Author: Tyler Muffly / Claude Code
# =============================================================================

library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

source(here("manuscript", "R", "workforce_data_contract.R"))

# ── A canonical VALID table (the frozen SSOT) --------------------------------
# Read once; every adversarial case perturbs a fresh copy of this.
.valid_path <- here("data", "workforce_projections_consolidated.csv")

valid_df <- function() {
  as.data.frame(readr::read_csv(.valid_path, show_col_types = FALSE))
}

# =============================================================================
# SANITY — the frozen table is present and passes as-is
# =============================================================================

test_that("frozen SSOT exists and validates cleanly", {
  expect_true(file.exists(.valid_path))
  expect_silent(validate_workforce_data(valid_df()))
  expect_invisible(validate_workforce_data(valid_df()))
})

# =============================================================================
# ADVERSARIAL — every broken table must be REJECTED (fail loud)
# =============================================================================

test_that("ADV1: all-zero scaffold is rejected", {
  df <- valid_df()
  df$baseline_2025 <- 0
  df$projected_2029 <- 0
  df$avg_annual_retirements <- 0
  df$annual_entrants <- 0
  df$replacement_ratio <- 0
  df$replacement_assessment <- "Unknown"
  expect_error(validate_workforce_data(df), "workforce contract")
})

test_that("ADV2: 'Unknown' replacement_assessment is rejected", {
  df <- valid_df()
  df$replacement_assessment[1] <- "Unknown"
  expect_error(validate_workforce_data(df), "invalid replacement_assessment")
})

test_that("ADV3: 7-subspecialty scaffold (wrong set) is rejected", {
  df <- valid_df()
  extra <- df[1, ]
  for (nm in c("CFP", "MFM", "PAG", "REI")) {
    e <- extra
    e$subspecialty_abbrev <- nm
    e$subspecialty <- nm
    df <- rbind(df, e)
  }
  expect_error(validate_workforce_data(df), "subspecialty set mismatch")
})

test_that("ADV4: missing a required subspecialty is rejected", {
  df <- valid_df()
  df <- df[df$subspecialty_abbrev != "MIGS", ]
  expect_error(validate_workforce_data(df), "subspecialty set mismatch")
})

test_that("ADV5: NA in a critical numeric column is rejected", {
  df <- valid_df()
  df$baseline_2025[2] <- NA
  expect_error(validate_workforce_data(df), "NA present in column 'baseline_2025'")
})

test_that("ADV6: negative/zero baseline is rejected", {
  df <- valid_df()
  df$baseline_2025[1] <- 0
  expect_error(validate_workforce_data(df), "baseline_2025 must be > 0")
})

test_that("ADV7: missing required column is rejected", {
  df <- valid_df()
  df$replacement_ratio <- NULL
  expect_error(validate_workforce_data(df), "missing required column")
})

test_that("ADV8: replacement_ratio inconsistent with entrants/retirements is rejected", {
  df <- valid_df()
  df$replacement_ratio[1] <- df$replacement_ratio[1] + 0.5  # break the identity
  expect_error(validate_workforce_data(df), "replacement_ratio disagrees")
})

test_that("ADV9: projected_2029 inconsistent with baseline + horizon*(ent-ret) is rejected", {
  df <- valid_df()
  df$projected_2029[2] <- df$projected_2029[2] + 25
  expect_error(validate_workforce_data(df), "projected_2029 disagrees")
})

test_that("ADV10: percent_change inconsistent with (proj-base)/base is rejected", {
  df <- valid_df()
  df$percent_change[3] <- df$percent_change[3] + 5
  expect_error(validate_workforce_data(df), "percent_change disagrees")
})

test_that("ADV11: replacement_assessment inconsistent with ratio thresholds is rejected", {
  df <- valid_df()
  # GO ratio ~4.1 -> Adequate; mislabel as Insufficient to force the mismatch.
  df$replacement_assessment[df$subspecialty_abbrev == "GO"] <- "Below replacement"
  expect_error(validate_workforce_data(df), "replacement_assessment disagrees")
})

test_that("ADV12: ci95_lower > ci95_upper is rejected", {
  df <- valid_df()
  lo <- df$ci95_lower[1]
  df$ci95_lower[1] <- df$ci95_upper[1] + 1
  df$ci95_upper[1] <- lo
  expect_error(validate_workforce_data(df), "ci95_lower exceeds ci95_upper")
})

test_that("ADV13: duplicate subspecialty row is rejected", {
  df <- valid_df()
  df <- rbind(df, df[df$subspecialty_abbrev == "GO", ])
  expect_error(validate_workforce_data(df), "duplicate subspecialty_abbrev")
})

test_that("ADV14: empty table is rejected", {
  df <- valid_df()[0, ]
  expect_error(validate_workforce_data(df))
})

# =============================================================================
# SEMANTIC — the frozen table satisfies domain arithmetic
# =============================================================================

test_that("SEM1: exactly the three surgical subspecialties, no more", {
  df <- valid_df()
  expect_setequal(df$subspecialty_abbrev, c("URPS", "GO", "MIGS"))
  expect_equal(nrow(df), 3L)
})

test_that("SEM2: replacement_ratio == annual_entrants / avg_annual_retirements", {
  df <- valid_df()
  expect_equal(df$replacement_ratio,
               df$annual_entrants / df$avg_annual_retirements,
               tolerance = 1e-6)
})

test_that("SEM3: projected_2029 == baseline + horizon*(entrants - retirements)", {
  df <- valid_df()
  expect_equal(
    df$projected_2029,
    df$baseline_2025 +
      WORKFORCE_PROJECTION_HORIZON_YEARS * (df$annual_entrants - df$avg_annual_retirements),
    tolerance = 1e-6
  )
})

test_that("SEM4: percent_change == 100*(projected - baseline)/baseline", {
  df <- valid_df()
  expect_equal(df$percent_change,
               100 * (df$projected_2029 - df$baseline_2025) / df$baseline_2025,
               tolerance = 1e-6)
})

test_that("SEM5: replacement_assessment matches the threshold classifier", {
  df <- valid_df()
  expect_equal(df$replacement_assessment, classify_replacement(df$replacement_ratio))
})

test_that("SEM6: all three subspecialties are adequately replaced (NRMP-corrected)", {
  # Corrected 2026-07-15: annual entrants set to NRMP positions filled
  # (URPS 70, GO 86, MIGS 47). All three replacement ratios now exceed 1.20,
  # reversing the prior GO-decline finding that rested on an unsourced GO=50.
  df <- valid_df()
  get <- function(ab) df$replacement_assessment[df$subspecialty_abbrev == ab]
  expect_equal(get("GO"), "Above replacement")
  expect_equal(get("MIGS"), "Above replacement")
  expect_equal(get("URPS"), "Above replacement")
})

test_that("SEM7: combined workforce grows and every subspecialty grows (NRMP-corrected)", {
  df <- valid_df()
  base <- sum(df$baseline_2025)
  proj <- sum(df$projected_2029)
  pct  <- 100 * (proj - base) / base
  expect_gt(proj, base)          # combined growth (~ +23% under empirical retirement rates)
  expect_gt(pct, 3)
  # Under NRMP entrants, no subspecialty declines.
  net <- setNames(df$projected_2029 - df$baseline_2025, df$subspecialty_abbrev)
  expect_true(all(net > 0))
})

test_that("SEM8: classify_replacement honors the documented thresholds", {
  expect_equal(classify_replacement(1.20), "Above replacement")
  expect_equal(classify_replacement(1.00), "At replacement")
  expect_equal(classify_replacement(0.94), "Below replacement")
  expect_equal(classify_replacement(1.06), "Above replacement")
})

# =============================================================================
# SEMANTIC — accessor helpers return domain-correct values
# =============================================================================

test_that("SEM9: helpers report graduates (sum entrants), not total workforce", {
  withr::local_envvar(WORKFORCE_DATA_CSV = .valid_path)
  source(here("manuscript", "R", "workforce_statistics.R"), local = TRUE)

  df <- valid_df()
  # get_total_annual_entrants == sum(entrants), and is NOT the baseline workforce.
  expect_equal(get_total_annual_entrants(),
               format(sum(df$annual_entrants), big.mark = ","))
  expect_false(identical(get_total_annual_entrants(), get_total_baseline()))

  # 4-year fellowship totals use the horizon constant.
  for (ab in c("URPS", "GO", "MIGS")) {
    ent <- df$annual_entrants[df$subspecialty_abbrev == ab]
    # get_fellowship_total_5yr() was a compat alias kept across the 5-year ->
    # 4-year horizon standardisation (2026-07-15) and has since been removed.
    # get_fellowship_total_4yr() is the entrants x horizon computation this
    # assertion is about, and is named for the horizon it actually uses.
    expect_equal(get_fellowship_total_4yr(ab),
                 format(ent * WORKFORCE_PROJECTION_HORIZON_YEARS, big.mark = ","))
  }
})

test_that("SEM10: .filter_subspec is unambiguous (exact abbrev, no substring bleed)", {
  withr::local_envvar(WORKFORCE_DATA_CSV = .valid_path)
  source(here("manuscript", "R", "workforce_statistics.R"), local = TRUE)

  # "GO" must resolve to Gynecologic Oncology only (not substring-match another).
  # Baseline is the consensus clinically-active count (final primary-sourced rebuild).
  expect_equal(get_baseline("GO"), format(1052, big.mark = ","))
  # A bogus abbreviation errors rather than silently matching.
  expect_error(get_baseline("ZZZ"), "No subspecialty found")
})

# =============================================================================
# SEMANTIC — direction-word helpers, 4-year horizon standardization (2026-07-15)
# =============================================================================

test_that("SEM11: direction helpers follow the sign of percent_change", {
  withr::local_envvar(WORKFORCE_DATA_CSV = .valid_path)
  source(here("manuscript", "R", "workforce_statistics.R"), local = TRUE)

  df <- valid_df()
  for (ab in c("URPS", "GO", "MIGS")) {
    pct <- df$percent_change[df$subspecialty_abbrev == ab]
    up <- pct >= 0
    expect_equal(get_direction(ab),   if (up) "growth"     else "decline")
    expect_equal(get_change_noun(ab), if (up) "increase"   else "decrease")
    expect_equal(get_change_verb(ab), if (up) "increasing" else "decreasing")
  }
})

test_that("SEM12: percent-change magnitude carries no sign (no double negative)", {
  withr::local_envvar(WORKFORCE_DATA_CSV = .valid_path)
  source(here("manuscript", "R", "workforce_statistics.R"), local = TRUE)

  for (ab in c("URPS", "GO", "MIGS")) {
    mag <- get_percent_change_magnitude(ab)
    expect_false(grepl("[-+]", mag))                 # no leading sign
    expect_true(grepl("^[0-9]+\\.[0-9]$", mag))      # bare "n.n"
  }
})

test_that("SEM13: policy target = ceil(retirements * adequate-min); threshold reads contract", {
  withr::local_envvar(WORKFORCE_DATA_CSV = .valid_path)
  source(here("manuscript", "R", "workforce_statistics.R"), local = TRUE)

  df <- valid_df()
  for (ab in c("URPS", "GO", "MIGS")) {
    ret <- df$avg_annual_retirements[df$subspecialty_abbrev == ab]
    expect_equal(get_positions_for_adequate(ab),
                 as.integer(ceiling(ret * WORKFORCE_REPLACEMENT_BUFFER)))
  }
  expect_equal(get_adequate_threshold(),
               sprintf("%.1f", WORKFORCE_REPLACEMENT_BUFFER))
})

test_that("SEM14: fellowship totals are 4-year and the two getters agree", {
  withr::local_envvar(WORKFORCE_DATA_CSV = .valid_path)
  source(here("manuscript", "R", "workforce_statistics.R"), local = TRUE)

  # Validation targets from the analysis (graduates * 4-year horizon).
  # Multi-year ACGME graduate means (URPS 64 BOTH-PATHWAY, GO 75; MIGS 47 from
  # NRMP/AAGL) * 4. URPS = OB/GYN-sponsored 48 + urology-sponsored ~16 (Table D.5).
  targets <- c(URPS = 256, GO = 300, MIGS = 188)
  for (ab in names(targets)) {
    expect_equal(get_fellowship_total(ab),
                 format(targets[[ab]], big.mark = ","))
    # Column reader and entrants*horizon computation must agree.
    expect_equal(get_fellowship_total(ab), get_fellowship_total_4yr(ab))
  }
})

test_that("SEM16: retirement rates are the cohort-EMPIRICAL rates, not HRSA bands", {
  # The SSOT departure rate is derived from the cohort's OWN observed departures
  # (scripts/compute_empirical_retirement_rate_nppes.R), NOT the HRSA general-physician
  # age bands (which gave URPS 4.7 / GO 6.0 / MIGS 2.6). Estimated over the
  # fully-observable window (2016-2021, peer-review #4) the effective rates are
  # ~GO 1.2 / URPS 1.1 / MIGS 0.9, at or below the Elemosho low-attrition benchmark.
  # Guard against a silent revert to the inflated HRSA assumption.
  df <- valid_df()
  rate <- setNames(df$annual_retirement_rate, df$subspecialty_abbrev)
  # every rate sits in the empirical low-attrition band, well below the HRSA values
  expect_true(all(rate >= 0.5 & rate <= 2.6))
  expect_lt(rate[["GO"]], 4.0)     # HRSA GO was 6.0
  expect_lt(rate[["URPS"]], 3.0)   # HRSA URPS was 4.7
})

test_that("SEM15: obsolete 5-year fellowship horizon cannot reappear", {
  df <- valid_df()
  # SSOT carries the 4-year fellowship column, never the old 5-year one.
  expect_true("fellowship_total_4yr" %in% names(df))
  expect_false("fellowship_total_5yr" %in% names(df))
  # The 5-year report-horizon constant was removed from the contract.
  expect_false(exists("WORKFORCE_FELLOWSHIP_REPORT_YEARS"))
})
