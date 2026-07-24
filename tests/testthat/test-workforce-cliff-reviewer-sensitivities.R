# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Adversarial + semantic tests for the two prespecified reviewer sensitivities
# added 2026-07-19 (scripts/build_reviewer_sensitivities.R):
#   #2 age-specific mortality (SSA Period Life Table 2020) -> mortality_sensitivity.csv
#   #3 consistent-definition (anchored) baseline -> consistent_definition_baseline_sensitivity.csv
# Adversarial = the committed artifacts must reconcile to the SSOT and obey the
#   arithmetic the prose claims. Semantic = the manuscript must assert the finished
#   analyses and must NOT reassert the retired "pending / zero deceased" language.
# Run: Rscript -e 'testthat::test_file("tests/testthat/test-workforce-cliff-reviewer-sensitivities.R")'
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
library(testthat)

.root <- tryCatch(here::here(), error = function(e) {
  d <- normalizePath("."); while (!file.exists(file.path(d, "manuscript", "manuscript_WORKFORCE_CLIFF.Rmd")) &&
       dirname(d) != d) d <- dirname(d); d })
DATA <- file.path(.root, "cliff", "data")
MAIN <- file.path(.root, "manuscript", "manuscript_WORKFORCE_CLIFF.Rmd")
main <- paste(readLines(MAIN, warn = FALSE), collapse = "\n")
csv  <- function(f) read.csv(file.path(DATA, f), stringsAsFactors = FALSE, check.names = FALSE)
has  <- function(txt, pat) grepl(pat, txt, ignore.case = TRUE, perl = TRUE)
SSOT <- csv("workforce_projections_consolidated.csv")
ssot_ratio <- function(ab) SSOT$replacement_ratio[SSOT$subspecialty_abbrev == ab]
ssot_base  <- function(ab) SSOT$baseline_2025[SSOT$subspecialty_abbrev == ab]

# ============================ #2 MORTALITY ================================
test_that("[adversarial] mortality sensitivity reconciles to the SSOT and stays above replacement", {
  m <- csv("mortality_sensitivity.csv")
  expect_true(all(c("GO", "URPS") %in% m$subspecialty_abbrev))
  for (ab in c("GO", "URPS")) {
    r <- m[m$subspecialty_abbrev == ab, ]
    # primary column must reproduce the SSOT headline ratio (no drift / wrong-source)
    expect_equal(round(r$ratio_primary, 1), round(ssot_ratio(ab), 1), info = ab)
    # adding expected deaths can only INCREASE departures -> LOWER the ratio
    expect_lt(r$ratio_adj_all_missed,  r$ratio_primary)
    expect_lt(r$ratio_adj_half_missed, r$ratio_primary)
    # half-missed sits strictly between primary and all-missed (monotone dose-response)
    expect_gt(r$ratio_adj_half_missed, r$ratio_adj_all_missed)
    # the paper's claim: even the all-missed UPPER bound stays above one-for-one
    expect_gt(r$ratio_adj_all_missed, 1.0)
    # deaths and the adjusted rate move in the expected direction
    expect_gt(r$expected_mortality_per_yr, 0)
    expect_gt(r$rate_adj_all_pct, r$rate_primary_pct)
    # mortality-adjusted 2029 is below the primary 2029 (deaths remove stock)
    expect_lt(r$projected_2029_mortality_adj, r$projected_2029_primary)
  }
})

test_that("[semantic] getters bind the mortality prose to the artifact", {
  ok <- tryCatch({ source(file.path(.root, "manuscript", "R", "workforce_statistics.R")); TRUE },
                 error = function(e) FALSE)
  skip_if_not(ok, "workforce_statistics.R could not be sourced in this env")
  m <- csv("mortality_sensitivity.csv")
  for (ab in c("GO", "URPS")) {
    r <- m[m$subspecialty_abbrev == ab, ]
    expect_identical(get_mortality_ratio_all(ab),  sprintf("%.1f", r$ratio_adj_all_missed))
    expect_identical(get_mortality_ratio_half(ab), sprintf("%.1f", r$ratio_adj_half_missed))
  }
})

