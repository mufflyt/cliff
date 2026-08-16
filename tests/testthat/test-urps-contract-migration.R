
# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()
# Proves the mufflyaccess contract migration keeps the three URPS baselines
# distinct (1295 legacy / 1306 active / 1339 roster) and that none is faked
# through urps_count(). Companion to test-no-unqualified-urps-baseline.R.
#
# 2026-08-09: the frozen SGS projection was DELIBERATELY re-baselined 1295 ->
# 1306 (797f36b "adopt 1306", 42fefcd), and workforce_data_contract.R now marks
# URPS_LEGACY_PROJECTION_BASELINE as "superseded by 1306". The CSV assertion
# below had been pinned at 1295 and was the last guard left behind by that
# migration. It now sources the expected value from the SSOT instead of
# restating a literal, so it cannot go stale the same way again.
suppressWarnings(suppressMessages({ library(testthat); library(mufflyaccess) }))

repo_root <- function() {
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) { if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
                   p <- dirname(d); if (identical(p, d)) break; d <- p }
  normalizePath(getwd(), winslash = "/")
}
prod_lines <- function() {
  root <- repo_root()
  fs <- list.files(root, pattern = "\\.[Rr]$", recursive = TRUE, full.names = TRUE)
  rel <- sub(paste0(root, "/"), "", fs, fixed = TRUE)
  fs <- fs[!grepl("(^|/)(tests?|testthat|renv|packrat|docs)(/|$)", rel, ignore.case = TRUE)]
  stats::setNames(lapply(fs, readLines, warn = FALSE), fs)
}

test_that("mufflyaccess supplies the v3.0.0 contract we consume", {
  expect_equal(urps_provenance()$contract_version, "3.0.0")
})

test_that("the 2025 status-quo baseline is 1339 via the SSOT (value preserved)", {
  n <- urps_count(2025, "roster_snapshot", "national", include_urology = TRUE,
                  incomplete = "error")
  expect_equal(n, 1339L)                       # de-hardcoding only: same value
})

test_that("three URPS baselines are distinct: 1295 legacy / 1306 active / 1339 roster", {
  active_2023 <- urps_count(2023, "board_certified_active", "national", TRUE)   # current
  roster_2025 <- urps_count(2025, "roster_snapshot",        "national", TRUE)   # snapshot
  expect_equal(active_2023, 1306L)       # v3.0.0 current 2023 active (NOT the retired 1332)
  expect_equal(roster_2025, 1339L)
  expect_false(active_2023 %in% c(1295L, 1332L, 1339L))  # separate from legacy/retired/roster
  expect_false(identical(active_2023, roster_2025))
})

test_that("the SGS projection baseline is the SSOT current-active count, not the legacy cohort", {
  csv <- file.path(repo_root(), "data", "workforce_projections_consolidated.csv")
  skip_if_not(file.exists(csv), "frozen projection CSV not present")
  d <- utils::read.csv(csv, stringsAsFactors = FALSE)
  urps <- d[d$subspecialty_abbrev == "URPS", ]
  expect_equal(nrow(urps), 1L)
  # Tied to the SSOT rather than restated as a literal.
  expect_equal(as.integer(urps$baseline_2025),
               urps_count(2023, "board_certified_active", "national", TRUE))
  # and it is no longer the superseded legacy frozen cohort
  expect_false(as.integer(urps$baseline_2025) == 1295L)
})

test_that("the new 1306 current-active scenario is sourced from the SSOT, separate from 1295", {
  # the current-active value is 1306 and is distinct from the frozen cohort (1295)
  expect_equal(urps_count(2023, "board_certified_active", "national", TRUE), 1306L)
  expect_equal(urps_count(2023, "board_certified_active", "conus",    TRUE), 1303L)
  expect_false(urps_count(2023, "board_certified_active", "national", TRUE) == 1295L)
  # the data contract defines the new scenario constants, routed through urps_count()
  dc <- file.path(repo_root(), "manuscript", "R", "workforce_data_contract.R")
  skip_if_not(file.exists(dc), "data contract not present")
  txt <- readLines(dc, warn = FALSE)
  expect_true(any(grepl("URPS_2023_ACTIVE_NATIONAL_CURRENT", txt)))     # scenario defined
  expect_true(any(grepl('urps_count\\(2023, "board_certified_active", "national"', txt)))  # sourced, not a literal
  # and the legacy cohort is still present and annotated
  expect_true(any(grepl("URPS_LEGACY_PROJECTION_BASELINE\\s*<-\\s*1295L", txt)))
})

test_that("application paths route through urps_count() with the RIGHT measure, not a literal", {
  # The measure is per application, because they model different things and
  # conflating them is the specific failure this guards against:
  #
  #   shiny_urps_scenarios  projects the COHORT, so its baseline is the
  #                         current-active count (board_certified_active, 1306).
  #   augs_application      anchors 2025 status-quo DEMAND, so it correctly uses
  #                         the roster snapshot (1339).
  #
  # Requiring roster_snapshot of both is what previously forced the scenarios app
  # to validate a 1,306 model against a 1,339 expectation and refuse to launch.
  root <- repo_root()
  targets <- list(
    "shiny_urps_scenarios/app.R"                          = "board_certified_active",
    "augs_application/scripts/cms_supply_demand_10styles.R" = "roster_snapshot")
  for (t in names(targets)) {
    measure <- targets[[t]]
    p <- file.path(root, t); skip_if_not(file.exists(p), t)
    code <- sub("#.*$", "", readLines(p, warn = FALSE))    # strip comments
    expect_true(any(grepl("urps_count\\(", code)), info = paste(t, "calls urps_count()"))
    expect_true(any(grepl(measure, code)), info = paste(t, "uses", measure))
    # No bare literal for EITHER estimand, in either file.
    expect_false(any(grepl("(?<![0-9.])1339(?![0-9.])", code, perl = TRUE)),
                 info = paste(t, "has no bare 1339 literal in code"))
    expect_false(any(grepl("(?<![0-9.])1306(?![0-9.])", code, perl = TRUE)),
                 info = paste(t, "has no bare 1306 literal in code"))
  }
})

test_that("no production code labels 1295 as a 2025 active count", {
  ll <- prod_lines()
  offenders <- unlist(lapply(names(ll), function(f) {
    x <- ll[[f]]
    # a mislabel asserts "1295 = 2025 active"; a prohibition ("never", "not") is fine
    hit <- grepl("1295", x) & grepl("2025[ _-]*active", x, ignore.case = TRUE) &
           !grepl("never|not |n't|do not|isn't", x, ignore.case = TRUE)
    if (any(hit)) paste0(f, ":", which(hit)) else NULL
  }))
  expect_length(offenders, 0)
})
