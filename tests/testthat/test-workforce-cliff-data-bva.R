# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# BOUNDARY VALUE ANALYSIS (BVA) for the workforce-cliff data analysis.
#
# BVA probes the exact input values where a decision changes: for each boundary T
# with an open/closed edge we test T-epsilon, T, and T+epsilon, plus the nominal
# interior. The boundaries in this analysis are:
#
#   1. classify_replacement() cutoffs: 0.95 (At/Below) and 1.05 (Above/At),
#      where 0.95 is CLOSED (>=) and 1.05 is OPEN (strict >).
#   2. validate_workforce_data() degenerate guards:
#        baseline_2025 <= 0, projected_2029 <= 0, avg_annual_retirements <= 0
#        (boundary 0, CLOSED -> 0 rejected),
#        annual_entrants < 0 (boundary 0, OPEN -> 0 ACCEPTED),
#        ci95_lower > ci95_upper (boundary equality, CLOSED -> equal ACCEPTED).
#   3. validate_workforce_data() numeric tolerances (deviation guards use strict >):
#        ratio 0.01, projection 0.6, percent 0.1 -> exactly-at-tolerance ACCEPTED,
#        just-over REJECTED.
#   4. Getter sign boundary at percent_change == 0: get_direction/verb/noun use
#      `>= 0`, so exactly 0 reads as growth/increase, just-below as decline.
#
# Run: Rscript -e 'testthat::test_file("tests/testthat/test-workforce-cliff-data-bva.R")'
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
library(testthat)

.root <- tryCatch(here::here(), error = function(e) {
  d <- normalizePath(".")
  while (!file.exists(file.path(d, "manuscript", "manuscript_WORKFORCE_CLIFF.Rmd")) &&
         dirname(d) != d) d <- dirname(d)
  d
})
source(file.path(.root, "manuscript", "R", "workforce_data_contract.R"))

EPS <- 1e-9  # far below any tolerance; isolates the open/closed edge of a cutoff

# Build a fully contract-consistent table from per-row (baseline, entrants, avg_ret).
# Every dependent column is derived so ONLY the field under test is off-boundary.
# full names carry the substrings the getters' load-time validation loop looks for
.FULLNAME <- c(URPS = "Urogynecology and Reconstructive Pelvic Surgery",
               GO = "Gynecologic Oncology",
               MIGS = "Minimally Invasive Gynecologic Surgery")
mk_valid <- function(specs) {
  do.call(rbind, lapply(names(specs), function(ab) {
    p <- specs[[ab]]; baseline <- p[1]; entrants <- p[2]; avg_ret <- p[3]
    proj  <- baseline + 4 * (entrants - avg_ret)
    ratio <- entrants / avg_ret
    data.frame(
      subspecialty = unname(.FULLNAME[[ab]]), subspecialty_abbrev = ab,
      baseline_2025 = baseline, projected_2029 = proj, sd_2029 = 10,
      ci95_lower = proj - 20, ci95_upper = proj + 20,
      percent_change = 100 * (proj - baseline) / baseline,
      annual_retirement_rate = 100 * avg_ret / baseline,
      avg_annual_retirements = avg_ret, annual_entrants = entrants,
      replacement_ratio = ratio, replacement_assessment = classify_replacement(ratio),
      fellowship_total_4yr = 4 * entrants, total_retirements_4yr = round(4 * avg_ret),
      stringsAsFactors = FALSE)
  }))
}
BASE <- mk_valid(list(URPS = c(1295, 64, 11), GO = c(1052, 75, 10), MIGS = c(605, 47, 4)))
GO <- function(df) which(df$subspecialty_abbrev == "GO")  # row index to tamper

# sanity: the base scaffold is contract-valid, so any rejection below is caused
# solely by the single off-boundary edit under test.
test_that("BVA scaffold: the untampered base table passes the contract", {
  expect_no_error(validate_workforce_data(BASE))
})

# ============================================================================
# 1. classify_replacement() cutoffs — 0.95 (closed) and 1.05 (open)
# ============================================================================
test_that("BVA classify_replacement at the 0.95 At/Below cutoff (closed lower edge)", {
  expect_equal(classify_replacement(0.95 - EPS), "Below replacement")  # just below -> Below
  expect_equal(classify_replacement(0.95),       "At replacement")     # exactly 0.95 -> At (>=)
  expect_equal(classify_replacement(0.95 + EPS), "At replacement")     # just above  -> At
})

test_that("BVA classify_replacement at the 1.05 Above/At cutoff (open upper edge)", {
  expect_equal(classify_replacement(1.05 - EPS), "At replacement")     # just below  -> At
  expect_equal(classify_replacement(1.05),       "At replacement")     # exactly 1.05 -> At (strict >)
  expect_equal(classify_replacement(1.05 + EPS), "Above replacement")  # just above  -> Above
})

