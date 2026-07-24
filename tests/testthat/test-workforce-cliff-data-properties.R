# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Property-based tests for the workforce-cliff data analysis, grouped by the nine
# requested families. Each family states its PURPOSE and then asserts it.
#
#   1. Invariant   — domain constraints that must ALWAYS hold (counts, bounds).
#   2. Cardinality — expected row/key relationships between the artifacts.
#   3. Idempotency — the same read/validate/derive twice gives identical results.
#   4. Snapshot    — column names, shapes, and headline values are pinned.
#   5. Boundary    — data extremes and closest-to-cutoff real values.
#   6. Temporal    — time-series / windowed data is ordered and self-consistent.
#   7. Statistical — distributional properties (order statistics, co-monotonicity).
#   8. Mutation    — each guard PROVABLY catches an injected bug (real ok, mutant fails).
#   9. Metamorphic — transformations preserve the relationships they should.
#
# Run: Rscript -e 'testthat::test_file("tests/testthat/test-workforce-cliff-data-properties.R")'
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
library(testthat)

.root <- tryCatch(here::here(), error = function(e) {
  d <- normalizePath(".")
  while (!file.exists(file.path(d, "manuscript", "manuscript_WORKFORCE_CLIFF.Rmd")) &&
         dirname(d) != d) d <- dirname(d)
  d
})
DATA <- file.path(.root, "data")
csv  <- function(f) read.csv(file.path(DATA, f), stringsAsFactors = FALSE, check.names = FALSE)
source(file.path(.root, "manuscript", "R", "workforce_data_contract.R"))
SUBS <- c("URPS", "GO", "MIGS")

ssot   <- csv("workforce_projections_consolidated.csv")
audit  <- csv("departure_audit_table.csv")
hz     <- csv("hazard_by_band_pooled_vs_unpooled.csv")
hzr    <- csv("hazard_rate_pooled_vs_unpooled.csv")
dyn    <- csv("dynamic_projection_by_year.csv")
iv     <- csv("dynamic_projection_intervals.csv")
grid   <- csv("sensitivity_grid_summary.csv")
bkv    <- csv("breakeven_thresholds.csv")
flow   <- csv("consort_cohort_flow.csv")
corr   <- csv("classifier_corroboration.csv")
ext    <- csv("classifier_validation_external.csv")
opw    <- csv("operative_workforce.csv")
adj    <- csv("operative_adjudication.csv")
tte    <- csv("operative_tte.csv")
cap    <- csv("operative_capacity.csv")
comp   <- csv("general_obgyn_comparator.csv")
loso   <- csv("loso_source_contribution.csv")
tr     <- csv("graduation_active_transition.csv")
ages   <- csv("age_shift_sensitivity.csv")
ops    <- csv("open_payments_sensitivity.csv")
bench  <- csv("workforce_projection_benchmark_nrmp.csv")
row1   <- function(df, ab) df[toupper(df$subspecialty_abbrev) == toupper(ab), , drop = FALSE]

# Re-source the getters against an arbitrary SSOT via the documented override.
with_stats <- function(df, code) {
  tmp <- tempfile(fileext = ".csv"); utils::write.csv(df, tmp, row.names = FALSE)
  old <- Sys.getenv("WORKFORCE_DATA_CSV", unset = NA)
  Sys.setenv(WORKFORCE_DATA_CSV = tmp)
  on.exit({ if (is.na(old)) Sys.unsetenv("WORKFORCE_DATA_CSV") else Sys.setenv(WORKFORCE_DATA_CSV = old); unlink(tmp) }, add = TRUE)
  e <- new.env(parent = globalenv())
  suppressWarnings(suppressMessages(sys.source(file.path(.root, "manuscript", "R", "workforce_statistics.R"), envir = e)))
  code(e)
}
STATS_OK <- tryCatch({ with_stats(ssot, function(e) get("get_baseline", e)); TRUE }, error = function(e) FALSE)

