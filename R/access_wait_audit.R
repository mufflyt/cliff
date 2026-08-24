# Access-wait AUDIT input format: an appointment-availability audit -> the
# measure_access_wait_anchor() sample.
#
# WHY THIS EXISTS. R/access_wait_anchor.R::measure_access_wait_anchor() turns a
# numeric vector of observed appointment waits into a gated absolute-adequacy
# anchor. But a real access study does not arrive as a clean numeric vector: it is
# a secret-shopper / appointment-availability audit — one row per contact attempt,
# with dates, dispositions, and clinics that refuse new patients outright. This
# file is the INPUT FORMAT for that audit and the loader that turns it into the
# estimator's `waits`, honestly:
#
#   * a documented, validated column contract (access_wait_audit_columns()),
#   * a template writer (access_wait_audit_template()) and a committed copy at
#     inst/extdata/access_wait_audit_template.csv,
#   * a fail-loud reader/validator (read_access_wait_audit / validate_...),
#   * an extractor (access_wait_audit_waits()) that separates MEASURED new-patient
#     waits from ACCESS FAILURES (clinic not taking new patients, no slot offered,
#     insurance declined) — the failures are COUNTED and reported, never silently
#     dropped, because a mean wait among the clinics that did offer a slot
#     understates access when many refuse outright,
#   * a bridge (access_wait_audit_to_anchor()) that feeds the measured waits to
#     measure_access_wait_anchor() and carries the access-denial accounting on the
#     result.
#
# There is NO wait-time data committed to this repo; the template ships empty (two
# clearly-synthetic example rows). The service parameters mu and s are NOT part of
# the audit — they are capacity assumptions supplied by the caller with their own
# provenance. Pure base R (utils::read.csv, as.Date); runs in the minimal runner.
# Functions are internal (@noRd) scaffolding; promote to exported API with man/ Rd
# once the format has been exercised against a real audit.

# ---- the column contract (single source of truth) --------------------------

#' @noRd
access_wait_audit_columns <- function() {
  data.frame(
    name = c("observation_id", "provider_npi", "region", "payer",
             "contact_method", "contact_date", "appointment_type",
             "accepting_new_patients", "outcome", "offered_appointment_date",
             "wait_days", "notes"),
    type = c("character", "character", "character", "character",
             "character", "Date", "character", "logical", "character",
             "Date", "numeric", "character"),
    required = c(TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE,
                 FALSE, FALSE, FALSE),
    description = c(
      "Unique key for the contact attempt.",
      "Provider or clinic identity (dedup, provenance, future geographic join).",
      "Geographic label (state / HRR / market) for later stratification.",
      "Insurance the shopper presented.",
      "How access was requested: 'phone' or 'portal'.",
      "Date access was requested (YYYY-MM-DD).",
      "'new_patient' (the estimand) or 'established'.",
      "Whether the clinic takes new patients at all (TRUE/FALSE).",
      paste0("Disposition: one of ",
             paste(ACCESS_WAIT_AUDIT_OUTCOMES, collapse = ", "), "."),
      "Third-next-available NEW-patient slot offered (YYYY-MM-DD; blank if none).",
      "Lead time in days (>= 0); blank -> derived from offered minus contact date.",
      "Free-text notes."),
    stringsAsFactors = FALSE
  )
}

ACCESS_WAIT_AUDIT_OUTCOMES <- c(
  "appointment_offered",       # a new-patient slot was offered -> a MEASURED wait
  "no_new_patients",           # clinic not accepting new patients -> access denial
  "no_appointment_available",  # accepting, but no bookable slot -> access denial
  "declined_insurance",        # payer not accepted -> access denial
  "unreachable"                # could not reach the clinic -> non-response (missing)
)
ACCESS_WAIT_AUDIT_APPT_TYPES <- c("new_patient", "established")

# ---- template --------------------------------------------------------------

#' @noRd
access_wait_audit_template <- function(path = NULL, examples = TRUE) {
  cols <- access_wait_audit_columns()$name
  empty <- as.data.frame(
    stats::setNames(replicate(length(cols), character(0), simplify = FALSE), cols),
    stringsAsFactors = FALSE
  )
  if (examples) {
    empty <- rbind(
      # A measured wait recorded directly as wait_days.
      data.frame(observation_id = "EXAMPLE-001", provider_npi = "1234567890",
                 region = "Region A", payer = "Commercial PPO",
                 contact_method = "phone", contact_date = "2026-09-01",
                 appointment_type = "new_patient", accepting_new_patients = "TRUE",
                 outcome = "appointment_offered",
                 offered_appointment_date = "2026-10-06", wait_days = "35",
                 notes = "synthetic example - delete before use",
                 stringsAsFactors = FALSE),
      # An access denial: clinic not taking new patients (no wait to measure).
      data.frame(observation_id = "EXAMPLE-002", provider_npi = "1234567891",
                 region = "Region A", payer = "Medicare",
                 contact_method = "phone", contact_date = "2026-09-01",
                 appointment_type = "new_patient", accepting_new_patients = "FALSE",
                 outcome = "no_new_patients", offered_appointment_date = "",
                 wait_days = "",
                 notes = "synthetic example - clinic not taking new patients",
                 stringsAsFactors = FALSE),
      # A measured wait left blank in wait_days -> derived from the two dates.
      data.frame(observation_id = "EXAMPLE-003", provider_npi = "1234567892",
                 region = "Region B", payer = "Commercial PPO",
                 contact_method = "portal", contact_date = "2026-09-02",
                 appointment_type = "new_patient", accepting_new_patients = "TRUE",
                 outcome = "appointment_offered",
                 offered_appointment_date = "2026-09-16", wait_days = "",
                 notes = "synthetic example - wait_days left blank, derived from dates",
                 stringsAsFactors = FALSE)
    )
  }
  if (!is.null(path)) {
    utils::write.csv(empty, path, row.names = FALSE, na = "")
  }
  empty
}

