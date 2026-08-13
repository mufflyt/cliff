# Capacity-evidence bundle + adequacy gate — single source of truth.
#
# WHY THIS EXISTS. cliff's canonical adequacy (shiny_urps_adequacy/model.R) is a
# RELATIVE index normalised so adequacy(2025) == 1; it assumes the base year is in
# balance and cannot state an ABSOLUTE adequacy. Two estimators in this package
# can supply the missing absolute anchor, each only within the region it can
# actually identify:
#   * R/wait_adequacy.R      -- an access fit: adequacy inferred from an observed
#                               wait time, identified only for adequacy > 1 and
#                               refused near/below balance.
#   * R/chia_medicare_bridge.R -- the all-payer demand basis the fit rests on,
#                               identified only for calibrated, above-capture-floor
#                               age bands.
#
# WHAT THIS PROVIDES. A bundle that carries those pieces of evidence and a GATE
# that resolves an absolute adequacy ONLY when the evidence validates: a
# validated (identified) access fit AND a fully identified all-payer demand basis
# behind it (no age band silently dropped). If either is missing, the gate
# REFUSES (resolved = FALSE, adequacy = NA, with reasons) rather than report an
# absolute number the evidence cannot support. This is the same fail-loud posture
# as R/wc_retirement_hazard.R (which refuses to project on an "observed" hazard
# unless mufflyaccess certifies the ascertainment) and dpmm_series_usable()
# (which gates a demand series on its per-tier calibration provenance).
#
# The gate does NOT recompute or overwrite the model's relative adequacy identity
# (that stays hard-guarded in project()/validate_scenario_projection); it decides
# whether the absolute anchor may be reported at all. Pure base R; the bundle is
# assembled from the sibling estimators' outputs, so this file has no data or path
# dependency and stays independently testable.

#' Assemble a capacity-evidence bundle from an access fit and a demand basis
#'
#' Package the two pieces of evidence the absolute-adequacy gate needs into one
#' validated object: an access fit (the shape returned by
#' [wait_to_adequacy()][wait_to_adequacy]) and an all-payer demand basis (the
#' shape returned by [chia_bridge_all_payer_total()][chia_bridge_all_payer_total]).
#'
#' Construction validates only the SHAPES; whether the evidence is strong enough
#' to resolve adequacy is decided later by [capacity_evidence_sufficient()] and
#' [resolve_adequacy_gated()], so an incomplete bundle is representable (and will
#' be refused at the gate) rather than un-constructable.
#'
#' @param access_fit A one-row `data.frame` carrying at least logical
#'   `identified` and numeric `adequacy` columns (e.g. a row of
#'   [wait_to_adequacy()] output).
#' @param demand_evidence A list carrying at least logical `fully_identified` and
#'   numeric `total` (e.g. [chia_bridge_all_payer_total()] output).
#' @param label Optional short character label for the unit of analysis (region,
#'   scenario). Defaults to `NA_character_`.
#' @return An object of class `capacity_evidence_bundle`: a list with
#'   `access_fit`, `demand_evidence`, and `label`.
#' @seealso [validate_capacity_evidence()], [resolve_adequacy_gated()].
#' @family capacity-evidence
#' @examples
#' af <- data.frame(identified = TRUE, adequacy = 1.4)
#' de <- list(fully_identified = TRUE, total = 1200)
#' capacity_evidence_bundle(af, de, label = "national")
#' @export
capacity_evidence_bundle <- function(access_fit, demand_evidence, label = NA_character_) {
  bundle <- structure(
    list(access_fit = access_fit, demand_evidence = demand_evidence,
         label = as.character(label)[1]),
    class = "capacity_evidence_bundle"
  )
  validate_capacity_evidence(bundle)
  bundle
}