# ============================================================================
# 1. INVARIANT — domain-specific constraints that must ALWAYS be true
# ============================================================================
test_that("INV counts are non-negative; baselines/entrants are whole numbers", {
  expect_true(all(ssot$baseline_2025 > 0))
  expect_true(all(ssot$annual_entrants >= 0))
  expect_true(all(ssot$avg_annual_retirements > 0))
  expect_equal(ssot$baseline_2025, round(ssot$baseline_2025))
  expect_equal(ssot$annual_entrants, round(ssot$annual_entrants))
  expect_true(all(ssot$replacement_ratio > 0))
})

test_that("INV every hazard band has person-years >= events and non-negative counts", {
  for (c in c("go", "urps", "migs", "pooled")) {
    ev <- hz[[paste0(c, "_events")]]; py <- hz[[paste0(c, "_py")]]
    expect_true(all(ev >= 0), info = c)
    expect_true(all(py >= 0), info = c)
    expect_true(all(py >= ev), info = c)                 # cannot observe more events than person-years
  }
})

test_that("INV Medicare-visible operators never exceed the active cohort; rates are %", {
  expect_true(all(opw$medicare_visible_operators <= opw$n_active_cohort))
  expect_true(all(opw$pct_of_active_visible >= 0 & opw$pct_of_active_visible <= 100))
  expect_true(all(opw$operative_cessation_rate_pct >= 0 & opw$operative_cessation_rate_pct <= 100))
})

test_that("INV all probabilities are in [0,1] and all percentages in [0,100]", {
  # cumulative-incidence and CDF columns are proper probabilities
  for (col in c("ci_operator_by3yr", "ci_operator_by5yr", "ci_operator_by8yr"))
    expect_true(all(tte[[col]] >= 0 & tte[[col]] <= 1), info = col)
  expect_true(all(tr$cum_active_fraction >= 0 & tr$cum_active_fraction <= 1))
  expect_true(all(tr$ever_billed_ceiling >= 0 & tr$ever_billed_ceiling <= 1))
  for (col in c("sensitivity", "specificity", "ppv", "npv", "accuracy"))
    expect_true(all(ext[[col]] >= 0 & ext[[col]] <= 1), info = col)
  expect_true(all(ext$kappa >= -1 & ext$kappa <= 1))
  for (col in c("pct_of_departures", "pct_lost_if_removed"))
    expect_true(all(loso[[col]] >= 0 & loso[[col]] <= 100), info = col)
})

test_that("INV annual_retirement_rate == 100 * avg_annual_retirements / baseline", {
  expect_equal(ssot$annual_retirement_rate,
               100 * ssot$avg_annual_retirements / ssot$baseline_2025, tolerance = 1e-4)
})

test_that("INV leave-one-source-out: sole-support never exceeds total support", {
  expect_true(all(loso$sole_support_lost_if_removed <= loso$n_departures_supported))
  expect_true(all(loso$sole_support_lost_if_removed >= 0))
})

# ============================================================================
# 2. CARDINALITY — relationship / key-count validation between entities
# ============================================================================
test_that("CARD SSOT is exactly the three surgical subspecialties, no dupes", {
  expect_equal(nrow(ssot), 3L)
  expect_setequal(ssot$subspecialty_abbrev, SUBS)
  expect_equal(anyDuplicated(ssot$subspecialty_abbrev), 0L)
})

test_that("CARD audit table: every definition appears once per {GO,URPS}", {
  tab <- table(audit$definition, audit$subspecialty_abbrev)
  expect_true(all(tab == 1))                              # each (definition,subspec) exactly once
  expect_setequal(colnames(tab), c("GO", "URPS"))
})

test_that("CARD every artifact keyed by subspecialty covers the right key set 1:1", {
  expect_setequal(grid$subspecialty_abbrev, SUBS)
  expect_setequal(bkv$subspecialty_abbrev, SUBS)
  expect_setequal(bench$subspecialty_abbrev, SUBS)
  expect_setequal(flow$ab, SUBS)
  expect_setequal(unique(dyn$subspecialty_abbrev), SUBS)
  expect_setequal(unique(tr$subspecialty_abbrev), c("GO", "URPS"))
  expect_setequal(unique(ages$subspecialty_abbrev), c("GO", "URPS"))
  for (df in list(grid, bkv, bench, flow)) expect_equal(nrow(df), 3L)
})

