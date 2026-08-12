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
#' The DMDM contract (from the simulation repo's `export_dmdm_demand_contract()`)
#' may carry a `tier_calibration_status` column, which stamps provenance PER TIER
#' rather than for the whole artifact: e.g. when the contract is produced from the
#' literature POP transitions, `dmdm_pop` is `derived_by_analogy` while `dmdm_ui`/
#' `dmdm_ai` remain placeholders. `tier_status` surfaces that mapping so a
#' consumer can gate on the provenance of the specific tier it reads. Older
#' contracts without the column yield `tier_status = NULL`; use [dpmm_tier_status()]
#' to read a tier's status with a fall back to the object-level `status`.
#'
#' @param path path to a `dpmm_demand_contract_v*.csv` (may be `""` / absent).
#' @return `list(data = data.frame, status = character, tier_status = named
#'   character or NULL)` or `NULL`.
read_dpmm_demand_contract <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) return(NULL)
  df <- utils::read.csv(path, stringsAsFactors = FALSE)
  status <- if ("calibration_status" %in% names(df))
    as.character(df$calibration_status[1]) else NA_character_
  tier_status <- NULL
  if (all(c("denominator_tier", "tier_calibration_status") %in% names(df))) {
    keep <- !duplicated(df$denominator_tier)
    tier_status <- stats::setNames(as.character(df$tier_calibration_status[keep]),
                                   as.character(df$denominator_tier[keep]))
  }
  list(data = df, status = status, tier_status = tier_status)
}

#' Per-tier calibration status of a demand contract (with fallback)
#'
#' Returns the provenance of a single `tier`, preferring the per-tier
#' `tier_calibration_status` (via [read_dpmm_demand_contract()]'s `tier_status`)
#' and falling back to the object-level `status` when the contract predates the
#' per-tier column. Pure; no I/O.
#'
#' @param ct list from [read_dpmm_demand_contract()] (or `NULL`).
#' @param tier denominator tier to look up. Default `"tier3_prevalent_pfd"`.
#' @return character scalar (the tier's status), or `NA_character_`.
dpmm_tier_status <- function(ct, tier = DPMM_DEFAULT_TIER) {
  if (is.null(ct)) return(NA_character_)
  if (!is.null(ct$tier_status) && tier %in% names(ct$tier_status))
    return(unname(ct$tier_status[[tier]]))
  if (!is.null(ct$status)) return(ct$status)
  NA_character_
}

#' Is a DPMM-derived series usable (non-NULL with at least one value)?
#' @param d1 numeric vector from [dpmm_alt_d1_index()] (or `NULL`).
#' @return logical scalar.
dpmm_series_usable <- function(d1) !is.null(d1) && any(!is.na(d1))
