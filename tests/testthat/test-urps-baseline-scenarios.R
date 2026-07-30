# The scientific follow-up must PRESERVE the published projection while making the
# baseline choice explicit through a CONTROLLED, same-engine comparison. These tests
# fail if the frozen projection is ever re-baselined, or if the hardened Table 1
# (published preservation) / Table 2 (controlled sensitivity) drift from the SSOT.
# The engine itself is guarded separately in test-wc-engine-equivalence.R.
suppressWarnings(suppressMessages({ library(testthat); library(mufflyaccess) }))

repo_root <- function() {
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) { if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
                   p <- dirname(d); if (identical(p, d)) break; d <- p }
  getwd()
}
sdir <- function() file.path(repo_root(), "scripts", "urps_baseline_scenarios")

test_that("the frozen SGS projection is preserved (legacy 1295 -> 1505.367)", {
  csv <- file.path(repo_root(), "data", "workforce_projections_consolidated.csv")
  skip_if_not(file.exists(csv), "frozen projection CSV not present")
  u <- utils::read.csv(csv, stringsAsFactors = FALSE)
  u <- u[u$subspecialty_abbrev == "URPS", ]
  expect_equal(as.integer(u$baseline_2025), 1295L)          # NOT re-baselined
  expect_equal(as.numeric(u$projected_2029), 1505.367, tolerance = 1e-3)
})

test_that("Table 1 preserves the published legacy result exactly (frozen, not recalculated)", {
  f <- file.path(sdir(), "table1_published_preservation.csv")
  skip_if_not(file.exists(f), "hardened Table 1 not generated")
  t1 <- utils::read.csv(f, stringsAsFactors = FALSE)
  expect_equal(nrow(t1), 1L)
  expect_equal(t1$scenario_id, "published_legacy_1295")
  expect_equal(as.integer(t1$baseline_count), 1295L)
  expect_equal(as.numeric(t1$projected_count), 1505.367, tolerance = 1e-3)
  expect_equal(as.numeric(t1$replacement_ratio), 5.61, tolerance = 1e-2)
  expect_identical(t1$frozen_or_recalculated, "frozen")   # reproducibility evidence, not a re-run
})

test_that("Table 2 is a controlled same-engine, same-horizon comparison tied to the SSOT", {
  f <- file.path(sdir(), "table2_controlled_sensitivity.csv")
  skip_if_not(file.exists(f), "hardened Table 2 not generated")
  s <- utils::read.csv(f, stringsAsFactors = FALSE)
  expect_setequal(s$scenario_id,
                  c("legacy_primarycert_rerun", "active_2023_1306", "roster_2025_1339"))

  # every controlled row is RECALCULATED through the same engine at horizon 4
  expect_true(all(s$frozen_or_recalculated == "recalculated"))
  expect_true(all(s$horizon == 4L))

  # data integrity: the generated table carries the v3.0.0 cells + legacy reconstruction
  active <- as.integer(s$baseline_count[s$scenario_id == "active_2023_1306"])
  roster <- as.integer(s$baseline_count[s$scenario_id == "roster_2025_1339"])
  expect_equal(active, 1306L)
  expect_equal(roster, 1339L)
  expect_equal(as.integer(s$baseline_count[s$scenario_id == "legacy_primarycert_rerun"]), 1301L)

  # SSOT tie: active/roster must equal the served cells -- verifiable only once
  # mufflyaccess v3.0.0 (0.7.1) is installed; the currently released 0.6.0 serves
  # the retired v2.1.0 count (1332), so this tie is skipped until then.
  v3_ready <- tryCatch(
    urps_count(2023, "board_certified_active", "national", TRUE) == 1306L,
    error = function(e) FALSE)
  if (isTRUE(v3_ready)) {
    expect_equal(active, urps_count(2023, "board_certified_active", "national", TRUE))
    expect_equal(roster, urps_count(2025, "roster_snapshot",        "national", TRUE))
  } else {
    skip("SSOT tie requires mufflyaccess v3.0.0 (1306); installed release serves the retired 1332")
  }

  # index-year discipline: the 2025 roster is 2025-indexed, NOT a 2023 baseline
  expect_equal(as.integer(s$index_year[s$scenario_id == "active_2023_1306"]), 2023L)
  expect_equal(as.integer(s$index_year[s$scenario_id == "roster_2025_1339"]), 2025L)
})

test_that("the legacy rerun is distinct from the frozen published result", {
  t1 <- utils::read.csv(file.path(sdir(), "table1_published_preservation.csv"), stringsAsFactors = FALSE)
  t2 <- utils::read.csv(file.path(sdir(), "table2_controlled_sensitivity.csv"), stringsAsFactors = FALSE)
  skip_if_not(nrow(t1) == 1L && nrow(t2) == 3L, "hardened tables not generated")
  rerun <- t2$replacement_ratio[t2$scenario_id == "legacy_primarycert_rerun"]
  # the same-engine rerun (~4.97) must NOT equal the frozen published ratio (5.61):
  # the shift is engine/hazard-driven, not baseline-count-driven.
  expect_false(isTRUE(all.equal(as.numeric(rerun), as.numeric(t1$replacement_ratio))))
  expect_lt(as.numeric(rerun), as.numeric(t1$replacement_ratio))
})