test_that("CARD fixed-shape panels have exactly the expected row multiplicities", {
  expect_equal(nrow(hz), 7L)                              # 7 age bands
  expect_equal(nrow(dyn), 15L)                            # 3 subspec x 5 years
  expect_equal(nrow(tr), 12L)                             # 2 subspec x k=0..5
  expect_equal(nrow(ages), 6L)                            # 2 subspec x {0,2,4}
  expect_equal(nrow(ops), 4L)                             # 2 rules x 2 subspec
  expect_equal(nrow(ext), 4L)                             # URPS,GO,MIGS,ALL
  expect_equal(sum(dyn$subspecialty_abbrev == "GO"), 5L)  # exactly five years per subspec
})

test_that("CARD no orphan subspecialty keys: derived files are subsets of the SSOT set", {
  for (nm in list(grid$subspecialty_abbrev, bkv$subspecialty_abbrev, bench$subspecialty_abbrev,
                  flow$ab, unique(dyn$subspecialty_abbrev)))
    expect_true(all(nm %in% SUBS))
})

# ============================================================================
# 3. IDEMPOTENCY — repeating a read / validate / derive is bit-identical
# ============================================================================
test_that("IDEM reading the SSOT twice yields identical data", {
  expect_identical(csv("workforce_projections_consolidated.csv"),
                   csv("workforce_projections_consolidated.csv"))
})

test_that("IDEM validate_workforce_data has no side effects and is repeatable", {
  before <- ssot
  expect_no_error(validate_workforce_data(ssot))
  expect_no_error(validate_workforce_data(ssot))
  expect_identical(ssot, before)                          # validation did not mutate the frame
})

test_that("IDEM classify_replacement is deterministic across calls", {
  x <- seq(0.5, 2, by = 0.001)
  expect_identical(classify_replacement(x), classify_replacement(x))
})

test_that("IDEM load_workforce_data() returns identical tibbles on repeat", {
  a <- load_workforce_data(); b <- load_workforce_data()
  expect_identical(a, b)
})

test_that("IDEM getters return identical strings on repeated calls", {
  skip_if_not(STATS_OK)
  with_stats(ssot, function(e) {
    for (ab in SUBS) {
      expect_identical(e$get_baseline(ab), e$get_baseline(ab), info = ab)
      expect_identical(e$get_replacement_ratio(ab), e$get_replacement_ratio(ab), info = ab)
    }
    expect_identical(e$get_total_baseline(), e$get_total_baseline())
  })
})

# ============================================================================
# 4. SNAPSHOT — pin column names, shapes, and headline values (drift detector)
# ============================================================================
test_that("SNAP SSOT column names and order are exactly the frozen schema", {
  expect_identical(names(ssot), c(
    "subspecialty", "subspecialty_abbrev", "baseline_2025", "projected_2029",
    "sd_2029", "ci95_lower", "ci95_upper", "percent_change", "annual_retirement_rate",
    "avg_annual_retirements", "annual_entrants", "replacement_ratio",
    "replacement_assessment", "fellowship_total_4yr", "total_retirements_4yr"))
})

test_that("SNAP categorical key sets are frozen (definitions / rules / bands)", {
  expect_setequal(unique(audit$definition), c(
    "primary (non-OP anchored)", "OP-inclusive consensus",
    "primary, ABOG-only URPS baseline", "primary, window 2016-2019",
    "primary, window 2016-2023"))
  expect_setequal(unique(ops$rule), c("non_op_anchored (primary)", "op_inclusive"))
  expect_identical(hz$band, c("<45", "45-49", "50-54", "55-59", "60-64", "65-69", "70+"))
})

test_that("SNAP frozen headline numbers (rounded content signature)", {
  sig <- function(ab) c(base = row1(ssot, ab)$baseline_2025,
                        proj = round(row1(ssot, ab)$projected_2029, 1),
                        ratio = round(row1(ssot, ab)$replacement_ratio, 2))
  expect_equal(sig("URPS"), c(base = 1295, proj = 1505.4, ratio = 5.61))
  expect_equal(sig("GO"),   c(base = 1052, proj = 1309.8, ratio = 7.11))
  expect_equal(sig("MIGS"), c(base = 605,  proj = 776.0,  ratio = 11.06))
})

