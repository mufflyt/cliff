
# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Semantic + adversarial tests for EVERY part of the workforce-cliff data analysis.
#
#   Semantic    = each artifact has the shape/columns/labels its consumers assume,
#                 and the numbers mean what the manuscript says they mean.
#   Adversarial = the arithmetic identities that tie columns and files together
#                 must hold; the fail-loud contract validator must REJECT tampered
#                 tables; and a silent drift of the headline numbers must trip a pin.
#
# Scope (one context per analysis surface):
#   A. SSOT table (workforce_projections_consolidated.csv) structure + identities + pin
#   B. Data-contract validator (validate_workforce_data) — must reject bad tables
#   C. Manuscript getters (workforce_statistics.R) — read/format/sign correctness
#   D. Cross-file reconciliation (audit, OP sensitivity, age shift, ramp) -> SSOT
#   E. Pooled-vs-unpooled age-band hazard decomposition
#   F. Multidimensional sensitivity grid
#   G. Break-even thresholds
#   H. CONSORT cohort flow (incl. ABU two-pathway arithmetic)
#   I. Departure-classifier corroboration + external confusion-matrix validation
#   J. Operative-workforce validity tables
#   K. General OB/GYN comparator + leave-one-source-out contribution
#   L. Dynamic stock-flow projection (internal recurrence invariants)
#   M. NRMP-filled benchmark
#
# Run: Rscript -e 'testthat::test_file("tests/testthat/test-workforce-cliff-data-analysis.R")'
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
row1 <- function(df, ab) {
  r <- df[toupper(df$subspecialty_abbrev) == toupper(ab), , drop = FALSE]
  if (nrow(r) != 1) stop(sprintf("expected exactly 1 row for %s, got %d", ab, nrow(r)))
  r
}
SUBS <- c("URPS", "GO", "MIGS")

# The frozen headline (drift pins). Any silent change to these trips a test.
# Centralized in workforce_data_contract.R (#9) so a value change touches one place.
source(file.path(.root, "manuscript", "R", "workforce_data_contract.R"))
PIN_BASELINE <- WORKFORCE_HEADLINE_BASELINE
PIN_RATIO    <- WORKFORCE_HEADLINE_RATIO   # GO+URPS-only primary hazard (MIGS excluded 2026-07-19)

ssot <- csv("workforce_projections_consolidated.csv")

# ============================================================================
# A. SSOT table — structure, internal arithmetic identities, and drift pins
# ============================================================================
test_that("A1 SSOT has exactly the three surgical subspecialties, no dupes", {
  expect_equal(nrow(ssot), 3L)
  expect_setequal(ssot$subspecialty_abbrev, SUBS)
  expect_equal(anyDuplicated(ssot$subspecialty_abbrev), 0L)
})

test_that("A2 no NA in any numeric SSOT column consumed downstream", {
  num <- c("baseline_2025", "projected_2029", "sd_2029", "ci95_lower", "ci95_upper",
           "percent_change", "annual_retirement_rate", "avg_annual_retirements",
           "annual_entrants", "replacement_ratio", "fellowship_total_4yr",
           "total_retirements_4yr")
  for (col in num) expect_false(any(is.na(ssot[[col]])), info = col)
})

test_that("A3 replacement_ratio == annual_entrants / avg_annual_retirements", {
  expect_equal(ssot$replacement_ratio,
               ssot$annual_entrants / ssot$avg_annual_retirements,
               tolerance = 1e-4)
})

test_that("A4 projected_2029 == baseline + 4*(entrants - retirements)", {
  expect_equal(ssot$projected_2029,
               ssot$baseline_2025 + 4 * (ssot$annual_entrants - ssot$avg_annual_retirements),
               tolerance = 0.6)
})

test_that("A5 percent_change == 100*(projected - baseline)/baseline", {
  expect_equal(ssot$percent_change,
               100 * (ssot$projected_2029 - ssot$baseline_2025) / ssot$baseline_2025,
               tolerance = 0.1)
})

