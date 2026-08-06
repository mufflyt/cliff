# ---------------------------------------------------------------------------
# Uncertainty summaries for the workforce projection Monte Carlo.
#
# The projection MC (scripts/urps_scenario_cube/regen_urps_1306_projection.R and
# the engine) already draws a full distribution of the 2029 workforce and the
# replacement ratio, but historically collapsed it to a point estimate + a 95%
# CI. This turns the SAME draws into the fuller uncertainty statement a
# microsimulation is meant to communicate (item 7, "quantify uncertainty
# everywhere"): median, a prediction interval, and decision probabilities
# (P(shortage exceeds X%), P(access improves), P(below replacement)).
#
# These are computational facts about the existing draws, not new modeling, and
# they do NOT alter the frozen consolidated-CSV schema or any published point
# estimate -- they are emitted as a separate, additive report.
#
# Pure base-R + stats so it is trivially unit- and boundary-tested
# (tests/testthat/test-workforce-uncertainty.R).
# ---------------------------------------------------------------------------

#' Summarize a workforce-projection Monte Carlo as median + interval + decision
#' probabilities.
#'
#' @param final_draws Numeric vector: projected end-of-horizon workforce, one per
#'   MC draw. Non-finite values are dropped.
#' @param ratio_draws Numeric vector aligned to `final_draws`: replacement ratio
#'   (entrants / departures) per draw. Pass `NULL` to skip below-replacement
#'   probability. Non-finite values are dropped pairwise for the ratio metric.
#' @param baseline Positive scalar: the baseline (start-of-horizon) workforce the
#'   shortage/improvement thresholds are measured against.
#' @param shortage_pct Non-negative scalar: "shortage exceeds X%" means the
#'   workforce falls to at most `baseline * (1 - shortage_pct/100)`. Default 0 =>
#'   any net decline.
#' @param improve_pct Non-negative scalar: "access improves" means the workforce
#'   reaches at least `baseline * (1 + improve_pct/100)`. Default 0 => any growth.
#' @param interval Two-sided prediction-interval width in (0,1). Default 0.95.
#' @return A one-row data.frame with baseline, median, mean, sd, pi_lower,
#'   pi_upper, pi_level, p_shortage_exceeds, shortage_pct, p_access_improves,
#'   improve_pct, p_below_replacement (NA if no ratio), and n_draws.
wc_uncertainty_summary <- function(final_draws, ratio_draws = NULL, baseline,
                                   shortage_pct = 0, improve_pct = 0,
                                   interval = 0.95) {
  if (!is.numeric(final_draws) || length(final_draws) == 0L)
    stop("wc_uncertainty_summary: final_draws must be a non-empty numeric vector", call. = FALSE)
  if (!is.numeric(baseline) || length(baseline) != 1L || is.na(baseline) || baseline <= 0)
    stop("wc_uncertainty_summary: baseline must be a positive scalar", call. = FALSE)
  if (!is.numeric(shortage_pct) || length(shortage_pct) != 1L || is.na(shortage_pct) || shortage_pct < 0)
    stop("wc_uncertainty_summary: shortage_pct must be a non-negative scalar", call. = FALSE)
  if (!is.numeric(improve_pct) || length(improve_pct) != 1L || is.na(improve_pct) || improve_pct < 0)
    stop("wc_uncertainty_summary: improve_pct must be a non-negative scalar", call. = FALSE)
  if (!is.numeric(interval) || length(interval) != 1L || is.na(interval) || interval <= 0 || interval >= 1)
    stop("wc_uncertainty_summary: interval must be a scalar in (0, 1)", call. = FALSE)

  fd <- final_draws[is.finite(final_draws)]
  if (length(fd) == 0L)
    stop("wc_uncertainty_summary: no finite values in final_draws", call. = FALSE)

  lo <- (1 - interval) / 2
  q <- stats::quantile(fd, c(lo, 1 - lo), names = FALSE, type = 7)
  # baseline +/- baseline*pct/100 (not baseline*(1 +/- pct/100)): the former keeps
  # round-number thresholds exact in double precision, so a draw sitting exactly
  # on the threshold is classified correctly instead of lost to 1.1 != 1.1.
  shortage_level <- baseline - baseline * shortage_pct / 100
  improve_level  <- baseline + baseline * improve_pct / 100

  p_below_replacement <- NA_real_
  if (!is.null(ratio_draws)) {
    if (length(ratio_draws) != length(final_draws))
      stop("wc_uncertainty_summary: ratio_draws must match final_draws length", call. = FALSE)
    rd <- ratio_draws[is.finite(ratio_draws)]
    if (length(rd) > 0L) p_below_replacement <- mean(rd < 1)
  }

  data.frame(
    baseline            = baseline,
    median              = stats::median(fd),
    mean                = mean(fd),
    sd                  = stats::sd(fd),
    pi_lower            = q[1],
    pi_upper            = q[2],
    pi_level            = interval,
    p_shortage_exceeds  = mean(fd <= shortage_level),  # P(workforce falls >= shortage_pct below baseline)
    shortage_pct        = shortage_pct,
    p_access_improves   = mean(fd >= improve_level),    # P(workforce grows >= improve_pct above baseline)
    improve_pct         = improve_pct,
    p_below_replacement = p_below_replacement,          # P(entrants < departures)
    n_draws             = length(fd),
    stringsAsFactors    = FALSE
  )
}

#' One-line human phrasing of an uncertainty summary row, for logs / captions.
wc_uncertainty_sentence <- function(u, unit = "urogynecologists") {
  sprintf(
    paste0("Median %d %s by the horizon (%.0f%% PI %d-%d); ",
           "P(shortage worsens >=%g%%) = %.0f%%, P(access improves >=%g%%) = %.0f%%%s."),
    round(u$median), unit, 100 * u$pi_level, round(u$pi_lower), round(u$pi_upper),
    u$shortage_pct, 100 * u$p_shortage_exceeds,
    u$improve_pct, 100 * u$p_access_improves,
    if (is.na(u$p_below_replacement)) "" else sprintf(", P(below replacement) = %.0f%%", 100 * u$p_below_replacement)
  )
}
