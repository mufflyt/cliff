# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# wc_retirement_hazard.R -- SINGLE SOURCE OF TRUTH for *which* retirement hazard
# the URPS projection runs on. The scientific rule this enforces:
#
#   Historical exits are OBSERVED in mufflyaccess; future exits are SIMULATED in
#   cliff from a hazard calibrated to those observations.
#
# So cliff never re-derives retirement from provider records -- the "observed_hazard"
# source reads ONLY mufflyaccess::urps_exit_hazard_by_age_year() (the frozen
# empirical age x year departure hazard) and aggregates it onto the engine's age
# bands. The forward projection stays stochastic: the Monte Carlo still draws a
# Beta posterior per band each iteration (build_urps_projection.R::mc_bounds), so
# the empirical hazard carries uncertainty -- it is NOT injected as a point mass,
# and historical exit COUNTS are never spliced into future years.
#
# Two sources:
#   * "legacy_modeled"  (DEFAULT) -- the reviewed frozen band model
#       (BAND_EV/BAND_PY, 2016-2021 primary window). Byte-identical to the prior
#       projection: this function just echoes the caller's frozen constants back
#       with provenance, so the point estimate and MC are unchanged.
#   * "observed_hazard" -- reads the mufflyaccess observed hazard. FAILS LOUD unless
#       mufflyaccess::urps_retirement_status() == "observed" (an unascertained
#       retirement is never silently projected as if observed).
#
# "observed_hazard" is deliberately NOT the production default. Promote it only
# after the real provider-month evidence is populated, the hazard is frozen and
# validated, and the back-test shows it predicts t+1..t+3 active supply better than
# the frozen model with calibrated intervals. See scripts/urps_projection/RETIREMENT_SOURCE.md.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

`%||%` <- function(a, b) if (is.null(a)) b else a

WC_RETIREMENT_SOURCES <- c("legacy_modeled", "observed_hazard")

# Uncertainty method is shared by both sources: the point hazard is a band ev/py,
# and mc_bounds() draws hz ~ Beta(ev + 0.5, py - ev + 0.5) per band per iteration.
# Naming it here (recorded in provenance) makes the "no hazard_cv = 0" guarantee
# explicit -- the hazard is drawn, never fixed to its mean.
WC_HAZARD_UNCERTAINTY_METHOD <-
  "beta_posterior_band: hz ~ Beta(band_ev + 0.5, band_py - band_ev + 0.5), drawn per MC iteration"

.wc_hash <- function(x) {
  if (requireNamespace("digest", quietly = TRUE)) return(digest::digest(x, algo = "sha256"))
  # deterministic, dependency-free fallback (not cryptographic): checksum the
  # serialized bytes so identical inputs hash identically across runs.
  raw <- serialize(x, connection = NULL)
  paste0("nohash-", format(sum(as.integer(raw)), scientific = FALSE), "-", length(raw))
}

