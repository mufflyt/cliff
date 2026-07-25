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
wc_duckdb_path <- function() wc_path("signals_duckdb")
