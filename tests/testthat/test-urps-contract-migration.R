# Proves the mufflyaccess contract migration is non-value-changing and that the
# legacy frozen projection cohort (1295) is preserved, not mislabeled, and not
# faked through urps_count(). Companion to test-no-unqualified-urps-baseline.R.
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

test_that("the frozen SGS projection still begins at the legacy 1295 baseline", {
  csv <- file.path(repo_root(), "data", "workforce_projections_consolidated.csv")
  skip_if_not(file.exists(csv), "frozen projection CSV not present")
  d <- utils::read.csv(csv, stringsAsFactors = FALSE)
  urps <- d[d$subspecialty_abbrev == "URPS", ]
  expect_equal(nrow(urps), 1L)
  expect_equal(as.integer(urps$baseline_2025), 1295L)   # NOT re-baselined
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

test_that("2025 status-quo application paths route through urps_count(), not a literal", {
  root <- repo_root()
  targets <- c("shiny_urps_scenarios/app.R",
               "augs_application/scripts/cms_supply_demand_10styles.R")
  for (t in targets) {
    p <- file.path(root, t); skip_if_not(file.exists(p), t)
    code <- sub("#.*$", "", readLines(p, warn = FALSE))    # strip comments
    expect_true(any(grepl("urps_count\\(", code)), info = paste(t, "calls urps_count()"))
    expect_true(any(grepl("roster_snapshot", code)),  info = paste(t, "uses roster_snapshot"))
    expect_false(any(grepl("(?<![0-9.])1339(?![0-9.])", code, perl = TRUE)),
                 info = paste(t, "has no bare 1339 literal in code"))
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
