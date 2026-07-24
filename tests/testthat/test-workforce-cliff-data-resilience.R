# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Resilience & ground-truth tests for the workforce-cliff data analysis.
#
#   METAMORPHIC   - additional relationship-preservation transforms not covered
#                   in test-workforce-cliff-data-properties.R.
#   CHAOS / FAULT - inject corruption into the SSOT and assert the fail-loud
#                   loader/validator rejects it (fail closed, never silent-pass).
#   GOLD STANDARD - hand-calculated ground truth; the pipeline numbers must match
#                   arithmetic done by hand, independent of the producing code.
#   SCHEMA (PROD) - assert the schema of the REAL tracked production CSVs directly
#                   (no mocks, no `if (col %in% names)` guards that skip silently).
#
# Run: Rscript -e 'testthat::test_file("tests/testthat/test-workforce-cliff-data-resilience.R")'
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
library(testthat)

.root <- tryCatch(here::here(), error = function(e) {
  d <- normalizePath(".")
  while (!file.exists(file.path(d, "manuscript", "manuscript_WORKFORCE_CLIFF.Rmd")) &&
         dirname(d) != d) d <- dirname(d)
  d
})
DATA <- file.path(.root, "cliff", "data")
csv  <- function(f) read.csv(file.path(DATA, f), stringsAsFactors = FALSE, check.names = FALSE)
source(file.path(.root, "manuscript", "R", "workforce_data_contract.R"))
SUBS <- c("URPS", "GO", "MIGS")
ssot <- csv("workforce_projections_consolidated.csv")
row1 <- function(df, ab) df[df$subspecialty_abbrev == ab, , drop = FALSE]

# write a data frame to a temp CSV and return the path (for fault injection)
tmp_csv <- function(df) { p <- tempfile(fileext = ".csv"); utils::write.csv(df, p, row.names = FALSE); p }

# ============================================================================
# METAMORPHIC (additional) — transformations that must preserve relationships
# ============================================================================
test_that("META annual<->4-year unit conversion round-trips (rate x 4 / 4 == rate)", {
  expect_equal(ssot$fellowship_total_4yr / 4, ssot$annual_entrants, tolerance = 1e-9)
  expect_equal(ssot$total_retirements_4yr, round(4 * ssot$avg_annual_retirements))
  # round-trip: annualize the 4-year fellowship total back to the per-year entrants
  expect_equal((ssot$fellowship_total_4yr / 4), ssot$annual_entrants)
})

test_that("META total percent change equals the baseline-weighted mean of per-row percents", {
  w <- ssot$baseline_2025 / sum(ssot$baseline_2025)
  weighted <- sum(w * ssot$percent_change)
  overall  <- 100 * (sum(ssot$projected_2029) - sum(ssot$baseline_2025)) / sum(ssot$baseline_2025)
  expect_equal(weighted, overall, tolerance = 1e-6)   # aggregation consistency
})

test_that("META subspecialty ordering by ratio is invariant to a common entrant scaling", {
  base_ord <- order(ssot$annual_entrants / ssot$avg_annual_retirements)
  for (c in c(0.5, 3, 9)) {
    scaled <- order((ssot$annual_entrants * c) / ssot$avg_annual_retirements)
    expect_identical(scaled, base_ord, info = as.character(c))
  }
})

test_that("META age-band hazard is invariant to a common scaling of events and person-years", {
  h <- csv("hazard_by_band_pooled_vs_unpooled.csv")
  nz <- h$pooled_py > 0
  base <- h$pooled_events[nz] / h$pooled_py[nz]
  for (c in c(2, 10))
    expect_equal((h$pooled_events[nz] * c) / (h$pooled_py[nz] * c), base, tolerance = 1e-12,
                 info = as.character(c))
})

# ============================================================================
# CHAOS / FAULT INJECTION — the loader/validator must fail CLOSED on corruption
# ============================================================================
test_that("CHAOS missing file is rejected, not silently tolerated", {
  expect_error(load_workforce_data(path = file.path(tempdir(), "does_not_exist_xyz.csv")),
               "not found")
})