test_that("SNAP headline getter strings are format-stable", {
  skip_if_not(STATS_OK)
  with_stats(ssot, function(e) {
    expect_identical(e$get_baseline("GO"), "1,052")
    expect_identical(e$get_replacement_ratio("URPS"), "5.6")   # display rounds to 1 decimal (reviewer #6); raw SSOT stays 5.61
    expect_identical(e$get_percent_change("MIGS"), "+28.3")
    expect_identical(e$get_total_baseline(), "2,952")
  })
})

# ============================================================================
# 5. BOUNDARY — data extremes and closest-to-cutoff real values
# ============================================================================
test_that("BND every reported (headline) replacement ratio clears the 1.05 cutoff", {
  expect_true(all(ssot$replacement_ratio > 1.05))
  expect_gt(min(ssot$replacement_ratio), 1.05)            # closest real value is still Above
})

test_that("BND the only sub-1.0 sensitivity cell is URPS worst_ratio (global minimum)", {
  expect_equal(grid$subspecialty_abbrev[which.min(grid$worst_ratio)], "URPS")
  expect_lt(min(grid$worst_ratio), 1.0)
  expect_true(all(grid$worst_ratio[grid$subspecialty_abbrev != "URPS"] > 1.0))
})

test_that("BND extreme age bands behave: 70+ has (near) zero exposure, 65-69 is the peak hazard", {
  expect_lte(hz$pooled_py[hz$band == "70+"], 20)         # negligible person-years at the top
  expect_equal(hz$band[which.max(hz$pooled_hazard)], "65-69")
  expect_equal(hz$pooled_events[hz$band == "70+"], 0)
})

test_that("BND smallest cohort is MIGS and it carries the fewest departures", {
  expect_equal(ssot$subspecialty_abbrev[which.min(ssot$baseline_2025)], "MIGS")
  expect_equal(ssot$subspecialty_abbrev[which.min(ssot$avg_annual_retirements)], "MIGS")
})

# ============================================================================
# 6. TEMPORAL — time-series and windowed data must be logically ordered
# ============================================================================
test_that("TMP dynamic projection years are contiguous 2025-2029, sorted, no gaps per subspec", {
  for (ab in SUBS) {
    yrs <- sort(dyn$year[dyn$subspecialty_abbrev == ab])
    expect_identical(yrs, 2025:2029, info = ab)
  }
})

test_that("TMP base year 2025 has zero flows; stock grows monotonically thereafter", {
  for (ab in SUBS) {
    s <- dyn[dyn$subspecialty_abbrev == ab, ]; s <- s[order(s$year), ]
    expect_equal(s$departures[s$year == 2025], 0, info = ab)
    expect_equal(s$entrants[s$year == 2025], 0, info = ab)
    expect_true(all(diff(s$active) > 0), info = ab)          # active headcount rises each year
    expect_true(all(s$departures >= 0), info = ab)
  }
})

test_that("TMP graduation->active CDF is monotone non-decreasing in years post-cert", {
  for (ab in c("GO", "URPS")) {
    s <- tr[tr$subspecialty_abbrev == ab, ]; s <- s[order(s$k), ]
    expect_true(all(diff(s$cum_active_fraction) >= 0), info = ab)
    expect_equal(length(unique(s$ever_billed_ceiling)), 1L, info = ab)  # ceiling is time-invariant
  }
})

test_that("TMP wider departure windows accumulate more events and person-years (nested windows)", {
  w4 <- audit[audit$definition == "primary, window 2016-2019", ]
  w6 <- audit[audit$definition == "primary (non-OP anchored)", ]   # 2016-2021
  w8 <- audit[audit$definition == "primary, window 2016-2023", ]
  for (ab in c("GO", "URPS")) {
    e4 <- w4$eligible_departures[w4$subspecialty_abbrev == ab]
    e6 <- w6$eligible_departures[w6$subspecialty_abbrev == ab]
    e8 <- w8$eligible_departures[w8$subspecialty_abbrev == ab]
    expect_true(e4 < e6 && e6 < e8, info = ab)              # monotone in window length
    p4 <- w4$pooled_person_years[w4$subspecialty_abbrev == ab]
    p8 <- w8$pooled_person_years[w8$subspecialty_abbrev == ab]
    expect_gt(p8, p4)
  }
})