# ---- read + validate -------------------------------------------------------

#' @noRd
read_access_wait_audit <- function(path, strict = TRUE) {
  if (!file.exists(path)) stop("read_access_wait_audit: file not found: ", path)
  raw <- utils::read.csv(path, colClasses = "character", check.names = FALSE,
                         na.strings = c("", "NA"), stringsAsFactors = FALSE)
  validate_access_wait_audit(raw, strict = strict)
}

#' @noRd
validate_access_wait_audit <- function(audit, strict = TRUE) {
  stopifnot(is.data.frame(audit))
  contract <- access_wait_audit_columns()
  req <- contract$name[contract$required]
  miss <- setdiff(req, names(audit))
  if (length(miss)) {
    stop("validate_access_wait_audit: missing required column(s): ",
         paste(miss, collapse = ", "))
  }
  # add any absent optional columns as NA so downstream code is uniform
  for (nm in setdiff(contract$name, names(audit))) audit[[nm]] <- NA_character_
  audit <- audit[, contract$name, drop = FALSE]

  # normalise blanks to NA so an in-memory data.frame behaves exactly like one
  # read via read_access_wait_audit() (utils::read.csv na.strings = c("", "NA")).
  for (nm in names(audit)) {
    if (is.character(audit[[nm]])) {
      v <- trimws(audit[[nm]])
      v[!nzchar(v)] <- NA
      audit[[nm]] <- v
    }
  }

  # coerce with loud failure
  as_chr <- function(x) if (is.character(x)) x else as.character(x)
  audit$observation_id <- as_chr(audit$observation_id)
  audit$provider_npi   <- as_chr(audit$provider_npi)

  if (any(is.na(audit$observation_id) | !nzchar(audit$observation_id))) {
    stop("validate_access_wait_audit: observation_id must be non-empty on every row.")
  }
  if (anyDuplicated(audit$observation_id)) {
    dup <- unique(audit$observation_id[duplicated(audit$observation_id)])
    stop("validate_access_wait_audit: duplicated observation_id: ",
         paste(dup, collapse = ", "))
  }

  audit$appointment_type <- as_chr(audit$appointment_type)
  bad_type <- !audit$appointment_type %in% ACCESS_WAIT_AUDIT_APPT_TYPES
  if (any(bad_type)) {
    stop("validate_access_wait_audit: appointment_type must be one of ",
         paste(ACCESS_WAIT_AUDIT_APPT_TYPES, collapse = "/"), "; bad rows: ",
         paste(audit$observation_id[bad_type], collapse = ", "))
  }

  audit$outcome <- as_chr(audit$outcome)
  bad_out <- !audit$outcome %in% ACCESS_WAIT_AUDIT_OUTCOMES
  if (any(bad_out)) {
    stop("validate_access_wait_audit: outcome must be one of {",
         paste(ACCESS_WAIT_AUDIT_OUTCOMES, collapse = ", "), "}; bad rows: ",
         paste(audit$observation_id[bad_out], collapse = ", "))
  }

  # logical accepting_new_patients (accept TRUE/FALSE spellings only)
  anp <- toupper(as_chr(audit$accepting_new_patients))
  ok_lgl <- anp %in% c("TRUE", "FALSE")
  if (any(!ok_lgl)) {
    stop("validate_access_wait_audit: accepting_new_patients must be TRUE/FALSE; bad rows: ",
         paste(audit$observation_id[!ok_lgl], collapse = ", "))
  }
  audit$accepting_new_patients <- anp == "TRUE"

  parse_date <- function(x, col) {
    x <- as_chr(x)
    d <- as.Date(x, format = "%Y-%m-%d")
    bad <- !is.na(x) & is.na(d)          # present but unparseable
    if (any(bad)) {
      stop("validate_access_wait_audit: ", col, " must be YYYY-MM-DD; bad rows: ",
           paste(audit$observation_id[bad], collapse = ", "))
    }
    d
  }
  audit$contact_date <- parse_date(audit$contact_date, "contact_date")
  if (any(is.na(audit$contact_date))) {
    stop("validate_access_wait_audit: contact_date is required on every row.")
  }
  audit$offered_appointment_date <- parse_date(audit$offered_appointment_date,
                                               "offered_appointment_date")

  wd <- suppressWarnings(as.numeric(as_chr(audit$wait_days)))
  bad_wd <- !is.na(audit$wait_days) & nzchar(as_chr(audit$wait_days)) & is.na(wd)
  if (any(bad_wd)) {
    stop("validate_access_wait_audit: wait_days must be numeric; bad rows: ",
         paste(audit$observation_id[bad_wd], collapse = ", "))
  }
  if (any(!is.na(wd) & wd < 0)) {
    stop("validate_access_wait_audit: wait_days must be >= 0; bad rows: ",
         paste(audit$observation_id[!is.na(wd) & wd < 0], collapse = ", "))
  }

  # derive wait_days from the two dates where blank; check consistency where both.
  derived <- as.numeric(audit$offered_appointment_date - audit$contact_date)
  need_derive <- is.na(wd) & !is.na(derived)
  wd[need_derive] <- derived[need_derive]
  both <- !is.na(wd) & !is.na(derived) & !need_derive
  disagree <- both & abs(wd - derived) > 0
  if (any(disagree)) {
    msg <- paste0("validate_access_wait_audit: wait_days disagrees with ",
                  "(offered - contact) on rows: ",
                  paste(audit$observation_id[disagree], collapse = ", "))
    if (strict) stop(msg) else warning(msg, "; preferring the date difference")
    wd[disagree] <- derived[disagree]
  }
  audit$wait_days <- wd

  attr(audit, "access_wait_audit_validated") <- TRUE
  audit
}

