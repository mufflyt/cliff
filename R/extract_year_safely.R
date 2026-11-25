extract_year_safely <- function(x) {
  if (inherits(x, c("Date", "POSIXct", "POSIXlt"))) {
    return(suppressWarnings(as.integer(format(as.Date(x), "%Y"))))
  }
  if (is.numeric(x)) {
    y <- suppressWarnings(as.integer(x))
    return(ifelse(!is.na(y) & y >= 1900L & y <= 2100L, y, NA_integer_))
  }
  if (!is.character(x)) x <- as.character(x)
  out <- rep(NA_integer_, length(x))
  ok <- !is.na(x) & nzchar(x)
  if (any(ok)) {
    pos <- regexpr("[12][0-9]{3}", x[ok])
    hit <- which(pos > 0)
    if (length(hit)) {
      out[which(ok)[hit]] <- suppressWarnings(as.integer(regmatches(x[ok], pos)))
    }
  }
  out
}
