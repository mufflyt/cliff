# Access-wait anchor: an observed appointment-wait SAMPLE -> a gated access fit.
#
# WHY THIS EXISTS. R/wait_adequacy.R inverts ONE mean wait-in-queue into an
# adequacy through a steady-state M/M/s queue. Real access data is not one clean
# number: it is a SAMPLE of observed appointment waits (e.g. third-next-available
# lead times across a panel of clinics), carrying sampling uncertainty. This file
# is the estimator that sits on top of wait_to_adequacy(): it summarises such a
# sample into the mean wait W_q the M/M/s model actually estimates, bootstraps the
# sample to put a confidence interval on the implied adequacy, and returns an
# ACCESS FIT in exactly the shape the capacity-evidence gate consumes
# (capacity_evidence_bundle()/project_absolute_adequacy()/absolute_adequacy_layer()).
#
# THE REFUSAL DISCIPLINE (inherited and sharpened). wait_to_adequacy() already
# refuses to manufacture a shortage (adequacy <= 1) and refuses in the near-balance
# band where the wait curve is vertical. A SAMPLE can straddle that band even when
# its point estimate does not, so this estimator refuses the whole anchor unless
# the entire bootstrap interval stays in the identified (surplus) region
# (require_full_interval, the honest default): a wait sample whose uncertainty
# reaches near-balance does not point-identify an absolute anchor, and the gate is
# told so rather than handed a truncated number. It also refuses a sample too small
# to bootstrap. Pure base R (stats::quantile, sample); the caller supplies the data
# and the queue service parameters (mu, s) with their own provenance -- there is no
# wait-time data committed to this repo.

