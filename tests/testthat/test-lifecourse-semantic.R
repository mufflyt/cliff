# tests/testthat/test-lifecourse-semantic.R
# SEMANTIC tests: assert the model's outputs obey the scientific relationships
# they claim -- not just that the code runs. If any of these flip, the model is
# saying something clinically/epidemiologically wrong even if every unit test
# passes.

library(testthat)
library(here)

source(here::here("R/workforce_concentration_metrics.R"))
source(here::here("demand_lifecourse/02_birth_history.R"))
source(here::here("demand_lifecourse/07_staffing_conversion.R"))
source(here::here("demand_lifecourse/09_validation.R"))

# ---- Exposure: the model's central obstetric claims --------------------------

test_that("vaginal + cesarean deliveries reconstruct total parity for every cohort", {
  ex <- cohort_vaginal_exposure(1930:1990)
  expect_equal(ex$mean_vaginal_deliveries + ex$mean_cesarean_deliveries,
               ex$mean_total_parity, tolerance = 1e-6)
})

test_that("later cohorts carry strictly less vaginal-delivery exposure (the thesis)", {
  ex <- cohort_vaginal_exposure(c(1935, 1950, 1965, 1975, 1985))
  expect_true(all(diff(ex$mean_vaginal_deliveries) < 0))   # falls monotonically
  expect_true(all(diff(ex$cohort_cesarean_fraction) > 0))  # cesarean rises
  # magnitude sanity: ~2.9 (1935) down to ~1.3 (1985)
  expect_gt(ex$mean_vaginal_deliveries[ex$birth_cohort == 1935], 2.5)
  expect_lt(ex$mean_vaginal_deliveries[ex$birth_cohort == 1985], 1.6)
})

test_that("cesarean rate rose over the modern era with the 1996 trough below the 2009 peak", {
  r <- cesarean_rate_for_year(c(1970, 1996, 2009))
  expect_true(all(r > 0 & r < 1))
  expect_lt(r[1], r[3])          # 1970 well below 2009
  expect_lt(r[2], r[3])          # 1996 trough below 2009 peak
})

test_that("completed parity fell from the mid-century to the 1970s cohorts", {
  p <- completed_parity_for_cohort(c(1935, 1975))
  expect_gt(p[1], p[2])
})

# ---- Staffing conversion: work-RVU semantics --------------------------------

test_that("required FTE is linear in service volume", {
  v1 <- tibble::tibble(service = "sling_procedure", volume = 1000)
  v2 <- tibble::tibble(service = "sling_procedure", volume = 2000)
  f1 <- convert_workload_to_fte(v1, wrvu_per_fte = 5000)$required_fte
  f2 <- convert_workload_to_fte(v2, wrvu_per_fte = 5000)$required_fte
  expect_equal(f2, 2 * f1, tolerance = 1e-9)
})

test_that("a high-RVU procedure generates proportionally more FTE than a low-RVU visit", {
  wl <- load_urps_workload_rvu()
  sling  <- wl$work_rvu[wl$service == "sling_procedure"]
  ret    <- wl$work_rvu[wl$service == "return_visit"]
  fs <- convert_workload_to_fte(tibble::tibble(service = "sling_procedure", volume = 100),
                                wrvu_per_fte = 5000)$required_fte
  fr <- convert_workload_to_fte(tibble::tibble(service = "return_visit", volume = 100),
                                wrvu_per_fte = 5000)$required_fte
  expect_equal(fs / fr, sling / ret, tolerance = 1e-6)   # ratio tracks the RVU ratio (~8.8x)
})

test_that("calibrate -> convert round-trips the base-year anchor, and productivity scales inversely with the anchor FTE", {
  vol <- tibble::tibble(service = "sling_procedure",
                        volume = 5.0e6 / load_urps_workload_rvu()$work_rvu[
                          load_urps_workload_rvu()$service == "sling_procedure"])  # 5.0e6 wRVU
  w1 <- calibrate_wrvu_per_fte(5.0e6, 1339, indirect_share = 0.10)
  expect_equal(convert_workload_to_fte(vol, w1, indirect_share = 0.10)$required_fte,
               1339, tolerance = 1e-6)
  # halving the base-year required FTE doubles the solved productivity denominator
  w2 <- calibrate_wrvu_per_fte(5.0e6, 1339 / 2, indirect_share = 0.10)
  expect_equal(w2, 2 * w1, tolerance = 1e-9)
})

# ---- Concentration: distributional ordering ---------------------------------

test_that("Gini and HHI both increase monotonically as providers concentrate", {
  even <- c(10, 10, 10, 10); mild <- c(20, 10, 8, 2); heavy <- c(38, 1, 0, 1)
  expect_lt(gini(even), gini(mild)); expect_lt(gini(mild), gini(heavy))
  expect_lt(herfindahl_index(even), herfindahl_index(mild))
  expect_lt(herfindahl_index(mild), herfindahl_index(heavy))
})

test_that("Lorenz curve is bounded by the endpoints and top-k share is non-decreasing in k", {
  lc <- lorenz_curve(c(1, 2, 3, 40))
  expect_equal(lc$cum_value_share[1], 0); expect_equal(tail(lc$cum_value_share, 1), 1)
  counts <- c(50, 30, 15, 5, 5, 5)
  expect_lte(top_k_share(counts, 1), top_k_share(counts, 3))
  expect_lte(top_k_share(counts, 3), top_k_share(counts, 10))
})

# ---- Validation harness: scoring semantics ----------------------------------

test_that("a prediction equal to the target scores ratio 1 and agrees; a far-off one disagrees", {
  hit  <- validate_against_targets(tibble::tibble(metric = "prevalence_any_pfd",
                                                  predicted_value = 0.237))
  miss <- validate_against_targets(tibble::tibble(metric = "prevalence_any_pfd",
                                                  predicted_value = 0.05))
  expect_equal(hit$ratio, 1, tolerance = 1e-6); expect_true(hit$agrees)
  expect_false(miss$agrees)
})

# ---- Within-woman cesarean correlation --------------------------------------

test_that("mean cesarean count increases monotonically with the repeat-cesarean rate", {
  set.seed(3)
  m <- sapply(c(0.22, 0.5, 0.86), function(rr)
    mean(cesarean_births_correlated(rep(3L, 20000), primary_rate = 0.22, repeat_rate = rr)))
  expect_true(all(diff(m) > 0))
})
