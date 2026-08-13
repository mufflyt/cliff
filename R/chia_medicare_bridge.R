# CHIA <-> Medicare all-payer workload bridge — single source of truth.
#
# WHY THIS EXISTS. cliff's Module B/C attribution and the life-course staffing
# conversion (demand_lifecourse/supply-staffing_conversion.R) measure clinical
# workload on a MEDICARE fee-for-service basis (CMS Part B by-Provider-and-Service
# for the URPS anchor procedures, R/urps_procedure_codes.R), under the standing
# assumption that "all-payer bias largely cancels" because both the numerator and
# the denominator are Medicare dollars. That cancellation is only credible where
# Medicare actually observes most of the care. It does not for pelvic-floor care
# delivered to women under 65, whom Medicare barely sees.
#
# WHAT THIS PROVIDES. An age-graded multiplier that lifts a Medicare-observed
# workload to an all-payer workload:
#
#     all_payer_volume(band) = medicare_volume(band) * multiplier(band)
#     multiplier(band)       = 1 / medicare_capture(band)
#
# where medicare_capture(band) is the share of the band's all-payer clinical
# volume that appears in Medicare fee-for-service. The multiplier is calibrated
# from CHIA -- the Massachusetts Center for Health Information and Analysis, whose
# All-Payer Claims Database (APCD) reports commercial + Medicaid + Medicare volume
# -- by taking the CHIA all-payer count over the Medicare FFS count for the URPS
# anchor procedures, by age band. Capture rises steeply with age (Medicare is the
# primary payer at 65+, near-absent below it), so the multiplier is the model's
# age gradient on payer mix.
#
# THE IDENTIFIABILITY LIMIT (mirrors R/wait_adequacy.R). Reconstructing an
# all-payer volume by scaling up a Medicare volume is only trustworthy when
# Medicare observes a substantial share of the truth. Below a capture floor
# (CHIA_BRIDGE_MIN_MEDICARE_CAPTURE) the answer is dominated by volume Medicare
# never saw -- you are extrapolating, not bridging -- so the bridge REFUSES
# (all_payer = NA, identified = FALSE, with a reason) rather than manufacture a
# number from a near-empty base. For URPS this means the 65+ bands resolve and the
# under-65 band is declined: that care must come from an all-payer source, not
# from scaling Medicare.
#
# CALIBRATION STATUS (mirrors R/dpmm_contract.R). The multipliers ship as a
# PROVISIONAL, illustrative contract with calibration_status = "not_calibrated";
# the bridge refuses every not_calibrated band, so the placeholder levels can
# never masquerade as a result. A real CHIA/Medicare extract replaces the levels
# and flips the status to "calibrated". Pure base R; no path/data dependencies.

# CHIA_BRIDGE_MIN_MEDICARE_CAPTURE
#   Meaning : the smallest Medicare fee-for-service capture share (Medicare volume
#             / all-payer volume) at which the all-payer bridge is still declared
#             IDENTIFIED. At or below it, most of the all-payer volume is unobserved
#             by Medicare, so scaling the Medicare base up to all-payer is
#             extrapolation and the bridge refuses.
#   Units   : dimensionless share in (0, 1).
#   Range   : a single scalar strictly between 0 and 1.
#   Source  : methodological choice for this estimator. 0.5 requires Medicare to
#             observe at least half of a band's all-payer volume before the other
#             half is reconstructed by scaling; caps the admissible multiplier at
#             1 / 0.5 = 2x.
CHIA_BRIDGE_MIN_MEDICARE_CAPTURE <- 0.5
stopifnot(
  is.numeric(CHIA_BRIDGE_MIN_MEDICARE_CAPTURE), length(CHIA_BRIDGE_MIN_MEDICARE_CAPTURE) == 1L,
  !is.na(CHIA_BRIDGE_MIN_MEDICARE_CAPTURE),
  CHIA_BRIDGE_MIN_MEDICARE_CAPTURE > 0, CHIA_BRIDGE_MIN_MEDICARE_CAPTURE < 1,
  CHIA_BRIDGE_MIN_MEDICARE_CAPTURE == 0.5   # pin the capture floor; a change must be deliberate
)

# CHIA_BRIDGE_MAX_MULTIPLIER
#   Meaning : the algebraic image of the capture floor: the largest all-payer /
#             Medicare multiplier the bridge will ever apply. A band whose
#             multiplier exceeds it is refused.
#   Units   : dimensionless (all-payer volume per unit Medicare volume).
#   Source  : derived, 1 / CHIA_BRIDGE_MIN_MEDICARE_CAPTURE; not independent.
CHIA_BRIDGE_MAX_MULTIPLIER <- 1 / CHIA_BRIDGE_MIN_MEDICARE_CAPTURE
stopifnot(
  isTRUE(all.equal(CHIA_BRIDGE_MAX_MULTIPLIER, 1 / CHIA_BRIDGE_MIN_MEDICARE_CAPTURE)),
  CHIA_BRIDGE_MAX_MULTIPLIER > 1
)

