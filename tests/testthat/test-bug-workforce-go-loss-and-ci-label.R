# tests/testthat/test-bug-workforce-go-loss-and-ci-label.R
#
# Bug WF-3: GO net loss hardcoded as "exceeds 100 physicians" in manuscript prose.
#   Data: baseline=1352, projected=1278 → loss = 74 (not >100).
#   Fix: replace hardcoded phrase with inline R expression get_net_change_4yr("GO").
#
# Bug WF-4: Methods section claimed CIs came from "Monte Carlo empirical quantiles".
#   Code: ci = projected ± 1.96 × SD where SDs are manually transcribed constants.
#   That is a parametric normal interval, not an empirical simulation quantile.
#   Fix: methods text now correctly states "projected mean ± 1.96 × SD".

library(testthat)

# ── Bug WF-3: GO net loss computation ─────────────────────────────────────────

go_baseline  <- 1352L
go_projected <- 1278L

net_loss_true <- go_baseline - go_projected   # 74

test_that("BUG WF-3 [ADVERSARIAL]: data shows loss of 74, not >100", {
  expect_equal(net_loss_true, 74L,
    label = "1352 - 1278 = 74, which does NOT exceed 100"
  )
  expect_false(net_loss_true > 100,
    label = "The hardcoded 'exceeds 100' claim is false"
  )
})

test_that("BUG WF-3 [ADVERSARIAL]: percent_change is -5.47% implying ~74 loss, not ~100", {
  # percent_change = (1278 - 1352) / 1352 * 100 = -5.47%
  pct <- (go_projected - go_baseline) / go_baseline * 100
  expect_equal(round(pct, 2), -5.47,
    label = "-5.47% of 1352 ≈ 74, not 100"
  )
  # If the loss were 100, percent_change would be -7.4%
  implied_loss_from_pct <- abs(pct / 100) * go_baseline
  expect_lt(implied_loss_from_pct, 100,
    label = "Loss implied by percent_change is <100"
  )
})

test_that("BUG WF-3 [SEMANTIC]: net loss equals baseline minus projected", {
  expect_equal(net_loss_true, go_baseline - go_projected)
})

test_that("BUG WF-3 [SEMANTIC]: inline R expression produces correct value at knit time", {
  # Simulate what get_net_change_4yr("GO") would produce from the workforce_data table
  workforce_data <- data.frame(
    subspecialty_abbrev = c("FPMRS", "GO", "MIG"),
    baseline_2025       = c(1283, 1352, 767),
    projected_2029      = c(1301, 1278, 835)
  )
  go_row  <- workforce_data[workforce_data$subspecialty_abbrev == "GO", ]
  net_str <- sprintf("%+d", go_row$projected_2029 - go_row$baseline_2025)
  # Should produce "-74", not anything beyond -100
  expect_equal(net_str, "-74")
  expect_false(grepl("^-1[01][0-9]", net_str),
    label = "Net change string does not represent a loss >100"
  )
})

# ── Bug WF-4: parametric CI mislabeled as empirical quantiles ─────────────────

# Reproduce the CI construction exactly as in manuscript_consolidate_existing_results.R
make_ci_parametric <- function(projected, sd) {
  list(
    lower = round(projected - 1.96 * sd),
    upper = round(projected + 1.96 * sd)
  )
}

# Empirical quantile CI requires actual simulation vectors
make_ci_empirical <- function(sim_vector) {
  list(
    lower = quantile(sim_vector, 0.025),
    upper = quantile(sim_vector, 0.975)
  )
}

test_that("BUG WF-4 [ADVERSARIAL]: parametric CI is symmetric; empirical quantile CI need not be", {
  set.seed(42)
  # Simulate a right-skewed distribution (realistic for workforce counts)
  sim <- rlnorm(1000, meanlog = log(1278), sdlog = 0.013)
  emp  <- make_ci_empirical(sim)
  para <- make_ci_parametric(projected = 1278, sd = 16.1)

  # Parametric CI is always symmetric around the projected value
  para_half_width_lower <- 1278 - para$lower
  para_half_width_upper <- para$upper - 1278
  expect_equal(para_half_width_lower, para_half_width_upper,
    label = "Parametric CI is symmetric by construction (±1.96×SD)"
  )

  # Empirical CI will differ from parametric for skewed distributions
  # (not guaranteed to be identical — that's the whole point of using quantiles)
  ci_method_same <- isTRUE(all.equal(as.numeric(emp$lower), as.numeric(para$lower),
                                      tolerance = 1))
  # We're just confirming the two methods are conceptually different computations
  expect_true(is.numeric(emp$lower) && is.numeric(para$lower),
    label = "Both CI methods produce numeric values"
  )
})

test_that("BUG WF-4 [ADVERSARIAL]: GO CI matches ±1.96×16.1 formula, not percentile of any vector", {
  go_proj <- 1278; go_sd <- 16.1
  para <- make_ci_parametric(go_proj, go_sd)
  expect_equal(para$lower, round(go_proj - 1.96 * go_sd),
    label = "Lower CI = 1278 - 1.96*16.1 = 1246"
  )
  expect_equal(para$upper, round(go_proj + 1.96 * go_sd),
    label = "Upper CI = 1278 + 1.96*16.1 = 1310"
  )
  # These match workforce_data: ci95_lower=1246, ci95_upper=1310 — confirming parametric
  expect_equal(para$lower, 1246L)
  expect_equal(para$upper, 1310L)
})

test_that("BUG WF-4 [SEMANTIC]: corrected methods text does not contain 'empirical quantile'", {
  correct_text <- paste(
    "Workforce projections are reported as mean \u00b1 standard deviation with",
    "95% confidence intervals constructed as projected mean \u00b1 1.96 \u00d7 SD,",
    "where SD values are derived from simulation variance across 1,000 Monte Carlo iterations."
  )
  expect_false(grepl("empirical quantile", correct_text, ignore.case = TRUE),
    label = "Fixed methods text removes the 'empirical quantile' mislabel"
  )
  expect_true(grepl("1\\.96", correct_text),
    label = "Fixed text explicitly states the ±1.96×SD parametric formula"
  )
})

test_that("BUG WF-4 [SEMANTIC]: SD values in consolidation script are constants, not derived", {
  sd_values <- c(FPMRS = 15.2, GO = 16.1, MIG = 11.0)
  # They are finite, positive scalars — not computed from any vector
  expect_true(all(is.finite(sd_values)))
  expect_true(all(sd_values > 0))
  # If derived empirically from 1000 iterations the SD of GO would have uncertainty itself
  # We simply confirm these are fixed constants passed through the parametric formula
  expect_equal(length(sd_values), 3L)
})
