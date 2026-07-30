# wc_path(): resolve an external input path via config/cliff_paths.yml.
#
# ONE config entry per input, resolved as: env override > path > fallback.
# Lightweight and side-effect-free (no data loading), so the upstream
# regeneration scripts can source THIS alone instead of the full
# workforce_cliff_engine.R just to get a machine-independent path.
#
# Registered keys live in config/cliff_paths.yml; per-machine overrides go in
# config/cliff_paths.local.yml (gitignored) or the WORKFORCE_* env var named in
# each entry. Raw inputs (isochrones cohort/ABU files, the Medicare DuckDB and
# provider-service download, the HRSA HPSA shapefile) are external by design and
# do not live in this repo — see URPS_CONTAINMENT_AND_BASELINE_NOTES.md.

.wc_paths_cfg <- NULL

#' Resolve an external input path from config/cliff_paths.yml
#'
#' Look up a registered input key in `config/cliff_paths.yml` (deep-merged with a
#' gitignored `config/cliff_paths.local.yml` for per-machine overrides) and return
#' its resolved filesystem path.
#'
#' @details Resolution order per entry is: the named `WORKFORCE_*` environment
#'   variable (if set and non-empty) > the entry's `path` > its `fallback` (used
#'   only when `path` does not exist). The parsed config is cached in the
#'   module-level `.wc_paths_cfg` on the first call. The function is
#'   side-effect-free (no data loading), so upstream regeneration scripts can
#'   source this module alone rather than the full engine just to obtain a
#'   machine-independent path.
#' @param key Character scalar naming a registered entry in `cliff_paths.yml`
#'   (e.g. `"signals_duckdb"`). An unknown key is a fail-loud `stop()`.
#' @param must_exist Logical; when `TRUE`, `stop()` if the resolved path does not
#'   exist on disk. Defaults to `FALSE` (return the path unchecked).
#' @return A length-1 character filesystem path.
#' @seealso [wc_duckdb_path()] for the Medicare signals DuckDB shorthand;
#'   `config/cliff_paths.yml` for the registered keys.
#' @examples
#' \dontrun{
#' wc_path("signals_duckdb")                     # env override > path > fallback
#' wc_path("signals_duckdb", must_exist = TRUE)  # stop() if the file is absent
#' }
wc_path <- function(key, must_exist = FALSE) {
  if (is.null(.wc_paths_cfg)) {
    cfg <- yaml::read_yaml(here::here("config", "cliff_paths.yml"))
    lf  <- here::here("config", "cliff_paths.local.yml")
    if (file.exists(lf)) cfg <- utils::modifyList(cfg, yaml::read_yaml(lf))
    .wc_paths_cfg <<- cfg
  }
  e <- .wc_paths_cfg[[key]]
  if (is.null(e)) stop("wc_path(): unknown key '", key, "'", call. = FALSE)
  if (!is.null(e$env)) { v <- Sys.getenv(e$env, ""); if (nzchar(v)) return(v) }   # env override wins
  p <- e$path
  if (!file.exists(p) && !is.null(e$fallback) && file.exists(e$fallback)) p <- e$fallback
  if (must_exist && !file.exists(p)) stop("wc_path('", key, "'): file not found: ", p, call. = FALSE)
  p
}
#' Path to the Medicare signals DuckDB database
#'
#' Convenience wrapper for `wc_path("signals_duckdb")` — the resolved path to the
#' external Medicare fee-for-service signals DuckDB that the workforce pipeline
#' reads from.
#'
#' @return A length-1 character filesystem path to the signals DuckDB.
#' @seealso [wc_path()].
#' @examples
#' \dontrun{ wc_duckdb_path() }
wc_duckdb_path <- function() wc_path("signals_duckdb")

# READ_GUESS_MAX_ROWS
#   Meaning : the readr::read_csv() `guess_max` default shared by the read-heavy regeneration/sensitivity
#             scripts — scan this many rows to infer column types on the large roster/crosswalk CSVs, so a
#             wide column is never mis-typed from a small sample. Co-located in this lightweight, side-effect-
#             free I/O module because every consumer already reaches it (directly or via the engine).
#   Units   : rows (numeric, matching read_csv's guess_max).
#   Range   : exactly 1e5.
#   Source  : project convention (large-file type-inference robustness).
#   Consumers: scripts/{abu_pathway_sensitivity,build_hazard_comparison,departure_anchor,
#             hierarchical_hazard_partial_pooling,scenario_projection_trajectories,validate_departure_classifier_external}.R
#   NOT: the per-100,000 rate base (R/units.R::RATE_PER_100K, also 1e5 but a rate multiplier, a different concept).
READ_GUESS_MAX_ROWS <- 1e5
stopifnot(
  is.numeric(READ_GUESS_MAX_ROWS), length(READ_GUESS_MAX_ROWS) == 1L,
  !is.na(READ_GUESS_MAX_ROWS), READ_GUESS_MAX_ROWS == 1e5
)