#' The CHIA <-> Medicare age-banded bridge contract (provisional)
#'
#' Return the age-banded all-payer/Medicare bridge as a tidy contract:
#' one row per age band with the Medicare fee-for-service capture share, the
#' implied all-payer multiplier (`1 / capture`), and a `calibration_status`.
#'
#' The shipped levels are PROVISIONAL and illustrative
#' (`calibration_status = "not_calibrated"`): they encode the expected age
#' gradient (capture near zero below 65, then rising 65 -> 75 -> 85+ as Medicare
#' Advantage penetration falls and fee-for-service dominates) but are NOT real
#' CHIA/Medicare figures. Because [bridge_medicare_to_all_payer()] refuses every
#' `not_calibrated` band, these placeholders can never produce an all-payer
#' number; a real CHIA APCD / Medicare FFS extract for the URPS anchor procedures
#' replaces `medicare_capture` and sets `calibration_status = "calibrated"`.
#'
#' @details Bands are left-closed `[age_lower, next age_lower)`, split at the
#'   Medicare eligibility boundary (65) so the pre-Medicare band is isolated. The
#'   65+ split (65/75/85) carries the within-eligible age gradient.
#' @return A `data.frame` with columns `age_lower` (integer), `medicare_capture`
#'   (double in `(0, 1]`), `multiplier` (double, `1 / medicare_capture`), and
#'   `calibration_status` (character).
#' @seealso [bridge_medicare_to_all_payer()], [validate_chia_bridge_contract()];
#'   `R/urps_procedure_codes.R` for the anchor procedures the extract keys on.
#' @family chia-medicare-bridge
#' @examples
#' chia_bridge_contract()
#' @export
chia_bridge_contract <- function() {
  capture <- c(0.05, 0.72, 0.82, 0.88)   # provisional; under-65 near-zero, rising with age
  d <- data.frame(
    age_lower          = c(0L, 65L, 75L, 85L),
    medicare_capture   = capture,
    multiplier         = 1 / capture,
    calibration_status = rep("not_calibrated", length(capture)),
    stringsAsFactors   = FALSE
  )
  validate_chia_bridge_contract(d)
  d
}

#' Validate a CHIA <-> Medicare bridge contract (hard-fail on any violation)
#'
#' Enforce the bridge contract schema: the required columns, strictly increasing
#' left-closed age bands, capture shares in `(0, 1]`, the `multiplier` being
#' exactly `1 / medicare_capture` (the two encodings can never disagree), and a
#' closed `calibration_status` vocabulary. Returns the contract invisibly so it
#' can wrap a constructor.
#'
#' @param contract A candidate bridge contract `data.frame`.
#' @return The validated `contract`, invisibly.
#' @seealso [chia_bridge_contract()]
#' @family chia-medicare-bridge
#' @examples
#' validate_chia_bridge_contract(chia_bridge_contract())
#' @export
validate_chia_bridge_contract <- function(contract) {
  stopifnot(
    is.data.frame(contract),
    all(c("age_lower", "medicare_capture", "multiplier", "calibration_status") %in% names(contract)),
    nrow(contract) >= 1L,
    is.numeric(contract$age_lower), !anyNA(contract$age_lower),
    !is.unsorted(contract$age_lower, strictly = TRUE),          # strictly increasing bands
    is.numeric(contract$medicare_capture), !anyNA(contract$medicare_capture),
    all(contract$medicare_capture > 0), all(contract$medicare_capture <= 1),
    is.numeric(contract$multiplier), !anyNA(contract$multiplier),
    isTRUE(all.equal(contract$multiplier, 1 / contract$medicare_capture)),   # lockstep encodings
    is.character(contract$calibration_status),
    all(contract$calibration_status %in% c("calibrated", "not_calibrated"))
  )
  invisible(contract)
}

