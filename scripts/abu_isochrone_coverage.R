# Shared helper for the ABU coverage scripts.
#
# The canonical 5 km point-to-isochrone matcher lives in the isochrones
# monorepo (R/match_points_to_isochrones.R). cliff deliberately does not copy
# it; resolve the monorepo through CLIFF_ISOCHRONES_ROOT (or ~/isochrones) and
# fail loudly when the checkout is absent.

abu_load_isochrone_matcher <- function() {
  iso_root <- Sys.getenv("CLIFF_ISOCHRONES_ROOT", path.expand("~/isochrones"))
  matcher <- file.path(iso_root, "R", "match_points_to_isochrones.R")
  if (!file.exists(matcher)) {
    stop(sprintf(paste0(
      "ABU coverage scripts require the isochrones checkout for the canonical ",
      "match_points_to_isochrones() matcher.\nSet CLIFF_ISOCHRONES_ROOT to an ",
      "isochrones checkout (currently %s)."), iso_root), call. = FALSE)
  }
  # The matcher sources its own dependencies through here::here(). here caches
  # the first project root it sees (usually cliff), so source it while both the
  # working directory and here's root are temporarily the isochrones checkout;
  # otherwise it looks for isochrones/R/utils/* under cliff and fails before the
  # matcher is defined.
  old_wd <- setwd(iso_root)
  on.exit({
    setwd(old_wd)
    try(suppressMessages(here::i_am("DESCRIPTION")), silent = TRUE)
  }, add = TRUE)
  suppressMessages(here::i_am("R/match_points_to_isochrones.R"))
  source(matcher, local = FALSE)
  invisible(matcher)
}

# match_points_to_isochrones() returns only covered points. Return the covered
# point ids so callers can mark the full roster without depending on the
# matcher's output column names.
abu_covered_ids <- function(points, iso_centers, id_col = "npi", threshold_km = 5.0) {
  abu_load_isochrone_matcher()
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("abu_covered_ids() needs dplyr.", call. = FALSE)
  }
  if (!id_col %in% names(points)) {
    stop(sprintf("points has no '%s' column for coverage matching", id_col),
         call. = FALSE)
  }
  matched <- match_points_to_isochrones(
    points, iso_centers,
    threshold_km = threshold_km,
    point_id_col = id_col
  )
  id_out <- intersect(c("point_id", ".point_id", id_col), names(matched))
  if (length(id_out) == 0L) {
    warning("matcher returned no usable point-id column; treating all as uncovered",
            call. = FALSE)
    return(character(0))
  }
  unique(as.character(matched[[id_out[1L]]]))
}
