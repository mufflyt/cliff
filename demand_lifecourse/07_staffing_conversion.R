#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# demand_lifecourse/07_staffing_conversion.R
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Level 7 (STAFFING CONVERSION) of the reproductive life-course demand model
# (DEMAND_LIFECOURSE_MODEL_SPEC.md): turn annual SERVICE VOLUMES into REQUIRED
# PROVIDER FTE, so demand and supply are compared in the same units. This closes
# the services-per-FTE gap flagged in PARAMETERS_EVIDENCE.md, where the interim
# denominator was an order-of-magnitude "visits per physician" placeholder.
#
# METHOD (work RVUs; Dall 2013's approach)
#   required_fte = (sum over services of volume * work_rvu) / wrvu_per_fte
#                  * 1 / (1 - indirect_share)
#   The per-service work RVUs are CMS Physician Fee Schedule values (RVU25A,
#   2025), mix-weighted over each service's CPT basket. wrvu_per_fte is NOT
#   assumed: calibrate_wrvu_per_fte() SOLVES it from a base-year anchor
#   (base-year work RVUs and base-year required FTE), so the productivity
#   denominator is internally consistent rather than a guessed constant. A
#   published external benchmark (WRVU_PER_FTE_BENCHMARK) is provided only as a
#   plausibility check.
#
# SSOT LINEAGE / SCOPE
#   Ported (thin) from the simulation package's R/17-workload_to_fte.R and
#   R/23-cms_rvu.R (work RVUs, calibration, indirect-time gross-up). simulation
#   remains the single source of truth for the FULL engine -- the provider-type
#   delegation matrix, setting time-share allocation, and productivity
#   validation. cliff carries only the URPS-attributed wRVU workload->FTE path it
#   needs for the life-course demand module; it does NOT re-implement delegation
#   or provider substitution. See SIMULATION_TO_CLIFF_INTEGRATION_PLAN.md.
#
# Inputs (committed, cited):
#   demand_lifecourse/params/urps_service_workload_rvu.csv
#
# Author: Tyler Muffly, MD / Claude Code
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
  library(tibble)
})

# Share of professional time that is INDIRECT (documentation, administration,
# teaching); required FTE is grossed up by 1/(1 - indirect_share) so this time is
# not silently free. Value ported from simulation INDIRECT_TIME_SHARE.
INDIRECT_TIME_SHARE <- 0.271

# External productivity benchmark (annual work RVUs per clinical FTE), used ONLY
# to sanity-check a solved wrvu_per_fte -- never as the default denominator.
WRVU_PER_FTE_BENCHMARK <- c(low = 3500, median = 7500, high = 12000)

#' Load the cited URPS service workload (per-service work RVUs)
#' @return Tibble: service, setting, unit, work_rvu, cpt_label, status, source.
#' @export
load_urps_workload_rvu <- function() {
  readr::read_csv(
    here::here("demand_lifecourse/params/urps_service_workload_rvu.csv"),
    show_col_types = FALSE)
}

#' Total annual work RVUs implied by a set of service volumes
#'
#' @param volumes Tibble with `service`, `volume`, and optionally `year`.
#' @param workload Per-service work-RVU table (default: the cited basket).
#' @return Tibble with `work_rvu` (and `year` if present). Unknown services error.
#' @export
service_volume_to_wrvu <- function(volumes, workload = load_urps_workload_rvu()) {
  stopifnot(all(c("service", "volume") %in% names(volumes)))
  unknown <- setdiff(unique(volumes$service), workload$service)
  if (length(unknown))
    stop(sprintf("service_volume_to_wrvu(): service(s) not in the workload basket: %s",
                 paste(unknown, collapse = ", ")), call. = FALSE)
  if (any(!is.finite(volumes$volume)) || any(volumes$volume < 0))
    stop("service_volume_to_wrvu(): volume must be finite and non-negative.", call. = FALSE)
  j <- dplyr::left_join(volumes, workload[, c("service", "work_rvu")], by = "service")
  j <- dplyr::mutate(j, wrvu = .data$volume * .data$work_rvu)
  if ("year" %in% names(j)) {
    dplyr::summarise(dplyr::group_by(j, .data$year),
                     work_rvu = sum(.data$wrvu, na.rm = TRUE), .groups = "drop")
  } else {
    tibble::tibble(work_rvu = sum(j$wrvu, na.rm = TRUE))
  }
}

#' Solve annual work RVUs per clinical FTE from a base-year anchor (Dall 2013)
#'
#' `required_fte = work_rvu / wrvu_per_fte * 1/(1 - indirect_share)`, inverted at
#' the base year so the denominator reproduces the observed base-year FTE rather
#' than assuming a productivity level.
#'
#' @param base_year_wrvu Total URPS work RVUs implied by base-year service volumes.
#' @param base_year_required_fte Base-year required FTE (e.g. observed workforce).
#' @param indirect_share Indirect-time share. Default `INDIRECT_TIME_SHARE`.
#' @return Numeric annual work RVUs per clinical FTE.
#' @export
calibrate_wrvu_per_fte <- function(base_year_wrvu, base_year_required_fte,
                                   indirect_share = INDIRECT_TIME_SHARE) {
  stopifnot(base_year_wrvu > 0, base_year_required_fte > 0,
            indirect_share >= 0, indirect_share < 1)
  (base_year_wrvu / base_year_required_fte) / (1 - indirect_share)
}

#' Convert annual service volumes to required provider FTE (work-RVU method)
#'
#' @param volumes Tibble with `service`, `volume`, optionally `year`.
#' @param wrvu_per_fte Annual work RVUs per clinical FTE (from
#'   [calibrate_wrvu_per_fte()]; do not assume a level).
#' @param workload Per-service work-RVU table.
#' @param indirect_share Indirect-time share. Default `INDIRECT_TIME_SHARE`.
#' @return Tibble with `required_fte` (and `year` if present).
#' @export
convert_workload_to_fte <- function(volumes, wrvu_per_fte,
                                    workload = load_urps_workload_rvu(),
                                    indirect_share = INDIRECT_TIME_SHARE) {
  stopifnot(is.numeric(wrvu_per_fte), wrvu_per_fte > 0,
            indirect_share >= 0, indirect_share < 1)
  gross_up <- 1 / (1 - indirect_share)
  rv <- service_volume_to_wrvu(volumes, workload)
  dplyr::mutate(rv, required_fte = .data$work_rvu / wrvu_per_fte * gross_up)
}

#' Is a solved productivity denominator within the external benchmark range?
#' @param wrvu_per_fte Annual work RVUs per clinical FTE.
#' @param benchmark Named low/median/high benchmark. Default the CMS-era range.
#' @return Logical: TRUE if within [low, high].
#' @export
check_productivity_plausible <- function(wrvu_per_fte,
                                         benchmark = WRVU_PER_FTE_BENCHMARK) {
  isTRUE(wrvu_per_fte >= benchmark[["low"]] && wrvu_per_fte <= benchmark[["high"]])
}
