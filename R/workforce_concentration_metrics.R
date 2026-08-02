#' @title Geographic Concentration and Workforce Equity Metrics
#'
#' @description
#' Dependency-light functions for quantifying how unevenly a physician
#' workforce is distributed across geography (Gini, Herfindahl-Hirschman
#' Index, Lorenz curve, top-k concentration) and for tabulating the
#' demographic / access-equity composition of a subspecialty roster.
#'
#' @family reporting-stats
#' @name workforce_concentration_metrics
NULL

#!/usr/bin/env Rscript
# R/workforce_concentration_metrics.R
# ============================================================================
# Geographic Concentration and Workforce Equity Metrics
# ============================================================================
#
# PURPOSE:
#   cliff's headline story is a SUPPLY-vs-RETIREMENT count (how many
#   subspecialists exist and whether fellowships replace departures). These
#   helpers add the ORTHOGONAL question the Cecil G. Sheps Center emphasizes in
#   its health-workforce work: given the providers that exist, are they
#   DISTRIBUTED where patients are, and WHO are they? A workforce can be
#   numerically "adequate" nationally and still be a maldistributed, homogeneous
#   one. These functions make that measurable.
#
# WHAT IT COMPUTES:
#   1. Geographic concentration
#        - gini()               Gini coefficient of a count vector (0 = perfectly
#                               even across units, 1 = all in one unit).
#        - herfindahl_index()   HHI = sum of squared shares (0-1), optionally
#                               size-normalized; the same metric cliff already
#                               uses for insurer markets, here for provider share.
#        - lorenz_curve()       Cumulative-unit vs cumulative-provider shares for
#                               plotting the Lorenz curve.
#        - top_k_share()        Share of the workforce in the k busiest units.
#        - concentration_summary()  One-row summary across a geography level,
#                               INCLUDING zero-provider units when the full unit
#                               universe (e.g. all 3,143 US counties) is supplied.
#   2. Provider-weighted rate dispersion
#        - rate_dispersion()    Median / IQR / p10 / p90 / 90:10 ratio of a
#                               per-provider access rate (e.g. urogynecologists
#                               per 100k women 65+ in the provider's county).
#   3. Equity composition
#        - equity_breakdown()   Counts and within-group percentages of a
#                               categorical characteristic (gender, med-school
#                               class, IMG status, rurality, HPSA) by roster
#                               stratum and overall.
#
# INSPIRATION / METHODS LINEAGE:
#   Fraher EP, Knapton A, McCartha E, Leslie LK. Forecasting the Future Supply
#   of Pediatric Subspecialists in the United States: 2020-2040. Pediatrics.
#   2024;153(Suppl 2):e2023063678C. doi:10.1542/peds.2023-063678C. PMID 38300007.
#   The Sheps peds-subspecialty microsimulation reports supply at national,
#   Census-region, and Census-division levels precisely because subnational
#   maldistribution is the policy-relevant signal. See
#   PEDS_SUBSPEC_MICROSIMULATION_COMPARISON.md for the full comparison.
#
# DESIGN NOTE:
#   Deliberately base-R / dplyr only so this runs from a bare clone exactly like
#   the rest of the cliff pipeline -- no external population pull is REQUIRED.
#   Population-weighted (true maldistribution) Gini is available by passing a
#   per-unit denominator to concentration_summary(weight = ...); when omitted the
#   functions report provider-count concentration, which needs no external data.
#
# DEPENDENCIES:
#   - dplyr, tibble (data frames); base R (everything else)
#
# USAGE:
#   source(here::here("R/workforce_concentration_metrics.R"))
#   gini(c(10, 0, 0, 0))                      # -> ~0.75
#   herfindahl_index(c(50, 30, 20))           # -> 0.38
#   concentration_summary(state_counts, n_units_total = 51)
#
# AUTHOR: Tyler Muffly, MD / Claude Code
# ============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

# ----------------------------------------------------------------------------
# 1. CONCENTRATION PRIMITIVES
# ----------------------------------------------------------------------------

#' Gini coefficient of a non-negative count/weight vector
#'
#' Uses the standard covariance/rank formula. A vector of length \code{n} with
#' all mass in a single unit tends to \code{(n-1)/n}; an even split gives 0.
#' Include zero-valued units (e.g. counties with no provider) to measure
#' concentration across the FULL geography rather than only occupied units.
#'
#' @param x Numeric vector of non-negative counts or weights.
#' @return Gini coefficient in [0, 1), or \code{NA_real_} if the total is 0.
#' @examples
#' gini(c(25, 25, 25, 25))   # 0 (perfectly even)
#' gini(c(100, 0, 0, 0))     # 0.75
gini <- function(x) {
  x <- x[is.finite(x)]
  if (any(x < 0)) stop("gini(): negative values are not allowed.", call. = FALSE)
  x <- sort(x)
  n <- length(x)
  total <- sum(x)
  if (n == 0L || total == 0) return(NA_real_)
  (2 * sum(seq_len(n) * x)) / (n * total) - (n + 1) / n
}

