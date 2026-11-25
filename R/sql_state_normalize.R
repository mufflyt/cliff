sql_state_normalize <- function(col = "plocstatename", alias = NULL) {
  stopifnot(is.character(col), length(col) == 1L, nzchar(col))
  pairs <- list(
    ALABAMA="AL", ALASKA="AK", ARIZONA="AZ", ARKANSAS="AR", CALIFORNIA="CA",
    COLORADO="CO", CONNECTICUT="CT", DELAWARE="DE", FLORIDA="FL", GEORGIA="GA",
    HAWAII="HI", IDAHO="ID", ILLINOIS="IL", INDIANA="IN", IOWA="IA", KANSAS="KS",
    KENTUCKY="KY", LOUISIANA="LA", MAINE="ME", MARYLAND="MD", MASSACHUSETTS="MA",
    MICHIGAN="MI", MINNESOTA="MN", MISSISSIPPI="MS", MISSOURI="MO", MONTANA="MT",
    NEBRASKA="NE", NEVADA="NV", "NEW HAMPSHIRE"="NH", "NEW JERSEY"="NJ",
    "NEW MEXICO"="NM", "NEW YORK"="NY", "NORTH CAROLINA"="NC", "NORTH DAKOTA"="ND",
    OHIO="OH", OKLAHOMA="OK", OREGON="OR", PENNSYLVANIA="PA", "RHODE ISLAND"="RI",
    "SOUTH CAROLINA"="SC", "SOUTH DAKOTA"="SD", TENNESSEE="TN", TEXAS="TX", UTAH="UT",
    VERMONT="VT", VIRGINIA="VA", WASHINGTON="WA", "WEST VIRGINIA"="WV",
    WISCONSIN="WI", WYOMING="WY", "DISTRICT OF COLUMBIA"="DC", "WASHINGTON DC"="DC",
    "PUERTO RICO"="PR", "VIRGIN ISLANDS"="VI", GUAM="GU", "AMERICAN SAMOA"="AS"
  )
  whens <- paste(sprintf("WHEN '%s' THEN '%s'", names(pairs), unlist(pairs, use.names = FALSE)), collapse = " ")
  norm_col <- sprintf("UPPER(TRIM(COALESCE(%s, '')))", col)
  frag <- sprintf("CASE %s %s ELSE %s END", norm_col, whens, norm_col)
  if (!is.null(alias) && length(alias) > 0L && nzchar(alias)) frag <- sprintf("%s AS %s", frag, alias)
  frag
}
