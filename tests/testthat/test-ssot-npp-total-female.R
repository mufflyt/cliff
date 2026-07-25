# SSOT guard: the Census-NPP total-female row filter (SEX==2 & ORIGIN==0 & RACE==0) — the demand population
# base before the women-65+ age selection. It was copy-pasted across 3 demand producers; a wrong ORIGIN/RACE
# code would silently narrow the denominator to a subgroup. Now canonical in R/demand_denominator.R::npp_total_female().
library(testthat)
library(here)
suppressPackageStartupMessages(library(data.table))

de <- new.env(); source(here::here("R", "demand_denominator.R"), local = de)
PRODUCERS <- c("urps_demand_module_bc_2026-07-23.R", "urps_module_bc_corrected_2026-07-23.R",
               "urps_supply_demand_national_2026-07-23.R")

mk <- function() data.table(
  SEX    = c(2, 2, 1, 2, 2),   # 2=female
  ORIGIN = c(0, 1, 0, 0, 0),   # 0=all origins
  RACE   = c(0, 0, 0, 1, 0),   # 0=all races
  POP_65 = c(10, 20, 30, 40, 50))

test_that("[behavior-preserving] npp_total_female selects the same rows as the literal filter", {
  dt <- mk()
  expect_identical(de$npp_total_female(dt), dt[SEX == 2 & ORIGIN == 0 & RACE == 0])
})

test_that("[semantic] it keeps only total female / all-origins / all-races rows", {
  got <- de$npp_total_female(mk())
  expect_equal(nrow(got), 2L)                    # rows 1 and 5
  expect_true(all(got$SEX == 2))                 # no males (SEX==1)
  expect_true(all(got$ORIGIN == 0))              # no Hispanic-only (ORIGIN==1)
  expect_true(all(got$RACE == 0))                # no race-specific (RACE!=0)
  expect_equal(got$POP_65, c(10, 50))
})

test_that("[fail-loud] a missing SEX/ORIGIN/RACE column errors", {
  expect_error(de$npp_total_female(data.table(SEX = 2, ORIGIN = 0)))   # RACE missing
})

test_that("[adversarial] all 3 producers use the helper; no bare SEX/ORIGIN/RACE filter remains", {
  for (b in PRODUCERS) {
    ls <- readLines(here::here("scripts", b), warn = FALSE)
    expect_false(any(grepl("SEX ?== ?2 ?& ?ORIGIN ?== ?0 ?& ?RACE ?== ?0", ls)), info = b)  # literal gone
    expect_true(any(grepl("npp_total_female\\(", ls)), info = b)                              # uses the SSOT
    expect_true(any(grepl("demand_denominator", ls)), info = b)                              # sources the module
  }
})