# ======================= #3 CONSISTENT BASELINE ==========================
test_that("[adversarial] consistent-definition baseline reconciles and stays adequate", {
  b <- csv("consistent_definition_baseline_sensitivity.csv")
  expect_true(all(c("GO", "URPS") %in% b$subspecialty_abbrev))
  for (ab in c("GO", "URPS")) {
    r <- b[b$subspecialty_abbrev == ab, ]
    # primary columns must reproduce the SSOT baseline + ratio
    expect_equal(r$baseline_primary, ssot_base(ab), info = ab)
    expect_equal(round(r$ratio_primary, 1), round(ssot_ratio(ab), 1), info = ab)
    expect_gt(r$baseline_consistent, 0)
    # "does not materially bias": anchored ratio stays adequate (>=1.2) and within
    # 15% of the primary ratio
    expect_gt(r$ratio_consistent, 1.2)
    expect_lt(abs(r$ratio_consistent - r$ratio_primary) / r$ratio_primary, 0.15)
  }
})

# ============================ LIFE TABLE =================================
test_that("[adversarial] SSA life table is well-formed and actuarially sane", {
  lt <- read.csv(file.path(DATA, "ssa_period_life_table_2020.csv"),
                 comment.char = "#", stringsAsFactors = FALSE)
  expect_true(all(c("age", "male_qx", "female_qx") %in% names(lt)))
  expect_true(all(lt$male_qx > 0 & lt$male_qx < 1))
  expect_true(all(lt$female_qx > 0 & lt$female_qx < 1))
  # male mortality exceeds female at every adult age (biological invariant)
  expect_true(all(lt$male_qx >= lt$female_qx))
  # q(x) increases with age across the working-age span (monotone non-decreasing)
  a <- lt[order(lt$age), ]
  expect_true(all(diff(a$male_qx[a$age >= 40 & a$age <= 90]) >= 0))
  # sanity anchor: 65-year-old male q(x) in a plausible SSA range (catches corruption)
  expect_true(lt$male_qx[lt$age == 65] > 0.008 & lt$male_qx[lt$age == 65] < 0.03)
})

# ======================= #10 AGE-BAND BACK-TEST ==========================
test_that("[adversarial] age-band back-test calibrates in the well-populated bands", {
  bt <- csv("temporal_backtest_ageband.csv")
  expect_true(all(c("GO","URPS") %in% bt$subspecialty_abbrev))
  expect_true(all(bt$n_base > 0) && all(bt$observed_active >= 0) && all(bt$predicted_active >= 0))
  # well-populated bands (n>=50) calibrate within a few percent
  well <- bt[bt$n_base >= 50, ]
  expect_lt(max(abs(well$pct_error), na.rm = TRUE), 5)
  ok <- tryCatch({ source(file.path(.root, "manuscript", "R", "workforce_statistics.R")); TRUE }, error = function(e) FALSE)
  if (ok) {
    expect_identical(get_backtest_band_maxerr(50), sprintf("%.0f", max(abs(well$pct_error), na.rm = TRUE)))
    expect_true(has(main, "Stratifying the back-test by age band"))
  }
})

# ======================= #5 BASELINE-LAG DECOMPOSITION ===================
test_that("[adversarial] baseline-lag decomposition reconciles and does not weaken the conclusion", {
  bl <- csv("baseline_lag_decomposition.csv")
  ssot <- csv("workforce_projections_consolidated.csv")
  for (ab in c("GO","URPS")) {
    r <- bl[bl$subspecialty_abbrev == ab, ]
    # categories + ABU sum to the estimated baseline
    parts <- r$directly_supported + r$carried_fwd_1_2yr + r$carried_fwd_3plus + r$presumed_entrant + r$no_admin_history + r$abu_net_new
    expect_equal(parts, r$baseline_total, info = ab)
    # baseline + primary ratio reconcile to the SSOT
    expect_equal(r$baseline_total, ssot$baseline_2025[ssot$subspecialty_abbrev == ab], info = ab)
    expect_equal(round(r$ratio_primary, 1), round(ssot$replacement_ratio[ssot$subspecialty_abbrev == ab], 1), info = ab)
    # removing long-lag carried-forward stock does not lower the ratio
    expect_gte(r$ratio_lag_trimmed, r$ratio_primary)
    # most of the Part B-observable stock is directly supported in the latest admin year
    expect_gt(r$directly_supported / (r$baseline_total - r$abu_net_new), 0.8, info = ab)
  }
})

