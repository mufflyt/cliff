# Wait-time -> adequacy inversion (M/M/s / Erlang-C) — single source of truth.
#
# WHY THIS EXISTS. The canonical adequacy model (shiny_urps_adequacy/model.R::project())
# is a RELATIVE index: adequacy(y) = (effective(y)/effective(2025)) / demand_growth(y),
# normalised so adequacy(2025) == 1. It *assumes* 2025 is in supply-demand balance and can
# only report drift away from that anchor — it has no external, absolute level. A wait-time
# signal (e.g. third-next-available appointment) is a *revealed* measure of imbalance and is
# therefore an attractive candidate to anchor the absolute level the index lacks.
#
# WHAT THIS PROVIDES. A pure, data-free transform that inverts a steady-state M/M/s
# (Erlang-C) queue: given an observed mean wait-in-queue and the clinic service parameters
# (number of parallel service channels s and per-channel service rate mu), it recovers the
# utilisation rho = demand / service-capacity and reports adequacy = service-capacity / demand
# = 1 / rho, on the SAME "supply / demand, 1.0 == balance" convention the rest of cliff uses.
#
# THE IDENTIFIABILITY LIMIT (the whole point). A stationary M/M/s queue exists only for
# rho < 1, i.e. adequacy > 1. Mean wait W_q is a strictly increasing function of rho on
# (0, 1): W_q -> 0 as rho -> 0 (adequacy -> Inf) and W_q -> Inf as rho -> 1- (adequacy -> 1+).
# Consequences, both enforced below:
#   (1) ANY finite positive wait maps to rho < 1, hence adequacy > 1. Wait time ALONE can
#       therefore never evidence adequacy <= 1 (a persistently under-resourced service). The
#       inverse is structurally incapable of manufacturing a shortage verdict, and this module
#       will never return an adequacy <= 1 — it refuses rather than fabricate one.
#   (2) As rho -> 1-, dW_q/d(adequacy) -> Inf: a whole neighbourhood of near-balance adequacies
#       fits the same (long) wait within any measurement noise. Near balance the inverse is not
#       identified, so it REFUSES (returns adequacy = NA, identified = FALSE, with a reason)
#       once the implied utilisation reaches WAIT_ADEQUACY_RHO_CEILING.
#
# This module deliberately does NOT modify project(): the effective-FTE adequacy identity is
# hard-guarded by validate_scenario_projection()/validate_scenario_contract(), and there is no
# wait-time data committed to this repo. It is a standalone estimator whose inputs the caller
# supplies. Pure base R (stats::uniroot); no path/data dependencies — safe to source anywhere.

# WAIT_ADEQUACY_RHO_CEILING
#   Meaning : the largest server utilisation rho = demand/capacity at which the wait -> adequacy
#             inversion is still declared IDENTIFIED. At or above it the mean wait is so
#             hypersensitive to rho (dW_q/drho -> Inf as rho -> 1) that a band of near-balance
#             adequacies is observationally indistinguishable, so the estimator refuses.
#   Units   : dimensionless utilisation (fraction of service capacity in use), in (0, 1).
#   Range   : a single scalar strictly between 0 and 1.
#   Source  : methodological choice for this estimator. 0.99 admits estimates down to an
#             adequacy floor of 1/0.99 ~= 1.0101 (capacity ~1% above demand) and refuses closer
#             to balance, where the M/M/s wait curve is effectively vertical.
WAIT_ADEQUACY_RHO_CEILING <- 0.99
stopifnot(
  is.numeric(WAIT_ADEQUACY_RHO_CEILING), length(WAIT_ADEQUACY_RHO_CEILING) == 1L,
  !is.na(WAIT_ADEQUACY_RHO_CEILING),
  WAIT_ADEQUACY_RHO_CEILING > 0, WAIT_ADEQUACY_RHO_CEILING < 1,
  WAIT_ADEQUACY_RHO_CEILING == 0.99   # pin the identifiability ceiling; a change must be deliberate
)

# WAIT_ADEQUACY_MIN_IDENTIFIED
#   Meaning : the smallest adequacy (= supply-capacity / demand) this estimator will ever assert.
#             It is the algebraic image of the utilisation ceiling: adequacy = 1 / rho, so the
#             ceiling on rho is a floor on adequacy. Any inverted value below it is REFUSED.
#   Units   : dimensionless supply/demand ratio (1.0 == balance), same convention as adeq_eff.
#   Source  : derived, 1 / WAIT_ADEQUACY_RHO_CEILING; not an independent constant.
WAIT_ADEQUACY_MIN_IDENTIFIED <- 1 / WAIT_ADEQUACY_RHO_CEILING
stopifnot(
  isTRUE(all.equal(WAIT_ADEQUACY_MIN_IDENTIFIED, 1 / WAIT_ADEQUACY_RHO_CEILING)),
  WAIT_ADEQUACY_MIN_IDENTIFIED > 1   # the floor is strictly in the surplus region, by construction
)

