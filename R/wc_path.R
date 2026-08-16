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
# do not live in this repo — see dev/archive/URPS_CONTAINMENT_AND_BASELINE_NOTES.md
# (archived; the baseline question it raises was resolved to 1,306).

.wc_paths_cfg <- NULL

# Expand ${VAR} references in a configured path.
#
# Config paths are written relative to a named root (${CLIFF_ISOCHRONES_ROOT}/...)
# rather than hard-coded. Each root resolves as: the environment variable of that
# name, else the default under `roots:` in cliff_paths.yml. Absolute paths in the
# committed config meant the whole external-input tree only resolved on one
# machine, and nothing could see that but that machine.
.wc_expand_roots <- function(p, cfg) {
  if (is.null(p) || !length(p) || !nzchar(p)) return(p)
  roots <- cfg[["roots"]]
  guard <- 0L
  while (grepl("\\$\\{[A-Za-z_][A-Za-z0-9_]*\\}", p)) {
    guard <- guard + 1L
    if (guard > 10L)
      stop("wc_path(): cyclic root expansion in '", p, "'", call. = FALSE)
    var <- sub(".*\\$\\{([A-Za-z_][A-Za-z0-9_]*)\\}.*", "\\1", p)
    val <- Sys.getenv(var, "")
    if (!nzchar(val) && !is.null(roots[[var]])) val <- roots[[var]]
    if (!nzchar(val))
      stop("wc_path(): root '", var, "' is not set and has no default in ",
           "config/cliff_paths.yml `roots:`", call. = FALSE)
    p <- sub("\\$\\{[A-Za-z_][A-Za-z0-9_]*\\}", val, p)
  }
  path.expand(p)
}

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
  p <- .wc_expand_roots(e$path, .wc_paths_cfg)
  fb <- .wc_expand_roots(e$fallback, .wc_paths_cfg)
  if (!file.exists(p) && !is.null(fb) && file.exists(fb)) p <- fb
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
