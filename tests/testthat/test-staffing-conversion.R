# tests/testthat/test-staffing-conversion.R
# Guards for demand_lifecourse/supply-staffing_conversion.R (services -> required FTE,
# work-RVU method ported from the simulation package's R/17/R/23).

library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

source(here::here("demand_lifecourse/supply-staffing_conversion.R"))

test_that("the cited workload basket loads with CMS-anchored work RVUs", {
  wl <- load_urps_workload_rvu()
  expect_true(all(c("service", "work_rvu", "status", "source") %in% names(wl)))
  expect_true(all(wl$work_rvu >= 0))
  # spot-check two anchors against the CMS RVU25A values ported from simulation
  expect_equal(wl$work_rvu[wl$service == "sling_procedure"], 12.2864, tolerance = 1e-4)
  expect_equal(wl$work_rvu[wl$service == "cystoscopy"], 1.53, tolerance = 1e-4)
})

test_that("service_volume_to_wrvu sums volume * work_rvu, and rejects unknown services", {
  v <- tibble::tibble(service = c("new_consultation", "sling_procedure"),
                      volume = c(1000, 100))
  rv <- service_volume_to_wrvu(v)
  expect_equal(rv$work_rvu, 1000 * 2.5350 + 100 * 12.2864, tolerance = 1e-6)
  expect_error(service_volume_to_wrvu(
    tibble::tibble(service = "not_a_service", volume = 1)))
})

test_that("service_volume_to_wrvu preserves a year grouping", {
  v <- tibble::tibble(year = c(2025, 2025, 2030),
                      service = c("cystoscopy", "pessary_care", "cystoscopy"),
                      volume = c(10, 10, 20))
  rv <- service_volume_to_wrvu(v)
  expect_setequal(rv$year, c(2025, 2030))
  expect_equal(rv$work_rvu[rv$year == 2030], 20 * 1.53, tolerance = 1e-6)
})

test_that("calibrate_wrvu_per_fte inverts the base-year identity (Dall 2013)", {
  # base_wrvu / base_fte / (1 - indirect)
  w <- calibrate_wrvu_per_fte(base_year_wrvu = 5.0e6, base_year_required_fte = 1339,
                              indirect_share = 0.10)
  expect_equal(w, (5.0e6 / 1339) / 0.90, tolerance = 1e-6)
  # round-trip: converting the base-year volume back must reproduce the anchor FTE
  vol <- tibble::tibble(service = "sling_procedure", volume = 5.0e6 / 12.2864)  # -> 5.0e6 wRVU
  fte <- convert_workload_to_fte(vol, wrvu_per_fte = w, indirect_share = 0.10)
  expect_equal(fte$required_fte, 1339, tolerance = 1e-6)
})

test_that("required FTE rises with volume and with the indirect-time gross-up", {
  v1 <- tibble::tibble(service = "sling_procedure", volume = 1000)
  v2 <- tibble::tibble(service = "sling_procedure", volume = 2000)
  w <- 5000
  f1 <- convert_workload_to_fte(v1, wrvu_per_fte = w, indirect_share = 0)$required_fte
  f2 <- convert_workload_to_fte(v2, wrvu_per_fte = w, indirect_share = 0)$required_fte
  expect_equal(f2, 2 * f1, tolerance = 1e-6)
  f_ind <- convert_workload_to_fte(v1, wrvu_per_fte = w, indirect_share = 0.271)$required_fte
  expect_gt(f_ind, f1)                              # gross-up increases required FTE
})

test_that("productivity plausibility check brackets the benchmark", {
  expect_true(check_productivity_plausible(7500))
  expect_false(check_productivity_plausible(500))
  expect_false(check_productivity_plausible(50000))
})
