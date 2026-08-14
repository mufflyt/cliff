# Absolute-adequacy seam: calibrated CHIA demand basis -> capacity gate -> project().
#
# WHY THIS EXISTS. shiny_urps_adequacy/model.R::project() produces a RELATIVE
# adequacy index (adeq_eff), normalised so adequacy(base year) == 1; it assumes
# the base year is in supply-demand balance and cannot state an ABSOLUTE
# adequacy. R/capacity_evidence.R defines the GATE that may supply that missing
# absolute anchor, but only when the evidence validates: a validated access fit
# (R/wait_adequacy.R) AND a fully identified all-payer demand basis behind it.
#
# Until now the only demand basis wired to that gate was the PROVISIONAL
# CHIA<->Medicare contract (chia_bridge_all_payer_total()), which is never
# fully_identified (it ships not_calibrated and refuses every band), so the gate
# could never resolve. This file wires in the CALIBRATED engine
# (R/chia_demand_bridge_calibration.R):
#
#   * chia_calibrated_all_payer_total() turns an apply_chia_demand_bridge()
#     result into the SAME demand-evidence shape the gate consumes, so a real
#     calibrated bridge can make the demand basis fully_identified. It is the
#     direct analog of chia_bridge_all_payer_total() for the calibrated engine.
#
#   * project_absolute_adequacy() is the seam into project(): it takes a
#     projection table, an access fit, and a demand basis, runs them through the
#     capacity-evidence gate, and — ONLY if the gate resolves — anchors the
#     projection's relative index to the gate's absolute adequacy, adding
#     adeq_absolute (and, where the FTE columns are present, the absolute
#     required FTE and capacity gap the relative model cannot express). If the
#     gate refuses, every absolute column is NA with the gate's reason.
#
# CRITICAL INVARIANT (mirrors R/capacity_evidence.R and R/wait_adequacy.R). This
# seam NEVER recomputes or overwrites project()'s guarded relative identity
# (adeq_eff, capacity_gap, the *_index columns): it operates on a COPY and only
# ADDS absolute columns, gated. project()/validate_scenario_projection stay the
# single source of truth for the relative model; the absolute anchor is a
# separate, refusing layer on top. Pure base R; no data or path dependency, so
# it stays independently testable (the projection is passed in, not loaded).

#' All-payer demand total from a CALIBRATED CHIA bridge application
#'
#' Turn the output of [apply_chia_demand_bridge()] into the demand-evidence shape
#' the capacity-evidence gate consumes — the calibrated-engine analog of
#' [chia_bridge_all_payer_total()]. A Medicare age band counts as identified only
#' when it received a finite calibrated all-payer workload (i.e. a non-`NA`
#' `bridge_multiplier`); bands the calibrated bridge could not cover are reported,
#' never silently summed over.
#'
#' Because [apply_chia_demand_bridge()] itself refuses (errors) unless the bridge
#' status is `"calibrated"`, any result reaching this function already rests on a
#' calibrated bridge; `fully_identified` then additionally requires that no
#' Medicare band was dropped for lack of a calibrated CHIA multiplier.
#'
#' @param applied The `data.frame` returned by [apply_chia_demand_bridge()] (must
#'   carry `age_band_lower`, `bridge_multiplier`, and
#'   `calibrated_all_payer_workload`).
#' @return A list with `total` (summed all-payer workload over identified bands,
#'   `NA_real_` if none), `fully_identified` (logical: every band identified),
#'   `n_identified`, `n_total`, and `unidentified_bands` (the `age_band_lower`
#'   values with no calibrated multiplier). This is exactly the shape
#'   [capacity_evidence_bundle()] expects for `demand_evidence`.
#' @seealso [apply_chia_demand_bridge()], [chia_bridge_all_payer_total()],
#'   [project_absolute_adequacy()], [capacity_evidence_bundle()].
#' @family capacity-evidence
#' @examples
#' applied <- data.frame(
#'   age_band_lower = c(65, 70, 75),
#'   bridge_multiplier = c(1.8, 1.5, NA),
#'   calibrated_all_payer_workload = c(900, 700, NA)
#' )
#' chia_calibrated_all_payer_total(applied)$fully_identified   # FALSE (75 dropped)
#' @export
chia_calibrated_all_payer_total <- function(applied) {
  stopifnot(
    is.data.frame(applied),
    all(c("age_band_lower", "bridge_multiplier", "calibrated_all_payer_workload")
        %in% names(applied)),
    is.numeric(applied$bridge_multiplier),
    is.numeric(applied$calibrated_all_payer_workload)
  )
  ident <- !is.na(applied$bridge_multiplier) &
    is.finite(applied$calibrated_all_payer_workload)
  list(
    total              = if (any(ident)) {
      sum(applied$calibrated_all_payer_workload[ident])
    } else {
      NA_real_
    },
    fully_identified   = nrow(applied) > 0L && all(ident),
    n_identified       = sum(ident),
    n_total            = nrow(applied),
    unidentified_bands = applied$age_band_lower[!ident]
  )
}

