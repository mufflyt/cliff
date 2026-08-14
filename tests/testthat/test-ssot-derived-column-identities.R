# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Invariant guards for every algebraically derived column in the SSOT.
#
# data/workforce_projections_consolidated.csv is the single source of truth for
# the publication-facing workforce numbers. Six of its columns are DEFINITIONS,
# not measurements, and must equal their defining expression at full precision:
#
#   annual_retirement_rate = 100 * avg_annual_retirements / baseline_2025
#   replacement_ratio      = annual_entrants / avg_annual_retirements
#   percent_change         = 100 * (projected_2029 - baseline_2025) / baseline_2025
#   replacement_assessment = "Above replacement" iff replacement_ratio >= 1
#   fellowship_total_4yr   = 4 * annual_entrants
#   total_retirements_4yr  = round(4 * avg_annual_retirements)
#
# These previously drifted because scripts/rebuild_ssot_revised.R hand-entered
# them as rounded literals (5.38 for 5.384894, 24.506 for 24.506264). The
# generator now computes them; this file is the guard that keeps it that way.
# A failure here means someone re-introduced a hand-entered derived value.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
library(testthat)

.repo <- function() {
  d <- normalizePath(getwd(), winslash = "/")
  for (i in 1:8) {
    if (file.exists(file.path(d, "DESCRIPTION"))) return(d)
    p <- dirname(d); if (identical(p, d)) break; d <- p
  }
  getwd()
}
.ssot_path <- file.path(.repo(), "data", "workforce_projections_consolidated.csv")

ssot <- local({
  skip_if_not(file.exists(.ssot_path), "SSOT artifact not present")
  utils::read.csv(.ssot_path, stringsAsFactors = FALSE)
})

test_that("the SSOT carries every column these identities are defined over", {
  expect_true(all(c("subspecialty_abbrev", "baseline_2025", "projected_2029",
                    "percent_change", "annual_retirement_rate",
                    "avg_annual_retirements", "annual_entrants",
                    "replacement_ratio", "replacement_assessment",
                    "fellowship_total_4yr", "total_retirements_4yr") %in% names(ssot)))
  expect_gt(nrow(ssot), 0L)
})

test_that("replacement_ratio == annual_entrants / avg_annual_retirements", {
  expect_equal(ssot$replacement_ratio,
               ssot$annual_entrants / ssot$avg_annual_retirements)
})

test_that("percent_change == 100 * (projected_2029 - baseline_2025) / baseline_2025", {
  expect_equal(ssot$percent_change,
               100 * (ssot$projected_2029 - ssot$baseline_2025) / ssot$baseline_2025)
})

test_that("annual_retirement_rate == 100 * avg_annual_retirements / baseline_2025", {
  expect_equal(ssot$annual_retirement_rate,
               100 * ssot$avg_annual_retirements / ssot$baseline_2025)
})

test_that("fellowship_total_4yr == 4 * annual_entrants", {
  expect_equal(as.numeric(ssot$fellowship_total_4yr),
               4 * as.numeric(ssot$annual_entrants))
})

test_that("total_retirements_4yr == round(4 * avg_annual_retirements)", {
  expect_equal(as.numeric(ssot$total_retirements_4yr),
               round(4 * ssot$avg_annual_retirements))
})

test_that("replacement_assessment agrees with the ratio it summarises", {
  expected <- ifelse(ssot$replacement_ratio >= 1,
                     "Above replacement", "Below replacement")
  expect_equal(ssot$replacement_assessment, expected)
})

# ---- precision ---------------------------------------------------------------
# The identities above are exact only because the artifact stores full double
# precision. If someone re-rounds a derived column on write, the identities go
# soft long before they visibly break, so pin the precision directly.
test_that("derived columns are stored at full precision, not rounded for display", {
  derived <- c("percent_change", "annual_retirement_rate", "replacement_ratio")
  for (col in derived) {
    v <- ssot[[col]]
    expect_false(isTRUE(all.equal(v, round(v, 2), tolerance = 0)),
                 info = paste0(col, " looks rounded to 2 dp; display rounding ",
                               "belongs in the manuscript, not the SSOT"))
  }
})

# ---- aggregation -------------------------------------------------------------
test_that("the baseline-weighted mean of per-row percent_change equals the overall change", {
  w        <- ssot$baseline_2025 / sum(ssot$baseline_2025)
  weighted <- sum(w * ssot$percent_change)
  overall  <- 100 * (sum(ssot$projected_2029) - sum(ssot$baseline_2025)) /
                sum(ssot$baseline_2025)
  # Exact once percent_change is unrounded: the weights are exactly the
  # baseline shares the identity is defined over.
  expect_equal(weighted, overall)
})