#' Erlang-B blocking probability (numerically stable recursion)
#'
#' The Erlang-B loss formula B(s, a) for an M/M/s/s system: the probability that
#' all `s` channels are busy given offered load `a` (Erlangs). Computed by the
#' standard iterative recurrence `B(0) = 1`, `B(k) = a B(k-1) / (k + a B(k-1))`,
#' which avoids the overflow of forming `a^s / s!` directly. Used here only as
#' the building block for [erlang_c()].
#'
#' @param s Number of parallel service channels: a single positive integer
#'   (or integer-valued double).
#' @param a Offered load in Erlangs (`lambda / mu`): a single non-negative finite
#'   scalar. Need not be `< s` (Erlang-B is defined for all loads).
#' @return A single probability in `[0, 1]`.
#' @seealso [erlang_c()], which converts this to the delay probability.
#' @family wait-adequacy
#' @examples
#' erlang_b(3, 2)      # offered load 2 Erlangs across 3 channels
#' @export
erlang_b <- function(s, a) {
  stopifnot(
    is.numeric(s), length(s) == 1L, !is.na(s), s >= 1, s == round(s),
    is.numeric(a), length(a) == 1L, !is.na(a), is.finite(a), a >= 0
  )
  b <- 1                        # B(0, a) = 1
  for (k in seq_len(s)) b <- (a * b) / (k + a * b)
  b
}

#' Erlang-C delay probability (probability an arrival must wait)
#'
#' The Erlang-C formula C(s, a): in a stationary M/M/s queue with `s` servers and
#' offered load `a = lambda / mu` Erlangs, the probability that an arriving
#' customer finds all servers busy and joins the queue. Derived from Erlang-B via
#' `C = s B / (s - a (1 - B))`. Requires a stable queue, `a < s`
#' (equivalently utilisation `rho = a / s < 1`); an unstable load fails loudly.
#'
#' @param s Number of parallel servers: a single positive integer.
#' @param a Offered load in Erlangs (`lambda / mu`): a single non-negative scalar,
#'   strictly less than `s` (stability).
#' @return A single probability in `[0, 1]`.
#' @seealso [erlang_b()]; [mmc_wait_in_queue()] for the mean wait this feeds.
#' @family wait-adequacy
#' @examples
#' erlang_c(3, 2)      # P(wait) with 3 servers, 2 Erlangs offered
#' @export
erlang_c <- function(s, a) {
  stopifnot(
    is.numeric(s), length(s) == 1L, !is.na(s), s >= 1, s == round(s),
    is.numeric(a), length(a) == 1L, !is.na(a), is.finite(a), a >= 0,
    a < s   # stationary M/M/s requires rho = a/s < 1
  )
  b <- erlang_b(s, a)
  (s * b) / (s - a * (1 - b))
}

#' Mean wait in queue for a stationary M/M/s system
#'
#' Expected time an arrival spends waiting *before* service (W_q, excluding the
#' service time itself) in an M/M/s queue with `s` servers, per-server service
#' rate `mu`, and utilisation `rho`. Uses `W_q = C(s, a) / (s mu (1 - rho))` with
#' `a = rho s`. Returned in the reciprocal time unit of `mu` (if `mu` is
#' patients per month, `W_q` is in months).
#'
#' @param s Number of parallel servers: a single positive integer.
#' @param mu Per-server service rate: a single positive finite scalar (completed
#'   visits per unit time per server).
#' @param rho Server utilisation `lambda / (s mu)`: a single scalar in `(0, 1)`.
#' @return A single non-negative mean wait, in `1 / mu` time units. Strictly
#'   increasing in `rho`; `-> 0` as `rho -> 0` and `-> Inf` as `rho -> 1-`.
#' @seealso [wait_to_adequacy()], the inverse of this map.
#' @family wait-adequacy
#' @examples
#' mmc_wait_in_queue(s = 4, mu = 2, rho = 0.8)
#' @export
mmc_wait_in_queue <- function(s, mu, rho) {
  stopifnot(
    is.numeric(s), length(s) == 1L, !is.na(s), s >= 1, s == round(s),
    is.numeric(mu), length(mu) == 1L, !is.na(mu), is.finite(mu), mu > 0,
    is.numeric(rho), length(rho) == 1L, !is.na(rho), rho > 0, rho < 1
  )
  erlang_c(s, rho * s) / (s * mu * (1 - rho))
}