test_that("A6 fellowship_total_4yr == 4 * annual_entrants (horizon = 4)", {
  expect_equal(ssot$fellowship_total_4yr, 4L * ssot$annual_entrants)
})

test_that("A7 total_retirements_4yr == round(4 * avg_annual_retirements)", {
  expect_equal(ssot$total_retirements_4yr, round(4 * ssot$avg_annual_retirements))
})

test_that("A8 CI brackets the point estimate and SD is strictly positive", {
  expect_true(all(ssot$ci95_lower < ssot$projected_2029))
  expect_true(all(ssot$projected_2029 < ssot$ci95_upper))
  expect_true(all(ssot$sd_2029 > 0))
  expect_true(all(ssot$ci95_lower < ssot$ci95_upper))
})

test_that("A9 replacement_assessment agrees with the ratio thresholds (>1.05 Above)", {
  lab <- ifelse(ssot$replacement_ratio > 1.05, "Above replacement",
         ifelse(ssot$replacement_ratio >= 0.95, "At replacement", "Below replacement"))
  expect_equal(ssot$replacement_assessment, lab)
  # every subspecialty is above replacement in the frozen SSOT
  expect_true(all(ssot$replacement_assessment == "Above replacement"))
})

test_that("A10 DRIFT PIN: baselines and replacement ratios match the frozen headline", {
  for (ab in SUBS) {
    r <- row1(ssot, ab)
    expect_equal(r$baseline_2025, unname(PIN_BASELINE[[ab]]), info = ab)
    expect_equal(r$replacement_ratio, unname(PIN_RATIO[[ab]]), tolerance = 5e-3, info = ab)
  }
})

test_that("A11 the contract loader accepts the real SSOT", {
  source(file.path(.root, "manuscript", "R", "workforce_data_contract.R"))
  expect_silent(validate_workforce_data(ssot))
  expect_s3_class(load_workforce_data(), "data.frame")
})

# ============================================================================
# B. Contract validator — adversarial: it MUST reject degenerate / tampered tables
# ============================================================================
test_that("B validate_workforce_data rejects every tampered variant", {
  source(file.path(.root, "manuscript", "R", "workforce_data_contract.R"))
  expect_silent(validate_workforce_data(ssot))                      # baseline: clean passes

  # zero / placeholder baseline (the original "silent zeros" failure)
  d <- ssot; d$baseline_2025[1] <- 0
  expect_error(validate_workforce_data(d), "baseline_2025")

  # wrong subspecialty set (a 7-row access-paper scaffold)
  d <- rbind(ssot, transform(ssot[1, ], subspecialty_abbrev = "MFM"))
  expect_error(validate_workforce_data(d))

  # broken replacement ratio
  d <- ssot; d$replacement_ratio[2] <- d$replacement_ratio[2] * 2
  expect_error(validate_workforce_data(d), "replacement_ratio")

  # broken projection identity
  d <- ssot; d$projected_2029[1] <- d$projected_2029[1] + 100
  expect_error(validate_workforce_data(d), "projected_2029")

  # NA injected into a critical column
  d <- ssot; d$annual_entrants[1] <- NA
  expect_error(validate_workforce_data(d), "NA")

  # inverted CI
  d <- ssot; tmp <- d$ci95_lower[1]; d$ci95_lower[1] <- d$ci95_upper[1]; d$ci95_upper[1] <- tmp
  expect_error(validate_workforce_data(d), "ci95")

  # duplicate subspecialty
  d <- rbind(ssot, ssot[1, ])
  expect_error(validate_workforce_data(d))

  # illegal assessment label ("Unknown" placeholder)
  d <- ssot; d$replacement_assessment[1] <- "Unknown"
  expect_error(validate_workforce_data(d))

  # missing required column
  d <- ssot[, setdiff(names(ssot), "annual_entrants")]
  expect_error(validate_workforce_data(d), "missing required column")
})

