# The scientific follow-up must PRESERVE the published projection while making the
# 1295 / 1306 / 1339 baseline choice explicit. These tests fail if the frozen
# projection is ever re-baselined or if the scenario comparison drifts from the SSOT.
suppressWarnings(suppressMessages({ library(testthat); library(mufflyaccess) }))

repo_root <- function() {
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) { if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
                   p <- dirname(d); if (identical(p, d)) break; d <- p }
  getwd()
}

test_that("the frozen SGS projection is preserved (legacy 1295 -> 1505.367)", {
  csv <- file.path(repo_root(), "data", "workforce_projections_consolidated.csv")
  skip_if_not(file.exists(csv), "frozen projection CSV not present")
  u <- utils::read.csv(csv, stringsAsFactors = FALSE)
  u <- u[u$subspecialty_abbrev == "URPS", ]
  expect_equal(as.integer(u$baseline_2025), 1295L)          # NOT re-baselined
  expect_equal(as.numeric(u$projected_2029), 1505.367, tolerance = 1e-3)
})

test_that("the scenario comparison holds three distinct baselines tied to the SSOT", {
  f <- file.path(repo_root(), "scripts", "urps_baseline_scenarios",
                 "urps_baseline_scenarios_v3.0.0.csv")
  skip_if_not(file.exists(f), "scenario comparison not generated")
  s <- utils::read.csv(f, stringsAsFactors = FALSE)
  expect_equal(nrow(s), 3L)
  expect_setequal(s$baseline_2023, c(1295L, 1306L, 1339L))

  # B and C baselines equal the current SSOT cells (not hardcoded)
  active <- s$baseline_2023[s$scenario == "B_active_2023"]
  roster <- s$baseline_2023[s$scenario == "C_roster_2025"]
  expect_equal(active, urps_count(2023, "board_certified_active", "national", TRUE))  # 1306
  expect_equal(roster, urps_count(2025, "roster_snapshot",        "national", TRUE))  # 1339

  # scenario A is the PUBLISHED record; B/C are fresh engine runs
  expect_match(s$source[s$scenario == "A_legacy"], "PUBLISHED")
  expect_true(all(grepl("engine re-run", s$source[s$scenario != "A_legacy"])))

  # projections are ordered by baseline and the legacy point matches the frozen record
  expect_true(all(diff(s$projected_2029[order(s$baseline_2023)]) > 0))
  expect_equal(s$projected_2029[s$scenario == "A_legacy"], 1505.4, tolerance = 0.1)
})

test_that("current cohorts retire faster than the legacy assumption", {
  f <- file.path(repo_root(), "scripts", "urps_baseline_scenarios",
                 "urps_baseline_scenarios_v3.0.0.csv")
  skip_if_not(file.exists(f), "scenario comparison not generated")
  s <- utils::read.csv(f, stringsAsFactors = FALSE)
  legacy_ret <- s$avg_annual_retirements[s$scenario == "A_legacy"]
  active_ret <- s$avg_annual_retirements[s$scenario == "B_active_2023"]
  expect_gt(active_ret, legacy_ret)   # the documented finding (older cohort, faster attrition)
})