# ---- honest extraction: measured waits vs access failures ------------------

#' @noRd
access_wait_audit_waits <- function(audit) {
  if (!isTRUE(attr(audit, "access_wait_audit_validated"))) {
    audit <- validate_access_wait_audit(audit)
  }
  is_new  <- audit$appointment_type == "new_patient"
  reached <- audit$outcome != "unreachable"
  offered <- audit$outcome == "appointment_offered"

  measured <- is_new & reached & offered & audit$accepting_new_patients &
    is.finite(audit$wait_days) & audit$wait_days >= 0

  # rows that were offered a slot but lack a usable wait (bad/missing after derive)
  invalid_wait <- is_new & reached & offered & audit$accepting_new_patients &
    !(is.finite(audit$wait_days) & audit$wait_days >= 0)

  denial <- is_new & reached & !offered   # not offered a new-patient slot
  n_new_reached <- sum(is_new & reached)

  list(
    waits          = audit$wait_days[measured],
    n_total        = nrow(audit),
    n_measured     = sum(measured),
    exclusions     = c(
      non_new_patient        = sum(!is_new),
      unreachable            = sum(is_new & !reached),
      not_accepting          = sum(is_new & reached & !audit$accepting_new_patients),
      no_appointment         = sum(is_new & reached & audit$accepting_new_patients &
                                     audit$outcome %in% c("no_appointment_available",
                                                          "no_new_patients")),
      declined_insurance     = sum(is_new & reached &
                                     audit$outcome == "declined_insurance"),
      invalid_wait           = sum(invalid_wait)
    ),
    # the scientifically load-bearing number: among reached new-patient contacts,
    # the share that could NOT get a new-patient appointment. A high denial rate
    # means the measured-wait anchor understates the true access barrier.
    n_new_patient_reached = n_new_reached,
    access_denial_rate    = if (n_new_reached > 0) sum(denial) / n_new_reached else NA_real_
  )
}

# ---- bridge to the anchor estimator ----------------------------------------

#' @noRd
access_wait_audit_to_anchor <- function(audit, mu, s, time_unit = "day",
                                        service_source = NA_character_, ...) {
  ex <- access_wait_audit_waits(audit)

  attach_accounting <- function(fit) {
    attr(fit, "audit_n_total")             <- ex$n_total
    attr(fit, "audit_n_measured")          <- ex$n_measured
    attr(fit, "audit_exclusions")          <- ex$exclusions
    attr(fit, "audit_access_denial_rate")  <- ex$access_denial_rate
    attr(fit, "service_source")            <- as.character(service_source)[1]
    fit
  }

  # No measured new-patient wait -> refuse cleanly rather than error on an empty
  # sample (all contacts were denials or unreachable).
  if (length(ex$waits) < 1L) {
    fit <- data.frame(
      identified = FALSE, adequacy = NA_real_, adequacy_lo = NA_real_,
      adequacy_hi = NA_real_, n = 0L, mu = mu, s = as.integer(s),
      time_unit = as.character(time_unit)[1], frac_identified = NA_real_,
      reason = sprintf(paste0("no measured new-patient waits in the audit ",
                              "(%d contacts; access-denial rate %s among reached ",
                              "new-patient contacts)"),
                       ex$n_total,
                       if (is.na(ex$access_denial_rate)) "NA"
                       else sprintf("%.0f%%", 100 * ex$access_denial_rate)),
      stringsAsFactors = FALSE
    )
    return(attach_accounting(fit))
  }

  fit <- measure_access_wait_anchor(ex$waits, mu = mu, s = s,
                                    time_unit = time_unit, ...)
  attach_accounting(fit)
}