# ============================================================================
# C. Manuscript getters — read the right cell, format correctly, keep the sign
# ============================================================================
HAVE_STATS <- tryCatch({
  suppressWarnings(suppressMessages(
    source(file.path(.root, "manuscript", "R", "workforce_statistics.R"))))
  TRUE
}, error = function(e) { message("stats source failed: ", conditionMessage(e)); FALSE })

test_that("C1 baseline/projected/ratio getters reproduce the SSOT cells", {
  skip_if_not(HAVE_STATS)
  for (ab in SUBS) {
    r <- row1(ssot, ab)
    expect_equal(get_baseline(ab), format(r$baseline_2025, big.mark = ","), info = ab)
    expect_equal(get_projected(ab), format(round(r$projected_2029), big.mark = ","), info = ab)
    expect_equal(get_replacement_ratio(ab), sprintf("%.1f", r$replacement_ratio), info = ab)  # display 1 decimal (reviewer #6)
    expect_equal(as.numeric(get_annual_entrants(ab)), r$annual_entrants, info = ab)
    expect_equal(get_avg_retirements(ab), sprintf("%.1f", r$avg_annual_retirements), info = ab)
  }
})

test_that("C2 percent-change getters carry the correct sign (BUG FIX #88 guard)", {
  skip_if_not(HAVE_STATS)
  for (ab in SUBS) {
    pct <- row1(ssot, ab)$percent_change
    expect_equal(get_percent_change(ab), sprintf("%+.1f", pct), info = ab)
    expect_equal(get_percent_change_magnitude(ab), sprintf("%.1f", abs(pct)), info = ab)
    # magnitude getter must never carry a sign
    expect_false(grepl("[+-]", get_percent_change_magnitude(ab)), info = ab)
    # signed getter must always carry a sign
    expect_true(grepl("^[+-]", get_percent_change(ab)), info = ab)
  }
})

test_that("C3 direction words are driven by the sign, never contradict it (BUG FIX #87)", {
  skip_if_not(HAVE_STATS)
  for (ab in SUBS) {
    pct <- row1(ssot, ab)$percent_change
    want_dir  <- if (pct >= 0) "growth"     else "decline"
    want_verb <- if (pct >= 0) "increasing" else "decreasing"
    want_noun <- if (pct >= 0) "increase"   else "decrease"
    expect_equal(get_direction(ab),   want_dir,  info = ab)
    expect_equal(get_change_verb(ab), want_verb, info = ab)
    expect_equal(get_change_noun(ab), want_noun, info = ab)
  }
})

test_that("C4 net-change getter equals round(projected) - baseline with sign", {
  skip_if_not(HAVE_STATS)
  for (ab in SUBS) {
    r <- row1(ssot, ab)
    expect_equal(get_net_change_4yr(ab),
                 sprintf("%+d", as.integer(round(r$projected_2029) - r$baseline_2025)), info = ab)
  }
})

test_that("C5 fellowship-total getters agree with each other and with 4*entrants", {
  skip_if_not(HAVE_STATS)
  for (ab in SUBS) {
    r <- row1(ssot, ab)
    expect_equal(get_fellowship_total(ab),     format(r$fellowship_total_4yr, big.mark = ","), info = ab)
    expect_equal(get_fellowship_total_4yr(ab), format(r$annual_entrants * 4L, big.mark = ","), info = ab)
    expect_equal(get_fellowship_total(ab), get_fellowship_total_4yr(ab), info = ab)
  }
})

test_that("C6 aggregate getters sum the SSOT correctly", {
  skip_if_not(HAVE_STATS)
  expect_equal(get_total_baseline(), format(sum(ssot$baseline_2025), big.mark = ","))
  expect_equal(get_total_projected(), format(round(sum(ssot$projected_2029)), big.mark = ","))
  expect_equal(get_total_annual_entrants(), format(sum(ssot$annual_entrants), big.mark = ","))
  expect_equal(count_by_assessment("Above replacement"), 3L)
  net <- sum(ssot$projected_2029) - sum(ssot$baseline_2025)
  expect_equal(get_total_net_change(), sprintf("%s%s", ifelse(net >= 0, "+", ""),
                                               format(round(net), big.mark = ",")))
})

