#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# THE PATH TO AN ABSOLUTE ADEQUACY NUMBER — runnable, end to end.
#
# shiny_urps_adequacy/model.R::project() reports only a RELATIVE adequacy index
# (adeq_eff, normalised to 1 at the base year); it assumes base-year balance and
# cannot state an absolute adequacy. This script walks the full, fully-gated path
# that turns real evidence into an ABSOLUTE adequacy on a projection, using the
# exported SSOT estimators. Every stage can REFUSE; you get a number only when
# all the gates pass. The path:
#
#   (1) wait_to_adequacy()             observed wait  -> base-year absolute adequacy
#   (2) calibrate_chia_demand_bridge() CHIA claims    -> age-graded volume bridge
#   (3) apply_chia_demand_bridge()     Medicare FFS   -> all-payer workload
#   (4) chia_calibrated_all_payer_total() applied     -> demand evidence for the gate
#   (5) project_absolute_adequacy()    projection + (1) + (4) -> ABSOLUTE adequacy
#
# THE DATA HERE IS SYNTHETIC AND ILLUSTRATIVE. There is no real CHIA APCD extract
# in-tree, so this script fabricates a CHIA world with a KNOWN age-graded
# multiplier purely to make the path executable and inspectable. It computes no
# real-world figure; swap in a real CHIA extract (stage 2) and the real
# project_from(DEFAULTS) table (stage 5) to get a real number. Mirrors the
# integration block of tests/testthat/test-ssot-absolute-adequacy-seam.R.
#
# OUTPUT: prints the resolved absolute-adequacy trajectory, then a REFUSAL demo.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({
  library(here)
  # The calibration engine (stage 2/3) needs these; fail loud if any is missing.
  for (pkg in c("dplyr", "tibble", "purrr", "scales", "splines", "broom")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("absolute_adequacy_path.R needs package '", pkg, "' for the ",
           "calibration stack; install it to run this demo.")
    }
  }
})

# SSOT sources (dev-checkout runnable without installing the package). In an
# installed context these are all exported: library(cliff) then call directly.
source(here::here("R", "wait_adequacy.R"))                 # wait_to_adequacy()
source(here::here("R", "chia_demand_bridge_calibration.R")) # calibrate_/apply_chia_demand_bridge()
source(here::here("R", "capacity_evidence.R"))             # capacity_evidence_bundle(), resolve_adequacy_gated()
source(here::here("R", "absolute_adequacy_seam.R"))        # chia_calibrated_all_payer_total(), project_absolute_adequacy()

BASE_YEAR <- 2025L

## ── (1) ACCESS FIT: an absolute adequacy at the base year, from an observed wait
# wait_to_adequacy() inverts a mean wait-in-queue through M/M/s. It REFUSES
# (identified = FALSE) at/below balance -- wait time alone can never evidence a
# shortage -- so any adequacy it returns is > 1 and point-identified.
#
# To make the demo self-consistent we go round-trip: target adequacy 1.25
# (utilisation rho = 1/1.25 = 0.8), use the FORWARD map mmc_wait_in_queue() to
# get the wait it implies, then invert that wait back to the adequacy.
mu <- 4; s <- 12L
observed_wait <- mmc_wait_in_queue(s = s, mu = mu, rho = 1 / 1.25)   # forward: adequacy -> wait
access_fit    <- wait_to_adequacy(wait = observed_wait, mu = mu, s = s)  # inverse: wait -> adequacy
cat("── (1) access fit ─────────────────────────────────────────────\n")
cat(sprintf("   observed wait = %.4f -> adequacy = %.3f  (identified = %s)\n",
            observed_wait, access_fit$adequacy, access_fit$identified))