test_that("CHAOS header-only (zero data rows) file is rejected", {
  p <- tmp_csv(ssot[0, , drop = FALSE])
  expect_error(load_workforce_data(path = p), "0 rows")
})

test_that("CHAOS a dropped required column is rejected", {
  p <- tmp_csv(ssot[, setdiff(names(ssot), "replacement_ratio")])
  expect_error(load_workforce_data(path = p), "missing required column")
})

test_that("CHAOS a stray NA in a critical column is rejected", {
  d <- ssot; d$annual_entrants[2] <- NA
  expect_error(load_workforce_data(path = tmp_csv(d)), "NA")
})

test_that("CHAOS a corrupted numeric cell (text where a number belongs) does not pass silently", {
  d <- ssot; d$baseline_2025 <- as.character(d$baseline_2025); d$baseline_2025[1] <- "corrupt"
  # readr/validator must NOT return a clean table with a garbage baseline
  expect_error(suppressWarnings(load_workforce_data(path = tmp_csv(d))))
})

test_that("CHAOS an injected extra subspecialty (wrong grain) is rejected", {
  d <- rbind(ssot, transform(ssot[1, ], subspecialty_abbrev = "MFM", subspecialty = "Maternal Fetal Medicine"))
  expect_error(load_workforce_data(path = tmp_csv(d)))
})

test_that("CHAOS a duplicated subspecialty row is rejected", {
  expect_error(load_workforce_data(path = tmp_csv(rbind(ssot, ssot[1, ]))))
})

test_that("CHAOS a truncated/garbage file does not yield a valid table", {
  p <- tempfile(fileext = ".csv"); writeLines(c("subspecialty_abbrev,baseline_2025", "GO,"), p)
  expect_error(suppressWarnings(load_workforce_data(path = p)))
})

# ============================================================================
# GOLD STANDARD — hand-calculated ground truth (independent of producing code)
# ============================================================================
test_that("GOLD GO ratio/projection/percent match hand arithmetic", {
  go <- row1(ssot, "GO")
  # ratio = 75 / 10.552582813358663 = 7.1073... (GO+URPS-only hazard)
  expect_equal(go$replacement_ratio, 75 / 10.552582813358663, tolerance = 1e-6)
  # projected = 1052 + 4*(75 - 10.552582813358663) = 1309.7897...
  expect_equal(go$projected_2029, 1052 + 4 * (75 - 10.552582813358663), tolerance = 1e-6)
  # percent = 100*(1309.7897 - 1052)/1052 = 24.5047...
  expect_equal(go$percent_change, 100 * (go$projected_2029 - 1052) / 1052, tolerance = 1e-6)
})

test_that("GOLD weighted aggregates match hand-calculated totals", {
  # baseline sum: 1295 + 1052 + 605 = 2952 (hand)
  expect_equal(sum(ssot$baseline_2025), 2952)
  # fellowship 4-yr totals: 64*4=256, 75*4=300, 47*4=188 (hand)
  expect_equal(sort(ssot$fellowship_total_4yr), sort(c(256, 300, 188)))
  # projected sum rounds to 3591 (hand: 1505.39 + 1309.79 + 776.01 = 3591.18)
  expect_equal(round(sum(ssot$projected_2029)), 3591)
})

test_that("GOLD hazard band and break-even drop match hand arithmetic", {
  h <- csv("hazard_by_band_pooled_vs_unpooled.csv")
  # <45 primary pooled hazard (GO+URPS) = 24 / 7635 = 0.0031434 -> stored 0.0031 (hand)
  expect_equal(round(24 / 7635, 4), h$pooled_hazard[h$band == "<45"])
  b <- csv("breakeven_thresholds.csv")
  # GO graduate_drop_pct = round(100*(1 - 1/7.35)) = round(86.39) = 86 (hand)
  expect_equal(b$graduate_drop_pct[b$subspecialty_abbrev == "GO"], 86)
})