#' Anchor a relative projection to a gated absolute adequacy
#'
#' The seam into `shiny_urps_adequacy/model.R::project()`. Given a projection
#' table (project()'s output, or any table with a year column and a relative
#' adequacy index normalised to 1 at the base year), a validated access fit, and
#' an all-payer demand basis, run them through the capacity-evidence gate
#' ([resolve_adequacy_gated()]) and — ONLY when the gate resolves — anchor the
#' relative index to the gate's absolute adequacy:
#'
#' \deqn{adequacy_{absolute}(y) = adequacy_{relative}(y) \times anchor}
#'
#' where `anchor` is the gate-resolved absolute adequacy. Because the relative
#' index is 1 at the base year, `adeq_absolute(base) == anchor`. Where the
#' projection also carries effective-FTE supply and the relative required FTE,
#' the absolute required FTE (`req_fte_relative / anchor`) and the absolute
#' capacity gap (`req_fte_absolute - effective`) are added too — the real FTE
#' shortage the relative model, pinned to base-year balance, cannot state.
#'
#' If the gate REFUSES (access fit not identified, or demand basis not fully
#' identified), every absolute column is `NA_real_` and the gate's reason is
#' carried on `absolute_reason`. The relative columns are never touched.
#'
#' @param projection A `data.frame`/`data.table` with a year column and a
#'   relative adequacy column. Operated on by copy; the input is not mutated.
#' @param access_fit A one-row access fit (e.g. [wait_to_adequacy()] output) with
#'   logical `identified` and numeric `adequacy`.
#' @param demand_evidence A demand basis with logical `fully_identified` and
#'   numeric `total` (e.g. [chia_calibrated_all_payer_total()] or
#'   [chia_bridge_all_payer_total()]).
#' @param base_year The projection base year at which the relative index equals 1.
#' @param adequacy_col Name of the relative adequacy column (default `"adeq_eff"`).
#' @param year_col Name of the year column (default `"YEAR"`).
#' @param effective_col Name of the effective-FTE supply column (default
#'   `"effective"`); absolute FTE columns are added only if it and
#'   `req_fte_col` are present.
#' @param req_fte_col Name of the relative required-FTE column (default
#'   `"req_fte"`).
#' @param label Optional label for the capacity-evidence bundle.
#' @param tol Numeric tolerance for the base-year normalisation check.
#' @return A `data.frame` copy of `projection` with added columns
#'   `adeq_absolute`, `absolute_resolved`, `absolute_reason` (and, when the FTE
#'   columns are present, `req_fte_absolute` and `capacity_gap_absolute`). The
#'   resolved anchor, resolution flag, and reason are also attached as attributes
#'   `absolute_anchor`, `absolute_resolved`, `absolute_reason`.
#' @seealso [resolve_adequacy_gated()], [capacity_evidence_bundle()],
#'   [chia_calibrated_all_payer_total()], [wait_to_adequacy()].
#' @family capacity-evidence
#' @examples
#' proj <- data.frame(YEAR = 2025:2027, adeq_eff = c(1, 0.95, 0.90),
#'                    effective = c(1000, 990, 980), req_fte = c(1000, 1042, 1089))
#' af <- data.frame(identified = TRUE, adequacy = 1.25)      # base-year absolute adequacy
#' de <- list(fully_identified = TRUE, total = 1200)
#' out <- project_absolute_adequacy(proj, af, de, base_year = 2025)
#' out$adeq_absolute        # 1.25, 1.1875, 1.125  (relative index x anchor)
#' @export
project_absolute_adequacy <- function(projection, access_fit, demand_evidence,
                                       base_year, adequacy_col = "adeq_eff",
                                       year_col = "YEAR",
                                       effective_col = "effective",
                                       req_fte_col = "req_fte",
                                       label = NA_character_, tol = 1e-8) {
  proj <- as.data.frame(projection)
  stopifnot(
    is.data.frame(proj), nrow(proj) > 0L,
    year_col %in% names(proj), adequacy_col %in% names(proj),
    is.numeric(proj[[adequacy_col]]),
    is.numeric(base_year) || is.integer(base_year), length(base_year) == 1L
  )

  base_rows <- which(proj[[year_col]] == base_year)
  if (length(base_rows) != 1L) {
    stop("project_absolute_adequacy: base_year ", base_year,
         " must match exactly one projection row (found ", length(base_rows), ").")
  }
  adeq_base <- proj[[adequacy_col]][base_rows]
  if (!is.finite(adeq_base) || abs(adeq_base - 1) > tol) {
    stop("project_absolute_adequacy: relative adequacy at base_year is ",
         format(adeq_base), ", not 1 (the anchor assumes a base-year-normalised ",
         "index). Pass the normalised relative column.")
  }

  # Run the capacity-evidence gate. capacity_evidence_bundle()/resolve_adequacy_gated()
  # live in R/capacity_evidence.R and are available in the package namespace.
  bundle <- capacity_evidence_bundle(access_fit, demand_evidence, label = label)
  gated  <- resolve_adequacy_gated(bundle)
  resolved <- isTRUE(gated$resolved)
  anchor   <- if (resolved) as.numeric(gated$adequacy) else NA_real_
  reason   <- gated$reason

  proj$adeq_absolute    <- if (resolved) proj[[adequacy_col]] * anchor else NA_real_
  proj$absolute_resolved <- resolved
  proj$absolute_reason   <- reason

  # Absolute FTE demand/gap follow from the anchor only when the projection
  # carries effective supply and the relative required FTE. Relative req_fte
  # assumes base-year balance (adequacy == 1); the absolute demand scales it by
  # 1/anchor, so adeq_absolute == effective / req_fte_absolute by construction.
  has_fte <- effective_col %in% names(proj) && req_fte_col %in% names(proj) &&
    is.numeric(proj[[effective_col]]) && is.numeric(proj[[req_fte_col]])
  if (has_fte) {
    proj$req_fte_absolute <- if (resolved) proj[[req_fte_col]] / anchor else NA_real_
    proj$capacity_gap_absolute <- if (resolved) {
      proj$req_fte_absolute - proj[[effective_col]]
    } else {
      NA_real_
    }
  }

  attr(proj, "absolute_anchor")   <- anchor
  attr(proj, "absolute_resolved") <- resolved
  attr(proj, "absolute_reason")   <- reason
  proj
}