# ======================= #8 GRADUATE-SUPPLY SCENARIOS ====================
test_that("[adversarial] every graduate-supply scenario stays above replacement", {
  gs <- csv("graduate_growth_scenarios.csv")
  need <- c("flat_recent_mean","cohort_accounting","contraction","cautious_trend")
  for (ab in c("GO","URPS")) {
    r <- gs[gs$subspecialty_abbrev == ab, ]
    expect_true(all(need %in% r$scenario), info = ab)
    expect_true(all(r$replacement_ratio > 1.0), info = ab)          # above one-for-one
    # flat recent mean reconciles to the primary headline ratio
    fm <- r$replacement_ratio[r$scenario == "flat_recent_mean"]
    expect_equal(round(fm, 1), if (ab == "GO") 7.1 else 5.6)
    # cohort accounting (most recent year) >= contraction (recent low)
    expect_gte(r$replacement_ratio[r$scenario=="cohort_accounting"], r$replacement_ratio[r$scenario=="contraction"])
  }
})

test_that("[semantic] the graduate-scenario getter binds the prose to the artifact", {
  ok <- tryCatch({ source(file.path(.root, "manuscript", "R", "workforce_statistics.R")); TRUE }, error = function(e) FALSE)
  skip_if_not(ok, "workforce_statistics.R could not be sourced in this env")
  gs <- csv("graduate_growth_scenarios.csv")
  for (ab in c("GO","URPS")) for (s in c("contraction","cohort_accounting")) {
    r <- gs[gs$subspecialty_abbrev == ab & gs$scenario == s, ]
    expect_identical(get_grad_scenario_ratio(s, ab), sprintf("%.1f", r$replacement_ratio))
  }
  expect_true(has(main, "distinct graduate-supply assumptions"))
})

# ======================= #9 INACTIVITY THRESHOLD =========================
test_that("[adversarial] inactivity-threshold sensitivity stays above replacement and rises with threshold", {
  it <- csv("inactivity_threshold_sensitivity.csv")
  expect_true(all(c(2, 3, 4) %in% it$threshold_years))
  for (ab in c("GO", "URPS")) {
    r <- it[it$subspecialty_abbrev == ab, ]
    r <- r[order(r$threshold_years), ]
    # the paper's claim: above one-for-one at every threshold
    expect_true(all(r$replacement_ratio > 1.0), info = ab)
    # a stricter (longer) inactivity requirement can only keep or raise the ratio
    expect_true(all(diff(r$replacement_ratio) >= 0), info = ab)
  }
})

test_that("[semantic] the inactivity getter binds the prose to the artifact", {
  ok <- tryCatch({ source(file.path(.root, "manuscript", "R", "workforce_statistics.R")); TRUE },
                 error = function(e) FALSE)
  skip_if_not(ok, "workforce_statistics.R could not be sourced in this env")
  it <- csv("inactivity_threshold_sensitivity.csv")
  for (ab in c("GO", "URPS")) for (T in c(2, 4)) {
    r <- it[it$subspecialty_abbrev == ab & it$threshold_years == T, ]
    expect_identical(get_inactivity_ratio(T, ab), sprintf("%.1f", r$replacement_ratio))
  }
  expect_true(has(main, "Varying the required inactivity duration"))
})

# ======================= sensitivity-artifact contract ==================
test_that("[contract] sensitivity-artifact contract passes for committed artifacts and fails on missing", {
  ok <- tryCatch({ source(file.path(.root, "manuscript", "R", "workforce_data_contract.R")); TRUE }, error = function(e) FALSE)
  skip_if_not(ok, "workforce_data_contract.R could not be sourced")
  # passes against the committed cliff/data artifacts
  expect_true(validate_sensitivity_artifacts(data_dir = file.path(.root, "cliff", "data"), strict = TRUE))
  # fails loud when the artifacts are absent (empty dir)
  expect_error(validate_sensitivity_artifacts(data_dir = tempdir(), strict = TRUE), "sensitivity contract")
  # every registered artifact is one the manuscript getters actually read
  stats_src <- paste(readLines(file.path(.root, "manuscript", "R", "workforce_statistics.R"), warn = FALSE), collapse = "\n")
  for (f in names(WORKFORCE_SENSITIVITY_ARTIFACTS))
    expect_true(grepl(f, stats_src, fixed = TRUE), info = f)
})