## ── (2) CALIBRATE the CHIA bridge from claims + population  [SYNTHETIC DATA]
# Synthetic CHIA world: all-payer volume = FFS volume x true_mult(age), with a
# known age gradient. calibrate_...() recovers it and stamps "calibrated" only if
# its sufficiency gates pass.
bands     <- c(65, 70, 75, 80, 85)
years     <- 2018:2021
true_mult <- c(`65` = 1.8, `70` = 1.5, `75` = 1.3, `80` = 1.2, `85` = 1.15)
claims <- list(); pop <- list()
for (yr in years) for (ag in bands) {
  ffs_vol <- 800 + 5 * (ag - 65)
  claims[[length(claims) + 1L]] <- data.frame(year = yr, age = ag, payer = "Medicare FFS", wrvu = ffs_vol)
  claims[[length(claims) + 1L]] <- data.frame(year = yr, age = ag, payer = "Commercial",
                                              wrvu = ffs_vol * true_mult[[as.character(ag)]] - ffs_vol)
  pop[[length(pop) + 1L]] <- data.frame(year = yr, age = ag, payer = "Medicare FFS", population = 50000)
  pop[[length(pop) + 1L]] <- data.frame(year = yr, age = ag, payer = "Commercial",   population = 50000)
}
bridge <- calibrate_chia_demand_bridge(
  chia_claims = do.call(rbind, claims),
  population   = do.call(rbind, pop),
  age_band_width = 5L, n_boot = 500L
)
cat("\n── (2) calibrated bridge ──────────────────────────────────────\n")
cat(sprintf("   status = %s  (%d age bands, ref year %d)\n",
            bridge$status$status, bridge$status$n_age_bands, bridge$status$reference_year))
stopifnot(identical(bridge$status$status[[1]], "calibrated"))  # else stage (3) refuses

## ── (3) APPLY the bridge to national Medicare-FFS workload -> all-payer  [SYNTHETIC]
# apply_...() hard-refuses (errors) unless the bridge status is "calibrated".
national_ffs <- data.frame(age = bands, wrvu = 800 + 5 * (bands - 65), population = 50000)
applied <- apply_chia_demand_bridge(national_ffs, bridge, age_band_width = 5L)

## ── (4) DEMAND EVIDENCE for the capacity gate
# fully_identified is FALSE if any Medicare band was dropped (reported below,
# never silently summed over).
demand_evidence <- chia_calibrated_all_payer_total(applied)
cat("\n── (4) demand evidence ────────────────────────────────────────\n")
cat(sprintf("   fully_identified = %s  (%d/%d bands, all-payer total = %.0f)\n",
            demand_evidence$fully_identified, demand_evidence$n_identified,
            demand_evidence$n_total, demand_evidence$total))

## ── (5) THE SEAM: run the relative projection through the gate and anchor it
# A synthetic, internally-consistent relative projection (adeq_eff == effective /
# req_fte, normalised to 1 at the base year). IN THE REAL APP, replace this with:
#     source("shiny_urps_adequacy/model.R"); projection <- project_from(DEFAULTS)
proj_years <- BASE_YEAR:2035L
adeq_eff   <- seq(1.0, 0.80, length.out = length(proj_years))  # relative index, 1 at base
effective  <- seq(1000, 900, length.out = length(proj_years))
projection <- data.frame(
  YEAR = proj_years, adeq_eff = adeq_eff, effective = effective,
  req_fte = effective / adeq_eff                                 # the guarded identity
)

out <- project_absolute_adequacy(
  projection = projection, access_fit = access_fit,
  demand_evidence = demand_evidence, base_year = BASE_YEAR
)
cat("\n── (5) ABSOLUTE adequacy (gate RESOLVED) ──────────────────────\n")
cat(sprintf("   anchor (base-year absolute adequacy) = %.3f\n", attr(out, "absolute_anchor")))
print(utils::head(
  data.frame(YEAR = out$YEAR,
             adeq_relative = round(out$adeq_eff, 3),
             adeq_absolute = round(out$adeq_absolute, 3),
             capacity_gap_absolute_fte = round(out$capacity_gap_absolute, 1)),
  6), row.names = FALSE)

## ── REFUSAL DEMO: drop one bridge band -> demand basis not fully identified
# The seam reports NO absolute number; every absolute column is NA, with the
# gate's reason. This is the whole point: the anchor is never reported on
# incomplete evidence.
applied_gap <- applied
applied_gap$bridge_multiplier[1] <- NA_real_
applied_gap$calibrated_all_payer_workload[1] <- NA_real_
out_refused <- project_absolute_adequacy(
  projection = projection, access_fit = access_fit,
  demand_evidence = chia_calibrated_all_payer_total(applied_gap), base_year = BASE_YEAR
)
cat("\n── REFUSAL demo (one band dropped) ────────────────────────────\n")
cat(sprintf("   resolved = %s\n   adeq_absolute = %s\n   reason = %s\n",
            unique(out_refused$absolute_resolved),
            unique(out_refused$adeq_absolute),
            unique(out_refused$absolute_reason)))

invisible(out)
