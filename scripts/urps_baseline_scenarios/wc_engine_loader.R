# Load cliff's ACTUAL projection engine functions WITHOUT its data/IO machinery.
#
# We do NOT reimplement wc_project(). We parse R/workforce_cliff_engine.R and
# evaluate ONLY the pure projection definitions (wc_band_of, wc_haz_for,
# wc_project) plus the band constants -- byte-identical to the engine. The
# engine's source-time preamble (library(readr/dplyr), duckdb paths,
# workforce_constants.R / wc_path.R) is skipped because those are needed only for
# cohort LOADING, not for the projection recurrence. A test
# (test-wc-engine-equivalence.R) asserts the loaded wc_project is character-
# identical to the engine's definition, so this can never silently drift.
#
# WC_ENTRY_AGE / WC_HORIZON come from R/workforce_constants.R
# (WORKFORCE_ENTRY_AGE = 34, WORKFORCE_PROJECTION_HORIZON_YEARS = 4); we seed
# those two canonical values so wc_project resolves them.

load_real_wc_engine <- function(engine_path) {
  exprs <- parse(engine_path)
  env <- new.env(parent = baseenv())
  env$WC_ENTRY_AGE <- 34L    # WORKFORCE_ENTRY_AGE (workforce_constants.R)
  env$WC_HORIZON   <- 4L     # WORKFORCE_PROJECTION_HORIZON_YEARS (workforce_constants.R)
  want <- c("WC_BANDS", "WC_BAND_LABELS", "wc_band_of", "wc_haz_for", "wc_project",
            "wc_project_trajectory", "wc_project_ages")
  for (e in exprs) {
    if (is.call(e) && (identical(e[[1L]], as.name("<-")) || identical(e[[1L]], as.name("=")))) {
      lhs <- e[[2L]]
      if (is.name(lhs) && as.character(lhs) %in% want) eval(e, env)
    }
  }
  miss <- setdiff(want, ls(env))
  if (length(miss)) stop("engine loader could not extract: ", paste(miss, collapse = ", "))
  env
}

# The verbatim source text of a top-level `name <- ...` assignment in a file,
# used by the equivalence test to prove the loaded fn IS the engine's fn.
engine_defn_text <- function(engine_path, name) {
  exprs <- parse(engine_path, keep.source = TRUE)
  for (e in exprs) {
    if (is.call(e) && (identical(e[[1L]], as.name("<-")) || identical(e[[1L]], as.name("=")))) {
      if (is.name(e[[2L]]) && identical(as.character(e[[2L]]), name))
        return(paste(deparse(e[[3L]]), collapse = "\n"))
    }
  }
  NA_character_
}