#' Herfindahl-Hirschman Index of market/provider share
#'
#' @param counts Numeric vector of counts per unit. Zero/negative entries are
#'   dropped (they contribute no share).
#' @param normalized If \code{TRUE}, return the size-corrected HHI*
#'   \eqn{(H - 1/n)/(1 - 1/n)} so values are comparable across differing numbers
#'   of occupied units. Default \code{FALSE} (raw HHI in [0, 1]).
#' @return HHI in [0, 1]; 1 = monopoly, \eqn{1/n} = even split. \code{NA_real_}
#'   if the total is 0.
#' @examples
#' herfindahl_index(c(50, 30, 20))              # 0.38
#' herfindahl_index(c(50, 30, 20), TRUE)        # normalized
herfindahl_index <- function(counts, normalized = FALSE) {
  counts <- counts[is.finite(counts) & counts > 0]
  total <- sum(counts)
  if (total == 0) return(NA_real_)
  h <- sum((counts / total)^2)
  if (!normalized) return(h)
  n <- length(counts)
  if (n <= 1L) return(NA_real_)
  (h - 1 / n) / (1 - 1 / n)
}

#' Lorenz-curve coordinates for a count vector
#'
#' @param x Numeric vector of counts per unit (include zeros for full geography).
#' @return A tibble with \code{cum_unit_share} and \code{cum_value_share},
#'   prepended with the origin (0, 0), units ordered fewest-to-most.
lorenz_curve <- function(x) {
  x <- sort(x[is.finite(x)])
  n <- length(x)
  total <- sum(x)
  if (n == 0L || total == 0) {
    return(tibble::tibble(cum_unit_share = 0, cum_value_share = 0))
  }
  tibble::tibble(
    cum_unit_share  = c(0, seq_len(n) / n),
    cum_value_share = c(0, cumsum(x) / total)
  )
}

#' Share of the total held by the k largest units
#'
#' @param counts Numeric vector of counts per unit.
#' @param k Number of top units to sum. Default 5.
#' @return Fraction in [0, 1], or \code{NA_real_} if the total is 0.
top_k_share <- function(counts, k = 5L) {
  counts <- counts[is.finite(counts)]
  total <- sum(counts)
  if (total == 0) return(NA_real_)
  sum(sort(counts, decreasing = TRUE)[seq_len(min(k, length(counts)))]) / total
}

#' One-row concentration summary for a geography level
#'
#' @param counts Named or unnamed numeric vector of provider counts for the
#'   OCCUPIED units at this geography level.
#' @param n_units_total Size of the full unit universe at this level (e.g. 3143
#'   US counties, 51 states incl. DC). Zero-provider units are padded in so Gini
#'   and the zero-share reflect the whole geography. Defaults to
#'   \code{length(counts)} (occupied-only).
#' @param label Character geography label for the output row.
#' @param weight Optional numeric vector, same length/order as \code{counts},
#'   giving a per-unit population denominator. When supplied, a
#'   population-weighted maldistribution Gini is added (providers ordered by
#'   provider-per-population). Occupied units only.
#' @return A one-row tibble.
concentration_summary <- function(counts, n_units_total = length(counts),
                                   label = NA_character_, weight = NULL) {
  counts <- as.numeric(counts)
  n_occupied <- sum(counts > 0, na.rm = TRUE)
  n_pad <- max(0L, n_units_total - length(counts))
  full <- c(counts, rep(0, n_pad))

  gini_weighted <- NA_real_
  if (!is.null(weight)) {
    weight <- as.numeric(weight)
    ok <- is.finite(weight) & weight > 0 & is.finite(counts)
    if (any(ok)) {
      ord   <- order(counts[ok] / weight[ok])          # areas: sparsest first
      w_ord <- weight[ok][ord]
      c_ord <- counts[ok][ord]
      Lx <- cumsum(w_ord) / sum(w_ord)                 # cum population
      Ly <- cumsum(c_ord) / sum(c_ord)                 # cum providers
      gini_weighted <- sum(utils::head(Lx, -1) * utils::tail(Ly, -1) -
                             utils::tail(Lx, -1) * utils::head(Ly, -1)) * -1
    }
  }

  tibble::tibble(
    geography            = label,
    n_units              = n_units_total,
    n_occupied           = n_occupied,
    pct_units_zero       = round(100 * (n_units_total - n_occupied) / n_units_total, 1),
    gini                 = round(gini(full), 4),
    gini_pop_weighted    = round(gini_weighted, 4),
    hhi                  = round(herfindahl_index(full), 4),
    top5_share           = round(top_k_share(full, 5L), 4),
    top10_share          = round(top_k_share(full, 10L), 4)
  )
}