test_that("C7 positions-for-buffer getter == ceil(1.2 * avg_annual_retirements)", {
  skip_if_not(HAVE_STATS)
  for (ab in SUBS) {
    r <- row1(ssot, ab)
    expect_equal(get_positions_for_adequate(ab), as.integer(ceiling(r$avg_annual_retirements * 1.2)), info = ab)
  }
  expect_equal(get_adequate_threshold(), "1.2")
})

test_that("C8 .filter_subspec resolves unambiguously and errors on no/loose match", {
  skip_if_not(HAVE_STATS)
  expect_equal(nrow(.filter_subspec("GO")), 1L)
  expect_equal(nrow(.filter_subspec("Urogynecology")), 1L)
  expect_error(.filter_subspec("NOPE_NOT_A_SUBSPEC"))
})

test_that("C9 no getter returns NA/empty for any of the three subspecialties", {
  skip_if_not(HAVE_STATS)
  getters <- c("get_baseline", "get_projected", "get_ci_lower", "get_ci_upper",
               "get_percent_change", "get_annual_rate", "get_replacement_ratio",
               "get_replacement_assessment", "get_fellowship_total", "get_avg_retirements",
               "get_sd", "get_net_change_4yr")
  for (g in getters) for (ab in SUBS) {
    v <- do.call(g, list(ab))
    expect_true(length(v) == 1 && !is.na(v) && nzchar(as.character(v)),
                info = sprintf("%s(%s)", g, ab))
  }
})

test_that("C10 tipping-point missed-fraction range is well-formed and shrinks with conversion", {
  skip_if_not(HAVE_STATS)
  r1 <- get_tipping_missed_range(1.0)
  expect_match(r1, "^[0-9]+% to [0-9]+%$")
  hi <- function(s) max(as.numeric(regmatches(s, gregexpr("[0-9]+", s))[[1]]))
  expect_gt(hi(get_tipping_missed_range(1.0)), hi(get_tipping_missed_range(0.7)))
})

# ============================================================================
# D. Cross-file reconciliation — every sensitivity's baseline row reproduces SSOT
# ============================================================================
test_that("D1 audit-table PRIMARY row reproduces the SSOT ratio and projection", {
  a <- csv("departure_audit_table.csv")
  p <- a[a$definition == "primary (non-OP anchored)", ]
  for (ab in c("GO", "URPS")) {
    ar <- p[p$subspecialty_abbrev == ab, ]
    sr <- row1(ssot, ab)
    expect_equal(ar$completion_to_departure_ratio, sr$replacement_ratio, tolerance = 5e-3, info = ab)
    expect_equal(ar$projected_2029, sr$projected_2029, tolerance = 0.1, info = ab)
  }
})

test_that("D2 audit-table OP-inclusive row has MORE departures and a LOWER ratio than primary", {
  a <- csv("departure_audit_table.csv")
  pr <- a[a$definition == "primary (non-OP anchored)", ]
  op <- a[a$definition == "OP-inclusive consensus", ]
  for (ab in c("GO", "URPS")) {
    expect_gt(op$eligible_departures[op$subspecialty_abbrev == ab],
              pr$eligible_departures[pr$subspecialty_abbrev == ab])
    expect_lt(op$completion_to_departure_ratio[op$subspecialty_abbrev == ab],
              pr$completion_to_departure_ratio[pr$subspecialty_abbrev == ab])
  }
})