#' Resolve the retirement hazard the projection will run on.
#'
#' @param source One of `WC_RETIREMENT_SOURCES`. Default `"legacy_modeled"`.
#' @param band_labels The engine's age-band labels (`eng$WC_BAND_LABELS`) -- the
#'   order the returned `band_ev` / `band_py` / `hz_point` vectors follow.
#' @param band_of A function age -> band label (`eng$wc_band_of`), reused so the
#'   observed hazard is banded EXACTLY as the engine bands ages (no reimplementation).
#' @param legacy_band_ev,legacy_band_py The frozen band event / person-year counts,
#'   required for `"legacy_modeled"` (passed straight through, so the legacy path
#'   is byte-identical to the caller's own constants).
#' @param confirmation_window_months Recorded in provenance; should mirror the
#'   mufflyaccess manifest `exit_confirmation_months` (default 12).
#' @param ns The mufflyaccess namespace (overridable in tests with a stub env).
#' @return A list: `retirement_source`, `band_labels`, `band_ev`, `band_py`,
#'   `hz_point` (named by `band_labels`; `NA` for a band with no person-years, which
#'   the engine fills with the max hazard), and `provenance` (a named list carrying
#'   `retirement_source`, `hazard_artifact`, `hazard_version`, `hazard_hash`,
#'   `ascertainment_status`, `confirmation_window_months`, `uncertainty_method`).
wc_retirement_hazard <- function(source = WC_RETIREMENT_SOURCES,
                                 band_labels,
                                 band_of,
                                 legacy_band_ev = NULL,
                                 legacy_band_py = NULL,
                                 confirmation_window_months = 12L,
                                 ns = "mufflyaccess") {
  source <- match.arg(source, WC_RETIREMENT_SOURCES)

  if (identical(source, "legacy_modeled")) {
    if (is.null(legacy_band_ev) || is.null(legacy_band_py) ||
        length(legacy_band_ev) != length(band_labels) ||
        length(legacy_band_py) != length(band_labels))
      stop("[wc_retirement_hazard] 'legacy_modeled' requires legacy_band_ev / legacy_band_py ",
           "of length ", length(band_labels), " (one per band).", call. = FALSE)
    band_ev <- setNames(as.numeric(legacy_band_ev), band_labels)
    band_py <- setNames(as.numeric(legacy_band_py), band_labels)
    hz_point <- setNames(ifelse(band_py > 0, band_ev / band_py, NA_real_), band_labels)
    return(list(
      retirement_source = source, band_labels = band_labels,
      band_ev = band_ev, band_py = band_py, hz_point = hz_point,
      provenance = list(
        retirement_source          = source,
        hazard_artifact            = "cliff frozen band model (BAND_EV/BAND_PY, 2016-2021 primary window)",
        hazard_version             = "fully_obs (BAND_EV/BAND_PY, 2016-2021 primary window)",
        hazard_hash                = .wc_hash(list(band_ev = unname(band_ev), band_py = unname(band_py))),
        ascertainment_status       = "modeled (frozen 2016-2021 window; not the observed exit panel)",
        confirmation_window_months = NA_integer_,   # n/a: the frozen model is not a confirmed-exit panel
        uncertainty_method         = WC_HAZARD_UNCERTAINTY_METHOD)))
  }

  ## ---- observed_hazard: read ONLY mufflyaccess; fail loud unless observed ------
  # `ns` is normally the "mufflyaccess" namespace string; tests may pass a list/env
  # of stub functions (same names) to exercise the aggregation without a real
  # observed manifest. Either way, cliff calls ONLY these mufflyaccess accessors.
  if (is.character(ns)) {
    if (!requireNamespace(ns, quietly = TRUE))
      stop("[wc_retirement_hazard] 'observed_hazard' requires the mufflyaccess package.", call. = FALSE)
    get_ma <- function(fn) {
      if (!exists(fn, envir = asNamespace(ns), inherits = FALSE))
        stop(sprintf(paste0("[wc_retirement_hazard] mufflyaccess::%s() is unavailable; the observed ",
                            "exit-panel contract is not present in the installed mufflyaccess. ",
                            "Bump the mufflyaccess pin to a build with the exit panel, or use ",
                            "retirement_source='legacy_modeled'."), fn), call. = FALSE)
      getExportedValue(ns, fn)
    }
    ns_ver <- ns
  } else {
    stub <- as.list(ns)
    get_ma <- function(fn) {
      if (is.null(stub[[fn]]))
        stop(sprintf("[wc_retirement_hazard] stub is missing %s().", fn), call. = FALSE)
      stub[[fn]]
    }
    ns_ver <- "mufflyaccess"
  }

  # (req 2) fail loud unless retirement is genuinely observed -- never project an
  # unascertained / partially-observed retirement as if it were observed.
  status <- tryCatch(get_ma("urps_retirement_status")(), error = function(e) "not_ascertained")
  if (!identical(status, "observed"))
    stop(sprintf(paste0("[wc_retirement_hazard] retirement_source='observed_hazard' but ",
                        "mufflyaccess::urps_retirement_status() is '%s', not 'observed'. ",
                        "Historical exits must be observed before cliff calibrates the forward ",
                        "hazard to them. Populate + freeze the provider-month evidence first, or ",
                        "use retirement_source='legacy_modeled'."), status), call. = FALSE)

  # (req 1) the ONLY retirement input: mufflyaccess's frozen empirical hazard.
  h <- get_ma("urps_exit_hazard_by_age_year")()
  need <- c("age", "n_at_risk", "n_exits")
  if (!all(need %in% names(h)))
    stop("[wc_retirement_hazard] the observed hazard artifact is missing column(s): ",
         paste(setdiff(need, names(h)), collapse = ", "), ".", call. = FALSE)

  # (req 6) partial pooling of sparse age x year cells: aggregate the risk set onto
  # the engine's age bands, pooling over ages within a band AND over calendar years
  # (the observed history is short). band_py = provider-years at risk, band_ev = exits.
  band <- band_of(h$age)
  py_by <- tapply(h$n_at_risk, band, sum)
  ev_by <- tapply(h$n_exits,   band, sum)
  band_py <- setNames(as.numeric(py_by[band_labels]), band_labels); band_py[is.na(band_py)] <- 0
  band_ev <- setNames(as.numeric(ev_by[band_labels]), band_labels); band_ev[is.na(band_ev)] <- 0
  hz_point <- setNames(ifelse(band_py > 0, band_ev / band_py, NA_real_), band_labels)

  artifact <- getOption("mufflyaccess.urps_exit_hazard_path",
                        Sys.getenv("MUFFLYACCESS_URPS_EXIT_HAZARD",
                                   "mufflyaccess::urps_exit_hazard_by_age_year()"))
  hazver <- tryCatch(as.character(utils::packageVersion(ns_ver)), error = function(e) NA_character_)

  list(
    retirement_source = source, band_labels = band_labels,
    band_ev = band_ev, band_py = band_py, hz_point = hz_point,
    provenance = list(
      retirement_source          = source,
      hazard_artifact            = artifact,
      hazard_version             = paste0("mufflyaccess ", hazver, " :: urps_exit_hazard_by_age_year"),
      hazard_hash                = .wc_hash(h[order(h$age, h$year %||% h$age), , drop = FALSE]),
      ascertainment_status       = status,
      confirmation_window_months = as.integer(confirmation_window_months),
      uncertainty_method         = WC_HAZARD_UNCERTAINTY_METHOD))
}
