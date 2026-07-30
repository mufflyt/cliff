# Scientific-validity gates for the URPS baseline scenario analysis.
# The published 1295 projection must be preserved; controlled scenarios must all
# use the same engine; 1339 must be 2025-indexed (not a 2023 baseline); age-band
# counts must sum to each baseline; count and age effects must be separable.
suppressWarnings(suppressMessages({ library(testthat); library(mufflyaccess) }))

repo_root <- function() {
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) { if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
                   p <- dirname(d); if (identical(p, d)) break; d <- p }
  getwd()
}
sdir <- file.path(repo_root(), "scripts", "urps_baseline_scenarios")
rd   <- function(f) { p <- file.path(sdir, f); skip_if_not(file.exists(p), f); utils::read.csv(p, stringsAsFactors = FALSE) }

test_that("GATE: the frozen published projection is preserved (1295 -> 1505.367)", {
  csv <- file.path(repo_root(), "data", "workforce_projections_consolidated.csv")
  skip_if_not(file.exists(csv), "frozen CSV not present")
  u <- utils::read.csv(csv, stringsAsFactors = FALSE); u <- u[u$subspecialty_abbrev == "URPS", ]
  expect_equal(as.integer(u$baseline_2025), 1295L)
  expect_equal(as.numeric(u$projected_2029), 1505.367, tolerance = 1e-3)
})

test_that("GATE: Table 1 holds only the frozen result, labelled not-recalculated", {
  t1 <- rd("table1_published_preservation_v3.0.0.csv")
  expect_equal(nrow(t1), 1L)
  expect_equal(t1$baseline_count, 1295L)
  expect_equal(t1$frozen_or_recalculated, "frozen")
  expect_true(is.na(t1$seed))                       # not recalculated
})

test_that("GATE: Table 2 scenarios all use the same recalculated engine; 1339 is 2025-indexed", {
  t2 <- rd("table2_controlled_sensitivity_v3.0.0.csv")
  expect_setequal(t2$scenario_id, c("legacy_rerun","active_2023","roster_2025"))
  expect_true(all(t2$frozen_or_recalculated == "recalculated"))
  expect_true(all(grepl("wc_project", t2$engine_version)))         # same engine for all
  expect_true(all(t2$seed == 20260718L))

  # the rerun 1295 is DISTINCT from the frozen published result
  frozen <- rd("table1_published_preservation_v3.0.0.csv")$projected_count
  rerun  <- t2$projected_count[t2$scenario_id == "legacy_rerun"]
  expect_false(isTRUE(all.equal(rerun, frozen)))

  # 1339 is labelled 2025-indexed, NOT a 2023 baseline
  r <- t2[t2$scenario_id == "roster_2025", ]
  expect_equal(r$index_year, 2025L)
  expect_match(r$observed_or_synthetic, "2025-indexed")
  # 2023 stocks are index 2023 with the honest 6-year horizon to 2029
  expect_equal(t2$index_year[t2$scenario_id == "active_2023"], 2023L)
  expect_equal(t2$horizon[t2$scenario_id == "active_2023"], 6L)
  expect_true(all(t2$target_year == 2029L))

  # baselines B and C tie to the SSOT (not hardcoded)
  expect_equal(t2$baseline_count[t2$scenario_id == "active_2023"],
               urps_count(2023, "board_certified_active", "national", TRUE))  # 1306
  expect_equal(t2$baseline_count[t2$scenario_id == "roster_2025"],
               urps_count(2025, "roster_snapshot", "national", TRUE))         # 1339
})

test_that("GATE: Table 4 is a same-horizon view (all index 2025, horizon 4)", {
  t4 <- rd("table4_same_horizon_h4_v3.0.0.csv")
  expect_setequal(t4$scenario_id, c("legacy_h4","active_h4","roster_h4"))
  expect_true(all(t4$index_year == 2025L))       # same index year
  expect_true(all(t4$horizon == 4L))             # same horizon (removes the confound)
  expect_true(all(t4$target_year == 2029L))
  expect_true(all(grepl("wc_project", t4$engine_version)))
  expect_true(all(t4$seed == 20260718L))
  # only the roster is a genuine 2025 stock; the 2023 stocks are adopted-as-2025
  expect_match(t4$observed_or_synthetic[t4$scenario_id == "active_h4"], "adopted as the 2025 baseline")
  expect_match(t4$observed_or_synthetic[t4$scenario_id == "roster_h4"], "genuine 2025 stock")
  # baselines tie to the SSOT
  expect_equal(t4$baseline_count[t4$scenario_id == "active_h4"],
               urps_count(2023, "board_certified_active", "national", TRUE))  # 1306
  expect_equal(t4$baseline_count[t4$scenario_id == "roster_h4"],
               urps_count(2025, "roster_snapshot", "national", TRUE))         # 1339
  # same-horizon projections must be ordered by baseline (no horizon confound)
  expect_true(all(diff(t4$projected_count[order(t4$baseline_count)]) > 0))
})

test_that("GATE: age-band counts sum exactly to each baseline", {
  ages <- rd("urps_cohort_ages_v3.0.0.csv")
  expect_equal(sum(ages$n_active_2023), 1306L)
  expect_equal(sum(ages$n_roster_2025), 1339L)
  expect_equal(sum(ages$n_roster_2025) - sum(ages$n_active_2023), 33L)   # excluded future-certified
  expect_true(all(ages$age_proxy >= 25 & ages$age_proxy <= 100))         # no impossible ages
})

test_that("GATE: count and age-composition effects are separately quantified", {
  t3 <- rd("table3_count_age_decomposition_v3.0.0.csv")
  expect_true(all(c("count_effect","age_effect_roster","combined_roster") %in% t3$contrast))
  # count effect changes the count but keeps the 2023-active age structure
  ce <- t3[t3$contrast == "count_effect", ]
  expect_equal(ce$baseline_count, 1295L); expect_equal(ce$age_structure, "2023-active")
  # age effect keeps the count (1306) but swaps to the roster structure
  ae <- t3[t3$contrast == "age_effect_roster", ]
  expect_equal(ae$baseline_count, 1306L); expect_equal(ae$age_structure, "2025-roster")
  # the count effect on the retirement RATE is negligible vs the reference (isolated size)
  ref_ret <- t3$avg_annual_retirements[t3$contrast == "reference_active_2023"]
  expect_lt(abs(ce$avg_annual_retirements - ref_ret), 0.2)
})

test_that("GATE: every exported row carries the required provenance columns", {
  need <- c("scenario_id","observed_or_synthetic","source_artifact","source_year","index_year",
            "target_year","horizon","baseline_count","age_proxy_method","entrant_assumption",
            "hazard_version","engine_version","seed","draw_count","projected_count","ci_lower",
            "ci_upper","avg_annual_retirements","frozen_or_recalculated")
  for (f in c("table1_published_preservation_v3.0.0.csv","table2_controlled_sensitivity_v3.0.0.csv",
              "table4_same_horizon_h4_v3.0.0.csv"))
    expect_true(all(need %in% names(rd(f))), info = f)
})
