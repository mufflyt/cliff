#' Statistical Summary Functions for FPMRS Workforce Forecasting
#'
#' Standardized statistical reporting for comprehensive forecasting results
#' following Statistical Summary Agent specifications

# Load required packages
library(dplyr)
library(readr)
library(scales)
library(tibble)

#' Format p-values nicely
#'
#' @param p Numeric p-value.
#' @return Character like "<0.001" or "0.023".
format_pval <- function(p) {
  if (is.na(p)) return("NA")
  if (p < 0.001) return("<0.001")
  sprintf("%.3f", p)
}

#' Summarize a numeric column (mean/SD, median/p25/p75)
#'
#' @param table_obj Tibble/data.frame.
#' @param value_col Quoted name of numeric column.
#' @return Tibble with n, mean, sd, median, p25, p75 (unformatted).
summarize_numeric <- function(table_obj, value_col) {
  x <- table_obj[[value_col]]
  tib <- tibble::tibble(
    n = base::sum(!base::is.na(x)),
    mean = base::mean(x, na.rm = TRUE),
    sd = stats::sd(x, na.rm = TRUE),
    median = stats::median(x, na.rm = TRUE),
    p25 = stats::quantile(x, 0.25, na.rm = TRUE, names = FALSE),
    p75 = stats::quantile(x, 0.75, na.rm = TRUE, names = FALSE)
  )

  return(tib)
}

#' Compare two periods and build a narrative sentence
#'
#' @param table_obj Tibble/data.frame.
#' @param value_col Quoted numeric column.
#' @param year_col Quoted year column.
#' @param y0 Optional start year; defaults to min(year).
#' @param y1 Optional end year; defaults to max(year).
#' @param treat_as_percent Logical; TRUE formats as percent (tenths).
#' @return List with stats tibble and summary sentence.
summarize_change_two_periods <- function(table_obj,
                                         value_col,
                                         year_col,
                                         y0 = NULL,
                                         y1 = NULL,
                                         treat_as_percent = FALSE) {

  yrs <- base::unique(table_obj[[year_col]])
  y_start <- if (is.null(y0)) base::min(yrs, na.rm = TRUE) else y0
  y_end <- if (is.null(y1)) base::max(yrs, na.rm = TRUE) else y1

  a <- table_obj |>
    dplyr::filter(.data[[year_col]] == y_start) |>
    dplyr::pull(!!rlang::sym(value_col))
  b <- table_obj |>
    dplyr::filter(.data[[year_col]] == y_end) |>
    dplyr::pull(!!rlang::sym(value_col))

  # t-test with NA removal; fall back if error
  p <- tryCatch(
    stats::t.test(a, b)$p.value,
    error = function(e) NA_real_
  )

  mean_a <- base::mean(a, na.rm = TRUE)
  mean_b <- base::mean(b, na.rm = TRUE)

  dir <- if (is.na(mean_a) || is.na(mean_b)) "no change"
  else if (mean_b > mean_a) "increased" else if (mean_b < mean_a)
    "decreased" else "no change"

  fmt_num <- function(v) scales::comma(v, accuracy = 0.01)
  fmt_pct <- function(v) scales::percent(v, accuracy = 0.1)

  fa <- if (treat_as_percent) fmt_pct(mean_a) else fmt_num(mean_a)
  fb <- if (treat_as_percent) fmt_pct(mean_b) else fmt_num(mean_b)

  sent <- paste0(
    "From ", y_start, " to ", y_end, ", the mean ",
    value_col, " ", dir, " from ", fa, " to ", fb,
    " (p=", format_pval(p), ")."
  )

  tib <- tibble::tibble(
    year_start = y_start, year_end = y_end,
    mean_start = mean_a, mean_end = mean_b, p_value = p
  )

  return(list(stats_table = tib, summary_sentence = sent))
}