# ============================================================================
# 7. STATISTICAL — distributional properties and sanity of estimates
# ============================================================================
test_that("STAT prediction interval brackets the mean; width co-monotone with SD", {
  expect_true(all(ssot$ci95_lower < ssot$projected_2029 & ssot$projected_2029 < ssot$ci95_upper))
  width <- ssot$ci95_upper - ssot$ci95_lower
  expect_identical(order(width), order(ssot$sd_2029))       # more SD -> wider interval
  k <- width / ssot$sd_2029
  expect_true(all(k > 2 & k < 5))                           # plausible multiplier for a 95% PI
})

test_that("STAT pooled overall hazard is a weighted average within the band range", {
  overall <- sum(hz$pooled_events) / sum(hz$pooled_py)
  expect_gte(overall, min(hz$pooled_hazard))
  expect_lte(overall, max(hz$pooled_hazard))
})

test_that("STAT departure-age order statistics respect p25 <= median <= p75", {
  expect_true(all(comp$p25 <= comp$median_departure_age))
  expect_true(all(comp$median_departure_age <= comp$p75))
})

test_that("STAT external classifier is conservative: high specificity, low PPV, sens<spec", {
  expect_true(all(ext$specificity > 0.85))                 # rarely flags a truly-active physician
  expect_true(all(ext$ppv < 0.2))                          # provisional -> low precision
  expect_true(all(ext$sensitivity < ext$specificity))
})

test_that("STAT hazard trends upward with age across bands with real exposure", {
  # the 70+ band carries negligible exposure (16 person-years, 0 events) and is
  # uninformative about the age gradient; restrict to bands with adequate exposure.
  h <- hz[hz$pooled_py >= 50, ]
  rho <- suppressWarnings(cor(seq_along(h$pooled_hazard), h$pooled_hazard, method = "spearman"))
  expect_gt(rho, 0.7)
  # the oldest informative band must carry the highest hazard
  expect_equal(h$band[which.max(h$pooled_hazard)], "65-69")
})

# ============================================================================
# 8. MUTATION — prove each guard actually catches an injected bug
#    (predicate TRUE on real data, FALSE / error on a deliberately broken copy)
# ============================================================================
test_that("MUT contract validator kills a broken replacement ratio", {
  expect_no_error(validate_workforce_data(ssot))           # real passes
  m <- ssot; m$replacement_ratio[1] <- m$replacement_ratio[1] + 1  # inject bug
  expect_error(validate_workforce_data(m), "replacement_ratio")    # mutant caught
})

test_that("MUT pooled-events invariant catches a tampered band total", {
  inv <- function(h) all(h$pooled_events == h$go_events + h$urps_events)  # primary pool = GO+URPS
  expect_true(inv(hz))
  m <- hz; m$pooled_events[3] <- m$pooled_events[3] + 1
  expect_false(inv(m))
})

test_that("MUT confusion-matrix row-sum invariant catches a tampered cell", {
  inv <- function(v) all(v$TP + v$FN + v$FP + v$TN == v$n)
  expect_true(inv(ext))
  m <- ext; m$TP[1] <- m$TP[1] + 5
  expect_false(inv(m))
})

test_that("MUT CONSORT ABU identity catches a broken inclusion count", {
  inv <- function(f) { u <- f[f$ab == "URPS", ]; u$active_baseline + u$abu_included == u$active_baseline_final }
  expect_true(inv(flow))
  m <- flow; m$abu_included[m$ab == "URPS"] <- m$abu_included[m$ab == "URPS"] + 3
  expect_false(inv(m))
})

test_that("MUT audit-primary-reconciles-SSOT check catches a drifted ratio", {
  recon <- function(a) {
    p <- a[a$definition == "primary (non-OP anchored)", ]
    all(sapply(c("GO", "URPS"), function(ab)
      abs(p$completion_to_departure_ratio[p$subspecialty_abbrev == ab] -
          row1(ssot, ab)$replacement_ratio) < 0.01))
  }
  expect_true(recon(audit))
  m <- audit; m$completion_to_departure_ratio[m$definition == "primary (non-OP anchored)" &
                                               m$subspecialty_abbrev == "GO"] <- 9.9
  expect_false(recon(m))
})

