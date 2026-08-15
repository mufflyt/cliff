# SSOT guard: the FPMRS supply-line figure (scripts/fig_fpmrs_supply_line.R) previously hardcoded
# the projection year axis (2025:2029, /4, length.out=5, year==2029, the breaks list, the title/label
# year ranges). The endpoint 2029 is not a free number: it is PROJ_YEAR0 (2025) + the study horizon
# (R/workforce_constants.R::WORKFORCE_PROJECTION_HORIZON_YEARS). Every plotted year now derives from it,
# matching the sibling scenario_projection_trajectories.R so the two figures cannot drift.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

FIG <- here::here("scripts", "fig_fpmrs_supply_line.R")
SIB <- here::here("scripts", "scenario_projection_trajectories.R")
ls_fig <- readLines(FIG, warn = FALSE)

ce <- new.env(); source(here::here("R", "workforce_constants.R"), local = ce)
H <- ce$WORKFORCE_PROJECTION_HORIZON_YEARS

# Re-derivation of the figure's year framing (mirrors the script; no ggplot side effects).
derive <- function(horizon, y0 = 2025L, obs_start = 2013L) {
  end   <- y0 + horizon
  years <- y0 + 0:horizon
  list(end = end, years = years, obs_end = y0 - 1L,
       breaks = c(seq(obs_start, (y0 - 1L) - 1L, 2L), seq(y0, end, 2L)))
}

test_that("the figure derives its axis from the horizon SSOT (no re-typed literals)", {
  expect_true(any(grepl("workforce_constants\\.R", ls_fig)))                 # sources the module
  expect_true(any(grepl("WORKFORCE_PROJECTION_HORIZON_YEARS", ls_fig)))      # uses the constant
  expect_true(any(grepl("PROJ_YEARS|PROJ_END|PROJ_HORIZON", ls_fig)))        # derived symbols exist
  # no stranded literal projection axis / endpoint filters remain
  expect_false(any(grepl("year\\s*=\\s*2025:2029", ls_fig)))
  expect_false(any(grepl("year\\s*==\\s*2029", ls_fig)))
  expect_false(any(grepl("2013,\\s*2015,\\s*2017", ls_fig)))                 # old literal breaks list
  expect_false(any(grepl("xintercept\\s*=\\s*2024\\.5", ls_fig)))            # old literal divider
})

test_that("the figure fails loudly if the horizon SSOT drifts (frozen 4-year endpoints)", {
  expect_true(any(grepl("stopifnot\\(PROJ_END == 2029L", ls_fig)))
})

test_that("[behavior-preserving] at the real horizon the derived axis equals the prior literals", {
  d <- derive(H)
  expect_identical(d$end, 2029L)
  expect_equal(as.integer(d$years), 2025:2029)
  expect_equal(as.numeric(d$breaks), c(2013,2015,2017,2019,2021,2023,2025,2027,2029))
  # code<->SSOT: endpoint is exactly baseline + the sourced horizon constant
  expect_identical(d$end, 2025L + H)
})

test_that("[semantic] the axis TRACKS the SSOT — a different horizon moves the endpoint and span", {
  d5 <- derive(5L)
  expect_identical(d5$end, 2030L)
  expect_equal(as.integer(d5$years), 2025:2030)
  expect_length(d5$years, 6L)                    # not frozen at 5 points
})

test_that("[adversarial] the sibling trajectory figure also derives from the shared horizon (no divergence)", {
  ls_sib <- readLines(SIB, warn = FALSE)
  expect_true(any(grepl("WC_YEAR0", ls_sib)) && any(grepl("WC_HORIZON", ls_sib)))
  expect_false(any(grepl("year\\s*=\\s*2025:2029", ls_sib)))   # sibling must not re-hardcode the axis
})