test_that("D3 Open-Payments sensitivity: primary == SSOT; op_inclusive rate up, ratio down", {
  o <- csv("open_payments_sensitivity.csv")
  pr <- o[o$rule == "non_op_anchored (primary)", ]
  op <- o[o$rule == "op_inclusive", ]
  for (ab in c("GO", "URPS")) {
    expect_equal(pr$replacement_ratio[pr$subspecialty_abbrev == ab],
                 row1(ssot, ab)$replacement_ratio, tolerance = 5e-3, info = ab)
    expect_gt(op$departure_rate_pct[op$subspecialty_abbrev == ab],
              pr$departure_rate_pct[pr$subspecialty_abbrev == ab])
    expect_lt(op$replacement_ratio[op$subspecialty_abbrev == ab],
              pr$replacement_ratio[pr$subspecialty_abbrev == ab])
  }
})

test_that("D4 age-shift sensitivity: +0 reproduces SSOT; aging raises the departure rate", {
  s <- csv("age_shift_sensitivity.csv")
  for (ab in c("GO", "URPS")) {
    base <- s[s$subspecialty_abbrev == ab & s$age_shift_years == 0, ]
    expect_equal(base$replacement_ratio, row1(ssot, ab)$replacement_ratio, tolerance = 5e-3, info = ab)
    sh2 <- s[s$subspecialty_abbrev == ab & s$age_shift_years == 2, ]
    expect_gt(sh2$departure_rate_pct, base$departure_rate_pct)     # older -> more departures
    expect_lt(sh2$replacement_ratio,  base$replacement_ratio)      # -> lower ratio
  }
})

test_that("D5 entry-ramp projection: immediate == SSOT; ramped < immediate; deferred % arithmetic", {
  t <- csv("graduation_active_transition_projection.csv")
  for (ab in c("GO", "URPS")) {
    r  <- t[t$subspecialty_abbrev == ab, ]
    sr <- row1(ssot, ab)
    expect_equal(r$projected_2029_immediate, round(sr$projected_2029), tolerance = 1, info = ab)
    expect_lt(r$projected_2029_ramped, r$projected_2029_immediate)
    expect_equal(r$difference, r$projected_2029_immediate - r$projected_2029_ramped, info = ab)
    growth <- r$projected_2029_immediate - r$baseline
    expect_equal(r$pct_of_growth_deferred, round(100 * r$difference / growth), tolerance = 1, info = ab)
  }
})

# ============================================================================
# E. Pooled-vs-unpooled age-band hazard decomposition
# ============================================================================
test_that("E1 primary pooled events == GO + URPS (MIGS excluded) in every age band", {
  h <- csv("hazard_by_band_pooled_vs_unpooled.csv")
  expect_equal(h$pooled_events, h$go_events + h$urps_events)          # MIGS excluded from primary
  expect_equal(h$pooled_py,     h$go_py + h$urps_py)
  # the MIGS-inclusive sensitivity column DOES add MIGS back
  expect_equal(h$pooled_incl_migs_events, h$go_events + h$urps_events + h$migs_events)
})

test_that("E2 event totals: primary pool 71 (GO 36 + URPS 35); MIGS-inclusive sensitivity 81", {
  h <- csv("hazard_by_band_pooled_vs_unpooled.csv")
  expect_equal(sum(h$go_events),     36L)
  expect_equal(sum(h$urps_events),   35L)
  expect_equal(sum(h$migs_events),   10L)
  expect_equal(sum(h$pooled_events), 71L)              # GO+URPS only
  expect_equal(sum(h$pooled_incl_migs_events), 81L)    # + MIGS sensitivity
})

test_that("E3 per-band hazards equal events/person-years", {
  h <- csv("hazard_by_band_pooled_vs_unpooled.csv")
  nz <- h$pooled_py > 0
  expect_equal(h$pooled_hazard[nz], round(h$pooled_events[nz] / h$pooled_py[nz], 4), tolerance = 1e-4)
  g <- h$go_py > 0
  expect_equal(h$go_hazard_unpooled[g], round(h$go_events[g] / h$go_py[g], 4), tolerance = 1e-4)
})

