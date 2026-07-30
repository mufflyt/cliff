# SSOT: the study observed-window start year (year_min_allowed below). Sourced once; guarded so a caller that
# already loaded the constants is not re-sourced.
if (!exists("WORKFORCE_OBSERVED_START_YEAR")) source(here::here("R", "workforce_constants.R"))

#' @title Validate Workforce Truth Contract
#'
#' @description
#' Semantic validator that enforces what "active", "retired", and "entry" mean
#' across the longitudinal workforce analysis. Complements mechanical validators
#' (row counts, geometry) with meaning-level checks that protect published
#' results.
#'
#' Directly guards against the 213-oscillator regression (Fix 2): a physician
#' cannot be reactivated into the workforce from a weak signal such as a single
#' Open Payment. This validator fires if that invariant is violated.
#'
#' @param workforce_tbl Data frame. Physician-level panel with one row per
#'   physician per year. Must contain the columns named by the `*_col` params.
#' @param npi_col Column holding the physician NPI identifier.
#' @param year_col Column holding the analysis year.
#' @param certification_year_col Column holding ABOG board certification year.
#' @param retired_col Logical column: TRUE = excluded from cohort
#'   (retired/inactive).
#' @param conflict_col Logical column: TRUE = retirement_data_conflict detected.
#' @param conflict_reason_col Character column: reason for conflict (e.g.
#'   "weak_cessation_only_billing_recent").
#' @param deceased_col Character column: "Y" if deceased.
#' @param output_dir Directory for violation CSV output.
#' @param strict If TRUE (default), `stop()` when any error-severity violation
#'   is found. Warning-severity violations always produce `warning()` only.
#'
#' @return Named list:
#'   - `valid` [logical]: TRUE if no error-severity violations.
#'   - `violation_rows` [data.frame]: Rows with severity == "error".
#'   - `warning_rows` [data.frame]: Rows with severity == "warning".
#'   - `violation_path` [character]: Path to saved violation CSV.
#'   - `contract_summary` [data.frame]: Counts by year x entry_type x signal.
#'   - `oscillator_rates` [data.frame]: Yearly pct_newly_certified /
#' pct_reactivated.
#'   - `n_violations` [integer]: Count of error-severity rows.
#'
#' @section Violation taxonomy:
#' | violation_reason | severity | condition |
#' |---|---|---|
#' | missing_npi | error | npi is NA or "" |
#' | missing_year | error | year is NA |
#' | missing_retirement_state | error | is_retired_for_cohorting is NA |
#' | future_certification_year | error | newly_certified AND cert_year > year+1 |
#' | weak_signal_reactivation | error | reactivated AND signal == "weak" |
#' | deceased_marked_active | error | deceased=="Y" AND not retired |
#' | inactive_but_marked_active | error | active AND no signal of any kind |
#' | reactivation_without_gap | error | reactivated AND weak signal AND gap <= 1yr |
#' | old_certification_first_appearance | warning | late_observation AND cert_year < year-2 |
#'
#' @section Entry type taxonomy:
#' - `newly_certified`: First appearance AND cert_year >= year - 1
#' - `late_observation`: First appearance AND cert_year < year - 1 (NPPES lag)
#' - `reactivated`: Previously retired, now active
#' - `continuing`: Active in prior year, still active
#'
#' @export
validate_workforce_truth_contract <- function(
    workforce_tbl,
    npi_col                = "npi",
    year_col               = "year",
    certification_year_col = "certification_year",
    retired_col            = "is_retired_for_cohorting",
    conflict_col           = "retirement_data_conflict",
    conflict_reason_col    = "conflict_reason",
    deceased_col           = "deceased",
    output_dir             = here::here("artifacts", "validation"),
    strict                 = TRUE
) {
  message("[truth_contract] Starting workforce semantic validation")
  message("[truth_contract] Input rows: ", format(nrow(workforce_tbl), big.mark = ","))

  # ── Required column check ──────────────────────────────────────────────────
  required_cols <- c(npi_col, year_col, certification_year_col,
                     retired_col, conflict_col, conflict_reason_col)
  missing_cols  <- setdiff(required_cols, names(workforce_tbl))
  if (length(missing_cols) > 0L) {
    stop("[truth_contract] Missing required columns: ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  has_deceased_col <- deceased_col %in% names(workforce_tbl)

  # ── Normalise column names for internal use ────────────────────────────────
  tbl <- workforce_tbl |>
    dplyr::mutate(
      truth_npi              = as.character(.data[[npi_col]]),
      truth_year             = as.integer(.data[[year_col]]),
      truth_cert_year        = as.integer(.data[[certification_year_col]]),
      truth_is_retired       = as.logical(.data[[retired_col]]),
      truth_has_conflict     = as.logical(.data[[conflict_col]]),
      truth_conflict_reason  = as.character(.data[[conflict_reason_col]]),
      truth_deceased         = if (has_deceased_col)
        as.character(.data[[deceased_col]]) else NA_character_
    )

  # ── Year-bounds guard (study scope 2013–2023) ─────────────────────────────
  year_min_allowed <- WORKFORCE_OBSERVED_START_YEAR   # SSOT: R/workforce_constants.R
  year_max_allowed <- WORKFORCE_OBSERVED_END_YEAR     # SSOT: observation-confirmable end 2023 (distinct from latest-data 2024)
  out_of_range_years <- tbl$truth_year[
    !is.na(tbl$truth_year) &
      (tbl$truth_year < year_min_allowed | tbl$truth_year > year_max_allowed)
  ]
  if (length(out_of_range_years) > 0L) {
    stop(
      sprintf(
        "[truth_contract] %d rows have truth_year outside study scope [%d, %d]: %s",
        length(out_of_range_years),
        year_min_allowed,
        year_max_allowed,
        paste(sort(unique(out_of_range_years)), collapse = ", ")
      ),
      call. = FALSE
    )
  }
  message(sprintf("[truth_contract] Year bounds OK: all years in [%d, %d]",
                  year_min_allowed, year_max_allowed))

  # ── Derive transition variables (requires ordering by npi + year) ──────────
  # Round 299 fix: bare column names in tidyselect context (arrange/group_by/
  # count) — .data$col deprecated since tidyselect 1.2.0; use bare names.
  transition_tbl <- tbl |>
    dplyr::arrange(truth_npi, truth_year) |>
    dplyr::group_by(truth_npi) |>
    dplyr::mutate(
      prior_seen     = dplyr::row_number() > 1L,
      prior_retired  = dplyr::lag(.data$truth_is_retired),
      prior_year     = dplyr::lag(.data$truth_year),

      # Entry type taxonomy — no ambiguous "never_seen_before"
      entry_type = dplyr::case_when(
        !.data$prior_seen & .data$truth_cert_year >= .data$truth_year - 1L ~ "newly_certified",
        !.data$prior_seen                                                   ~ "late_observation",
        !is.na(.data$prior_retired) & .data$prior_retired &
          !.data$truth_is_retired                                           ~ "reactivated",
        TRUE                                                                ~ "continuing"
      ),

      # Signal strength — explicit source grep, not relying on conflict flag alone
      activity_signal_strength = dplyr::case_when(
        .data$truth_conflict_reason == "weak_cessation_only_billing_recent" ~ "weak",
        grepl("medicare|part_b|claims",
              .data$truth_conflict_reason, ignore.case = TRUE)              ~ "strong",
        TRUE                                                                 ~ "none"
      ),

      retirement_state = dplyr::if_else(.data$truth_is_retired, "retired", "active")
    ) |>
    dplyr::ungroup()

  # ── Sort-order guard ──────────────────────────────────────────────────────
  # lag() in transition_tbl depends on npi+year ordering. Check BEFORE arrange()
  # so the warning fires only when the input was actually unsorted (not after
  # transition_tbl has already been corrected).
  if (!identical(order(workforce_tbl[[npi_col]], workforce_tbl[[year_col]]),
                 seq_len(nrow(workforce_tbl)))) {
    warning("[truth_contract] Input not sorted by npi/year — sorting internally; fix upstream sort to silence this.",
            call. = FALSE)
  }

  message("[truth_contract] Derived entry_type and activity_signal_strength")

  # ── Nine violation checks ──────────────────────────────────────────────────
  all_flags <- transition_tbl |>
    dplyr::mutate(
      violation_reason = dplyr::case_when(
        is.na(.data$truth_npi) | .data$truth_npi == ""        ~ "missing_npi",
        is.na(.data$truth_year)                                ~ "missing_year",
        is.na(.data$truth_is_retired)                          ~ "missing_retirement_state",
        .data$entry_type == "newly_certified" &
          .data$truth_cert_year > .data$truth_year + 1L        ~ "future_certification_year",
        .data$entry_type == "reactivated" &
          .data$activity_signal_strength == "weak"             ~ "weak_signal_reactivation",
        !is.na(.data$truth_deceased) &
          .data$truth_deceased == "Y" &
          !.data$truth_is_retired                              ~ "deceased_marked_active",
        # Only flag reactivated physicians with no signal — continuous-active
        # physicians naturally have no conflict and no signal (that's normal).
        .data$entry_type == "reactivated" &
          .data$activity_signal_strength == "none"             ~ "inactive_but_marked_active",
        .data$entry_type == "reactivated" &
          .data$activity_signal_strength == "weak" &
          !is.na(.data$prior_year) &
          (.data$truth_year - .data$prior_year) <= 1L          ~ "reactivation_without_gap",
        TRUE                                                    ~ NA_character_
      ),
      violation_severity = dplyr::case_when(
        .data$violation_reason == "old_certification_first_appearance" ~ "warning",
        !is.na(.data$violation_reason)                                  ~ "error",
        TRUE                                                            ~ NA_character_
      )
    ) |>
    # late_observation check — warning only
    dplyr::mutate(
      violation_reason = dplyr::if_else(
        is.na(.data$violation_reason) &
          .data$entry_type == "late_observation" &
          .data$truth_cert_year < .data$truth_year - 2L,
        "old_certification_first_appearance",
        .data$violation_reason
      ),
      violation_severity = dplyr::if_else(
        .data$violation_reason == "old_certification_first_appearance",
        "warning",
        .data$violation_severity
      )
    ) |>
    dplyr::filter(!is.na(.data$violation_reason))

  violation_rows <- dplyr::filter(all_flags, .data$violation_severity == "error")
  warning_rows   <- dplyr::filter(all_flags, .data$violation_severity == "warning")
  n_violations   <- nrow(violation_rows)

  message("[truth_contract] Error violations: ",   n_violations)
  message("[truth_contract] Warning violations: ", nrow(warning_rows))

  # ── Contract summary and oscillator rates ─────────────────────────────────
  contract_summary <- transition_tbl |>
    dplyr::count(truth_year, entry_type,
                 activity_signal_strength, name = "n") |>
    dplyr::arrange(truth_year, entry_type)

  oscillator_rates <- transition_tbl |>
    dplyr::group_by(truth_year) |>
    dplyr::summarise(
      pct_newly_certified = mean(.data$entry_type == "newly_certified", na.rm = TRUE),
      pct_reactivated     = mean(.data$entry_type == "reactivated",     na.rm = TRUE),
      pct_late_obs        = mean(.data$entry_type == "late_observation", na.rm = TRUE),
      .groups = "drop"
    )

  if (any(oscillator_rates$pct_reactivated > 0.20, na.rm = TRUE)) {
    warning("[truth_contract] High oscillator rate (>20% reactivated in a year) — ",
            "possible retirement misclassification", call. = FALSE)
  }

  # ── Save violations to disk ────────────────────────────────────────────────
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  ts             <- format(Sys.time(), "%Y%m%d_%H%M%S")
  violation_path <- file.path(output_dir,
    paste0("workforce_truth_contract_violations_", ts, ".csv"))
  violation_path_tmp <- paste0(violation_path, ".tmp.", Sys.getpid())
  readr::write_csv(all_flags, violation_path_tmp)
  file.rename(violation_path_tmp, violation_path)
  message("[truth_contract] Saved violations to: ", violation_path)

  # ── Emit warnings for warning-level rows ──────────────────────────────────
  if (nrow(warning_rows) > 0L) {
    warning(sprintf("[truth_contract] %d warning-level violations (see %s)",
                    nrow(warning_rows), violation_path), call. = FALSE)
  }

  # ── Stop on error-level violations if strict ──────────────────────────────
  if (strict && n_violations > 0L) {
    stop(sprintf(
      "[truth_contract] RETRACTION GUARD: %d workforce truth violations.\nReview: %s",
      n_violations, violation_path
    ), call. = FALSE)
  }

  message("[truth_contract] Validation complete")

  list(
    valid            = n_violations == 0L,
    violation_rows   = violation_rows,
    warning_rows     = warning_rows,
    violation_path   = violation_path,
    contract_summary = contract_summary,
    oscillator_rates = oscillator_rates,
    n_violations     = n_violations
  )
}


#' DAG-compatible wrapper for validate_workforce_truth_contract
#'
#' Adapts the validator to the fixed interface expected by the orchestrator's
#' custom_validator dispatch loop at orchestrator_utils.R:6787.
#'
#' @param file_path Passed by orchestrator (unused — validator receives data
#'   directly).
#' @param checks Passed by orchestrator (unused).
#' @param data The workforce data frame to validate.
#' @param ... Additional arguments (ignored).
#' @return list(valid, message, details)
#' @keywords internal
validate_workforce_truth_contract_wrapper <- function(file_path, checks, data, ...) {
  if (is.null(data)) {
    return(list(valid = TRUE, message = "no data passed", details = NULL))
  }
  res <- validate_workforce_truth_contract(data, strict = FALSE)
  list(
    valid   = nrow(res$violation_rows) == 0L,
    message = sprintf("%d violations → %s", res$n_violations, res$violation_path),
    details = list(
      n_violations   = res$n_violations,
      violation_path = res$violation_path,
      oscillator_rates = res$oscillator_rates
    )
  )
}