# ----------------------------------------------------------------------------
# 2. PROVIDER-WEIGHTED RATE DISPERSION
# ----------------------------------------------------------------------------

#' Distribution of a per-provider access rate
#'
#' Summarizes the spread of, e.g., urogynecologists-per-100k-women-65+ carried
#' by each provider's own county. A wide 90:10 ratio is a maldistribution signal
#' even when the national count looks adequate.
#'
#' @param rate Numeric per-provider rate; NA/NaN dropped.
#' @return One-row tibble: n, median, p10, p25, p75, p90, ratio_90_10.
rate_dispersion <- function(rate) {
  rate <- rate[is.finite(rate)]
  if (length(rate) == 0L) {
    return(tibble::tibble(n = 0L, median = NA_real_, p10 = NA_real_,
                          p25 = NA_real_, p75 = NA_real_, p90 = NA_real_,
                          ratio_90_10 = NA_real_))
  }
  qs <- stats::quantile(rate, c(.10, .25, .50, .75, .90), names = FALSE, type = 7)
  tibble::tibble(
    n           = length(rate),
    median      = round(qs[3], 3),
    p10         = round(qs[1], 3),
    p25         = round(qs[2], 3),
    p75         = round(qs[4], 3),
    p90         = round(qs[5], 3),
    ratio_90_10 = if (qs[1] > 0) round(qs[5] / qs[1], 3) else NA_real_
  )
}

# ----------------------------------------------------------------------------
# 3. EQUITY / DEMOGRAPHIC COMPOSITION
# ----------------------------------------------------------------------------

#' Counts and within-stratum percentages of a categorical characteristic
#'
#' @param df Roster data frame.
#' @param characteristic Bare or string column name to tabulate (e.g. gender).
#' @param stratum Optional column name defining strata (e.g. pathway ABU/ABOG).
#'   Columns are produced per stratum plus an Overall column.
#' @param levels Optional character vector fixing the row order; unlisted levels
#'   are appended by descending overall count.
#' @param missing_label Label for empty/NA values. Default "Missing".
#' @return Long tibble: characteristic, level, then <stratum>_n / <stratum>_pct
#'   pairs and overall_n / overall_pct.
equity_breakdown <- function(df, characteristic, stratum = NULL,
                             levels = NULL, missing_label = "Missing") {
  ch <- rlang::as_name(rlang::ensym(characteristic))
  # Capture the stratum as an expression WITHOUT evaluating it (a bare column
  # name is not a variable in the caller frame): NULL when the arg is omitted.
  stratum_expr <- rlang::enexpr(stratum)
  st_name <- if (is.null(stratum_expr)) NULL else rlang::as_string(stratum_expr)

  vals <- as.character(df[[ch]])
  vals[is.na(vals) | trimws(vals) == ""] <- missing_label
  df$.level <- vals

  ordered_levels <- {
    ov <- sort(table(vals), decreasing = TRUE)
    if (is.null(levels)) names(ov)
    else c(levels[levels %in% names(ov)], setdiff(names(ov), levels))
  }

  st_col <- if (is.null(st_name)) NULL else as.character(df[[st_name]])
  strata <- if (is.null(st_col)) character(0) else sort(unique(st_col))

  build_col <- function(mask, level) {
    sub <- df$.level[mask]
    n <- sum(sub == level)
    denom <- length(sub)
    c(n = n, pct = if (denom) round(100 * n / denom, 1) else NA_real_)
  }

  out <- tibble::tibble(characteristic = ch, level = ordered_levels)
  for (s in strata) {
    mask <- st_col == s
    stats <- vapply(ordered_levels, function(l) build_col(mask, l), numeric(2))
    out[[paste0(s, "_n")]]   <- stats["n", ]
    out[[paste0(s, "_pct")]] <- stats["pct", ]
  }
  overall <- vapply(ordered_levels, function(l) build_col(rep(TRUE, nrow(df)), l), numeric(2))
  out[["overall_n"]]   <- overall["n", ]
  out[["overall_pct"]] <- overall["pct", ]
  out
}