# ======================= #4 HIERARCHICAL PARTIAL POOLING =================
test_that("[adversarial] hierarchical partial-pooling stays above replacement and shrinks between unpooled and pooled", {
  hh <- csv("hierarchical_hazard_comparison.csv")
  for (m in c("unpooled", "pooled", "partial_pooled")) expect_true(all(c("GO","URPS") %in% hh$subspecialty_abbrev[hh$method == m]), info = m)
  # pooled method must reconcile to the SSOT primary ratios (7.11 / 5.61)
  expect_equal(round(hh$replacement_ratio[hh$method=="pooled" & hh$subspecialty_abbrev=="GO"],1), 7.1)
  expect_equal(round(hh$replacement_ratio[hh$method=="pooled" & hh$subspecialty_abbrev=="URPS"],1), 5.6)
  for (ab in c("GO","URPS")) {
    un <- hh$replacement_ratio[hh$method=="unpooled" & hh$subspecialty_abbrev==ab]
    po <- hh$replacement_ratio[hh$method=="pooled"   & hh$subspecialty_abbrev==ab]
    pp <- hh$replacement_ratio[hh$method=="partial_pooled" & hh$subspecialty_abbrev==ab]
    lo <- hh$ci_lo[hh$method=="partial_pooled" & hh$subspecialty_abbrev==ab]
    expect_gt(un, 1.0); expect_gt(po, 1.0); expect_gt(pp, 1.0)
    # partial pool sits between unpooled and pooled (shrinkage)
    expect_gte(pp, min(un, po) - 1e-9); expect_lte(pp, max(un, po) + 1e-9)
    # the reported lower credible bound stays above replacement
    expect_gt(lo, 1.0)
  }
  # ABU 0.5x/2x envelope for URPS stays above replacement
  expect_true(all(hh$replacement_ratio[grepl("abu", hh$method)] > 1.0))
})

test_that("[semantic] the hierarchical getters bind the prose to the artifact", {
  ok <- tryCatch({ source(file.path(.root, "manuscript", "R", "workforce_statistics.R")); TRUE },
                 error = function(e) FALSE)
  skip_if_not(ok, "workforce_statistics.R could not be sourced in this env")
  hh <- csv("hierarchical_hazard_comparison.csv")
  for (ab in c("GO","URPS")) for (m in c("unpooled","pooled","partial_pooled")) {
    r <- hh[hh$method==m & hh$subspecialty_abbrev==ab, ]
    expect_identical(get_hier_ratio(m, ab), sprintf("%.1f", r$replacement_ratio))
  }
  expect_true(has(main, "hierarchical partial-pooling model"))
})

# ============================ SEMANTIC PROSE ==============================
test_that("[semantic] manuscript reports both finished sensitivities, not the retired language", {
  expect_true(has(main, "age- and sex-specific expected-mortality sensitivity"))
  expect_true(has(main, "SSA Period Life Table, 2020"))
  expect_true(has(main, "regenerates the 2025 active stock under the same anchored departure rule"))
  # retired phrasings must be gone
  expect_false(has(main, "removes zero deceased physicians"))
  expect_false(has(main, "prespecified but is not yet complete"))
})

# ============================ FIGURES =====================================
test_that("[adversarial] figure builders return ggplot objects from the committed data", {
  ok <- tryCatch({ source(file.path(.root, "manuscript", "R", "workforce_figures.R")); TRUE },
                 error = function(e) FALSE)
  skip_if_not(ok, "workforce_figures.R could not be sourced in this env")
  expect_s3_class(fig_trajectory(), "ggplot")
  expect_s3_class(fig_robustness(), "ggplot")
})

test_that("[semantic] both figures are wired into the manuscript with cross-references", {
  expect_true(has(main, "source\\(here\\(\"manuscript/R/workforce_figures.R\"\\)\\)"))
  expect_true(has(main, "fig_trajectory\\(\\)"))
  expect_true(has(main, "fig_robustness\\(\\)"))
  expect_true(has(main, "left both board-certified cohorts above replacement \\(Figure 2\\)"))
  # the retired 3-scenario Figure 1 generator is no longer the Figure 1 source
  expect_false(has(main, "create_figure_scenario_projection"))
})