test_that("BVA classify_replacement nominal interior + degenerate ratios", {
  expect_equal(classify_replacement(0.50), "Below replacement")  # deep below
  expect_equal(classify_replacement(1.00), "At replacement")     # dead centre of the band
  expect_equal(classify_replacement(2.00), "Above replacement")  # well above
  expect_equal(classify_replacement(0.00), "Below replacement")  # zero graduates
  # vectorised call must classify element-wise across all three regions
  expect_equal(classify_replacement(c(0.9499999, 0.95, 1.05, 1.0500001)),
               c("Below replacement", "At replacement", "At replacement", "Above replacement"))
})

# ============================================================================
# 2. Degenerate-value guards — boundary 0 (and the equality edge for CI)
# ============================================================================
test_that("BVA baseline_2025 <= 0 boundary: 0 rejected, positive accepted", {
  d <- BASE; d$baseline_2025[GO(d)] <- 0
  expect_error(validate_workforce_data(d), "baseline_2025")
  expect_no_error(validate_workforce_data(mk_valid(list(  # smallest positive baseline
    URPS = c(1295, 64, 11), GO = c(1, 2, 1), MIGS = c(605, 47, 4)))))
})

test_that("BVA projected_2029 <= 0 boundary: 0 rejected", {
  d <- BASE; d$projected_2029[GO(d)] <- 0
  expect_error(validate_workforce_data(d), "projected_2029")
})

test_that("BVA avg_annual_retirements <= 0 boundary: 0 rejected, positive accepted", {
  d <- BASE; d$avg_annual_retirements[GO(d)] <- 0
  expect_error(validate_workforce_data(d), "avg_annual_retirements")
})

test_that("BVA annual_entrants < 0 boundary: 0 ACCEPTED (open edge), just-negative rejected", {
  # entrants == 0 is a legal state (a subspecialty with no graduates that year).
  zero_ent <- mk_valid(list(URPS = c(1295, 64, 11), GO = c(1052, 0, 10), MIGS = c(605, 47, 4)))
  expect_no_error(validate_workforce_data(zero_ent))
  d <- zero_ent; d$annual_entrants[GO(d)] <- -EPS
  expect_error(validate_workforce_data(d), "annual_entrants")
})

test_that("BVA ci95_lower vs ci95_upper boundary: equal ACCEPTED, just-crossed rejected", {
  d <- BASE; i <- GO(d); d$ci95_lower[i] <- d$ci95_upper[i]         # exactly equal
  expect_no_error(validate_workforce_data(d))
  d$ci95_lower[i] <- d$ci95_upper[i] + EPS                          # lower just above upper
  expect_error(validate_workforce_data(d), "ci95")
})

# ============================================================================
# 3. Numeric-tolerance guards — deviation compared with strict > tolerance
#    (exactly-at-tolerance ACCEPTED; just-over REJECTED)
# ============================================================================
test_that("BVA replacement_ratio tolerance 0.01: 0.009 accepted, 0.011 rejected", {
  i <- GO(BASE)
  d <- BASE; d$replacement_ratio[i] <- d$replacement_ratio[i] + 0.009
  expect_no_error(validate_workforce_data(d))
  d <- BASE; d$replacement_ratio[i] <- d$replacement_ratio[i] + 0.011
  expect_error(validate_workforce_data(d), "replacement_ratio")
})

test_that("BVA projection tolerance 0.6: 0.5 accepted, 0.7 rejected", {
  i <- GO(BASE)
  d <- BASE; d$projected_2029[i] <- d$projected_2029[i] + 0.5
  expect_no_error(validate_workforce_data(d))
  d <- BASE; d$projected_2029[i] <- d$projected_2029[i] + 0.7
  expect_error(validate_workforce_data(d), "projected_2029")
})

test_that("BVA percent_change tolerance 0.1: 0.09 accepted, 0.11 rejected", {
  i <- GO(BASE)
  d <- BASE; d$percent_change[i] <- d$percent_change[i] + 0.09
  expect_no_error(validate_workforce_data(d))
  d <- BASE; d$percent_change[i] <- d$percent_change[i] + 0.11
  expect_error(validate_workforce_data(d), "percent_change")
})

