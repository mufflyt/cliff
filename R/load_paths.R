load_paths <- function(verbose = FALSE) {
  # cliff resolves external inputs through wc_path()/config/cliff_paths.yml.
  # This compatibility shim exposes the keys the ported inference code expects.
  if (!exists("wc_path", mode = "function")) {
    stop("load_paths() requires wc_path() (R/wc_path.R) to be loaded.", call. = FALSE)
  }
  list(
    nber_duckdb_main = wc_path("signals_duckdb"),
    cohort_csv        = wc_path("cohort_csv"),
    abu_crosswalk     = wc_path("abu_crosswalk"),
    abu_net_new       = wc_path("abu_net_new")
  )
}