#' Invert an observed clinic wait time into an adequacy estimate (M/M/s)
#'
#' Recover the supply/demand adequacy implied by an observed mean wait-in-queue,
#' under a steady-state M/M/s (Erlang-C) model of the clinic. Solves
#' `mmc_wait_in_queue(s, mu, rho) == wait` for the utilisation `rho` and reports
#' `adequacy = 1 / rho` on cliff's standard "supply / demand, 1.0 == balance"
#' convention.
#'
#' The estimator is deliberately partial and says so. Because mean wait strictly
#' increases in `rho` over `(0, 1)`, every finite positive wait implies `rho < 1`
#' and hence `adequacy > 1`: wait time alone can never evidence a shortage
#' (`adequacy <= 1`), so this function never returns one — it refuses. It also
#' refuses in the near-balance region `rho >= WAIT_ADEQUACY_RHO_CEILING`, where
#' the wait curve is effectively vertical and a band of adequacies is
#' observationally indistinguishable. Refusal is reported as `identified = FALSE`
#' with `adequacy = NA_real_` and a human-readable `reason`, not by erroring.
#'
#' @param wait Observed mean wait in queue: a single positive finite scalar, in
#'   the SAME time unit as `1 / mu` (e.g. if `mu` is visits per month, `wait` is
#'   in months). `wait <= 0` means no queue and is reported as unbounded surplus.
#' @param mu Per-server service rate: a single positive finite scalar (completed
#'   new-patient visits per unit time per parallel service channel).
#' @param s Number of parallel service channels (clinic capacity units): a single
#'   positive integer. Defaults to `1` (an M/M/1 clinic).
#' @param rho_ceiling Utilisation above which the inverse is declared not
#'   identified. Defaults to the SSOT [WAIT_ADEQUACY_RHO_CEILING].
#' @return A one-row `data.frame` with columns: `wait`, `mu`, `s` (the inputs);
#'   `rho` (implied utilisation, `NA` if unidentified); `adequacy`
#'   (`1 / rho`, `NA` if unidentified); `identified` (logical); and `reason`
#'   (`NA` when identified, else why it refused).
#' @seealso [mmc_wait_in_queue()] (the forward map this inverts);
#'   `shiny_urps_adequacy/model.R` for the relative adequacy index this could
#'   anchor; `tests/testthat/test-ssot-wait-adequacy.R` for the guard.
#' @family wait-adequacy
#' @examples
#' # A 4-channel clinic serving ~2 new patients/channel/month, observed 0.5-month wait:
#' wait_to_adequacy(wait = 0.5, mu = 2, s = 4)
#' # Very long wait -> near balance -> refused rather than pinned:
#' wait_to_adequacy(wait = 1e6, mu = 2, s = 4)$identified
#' @export
wait_to_adequacy <- function(wait, mu, s = 1L, rho_ceiling = WAIT_ADEQUACY_RHO_CEILING) {
  stopifnot(
    is.numeric(wait), length(wait) == 1L, !is.na(wait), is.finite(wait),
    is.numeric(mu), length(mu) == 1L, !is.na(mu), is.finite(mu), mu > 0,
    is.numeric(s), length(s) == 1L, !is.na(s), s >= 1, s == round(s),
    is.numeric(rho_ceiling), length(rho_ceiling) == 1L, !is.na(rho_ceiling),
    rho_ceiling > 0, rho_ceiling < 1
  )
  s <- as.integer(s)

  out <- function(rho, adequacy, identified, reason) {
    data.frame(wait = wait, mu = mu, s = s, rho = rho, adequacy = adequacy,
               identified = identified, reason = reason,
               stringsAsFactors = FALSE)
  }

  # No queue observed -> demand well below capacity; surplus is real but unbounded
  # (the inverse cannot pin how large), so it is not a point-identified adequacy.
  if (wait <= 0) {
    return(out(NA_real_, NA_real_, FALSE,
               "wait <= 0: no queue; adequacy is unbounded above and not point-identified"))
  }

  # Mean wait is strictly increasing in rho, so a unique root exists in (0, ceiling]
  # iff the observed wait does not exceed the wait at the ceiling. If it does, the
  # implied utilisation is in the refused near-balance band.
  wait_at_ceiling <- mmc_wait_in_queue(s, mu, rho_ceiling)
  if (wait >= wait_at_ceiling) {
    return(out(NA_real_, NA_real_, FALSE,
               sprintf(paste0("observed wait (%.4g) implies utilisation >= ceiling %.4g ",
                              "(adequacy <= %.4g): near-balance region is not identified"),
                       wait, rho_ceiling, 1 / rho_ceiling)))
  }

  rho <- stats::uniroot(
    function(r) mmc_wait_in_queue(s, mu, r) - wait,
    lower = .Machine$double.eps, upper = rho_ceiling,
    tol = .Machine$double.eps^0.5
  )$root

  adequacy <- 1 / rho
  # Structural invariant: a finite positive wait can only ever land in the surplus
  # region. If it did not, refuse rather than emit an adequacy <= the floor.
  if (!is.finite(adequacy) || adequacy < WAIT_ADEQUACY_MIN_IDENTIFIED) {
    return(out(NA_real_, NA_real_, FALSE,
               "inverted adequacy fell below the identified floor; refused"))
  }
  out(rho, adequacy, TRUE, NA_character_)
}
