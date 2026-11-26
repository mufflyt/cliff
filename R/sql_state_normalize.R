sql_state_normalize <- function(col = "plocstatename", alias = NULL) {
  stopifnot(is.character(col), length(col) == 1L, nzchar(col))
  if (!is.null(alias)) {
    stopifnot(is.character(alias), length(alias) == 1L, !is.na(alias), nzchar(alias))
  }

  canonical_names <- c(
    datasets::state.name,
    "District of Columbia",
    "Puerto Rico",
    "Guam",
    "American Samoa",
    "Northern Mariana Islands"
  )
  canonical_abbr <- mufflyaccess::standardize_state_name(canonical_names, output = "abbr")
  if (anyNA(canonical_abbr)) {
    stop("sql_state_normalize: canonical state normalization failed", call. = FALSE)
  }

  pairs <- stats::setNames(canonical_abbr, toupper(canonical_names))
  pairs <- c(pairs,
             "WASHINGTON DC" = "DC",
             "U.S. VIRGIN ISLANDS" = "VI",
             "US VIRGIN ISLANDS" = "VI",
             "U S VIRGIN ISLANDS" = "VI",
             "VIRGIN ISLANDS" = "VI")
  pairs <- pairs[!duplicated(names(pairs))]

  whens <- paste(sprintf("WHEN '%s' THEN '%s'", names(pairs), unlist(pairs, use.names = FALSE)), collapse = " ")
  norm_col <- sprintf("UPPER(TRIM(COALESCE(%s, '')))", col)
  frag <- sprintf("CASE %s %s ELSE %s END", norm_col, whens, norm_col)
  if (!is.null(alias)) frag <- sprintf("%s AS %s", frag, alias)
  frag
}