test_that("E4 hazard rises with age (65-69 band exceeds the <45 band)", {
  h <- csv("hazard_by_band_pooled_vs_unpooled.csv")
  young <- h$pooled_hazard[h$band == "<45"]
  old   <- h$pooled_hazard[h$band == "65-69"]
  expect_gt(old, young)
})

test_that("E5 ORDERING FLIP: pooled GO>URPS but unpooled (age-specific) GO<URPS", {
  r <- csv("hazard_rate_pooled_vs_unpooled.csv")
  go <- r[r$subspecialty_abbrev == "GO", ]; ur <- r[r$subspecialty_abbrev == "URPS", ]
  expect_gt(go$rate_pooled_pct,   ur$rate_pooled_pct)     # pooled hazard + older GO ages
  expect_lt(go$rate_unpooled_pct, ur$rate_unpooled_pct)   # URPS hazard itself is higher
})

# ============================================================================
# F. Multidimensional sensitivity grid
# ============================================================================
test_that("F1 grid cell counts partition the total; worst <= one-way minimum", {
  g <- csv("sensitivity_grid_summary.csv")
  expect_equal(g$n_cells, g$n_above + g$n_at + g$n_below)
  expect_true(all(g$n_cells == 27))
  expect_true(all(g$worst_ratio <= g$oneway_min))          # worst is a multi-lever cell
})

test_that("F2 below-replacement cells exist iff worst_ratio < 0.95 (URPS only)", {
  g <- csv("sensitivity_grid_summary.csv")
  expect_equal(g$n_below > 0, g$worst_ratio < 0.95)
  expect_gt(g$n_below[g$subspecialty_abbrev == "URPS"], 0)
  expect_equal(g$n_below[g$subspecialty_abbrev == "GO"], 0)
  expect_equal(g$n_below[g$subspecialty_abbrev == "MIGS"], 0)  # MIGS never dips
})

# ============================================================================
# G. Break-even thresholds
# ============================================================================
test_that("G1 break-even replacement_ratio matches the SSOT ratio per subspecialty", {
  b <- csv("breakeven_thresholds.csv")
  for (ab in SUBS) {
    expect_equal(b$replacement_ratio[b$subspecialty_abbrev == ab],
                 row1(ssot, ab)$replacement_ratio, tolerance = 5e-3, info = ab)
  }
})

test_that("G2 graduate_drop_pct == round(100*(1 - 1/ratio)); break-even grads == round(avg retirements)", {
  b <- csv("breakeven_thresholds.csv")
  expect_equal(b$graduate_drop_pct, round(100 * (1 - 1 / b$replacement_ratio)), tolerance = 1)
  for (ab in SUBS) {
    expect_equal(b$breakeven_graduates[b$subspecialty_abbrev == ab],
                 round(row1(ssot, ab)$avg_annual_retirements), tolerance = 1, info = ab)
  }
})

test_that("G3 break-even rate multiple approximates the replacement ratio", {
  b <- csv("breakeven_thresholds.csv")
  expect_equal(b$breakeven_rate_multiple, b$replacement_ratio, tolerance = 0.15)
})

test_that("G4 compound_below_replacement flag == (compound worst-case ratio < 1)", {
  b <- csv("breakeven_thresholds.csv")
  expect_equal(as.logical(b$compound_below_replacement), b$compound_worstcase_ratio < 1)
})

# ============================================================================
# H. CONSORT cohort flow — subtraction chain + ABU two-pathway arithmetic
# ============================================================================
test_that("H1 active_baseline == certified_matched - deceased - inactive", {
  f <- csv("consort_cohort_flow.csv")
  expect_equal(f$active_baseline, f$certified_matched - f$removed_deceased - f$removed_inactive)
})

test_that("H2 ABU flow: 308 identified - 29 cert>2023 = 279 active; 1027 + 279 = 1306 final", {
  f <- csv("consort_cohort_flow.csv")
  u <- f[f$ab == "URPS", ]
  expect_equal(u$abu_identified - u$abu_excluded_nocert, u$abu_included)
  expect_equal(u$active_baseline + u$abu_included, u$active_baseline_final)
  expect_equal(u$active_baseline_final, 1306)
})