#' Lift a Medicare-observed workload to an all-payer workload, by age band
#'
#' Apply the age-graded CHIA/Medicare multiplier to a Medicare fee-for-service
#' workload, band by band, returning the implied all-payer workload where the
#' bridge is identified and refusing where it is not.
#'
#' A band resolves only when its contract row is `calibrated` AND its Medicare
#' capture share is at least `min_capture` (equivalently its multiplier is at
#' most `1 / min_capture`). Otherwise the all-payer volume is `NA` and
#' `identified` is `FALSE` with a `reason` — the bridge never fabricates an
#' all-payer number from a near-empty Medicare base or from an uncalibrated band.
#'
#' @param medicare_by_band A `data.frame` with columns `age_lower` (matching the
#'   contract's bands) and `medicare_volume` (a non-negative workload measure,
#'   e.g. service volume or work RVUs). One row per band.
#' @param contract A bridge contract, defaulting to [chia_bridge_contract()].
#'   Validated via [validate_chia_bridge_contract()].
#' @param min_capture The Medicare-capture floor for identifiability. Defaults to
#'   the SSOT [CHIA_BRIDGE_MIN_MEDICARE_CAPTURE].
#' @return A `data.frame`, one row per input band, with `age_lower`,
#'   `medicare_volume`, `medicare_capture`, `multiplier`, `calibration_status`,
#'   `all_payer_volume` (`NA` when unidentified), `identified` (logical), and
#'   `reason` (`NA` when identified).
#' @seealso [chia_bridge_all_payer_total()] to aggregate the identified bands;
#'   `demand_lifecourse/supply-staffing_conversion.R` for the workload path this
#'   feeds; `tests/testthat/test-ssot-chia-medicare-bridge.R` for the guard.
#' @family chia-medicare-bridge
#' @examples
#' md <- data.frame(age_lower = c(0L, 65L, 75L, 85L),
#'                  medicare_volume = c(10, 400, 300, 120))
#' # shipped contract is provisional -> every band is refused:
#' bridge_medicare_to_all_payer(md)$identified
#' @export
bridge_medicare_to_all_payer <- function(medicare_by_band,
                                         contract = chia_bridge_contract(),
                                         min_capture = CHIA_BRIDGE_MIN_MEDICARE_CAPTURE) {
  validate_chia_bridge_contract(contract)
  stopifnot(
    is.data.frame(medicare_by_band),
    all(c("age_lower", "medicare_volume") %in% names(medicare_by_band)),
    is.numeric(medicare_by_band$medicare_volume), !anyNA(medicare_by_band$medicare_volume),
    all(medicare_by_band$medicare_volume >= 0),
    all(medicare_by_band$age_lower %in% contract$age_lower),   # every requested band is in the contract
    is.numeric(min_capture), length(min_capture) == 1L, !is.na(min_capture),
    min_capture > 0, min_capture <= 1
  )

  m <- merge(medicare_by_band, contract, by = "age_lower", all.x = TRUE, sort = TRUE)

  calibrated <- m$calibration_status == "calibrated"
  above_floor <- m$medicare_capture >= min_capture
  identified <- calibrated & above_floor

  reason <- rep(NA_character_, nrow(m))
  reason[!calibrated] <- "band not calibrated: no CHIA/Medicare extract for this band"
  reason[calibrated & !above_floor] <- sprintf(
    "Medicare capture %.2f < floor %.2f (multiplier %.2f > %.2f): all-payer not identified from Medicare",
    m$medicare_capture[calibrated & !above_floor], min_capture,
    m$multiplier[calibrated & !above_floor], 1 / min_capture)

  all_payer <- ifelse(identified, m$medicare_volume * m$multiplier, NA_real_)

  data.frame(
    age_lower          = m$age_lower,
    medicare_volume    = m$medicare_volume,
    medicare_capture   = m$medicare_capture,
    multiplier         = m$multiplier,
    calibration_status = m$calibration_status,
    all_payer_volume   = all_payer,
    identified         = identified,
    reason             = reason,
    stringsAsFactors   = FALSE
  )
}

#' Aggregate an all-payer bridge result over its identified bands
#'
#' Sum the identified all-payer volume and report whether every requested band
#' resolved. The `fully_identified` flag is the hook the capacity-evidence gate
#' keys on: an all-payer workload total is only admissible when no band was
#' silently dropped.
#'
#' @param bridged The `data.frame` returned by [bridge_medicare_to_all_payer()].
#' @return A list with `total` (sum of `all_payer_volume` over identified bands;
#'   `NA_real_` if none), `fully_identified` (logical: all input bands
#'   identified), `n_identified`, `n_total`, and `unidentified_bands` (the
#'   `age_lower` values that were refused).
#' @seealso [bridge_medicare_to_all_payer()]
#' @family chia-medicare-bridge
#' @examples
#' md <- data.frame(age_lower = c(65L, 75L), medicare_volume = c(400, 300))
#' chia_bridge_all_payer_total(bridge_medicare_to_all_payer(md))
#' @export
chia_bridge_all_payer_total <- function(bridged) {
  stopifnot(
    is.data.frame(bridged),
    all(c("age_lower", "all_payer_volume", "identified") %in% names(bridged)),
    is.logical(bridged$identified)
  )
  ident <- bridged$identified
  list(
    total              = if (any(ident)) sum(bridged$all_payer_volume[ident]) else NA_real_,
    fully_identified   = all(ident),
    n_identified       = sum(ident),
    n_total            = nrow(bridged),
    unidentified_bands = bridged$age_lower[!ident]
  )
}
