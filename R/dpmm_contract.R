# =============================================================================
# Ingestion of the simulation repo's versioned DPMM demand contract
# =============================================================================
# The simulation repo (DPMM) emits a versioned demand-hierarchy artifact via
# export_demand_contract.R. cliff consumes it as a COMPARISON-ONLY alternative
# D1 (dynamic prevalence) in the demand-denominator sensitivity. These helpers
# are pure and base-R only (no tidyverse), so the alignment/rebase logic is unit-
# testable in isolation. See SIMULATION_TO_CLIFF_INTEGRATION_PLAN.md and the
# URPS microsimulation improvement plan (2026-07-30), sec 10 & 16.

DPMM_DEFAULT_TIER <- "tier3_prevalent_pfd"

#' Align + rebase a DPMM demand-contract tier to a set of projection years
#'
#' Pure transform. Given the tidy DPMM demand contract (as produced by the
#' simulation repo's `export_demand_contract.R`) and a vector of projection
#' years, return the demand index for `tier`, aligned to `years` and rebased so
#' that `base_year == 100`. Years absent from the contract yield `NA`. If
#' `base_year` is absent from the contract (or its value is non-positive), the
#' tier's own index is returned unchanged (passthrough) rather than erroring —
#' the caller decides usability via [dpmm_series_usable()].
#'
#' @param contract data.frame with columns `denominator_tier`, `calendar_year`,
#'   `denominator_index`.
#' @param years integer vector of projection years to align to.
#' @param base_year year to normalise the index to (= 100). Default 2025.
#' @param tier denominator tier to extract. Default `"tier3_prevalent_pfd"`.
#' @return numeric vector of `length(years)`.
dpmm_alt_d1_index <- function(contract, years,
                              base_year = 2025L,
                              tier = DPMM_DEFAULT_TIER) {
  stopifnot(is.data.frame(contract),
            all(c("denominator_tier", "calendar_year", "denominator_index") %in% names(contract)))
  sel <- contract[contract$denominator_tier == tier, , drop = FALSE]
  idx <- as.numeric(sel$denominator_index)[
    match(as.integer(years), as.integer(sel$calendar_year))]
  base_idx <- idx[as.integer(years) == as.integer(base_year)]
  if (length(base_idx) == 1L && !is.na(base_idx) && base_idx > 0) {
    100 * idx / base_idx
  } else {
    idx  # base year absent/invalid -> passthrough (already-indexed contract)
  }
}

#' Read a DPMM demand-contract CSV and its calibration status
#'
#' Thin base-R I/O wrapper. Returns `NULL` when `path` is empty or missing, so a
#' caller can cleanly fall back to the published-anchor denominators.
#'
#' @param path path to a `dpmm_demand_contract_v*.csv` (may be `""` / absent).
#' @return `list(data = data.frame, status = character)` or `NULL`.
read_dpmm_demand_contract <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) return(NULL)
  df <- utils::read.csv(path, stringsAsFactors = FALSE)
  status <- if ("calibration_status" %in% names(df))
    as.character(df$calibration_status[1]) else NA_character_
  list(data = df, status = status)
}

#' Is a DPMM-derived series usable (non-NULL with at least one value)?
#' @param d1 numeric vector from [dpmm_alt_d1_index()] (or `NULL`).
#' @return logical scalar.
dpmm_series_usable <- function(d1) !is.null(d1) && any(!is.na(d1))