test_that("GOLD confusion-matrix rates match hand arithmetic on the external validation set", {
  v <- csv("classifier_validation_external.csv")
  u <- v[v$subspec == "URPS", ]
  # sensitivity = TP/(TP+FN) = 1/(1+3) = 0.25 exactly (hand)
  expect_equal(u$sensitivity, 0.25)
  # accuracy = (TP+TN)/n = (1+366)/415 = 0.8843 -> 0.884 (hand)
  expect_equal(u$accuracy, round((1 + 366) / 415, 3))
})

# ============================================================================
# SCHEMA (PRODUCTION FILES) — assert the REAL tracked CSV schemas DIRECTLY
# (no mocks; no conditional `if (col %in% names)` guards that skip silently)
# ============================================================================
test_that("SCHEMA production SSOT has the exact column set and correct column types", {
  expect_identical(names(ssot), c(
    "subspecialty", "subspecialty_abbrev", "baseline_2025", "projected_2029",
    "sd_2029", "ci95_lower", "ci95_upper", "percent_change", "annual_retirement_rate",
    "avg_annual_retirements", "annual_entrants", "replacement_ratio",
    "replacement_assessment", "fellowship_total_4yr", "total_retirements_4yr"))
  # direct type assertions (unconditional)
  expect_true(is.character(ssot$subspecialty))
  expect_true(is.character(ssot$subspecialty_abbrev))
  expect_true(is.numeric(ssot$baseline_2025))
  expect_true(is.numeric(ssot$projected_2029))
  expect_true(is.numeric(ssot$replacement_ratio))
  expect_true(is.character(ssot$replacement_assessment))
  expect_true(all(ssot$replacement_assessment %in% WORKFORCE_VALID_ASSESSMENTS))
})

test_that("SCHEMA production hazard table columns are present and numeric (direct)", {
  h <- csv("hazard_by_band_pooled_vs_unpooled.csv")
  need <- c("band", "go_events", "go_py", "urps_events", "urps_py",
            "migs_events", "migs_py", "pooled_events", "pooled_py", "pooled_hazard")
  expect_true(all(need %in% names(h)))
  expect_true(is.character(h$band))
  for (col in setdiff(need, "band")) expect_true(is.numeric(h[[col]]), info = col)
})

test_that("SCHEMA production audit table has its declared key columns and types (direct)", {
  a <- csv("departure_audit_table.csv")
  need <- c("definition", "subspecialty_abbrev", "window", "eligible_departures",
            "pooled_person_years", "completion_to_departure_ratio", "projected_2029")
  expect_true(all(need %in% names(a)))
  expect_true(is.character(a$definition))
  expect_true(is.character(a$subspecialty_abbrev))
  expect_true(is.numeric(a$eligible_departures))
  expect_true(is.numeric(a$completion_to_departure_ratio))
})

test_that("SCHEMA production CONSORT flow has the ABU columns with numeric counts (direct)", {
  f <- csv("consort_cohort_flow.csv")
  need <- c("ab", "certified_matched", "removed_deceased", "removed_inactive",
            "active_baseline", "abu_identified", "abu_excluded_nocert", "abu_included",
            "active_baseline_final")
  expect_true(all(need %in% names(f)))
  expect_true(is.character(f$ab))
  for (col in setdiff(need, "ab")) expect_true(is.numeric(f[[col]]), info = col)
})

test_that("SCHEMA departure_anchor NPI column preserves 10-digit identifiers (direct)", {
  an <- csv("departure_anchor.csv")
  expect_true("npi" %in% names(an))
  expect_true("has_nonop_anchor" %in% names(an))
  # NPIs must be exactly 10 digits (leading zeros preserved when read as text)
  npi_chr <- as.character(an$npi)
  expect_true(all(nchar(npi_chr) == 10 | grepl("^[0-9]{10}$", npi_chr)),
              label = "every NPI is a 10-digit identifier")
})