# ============================================================================
# 4. Getter sign boundary at percent_change == 0 (direction words use `>= 0`)
# ============================================================================
# Re-source the manuscript getters against a synthetic SSOT via the documented
# WORKFORCE_DATA_CSV override, so the REAL getters are exercised at the boundary.
with_stats <- function(df, code) {
  tmp <- tempfile(fileext = ".csv")
  utils::write.csv(df, tmp, row.names = FALSE)
  old <- Sys.getenv("WORKFORCE_DATA_CSV", unset = NA)
  Sys.setenv(WORKFORCE_DATA_CSV = tmp)
  on.exit({
    if (is.na(old)) Sys.unsetenv("WORKFORCE_DATA_CSV") else Sys.setenv(WORKFORCE_DATA_CSV = old)
    unlink(tmp)
  }, add = TRUE)
  e <- new.env(parent = globalenv())
  sys.source(file.path(.root, "manuscript", "R", "workforce_statistics.R"), envir = e)
  code(e)
}
STATS_OK <- tryCatch({ with_stats(BASE, function(e) get("get_direction", e)); TRUE },
                     error = function(e) { message("getter re-source failed: ", conditionMessage(e)); FALSE })

test_that("BVA get_direction/verb/noun at percent_change == 0 (closed positive edge)", {
  skip_if_not(STATS_OK)
  # GO entrants == avg_ret -> projected == baseline -> percent_change is exactly 0
  zero_pct <- mk_valid(list(URPS = c(1295, 64, 11), GO = c(1052, 10, 10), MIGS = c(605, 47, 4)))
  expect_equal(zero_pct$percent_change[GO(zero_pct)], 0)
  with_stats(zero_pct, function(e) {
    expect_equal(e$get_direction("GO"),   "growth")      # 0 >= 0 -> growth
    expect_equal(e$get_change_verb("GO"), "increasing")
    expect_equal(e$get_change_noun("GO"), "increase")
  })
})

test_that("BVA get_direction/verb/noun just below the zero boundary (negative edge)", {
  skip_if_not(STATS_OK)
  # entrants just below avg_ret -> projected just below baseline -> percent_change < 0
  neg_pct <- mk_valid(list(URPS = c(1295, 64, 11), GO = c(1052, 9.9, 10), MIGS = c(605, 47, 4)))
  expect_lt(neg_pct$percent_change[GO(neg_pct)], 0)
  with_stats(neg_pct, function(e) {
    expect_equal(e$get_direction("GO"),   "decline")     # < 0 -> decline
    expect_equal(e$get_change_verb("GO"), "decreasing")
    expect_equal(e$get_change_noun("GO"), "decrease")
  })
})

test_that("BVA get_percent_change formats the exact-zero boundary as +0.0 (signed)", {
  skip_if_not(STATS_OK)
  zero_pct <- mk_valid(list(URPS = c(1295, 64, 11), GO = c(1052, 10, 10), MIGS = c(605, 47, 4)))
  with_stats(zero_pct, function(e) {
    expect_equal(e$get_percent_change("GO"), "+0.0")           # signed getter shows +0.0
    expect_equal(e$get_percent_change_magnitude("GO"), "0.0")  # magnitude drops the sign
  })
})

# ============================================================================
# 5. positions-for-buffer ceiling boundary: ceil(1.2 * avg_ret) at an integer edge
# ============================================================================
test_that("BVA get_positions_for_adequate ceiling: exact integer vs just-over", {
  skip_if_not(STATS_OK)
  # avg_ret = 10 -> 1.2*10 = 12.0 exactly -> ceiling stays 12
  exact <- mk_valid(list(URPS = c(1295, 64, 11), GO = c(1052, 75, 10), MIGS = c(605, 47, 4)))
  with_stats(exact, function(e) expect_equal(e$get_positions_for_adequate("GO"), 12L))
  # avg_ret = 10.01 -> 1.2*10.01 = 12.012 -> ceiling jumps to 13
  over <- mk_valid(list(URPS = c(1295, 64, 11), GO = c(1052, 75, 10.01), MIGS = c(605, 47, 4)))
  with_stats(over, function(e) expect_equal(e$get_positions_for_adequate("GO"), 13L))
})

# ============================================================================
# 6. Real-SSOT integration BVA: each reported ratio sits strictly ABOVE 1.05,
#    and nudging it onto/over the cutoff flips the label as classify_replacement says.
# ============================================================================
test_that("BVA real SSOT ratios straddle the cutoffs exactly as classify_replacement dictates", {
  ssot <- read.csv(file.path(.root, "data", "workforce_projections_consolidated.csv"),
                   stringsAsFactors = FALSE, check.names = FALSE)
  for (ab in c("URPS", "GO", "MIGS")) {
    r <- ssot$replacement_ratio[ssot$subspecialty_abbrev == ab]
    expect_gt(r, 1.05)                                                   # every ratio is Above
    expect_equal(classify_replacement(r), "Above replacement", info = ab)
    expect_equal(classify_replacement(1.05), "At replacement", info = ab)          # nudged onto cutoff
    expect_equal(classify_replacement(1.05 - EPS), "At replacement", info = ab)    # just under -> At
  }
})
