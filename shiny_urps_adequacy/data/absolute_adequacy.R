# App-local ABSOLUTE-ADEQUACY layer — standalone-deploy port of the package seam.
#
# WHY THIS EXISTS. model.R::project() reports only a RELATIVE adequacy index
# (adeq_eff), normalised so adequacy(2025) == 1; it assumes the base year is in
# balance and cannot state an ABSOLUTE adequacy. The package supplies the gate +
# seam that turn evidence into an absolute anchor:
#   R/capacity_evidence.R      -- the gate (resolve_adequacy_gated)
#   R/absolute_adequacy_seam.R -- project_absolute_adequacy() + the calibrated total
# but this Shiny app deploys STANDALONE (rsconnect bundles only app.R, model.R,
# and data/; it cannot source R/). So the pure-base-R decision surface is mirrored
# here, app-locally, exactly like BASE_YEAR / PROJECTION_END_YEAR / RATE_PER_100K
# are app-local copies of R/ constants. A repo-level PARITY GUARD
# (tests/testthat/test-ssot-app-absolute-parity.R) sources BOTH this file and the
# canonical R/ implementation and asserts they agree on shared fixtures, so this
# port cannot drift from the single source of truth.
#
# Functions are `app_`-prefixed so the parity guard can load them beside the
# identically-named R/ originals and compare. Faithful mirror of R/ — same shapes,
# same refusal reasons, same anchoring algebra. Pure base R; no data/path deps.
# The app currently supplies NEITHER evidence input, so the layer refuses (shows
# the honest "relative only" state); it resolves the moment a validated access fit
# and a fully identified all-payer demand basis are wired in.

## ── mirror of chia_calibrated_all_payer_total() (R/absolute_adequacy_seam.R) ───
app_chia_calibrated_all_payer_total <- function(applied) {
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
    total              = if (any(ident)) sum(applied$calibrated_all_payer_workload[ident]) else NA_real_,
    fully_identified   = nrow(applied) > 0L && all(ident),
    n_identified       = sum(ident),
    n_total            = nrow(applied),
    unidentified_bands = applied$age_band_lower[!ident]
  )
}

## ── mirror of the capacity-evidence gate (R/capacity_evidence.R) ──────────────
app_validate_capacity_evidence <- function(bundle) {
  stopifnot(
    inherits(bundle, "app_capacity_evidence_bundle"),
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

app_capacity_evidence_bundle <- function(access_fit, demand_evidence, label = NA_character_) {
  bundle <- structure(
    list(access_fit = access_fit, demand_evidence = demand_evidence,
         label = as.character(label)[1]),
    class = "app_capacity_evidence_bundle"
  )
  app_validate_capacity_evidence(bundle)
  bundle
}

app_capacity_evidence_sufficient <- function(bundle) {
  app_validate_capacity_evidence(bundle)
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

app_resolve_adequacy_gated <- function(bundle) {
  suff <- app_capacity_evidence_sufficient(bundle)
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

## ── mirror of project_absolute_adequacy() (R/absolute_adequacy_seam.R) ────────
app_project_absolute_adequacy <- function(projection, access_fit, demand_evidence,
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
    stop("app_project_absolute_adequacy: base_year ", base_year,
         " must match exactly one projection row (found ", length(base_rows), ").")
  }
  adeq_base <- proj[[adequacy_col]][base_rows]
  if (!is.finite(adeq_base) || abs(adeq_base - 1) > tol) {
    stop("app_project_absolute_adequacy: relative adequacy at base_year is ",
         format(adeq_base), ", not 1 (the anchor assumes a base-year-normalised index).")
  }

  bundle <- app_capacity_evidence_bundle(access_fit, demand_evidence, label = label)
  gated  <- app_resolve_adequacy_gated(bundle)
  resolved <- isTRUE(gated$resolved)
  anchor   <- if (resolved) as.numeric(gated$adequacy) else NA_real_
  reason   <- gated$reason

  proj$adeq_absolute     <- if (resolved) proj[[adequacy_col]] * anchor else NA_real_
  proj$absolute_resolved <- resolved
  proj$absolute_reason   <- reason

  has_fte <- effective_col %in% names(proj) && req_fte_col %in% names(proj) &&
    is.numeric(proj[[effective_col]]) && is.numeric(proj[[req_fte_col]])
  if (has_fte) {
    proj$req_fte_absolute <- if (resolved) proj[[req_fte_col]] / anchor else NA_real_
    proj$capacity_gap_absolute <- if (resolved) proj$req_fte_absolute - proj[[effective_col]] else NA_real_
  }

  attr(proj, "absolute_anchor")   <- anchor
  attr(proj, "absolute_resolved") <- resolved
  attr(proj, "absolute_reason")   <- reason
  proj
}

## ── app convenience: run the seam on the app's CURRENT evidence ───────────────
# The app holds no wait-based access fit and no calibrated CHIA demand basis, so
# both inputs default to their ABSENT (refusing) shapes and the gate refuses. The
# moment an operator wires in a validated access fit (wait_to_adequacy()) and a
# fully identified all-payer demand basis (a calibrated CHIA bridge, summarised by
# app_chia_calibrated_all_payer_total()), the same call resolves and the absolute
# columns populate. `absolute_adequacy_absent()` names why each input is missing.
absolute_adequacy_absent <- function() {
  list(
    access_fit      = data.frame(identified = FALSE, adequacy = NA_real_),
    demand_evidence = list(fully_identified = FALSE, total = NA_real_)
  )
}

absolute_adequacy_layer <- function(projection, access_fit = NULL,
                                    demand_evidence = NULL, base_year = BASE_YEAR,
                                    label = NA_character_) {
  absent <- absolute_adequacy_absent()
  af <- if (is.null(access_fit))      absent$access_fit      else access_fit
  de <- if (is.null(demand_evidence)) absent$demand_evidence else demand_evidence
  app_project_absolute_adequacy(projection, af, de, base_year = base_year, label = label)
}