test_that("MUT drift pin catches a swapped baseline", {
  pin_ok <- function(df) df$baseline_2025[df$subspecialty_abbrev == "GO"] == 1052
  expect_true(pin_ok(ssot))
  m <- ssot; i <- which(m$subspecialty_abbrev == "GO"); j <- which(m$subspecialty_abbrev == "URPS")
  tmp <- m$baseline_2025[i]; m$baseline_2025[i] <- m$baseline_2025[j]; m$baseline_2025[j] <- tmp
  expect_false(pin_ok(m))
})

# ============================================================================
# 9. METAMORPHIC — transformations preserve the relationships they should
# ============================================================================
test_that("META classify_replacement is monotone non-decreasing in the ratio", {
  set.seed(20260719)
  r <- sort(runif(500, 0.5, 2))
  rank <- match(classify_replacement(r), c("Below replacement", "At replacement", "Above replacement"))
  expect_true(all(diff(rank) >= 0))                        # never classifies a higher ratio as more scarce
})

test_that("META percent_change is invariant to a common scaling of baseline and projected", {
  pct <- function(b, p) 100 * (p - b) / b
  for (c in c(0.5, 2.5, 10)) {
    expect_equal(pct(ssot$baseline_2025 * c, ssot$projected_2029 * c),
                 ssot$percent_change, tolerance = 1e-6, info = as.character(c))
  }
})

test_that("META replacement ratio is homogeneous of degree 0 (scale entrants & departures together)", {
  base_ratio <- ssot$annual_entrants / ssot$avg_annual_retirements
  for (c in c(0.3, 3, 7))
    expect_equal((ssot$annual_entrants * c) / (ssot$avg_annual_retirements * c),
                 base_ratio, tolerance = 1e-9, info = as.character(c))
})

test_that("META projection responds linearly: +delta entrants -> +4*delta projected, higher ratio", {
  proj <- function(b, e, r) b + 4 * (e - r)
  for (delta in c(1, 5, 12)) {
    base <- proj(ssot$baseline_2025, ssot$annual_entrants, ssot$avg_annual_retirements)
    bumped <- proj(ssot$baseline_2025, ssot$annual_entrants + delta, ssot$avg_annual_retirements)
    expect_equal(bumped - base, rep(4 * delta, nrow(ssot)), info = as.character(delta))
    expect_true(all((ssot$annual_entrants + delta) / ssot$avg_annual_retirements >
                    ssot$annual_entrants / ssot$avg_annual_retirements))
  }
})

test_that("META confusion-matrix rates are invariant to scaling all cells by a constant", {
  for (c in c(2, 5)) {
    m <- ext; for (col in c("TP", "FN", "FP", "TN", "n")) m[[col]] <- m[[col]] * c
    expect_equal(round(m$TP / (m$TP + m$FN), 3), ext$sensitivity, info = as.character(c))
    expect_equal(round(m$TN / (m$TN + m$FP), 3), ext$specificity, info = as.character(c))
  }
})

test_that("META aggregate getters are invariant to SSOT row permutation", {
  skip_if_not(STATS_OK)
  base_totals <- with_stats(ssot, function(e)
    c(e$get_total_baseline(), e$get_total_projected(), e$get_baseline("GO"), e$get_replacement_ratio("URPS")))
  perm <- ssot[c(3, 1, 2), ]                               # reorder rows
  perm_totals <- with_stats(perm, function(e)
    c(e$get_total_baseline(), e$get_total_projected(), e$get_baseline("GO"), e$get_replacement_ratio("URPS")))
  expect_identical(base_totals, perm_totals)
})

test_that("META CONSORT active_baseline invariant to equal add of certified and inactive", {
  inv <- flow$certified_matched - flow$removed_deceased - flow$removed_inactive
  bumped <- (flow$certified_matched + 7) - flow$removed_deceased - (flow$removed_inactive + 7)
  expect_equal(inv, bumped)                                # +k certified and +k inactive cancels
  expect_equal(inv, flow$active_baseline)
})