#' Measure an absolute-adequacy anchor from a sample of observed access waits
#'
#' Turn a sample of observed appointment waits into a gated access fit: the
#' absolute base-year adequacy the relative model ([shiny_urps_adequacy/model.R]
#' `project()`) lacks. The sample mean estimates the M/M/s mean wait-in-queue
#' \eqn{W_q}; that point wait is inverted through [wait_to_adequacy()], and a
#' nonparametric bootstrap over the sample gives a percentile confidence interval
#' on the implied adequacy.
#'
#' The estimand is the MEAN wait (\eqn{W_q}), so the point statistic is the sample
#' mean; `trim` gives an optional trimmed mean for robustness to a few extreme
#' waits, at the cost of a small bias away from \eqn{W_q}. Because a sample can
#' straddle the near-balance region where [wait_to_adequacy()] refuses even when
#' its mean does not, the anchor is reported as identified ONLY when the point
#' inversion is identified AND (with `require_full_interval = TRUE`, the default)
#' every bootstrap replicate is identified too; otherwise it refuses with a reason
#' and `adequacy = NA`. The returned one-row `data.frame` carries `identified` and
#' `adequacy`, so it drops straight into [capacity_evidence_bundle()] as the
#' `access_fit`.
#'
#' @param waits Observed appointment waits: a numeric vector, each `>= 0`, all in
#'   the SAME time unit as `1 / mu` (e.g. if `mu` is new patients per month per
#'   channel, `waits` are in months). `NA`s are dropped and counted.
#' @param mu Per-channel service rate: a single positive finite scalar (completed
#'   new-patient visits per unit time per parallel service channel), in the time
#'   unit that makes `waits` equal to `1 / mu` units.
#' @param s Number of parallel service channels serving the pooled queue: a single
#'   positive integer.
#' @param time_unit Optional label for the shared time unit (recorded for
#'   provenance only; not used in the math). Defaults to `"unit"`.
#' @param trim Fraction (0 to 0.5) trimmed from each end for the point statistic
#'   (a trimmed mean). `0` (default) is the plain sample mean = the \eqn{W_q}
#'   estimand.
#' @param n_boot Bootstrap replicate count: a single positive integer
#'   (default `2000`).
#' @param conf_level Confidence level for the percentile interval (default `0.95`).
#' @param min_n Smallest usable sample size after dropping `NA`s; below it the
#'   anchor refuses (default `5`).
#' @param require_full_interval If `TRUE` (default), refuse unless EVERY bootstrap
#'   replicate is identified (the interval stays clear of the near-balance band).
#'   If `FALSE`, the anchor is identified whenever the point inversion is, and the
#'   interval is taken over the identified replicates only.
#' @param rho_ceiling Utilisation ceiling passed through to [wait_to_adequacy()].
#' @param seed Optional integer seed for the bootstrap (the RNG state is saved and
#'   restored, so calling this does not perturb the caller's stream).
#' @param label Optional character label for the unit of analysis.
#' @return A one-row `data.frame` with `label`, `identified` (logical), `adequacy`
#'   (point anchor, `NA` if refused), `adequacy_lo`/`adequacy_hi` (percentile
#'   interval, `NA` if refused), `conf_level`, `wait` (the point statistic),
#'   `rho` (implied utilisation), `n`, `n_missing`, `mu`, `s`, `time_unit`,
#'   `n_boot`, `frac_identified` (share of bootstrap replicates that were
#'   identified), and `reason` (`NA` when identified, else why it refused).
#' @seealso [wait_to_adequacy()] (the single-wait inverse this wraps),
#'   [capacity_evidence_bundle()], [project_absolute_adequacy()];
#'   `tests/testthat/test-ssot-access-wait-anchor.R` for the guard.
#' @examples
#' # A synthetic audit: 40 waits whose mean sits at a ~1.4-adequacy queue.
#' set.seed(1)
#' wq <- mmc_wait_in_queue(s = 6, mu = 2, rho = 1 / 1.4)      # true mean wait
#' waits <- rgamma(40, shape = 4, scale = wq / 4)             # mean ~ wq
#' fit <- measure_access_wait_anchor(waits, mu = 2, s = 6, n_boot = 300L, seed = 1)
#' fit$identified; round(fit$adequacy, 2)
#' @export
measure_access_wait_anchor <- function(waits, mu, s, time_unit = "unit",
                                       trim = 0, n_boot = 2000L, conf_level = 0.95,
                                       min_n = 5L, require_full_interval = TRUE,
                                       rho_ceiling = WAIT_ADEQUACY_RHO_CEILING,
                                       seed = NULL, label = NA_character_) {
  stopifnot(
    is.numeric(waits), length(waits) >= 1L,
    is.numeric(mu), length(mu) == 1L, !is.na(mu), is.finite(mu), mu > 0,
    is.numeric(s), length(s) == 1L, !is.na(s), s >= 1, s == round(s),
    is.numeric(trim), length(trim) == 1L, !is.na(trim), trim >= 0, trim < 0.5,
    is.numeric(n_boot), length(n_boot) == 1L, !is.na(n_boot), n_boot >= 1, n_boot == round(n_boot),
    is.numeric(conf_level), length(conf_level) == 1L, conf_level > 0, conf_level < 1,
    is.numeric(min_n), length(min_n) == 1L, min_n >= 1, min_n == round(min_n),
    is.logical(require_full_interval), length(require_full_interval) == 1L
  )
  s <- as.integer(s)
  n_boot <- as.integer(n_boot)

  n_missing <- sum(is.na(waits))
  w <- waits[!is.na(waits)]
  if (length(w) > 0L && any(w < 0)) {
    stop("measure_access_wait_anchor: all waits must be >= 0 (a negative wait is impossible).")
  }
  n <- length(w)

  stat_fun <- function(x) mean(x, trim = trim)
  alpha <- 1 - conf_level

  one_row <- function(identified, adequacy, adequacy_lo, adequacy_hi, wait, rho,
                       frac_identified, reason) {
    data.frame(
      label = as.character(label)[1], identified = identified,
      adequacy = adequacy, adequacy_lo = adequacy_lo, adequacy_hi = adequacy_hi,
      conf_level = conf_level, wait = wait, rho = rho,
      n = n, n_missing = n_missing, mu = mu, s = s,
      time_unit = as.character(time_unit)[1], n_boot = n_boot,
      frac_identified = frac_identified, reason = reason,
      stringsAsFactors = FALSE
    )
  }

  # Too small to bootstrap a defensible interval -> refuse (no anchor).
  if (n < min_n) {
    return(one_row(FALSE, NA_real_, NA_real_, NA_real_, NA_real_, NA_real_, NA_real_,
                   sprintf("sample too small: n = %d < min_n = %d", n, min_n)))
  }

  # Point estimate: the sample (trimmed) mean estimates W_q; invert it.
  point_wait <- stat_fun(w)
  point_fit  <- wait_to_adequacy(point_wait, mu = mu, s = s, rho_ceiling = rho_ceiling)

  # Bootstrap the sample; invert each replicate's mean wait.
  if (!is.null(seed)) {
    has_old <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
    if (has_old) old_seed <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
    on.exit(if (has_old) assign(".Random.seed", old_seed, envir = globalenv())
            else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE))
              rm(".Random.seed", envir = globalenv()), add = TRUE)
    set.seed(seed)
  }
  boot_adeq <- numeric(n_boot)
  boot_idn  <- logical(n_boot)
  for (b in seq_len(n_boot)) {
    wb  <- stat_fun(sample(w, n, replace = TRUE))
    fit <- wait_to_adequacy(wb, mu = mu, s = s, rho_ceiling = rho_ceiling)
    boot_idn[b]  <- isTRUE(fit$identified)
    boot_adeq[b] <- if (isTRUE(fit$identified)) fit$adequacy else NA_real_
  }
  frac_identified <- mean(boot_idn)

  # Refuse if the point does not identify, or (default) any replicate strays into
  # the near-balance / no-queue region: an interval that reaches there does not
  # point-identify an absolute anchor.
  if (!isTRUE(point_fit$identified)) {
    return(one_row(FALSE, NA_real_, NA_real_, NA_real_, point_wait, NA_real_,
                   frac_identified, point_fit$reason))
  }
  if (require_full_interval && frac_identified < 1) {
    return(one_row(FALSE, NA_real_, NA_real_, NA_real_, point_wait, point_fit$rho,
                   frac_identified,
                   sprintf(paste0("%.1f%% of bootstrap replicates fell in the unidentified ",
                                  "near-balance/no-queue region; interval does not point-identify ",
                                  "an anchor"), 100 * (1 - frac_identified))))
  }

  ci <- stats::quantile(boot_adeq[boot_idn], probs = c(alpha / 2, 1 - alpha / 2),
                        names = FALSE, na.rm = TRUE)
  one_row(TRUE, point_fit$adequacy, ci[1], ci[2], point_wait, point_fit$rho,
          frac_identified, NA_character_)
}