test_that("H3 non-URPS cohorts add no ABU physicians; final == baseline", {
  f <- csv("consort_cohort_flow.csv")
  for (ab in c("GO", "MIGS")) {
    r <- f[f$ab == ab, ]
    expect_equal(r$abu_identified, 0)
    expect_equal(r$abu_included, 0)
    expect_equal(r$active_baseline_final, r$active_baseline)
  }
})

test_that("H4 CONSORT final baselines equal the SSOT baselines", {
  f <- csv("consort_cohort_flow.csv")
  for (ab in SUBS) {
    expect_equal(f$active_baseline_final[f$ab == ab], unname(PIN_BASELINE[[ab]]), info = ab)
  }
})

# ============================================================================
# I. Departure-classifier corroboration + external confusion-matrix validation
# ============================================================================
test_that("I1 corroboration departure counts match the OP-inclusive detection layer (56/41)", {
  c <- csv("classifier_corroboration.csv")
  expect_equal(c$n_departures[c$subspecialty_abbrev == "GO"], 56L)
  expect_equal(c$n_departures[c$subspecialty_abbrev == "URPS"], 41L)
  # all corroboration percentages are valid proportions
  for (col in c("pct_nppes_deactivated", "pct_billing_ceased", "pct_abms_concordant", "ppv_proxy_corroborated"))
    expect_true(all(c[[col]] >= 0 & c[[col]] <= 100), info = col)
})

test_that("I2 external validation confusion matrix: TP+FN+FP+TN == n each row", {
  v <- csv("classifier_validation_external.csv")
  expect_equal(v$TP + v$FN + v$FP + v$TN, v$n)
})

test_that("I3 external validation ALL row == column sums of the per-subspecialty rows", {
  v <- csv("classifier_validation_external.csv")
  parts <- v[v$subspec %in% SUBS, ]
  all_row <- v[v$subspec == "ALL", ]
  for (col in c("n", "TP", "FN", "FP", "TN"))
    expect_equal(all_row[[col]], sum(parts[[col]]), info = col)
})

test_that("I4 external validation rates equal their confusion-matrix definitions", {
  v <- csv("classifier_validation_external.csv")
  # the CSV stores these rounded to 3 dp, so compare at that stored precision
  # (an absolute check; relative tolerance is meaningless for a ~0.02 PPV).
  expect_equal(v$sensitivity, round(v$TP / (v$TP + v$FN), 3))
  expect_equal(v$specificity, round(v$TN / (v$TN + v$FP), 3))
  expect_equal(v$ppv, round(v$TP / (v$TP + v$FP), 3))
  expect_equal(v$npv, round(v$TN / (v$TN + v$FN), 3))
  expect_equal(v$accuracy, round((v$TP + v$TN) / v$n, 3))
})

# ============================================================================
# J. Operative-workforce validity tables (Medicare-provisional, reported as validity)
# ============================================================================
test_that("J1 operative visibility % == medicare_visible_operators / n_active_cohort", {
  w <- csv("operative_workforce.csv")
  expect_equal(w$pct_of_active_visible, round(100 * w$medicare_visible_operators / w$n_active_cohort, 1),
               tolerance = 0.1)
})

test_that("J2 operative-cessation adjudication: continued + stopped == 100; corroboration is low", {
  a <- csv("operative_adjudication.csv")
  expect_equal(a$pct_total_billing_continued + a$pct_total_billing_stopped, rep(100, nrow(a)))
  # the key validity finding: most apparent cessations are NOT corroborated true exits
  expect_true(all(a$pct_corroborated_true_exit <= 20))
  expect_equal(a$pct_corroborated_true_exit, a$pct_total_billing_stopped)  # exit == billing stopped
})