#' Validate a capacity-evidence bundle's shape (hard-fail on any violation)
#'
#' Enforce that the bundle carries a one-row access fit with the required
#' `identified`/`adequacy` fields and a demand-evidence list with the required
#' `fully_identified`/`total` fields. Shape only — not sufficiency.
#'
#' @param bundle A candidate `capacity_evidence_bundle`.
#' @return The validated `bundle`, invisibly.
#' @seealso [capacity_evidence_bundle()]
#' @family capacity-evidence
#' @examples
#' validate_capacity_evidence(
#'   capacity_evidence_bundle(data.frame(identified = FALSE, adequacy = NA_real_),
#'                            list(fully_identified = FALSE, total = NA_real_)))
#' @export
validate_capacity_evidence <- function(bundle) {
  stopifnot(
    inherits(bundle, "capacity_evidence_bundle"),
    is.list(bundle), all(c("access_fit", "demand_evidence") %in% names(bundle)),
    is.data.frame(bundle$access_fit), nrow(bundle$access_fit) == 1L,
    all(c("identified", "adequacy") %in% names(bundle$access_fit)),
    is.logical(bundle$access_fit$identified), length(bundle$access_fit$identified) == 1L,
    is.numeric(bundle$access_fit$adequacy),
    is.list(bundle$demand_evidence),
    all(c("fully_identified", "total") %in% names(bundle$demand_evidence)),
    is.logical(bundle$demand_evidence$fully_identified),
    length(bundle$demand_evidence$fully_identified) == 1L,
    is.numeric(bundle$demand_evidence$total)
  )
  invisible(bundle)
}

#' Is a capacity-evidence bundle strong enough to resolve absolute adequacy?
#'
#' The evidence is sufficient only when BOTH conditions hold: the access fit is
#' identified (a wait-based adequacy exists and was not refused), and the
#' all-payer demand basis behind it is fully identified (no age band was dropped).
#'
#' @param bundle A `capacity_evidence_bundle`.
#' @return A list with `sufficient` (logical) and `reasons` (character vector of
#'   the failing conditions; empty when sufficient).
#' @seealso [resolve_adequacy_gated()]
#' @family capacity-evidence
#' @examples
#' capacity_evidence_sufficient(
#'   capacity_evidence_bundle(data.frame(identified = TRUE, adequacy = 1.3),
#'                            list(fully_identified = TRUE, total = 900)))
#' @export
capacity_evidence_sufficient <- function(bundle) {
  validate_capacity_evidence(bundle)
  reasons <- character(0)
  if (!isTRUE(bundle$access_fit$identified)) {
    reasons <- c(reasons, "access fit not identified (no validated wait-based adequacy)")
  }
  if (!isTRUE(bundle$demand_evidence$fully_identified)) {
    reasons <- c(reasons,
                 "all-payer demand basis not fully identified (an age band was refused)")
  }
  list(sufficient = length(reasons) == 0L, reasons = reasons)
}

#' Resolve an absolute adequacy through the capacity-evidence gate
#'
#' The gate. Returns the access fit's absolute adequacy ONLY when the bundle's
#' evidence is sufficient (see [capacity_evidence_sufficient()]); otherwise it
#' refuses with `resolved = FALSE`, `adequacy = NA`, and a reason. The absolute
#' anchor is never reported on incomplete evidence.
#'
#' @param bundle A `capacity_evidence_bundle`.
#' @return A one-row `data.frame` with `label`, `resolved` (logical), `adequacy`
#'   (the resolved absolute adequacy, or `NA_real_`), `access_identified`,
#'   `demand_fully_identified`, and `reason` (`NA` when resolved).
#' @seealso [capacity_evidence_bundle()], [wait_to_adequacy()],
#'   [chia_bridge_all_payer_total()];
#'   `tests/testthat/test-ssot-capacity-evidence.R` for the guard.
#' @family capacity-evidence
#' @examples
#' good <- capacity_evidence_bundle(data.frame(identified = TRUE, adequacy = 1.4),
#'                                  list(fully_identified = TRUE, total = 1000),
#'                                  label = "national")
#' resolve_adequacy_gated(good)$adequacy        # 1.4
#' bad <- capacity_evidence_bundle(data.frame(identified = FALSE, adequacy = NA_real_),
#'                                 list(fully_identified = TRUE, total = 1000))
#' resolve_adequacy_gated(bad)$resolved         # FALSE
#' @export
resolve_adequacy_gated <- function(bundle) {
  suff <- capacity_evidence_sufficient(bundle)
  access_ok <- isTRUE(bundle$access_fit$identified)
  demand_ok <- isTRUE(bundle$demand_evidence$fully_identified)
  resolved  <- suff$sufficient
  data.frame(
    label                   = bundle$label,
    resolved                = resolved,
    adequacy                = if (resolved) as.numeric(bundle$access_fit$adequacy) else NA_real_,
    access_identified       = access_ok,
    demand_fully_identified = demand_ok,
    reason                  = if (resolved) NA_character_ else paste(suff$reasons, collapse = "; "),
    stringsAsFactors        = FALSE
  )
}
