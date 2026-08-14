#' @keywords internal
"_PACKAGE"

# ---- imports -----------------------------------------------------------------
# Until now NAMESPACE declared no imports at all, and the package relied on
# library() calls at file scope in R/safe_divide.R, R/workforce_cliff_engine.R
# and others. Those run when the package is BUILT, not when an installed copy is
# loaded, so every bare dplyr verb resolved during development via load_all() and
# failed in the installed package with "could not find function". R CMD check
# surfaced it as three separate example ERRORs (%>%, safe_divide, and the
# dplyr chain in calculate_state_vulnerability) and 187 "no visible global
# function definition" notes.
#
# Each symbol below is imported from the package that actually exports it,
# verified against getNamespaceExports() rather than assumed: dplyr re-exports
# %>%, matches, sym and tribble, so no dependency on magrittr, tidyselect, rlang
# or tibble is needed for them.
#
#' @importFrom dplyr %>% arrange bind_rows case_when coalesce count desc distinct
#' @importFrom dplyr filter group_by if_else left_join matches mutate n pull
#' @importFrom dplyr rename rowwise select slice summarise transmute ungroup
#' @importFrom dplyr sym tribble
#' @importFrom tidyr unnest
#' @importFrom stats na.omit setNames
#' @importFrom utils head
NULL
