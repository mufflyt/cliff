# Canonical active-baseline cohort filter — single source of truth.
#
# `in_model_baseline` is the PI-adjudicated (2026-07-23) active-in-year determination
# carried per row on the enriched ABOG/ABU rosters. It is the UPSTREAM authority: the
# isochrones charter adopts `in_model_baseline == TRUE` as the fail-closed active
# definition, superseding `credentials.retirement_consensus` for the 48 providers where
# they disagree. cliff CONSUMES that flag; it never re-derives it.
#
# The predicate that reads the flag was previously written four different ways across
# ten call sites:
#   1) `inmodel(x) <- x %in% c(TRUE,"TRUE","true",1,"1")`  — redefined VERBATIM in 7 scripts
#   2) `d[in_model_baseline == TRUE]`                      — module_d_geographic_access
#   3) `toupper(trimws(x)) %in% c("TRUE","1")`             — concentration_equity
#   4) the (1) body inlined, with no helper                — enrich_rosters_hpsa
# All four agree on the CURRENT rosters (the column reads as clean `logical`, no NAs:
# ABOG 1,031/1,135 + ABU 308/365 = the 1,339 baseline under every variant). The risk was
# latent, not live: form (2) alone silently drops EVERY row if the column is ever
# re-serialised as "true"/"1"/whitespace-padded, and yields NA rather than FALSE on a
# missing flag. Defined ONCE here so the geographic and concentration analyses cannot
# drift to different N.
#
# Pure function, no path/data dependencies — safe to source from any cwd.

#' TRUE for a roster row that is IN the active model baseline.
#'
#' Vectorised, type-agnostic, and total: accepts the flag as `logical`, `numeric`,
#' `character`, or `factor`, and always returns `TRUE`/`FALSE` — never `NA`.
#'
#'   Accepted as in-baseline : TRUE, 1, "TRUE", "true", "True", "1", and any of those
#'                             with surrounding whitespace (case- and space-insensitive).
#'   Everything else         : FALSE, including NA, "", "FALSE", 0.
#'
#' This is the UNION of the four prior variants, so it is behaviour-preserving on the
#' committed rosters while being robust to a character re-serialisation of the column.
#' The one intentional difference: a missing flag returns FALSE, where the bare
#' `== TRUE` form returned NA (which data.table happened to treat as FALSE in `i`, but
#' which propagates in a base-R subset).
#'
#'   Consumers: \code{scripts/urps_module_[a_age_productivity,bc_corrected,bc_gate_audit]*.R},
#'              \code{scripts/urps_[demand_module_bc,plasticity_stage0_audit]*.R},
#'              scripts/urps_module_d_geographic_access_2026-07-23.R,
#'              scripts/urps_concentration_equity_2026-08-01.R,
#'              scripts/build_table1_urps_2026-07-23.R,
#'              \code{scripts/enrich_rosters_[hpsa_point_in_polygon,medicare_procedures_2024_refresh]*.R}
#' @param x [vector]: Values to test for membership in the in-model baseline.
inmodel <- function(x) {
  !is.na(x) & toupper(trimws(as.character(x))) %in% c("TRUE", "1")
}

stopifnot(
  is.function(inmodel),
  # accepted forms, across storage types
  identical(inmodel(c(TRUE, FALSE)),            c(TRUE, FALSE)),
  identical(inmodel(c(1, 0)),                   c(TRUE, FALSE)),
  identical(inmodel(c("TRUE", "true", "True")), c(TRUE, TRUE, TRUE)),
  identical(inmodel(c(" TRUE ", "1")),          c(TRUE, TRUE)),
  identical(inmodel(c("FALSE", "false", "0", "")), rep(FALSE, 4L)),
  # total: a missing flag is FALSE, never NA (this is what `== TRUE` got wrong)
  identical(inmodel(NA),                        FALSE),
  identical(inmodel(NA_character_),             FALSE),
  !anyNA(inmodel(c(TRUE, NA, FALSE))),
  # length-preserving, and empty-in / empty-out
  length(inmodel(logical(0))) == 0L,
  identical(inmodel(c(TRUE, NA, "true", "no")), c(TRUE, FALSE, TRUE, FALSE))
)