test_that("J3 adjudicated cessation counts match capacity-table retiring operators", {
  a  <- csv("operative_adjudication.csv")
  cp <- csv("operative_capacity.csv")
  for (ab in c("GO", "URPS"))
    expect_equal(a$n_cessations[a$subspecialty_abbrev == ab],
                 cp$retiring_operators_in_window[cp$subspecialty_abbrev == ab], info = ab)
})

test_that("J4 time-to-operator CDF is monotone increasing (3yr < 5yr < 8yr)", {
  t <- csv("operative_tte.csv")
  expect_true(all(t$ci_operator_by3yr < t$ci_operator_by5yr))
  expect_true(all(t$ci_operator_by5yr < t$ci_operator_by8yr))
  expect_true(all(t$ci_operator_by8yr <= 1))
})

# ============================================================================
# K. General OB/GYN comparator + leave-one-source-out source contribution
# ============================================================================
test_that("K1 comparator rows are valid; departures never exceed the cohort size", {
  g <- csv("general_obgyn_comparator.csv")
  expect_true(all(g$departures <= g$n))
  expect_true(all(g$annual_departure_rate_pct > 0))
  expect_true(all(g$pct_departures_before_50 >= 0 & g$pct_departures_before_50 <= 100))
  expect_true("General OB/GYN" %in% g$cohort)
})

test_that("K2 leave-one-source-out: Open Payments (priority 3) is the dominant sole-support", {
  l <- csv("loso_source_contribution.csv")
  op <- l[grepl("Open Payments", l$source), ]
  expect_equal(nrow(op), 1L)
  # OP removal loses the most departures -> it dominates detection (the paper's finding)
  expect_equal(op$sole_support_lost_if_removed, max(l$sole_support_lost_if_removed))
  expect_true(all(l$pct_of_departures >= 0 & l$pct_of_departures <= 100))
  expect_true(all(l$sole_support_lost_if_removed <= l$n_departures_supported))
})

# ============================================================================
# L. Dynamic stock-flow projection — internal recurrence invariants
# ============================================================================
test_that("L1 dynamic projection starts at the stated cohort baseline in 2025", {
  d <- csv("dynamic_projection_by_year.csv")
  start <- c(URPS = 1031, GO = 1052, MIGS = 605)  # ABOG-only URPS baseline for this exploratory surface
  for (ab in SUBS) {
    v <- d$active[d$subspecialty_abbrev == ab & d$year == 2025]
    expect_equal(v, unname(start[[ab]]), info = ab)
  }
})

test_that("L2 stock recurrence holds: active[t] == active[t-1] + entrants[t] - departures[t]", {
  d <- csv("dynamic_projection_by_year.csv")
  for (ab in SUBS) {
    s <- d[d$subspecialty_abbrev == ab, ]
    s <- s[order(s$year), ]
    for (i in 2:nrow(s))
      expect_equal(s$active[i], s$active[i-1] + s$entrants[i] - s$departures[i],
                   tolerance = 1e-6, info = sprintf("%s %d", ab, s$year[i]))
    # entrants (inflow) exceed departures each transition -> stock grows
    expect_true(all(diff(s$active) > 0), info = ab)
  }
})

test_that("L3 dynamic Monte Carlo intervals bracket the median", {
  iv <- csv("dynamic_projection_intervals.csv")
  expect_true(all(iv$mc_lo95 < iv$mc_median))
  expect_true(all(iv$mc_median < iv$mc_hi95))
})

# ============================================================================
# M. NRMP-filled benchmark
# ============================================================================
test_that("M1 NRMP benchmark ratio == nrmp_entrants / SSOT avg retirements; all above replacement", {
  b <- csv("workforce_projection_benchmark_nrmp.csv")
  for (ab in SUBS) {
    r  <- b[b$subspecialty_abbrev == ab, ]
    sr <- row1(ssot, ab)
    expect_equal(r$replacement_ratio_nrmp, r$nrmp_entrants / sr$avg_annual_retirements,
                 tolerance = 0.05, info = ab)
    expect_equal(r$assessment_nrmp, "Above replacement", info = ab)
  }
})
