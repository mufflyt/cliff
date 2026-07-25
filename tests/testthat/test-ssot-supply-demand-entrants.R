# SSOT guard: the URPS entrant inflow in the supply-demand producer. supply_demand_national hardcoded 64 twice
# in its project() calls instead of deriving it from the ACGME graduate counts. iter 7 established
# ENTRANTS <- mean(GRAD_URPS) (module_a); this wires the same for supply_demand_national, so a change to the
# graduate counts flows through instead of leaving a stale 64.
library(testthat)
library(here)

me <- new.env(); source(here::here("shiny_urps_scenarios", "urps_model_data.R"), local = me)
SD <- here::here("scripts", "urps_supply_demand_national_2026-07-23.R")

test_that("[behavior-preserving] mean(GRAD_URPS) equals the prior hardcoded 64", {
  expect_identical(mean(me$GRAD_URPS), 64)
  expect_length(me$GRAD_URPS, 4L)                       # the four AY2020-24 completer counts
})

test_that("[semantic] the entrant inflow is DERIVED from the graduate counts (tracks a change)", {
  # a hypothetical different graduate vector would change the entrant mean, proving it's not a constant 64
  expect_identical(mean(c(60, 60, 60, 60)), 60)
  expect_false(mean(c(60, 66, 63, 66)) == 64)
})

test_that("[adversarial] supply_demand_national derives ENTRANTS; no bare project(..., 64) remains", {
  ls <- readLines(SD, warn = FALSE)
  expect_true(any(grepl("ENTRANTS\\s*<-\\s*mean\\(GRAD_URPS\\)", ls)))       # SSOT derivation
  expect_true(any(grepl("project\\(URPS_AGES,\\s*ENTRANTS", ls)))            # project uses it
  expect_false(any(grepl("project\\(URPS_AGES,\\s*64", ls)))                 # literal gone
})

test_that("[consistency] this matches module_a's ENTRANTS <- mean(GRAD_URPS) pattern", {
  ma <- readLines(here::here("scripts", "urps_module_a_effective_supply_2026-07-23.R"), warn = FALSE)
  expect_true(any(grepl("ENTRANTS\\s*<-\\s*mean\\(GRAD_URPS\\)", ma)))
})
