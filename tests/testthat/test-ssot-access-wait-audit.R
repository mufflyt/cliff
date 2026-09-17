# SSOT guard for the access-wait AUDIT input format (R/access_wait_audit.R):
# an appointment-availability audit -> measure_access_wait_anchor()'s sample.
#
# Pins the properties that keep the ingestion honest:
#   1. The committed template (inst/extdata/access_wait_audit_template.csv) is in
#      sync with the generator, round-trips through the reader, and derives
#      wait_days from the two dates when left blank.
#   2. Validation fails LOUD on every malformed field (bad outcome/type, negative
#      or non-numeric wait_days, non-ISO date, duplicate id, date/wait mismatch).
#   3. Extraction separates MEASURED new-patient waits from ACCESS FAILURES and
#      counts the failures (denial rate) rather than silently dropping them.
#   4. The bridge feeds the measured waits to the anchor and recovers the truth,
#      carrying the access-denial accounting; an all-denials audit refuses cleanly
#      instead of erroring on an empty sample.
#
# Pure base R (sources wait_adequacy.R + access_wait_anchor.R + access_wait_audit.R);
# runs in the minimal contract runner.
library(testthat)
library(here)

skip_if_no_repo()

e <- new.env()
source(here::here("R", "wait_adequacy.R"), local = e)
source(here::here("R", "access_wait_anchor.R"), local = e)
source(here::here("R", "access_wait_audit.R"), local = e)

# a new-patient "appointment_offered" row with an explicit wait
offered_row <- function(id, wait, provider = "1") {
  data.frame(observation_id = id, provider_npi = provider, region = "X", payer = "P",
             contact_method = "phone", contact_date = "2026-09-01",
             appointment_type = "new_patient", accepting_new_patients = "TRUE",
             outcome = "appointment_offered", offered_appointment_date = "",
             wait_days = as.character(wait), notes = "", stringsAsFactors = FALSE)
}

test_that("[template] committed CSV is in sync with the generator and round-trips", {
  committed <- here::here("inst", "extdata", "access_wait_audit_template.csv")
  expect_true(file.exists(committed))
  tmp <- tempfile(fileext = ".csv")
  e$access_wait_audit_template(tmp)                       # generate from the SSOT
  expect_identical(readLines(tmp), readLines(committed))  # committed == generated

  a <- e$read_access_wait_audit(committed)
  expect_true(isTRUE(attr(a, "access_wait_audit_validated")))
  # EXAMPLE-001 explicit 35; EXAMPLE-002 denial -> NA; EXAMPLE-003 derived 14
  expect_equal(a$wait_days, c(35, NA, 14))
})

test_that("[validate] malformed fields fail loud", {
  base <- offered_row("A", 30)
  expect_error(e$validate_access_wait_audit(transform(base, outcome = "banana")), "outcome must be one")
  expect_error(e$validate_access_wait_audit(transform(base, appointment_type = "walk_in")), "appointment_type")
  expect_error(e$validate_access_wait_audit(transform(base, wait_days = "-3")), "wait_days must be >= 0")
  expect_error(e$validate_access_wait_audit(transform(base, wait_days = "soon")), "wait_days must be numeric")
  expect_error(e$validate_access_wait_audit(transform(base, contact_date = "09/01/2026")), "YYYY-MM-DD")
  expect_error(e$validate_access_wait_audit(rbind(base, base)), "duplicated observation_id")
  # wait_days that disagrees with (offered - contact) is a data error in strict mode
  bad <- transform(base, offered_appointment_date = "2026-09-20", wait_days = "5")  # dates imply 19
  expect_error(e$validate_access_wait_audit(bad, strict = TRUE), "disagrees")
  expect_warning(w <- e$validate_access_wait_audit(bad, strict = FALSE), "disagrees")
  expect_equal(w$wait_days, 19)                            # date difference wins
})

test_that("[extract] measured waits are separated from access failures and counted", {
  aud <- e$validate_access_wait_audit(rbind(
    offered_row("R1", 20), offered_row("R2", 40),
    transform(offered_row("D1", 0), accepting_new_patients = "FALSE", outcome = "no_new_patients", wait_days = ""),
    transform(offered_row("D2", 0), outcome = "declined_insurance", wait_days = ""),
    transform(offered_row("U1", 0), outcome = "unreachable", wait_days = ""),
    transform(offered_row("E1", 0), appointment_type = "established")
  ))
  w <- e$access_wait_audit_waits(aud)
  expect_equal(sort(w$waits), c(20, 40))
  expect_equal(w$n_measured, 2L)
  expect_equal(unname(w$exclusions["not_accepting"]), 1L)
  expect_equal(unname(w$exclusions["declined_insurance"]), 1L)
  expect_equal(unname(w$exclusions["unreachable"]), 1L)
  expect_equal(unname(w$exclusions["non_new_patient"]), 1L)
  # denial rate = denials / reached new-patient contacts = 2 / 4 = 0.5
  expect_equal(w$access_denial_rate, 0.5)
})

test_that("[bridge] the audit recovers the true adequacy and carries the accounting", {
  set.seed(3)
  wq <- e$mmc_wait_in_queue(s = 6, mu = 2, rho = 1 / 1.4)   # target adequacy 1.4
  waits <- stats::rgamma(60, shape = 4, scale = wq / 4)      # E[wait] = wq (unrounded)
  rows <- do.call(rbind, Map(function(i, w) offered_row(paste0("R", i), w),
                             seq_along(waits), waits))
  # add a handful of denials so the denial-rate accounting is exercised
  denials <- do.call(rbind, lapply(1:10, function(i)
    transform(offered_row(paste0("D", i), 0), accepting_new_patients = "FALSE",
              outcome = "no_new_patients", wait_days = "")))
  aud <- e$validate_access_wait_audit(rbind(rows, denials))

  fit <- e$access_wait_audit_to_anchor(aud, mu = 2, s = 6, time_unit = "day",
                                       service_source = "assumed 2 new pts/provider/day",
                                       n_boot = 300L, seed = 3)
  expect_true(fit$identified)
  expect_equal(fit$adequacy, 1.4, tolerance = 0.08)
  expect_gt(fit$adequacy, 1)                                 # never asserts a shortage
  expect_equal(attr(fit, "audit_n_measured"), 60L)
  expect_equal(attr(fit, "audit_access_denial_rate"), 10 / 70)
  expect_identical(attr(fit, "service_source"), "assumed 2 new pts/provider/day")
})

test_that("[refuse] an all-denials audit refuses cleanly, not by erroring", {
  aud <- e$validate_access_wait_audit(do.call(rbind, lapply(1:8, function(i)
    transform(offered_row(paste0("D", i), 0), accepting_new_patients = "FALSE",
              outcome = "no_new_patients", wait_days = ""))))
  fit <- e$access_wait_audit_to_anchor(aud, mu = 2, s = 6)
  expect_false(fit$identified)
  expect_true(is.na(fit$adequacy))
  expect_match(fit$reason, "no measured new-patient waits")
  expect_equal(attr(fit, "audit_access_denial_rate"), 1)     # 100% denial
})
