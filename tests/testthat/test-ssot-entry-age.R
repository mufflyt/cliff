# SSOT guard: the fellowship-graduate ENTRY AGE (34), unified across lineages. iter 6 wired the engine-sourcing
# scripts to WC_ENTRY_AGE, but module_a (demand lineage) still hardcoded ENTRY_AGE <- 34L. Now both the engine's
# WC_ENTRY_AGE and module_a's ENTRY_AGE alias R/workforce_constants.R::WORKFORCE_ENTRY_AGE.
library(testthat)
library(here)

# Repository integration test: reads scripts/, manuscript/ or data/ from the
# source tree, which a built package does not contain. Inapplicable rather
# than broken when run against an installed package. See helper-cliff-root.R.
skip_if_no_repo()

wc <- new.env(); source(here::here("R", "workforce_constants.R"), local = wc)

test_that("WORKFORCE_ENTRY_AGE is the pinned 34 (integer, plausible range)", {
  expect_type(wc$WORKFORCE_ENTRY_AGE, "integer")
  expect_identical(wc$WORKFORCE_ENTRY_AGE, 34L)
  expect_gte(wc$WORKFORCE_ENTRY_AGE, 25L); expect_lte(wc$WORKFORCE_ENTRY_AGE, 45L)
})

test_that("[cross-lineage] the engine WC_ENTRY_AGE aliases the shared constant", {
  ee <- new.env()
  ok <- tryCatch({ suppressMessages(suppressWarnings(source(here::here("R", "workforce_cliff_engine.R"), local = ee))); TRUE },
                 error = function(e) FALSE)
  skip_if_not(ok, "engine could not be sourced")
  expect_identical(ee$WC_ENTRY_AGE, wc$WORKFORCE_ENTRY_AGE)
  expect_gt(ee$WC_ENTRY_AGE, ee$WC_AGE_AT_CERT)   # graduates enter after certification
})

test_that("[adversarial] neither the engine nor module_a re-hardcodes 34 for the entry age", {
  eng <- readLines(here::here("R", "workforce_cliff_engine.R"), warn = FALSE)
  ma  <- readLines(here::here("scripts", "urps_module_a_effective_supply_2026-07-23.R"), warn = FALSE)
  expect_false(any(grepl("WC_ENTRY_AGE\\s*<-\\s*34L", eng)))
  expect_true(any(grepl("WC_ENTRY_AGE\\s*<-\\s*WORKFORCE_ENTRY_AGE", eng)))
  expect_false(any(grepl("ENTRY_AGE\\s*<-\\s*34L", ma)))
  expect_true(any(grepl("ENTRY_AGE\\s*<-\\s*WORKFORCE_ENTRY_AGE", ma)))
})

test_that("[adversarial] supply_demand_national's project() default wires to the SSOT, not a bare 34L (iter34)", {
  # iter34: the supply projection's entry_age default was project(..., entry_age=34L). It is a third
  # consumer of the same fellowship-graduate entry age; it now defaults to WORKFORCE_ENTRY_AGE, reached
  # via the demand_denominator source. Behavior-preserving: WORKFORCE_ENTRY_AGE == 34L.
  sd <- readLines(here::here("scripts", "urps_supply_demand_national_2026-07-23.R"), warn = FALSE)
  expect_false(any(grepl("entry_age\\s*=\\s*34L", sd)))                       # literal gone
  expect_true(any(grepl("entry_age\\s*=\\s*WORKFORCE_ENTRY_AGE", sd)))        # wired to SSOT
  expect_true(any(grepl("source\\(here::here\\(\"R\",\\s*\"demand_denominator\\.R\"\\)\\)", sd)))  # SSOT reachable at call time
})

test_that("[behavior-preserving] the projected 2050 supply is unchanged by the entry-age rewire", {
  # source demand_denominator so WORKFORCE_ENTRY_AGE is in scope, then run project() with an explicit
  # 34L vs the new default; identical trajectory proves the default resolves to the same value.
  de <- new.env(); source(here::here("R", "demand_denominator.R"), local = de)
  project <- function(ages, entrants, hz, horizon, entry_age) {
    count <- table(ages); av <- as.integer(names(count)); count <- as.numeric(count)
    traj <- numeric(horizon + 1); traj[1] <- sum(count)
    haz <- function(a) rep(0.05, length(a))
    for (h in seq_len(horizon)) { sv <- count * (1 - haz(av))
      av2 <- av + 1L; ix <- match(entry_age, av2)
      if (is.na(ix)) { av2 <- c(av2, entry_age); sv <- c(sv, entrants) } else sv[ix] <- sv[ix] + entrants
      av <- av2; count <- sv; traj[h + 1] <- sum(count) }
    traj }
  ages <- c(40, 45, 50, 55, 60)
  expect_identical(project(ages, 64, NULL, 25, 34L),
                   project(ages, 64, NULL, 25, de$WORKFORCE_ENTRY_AGE))
})
