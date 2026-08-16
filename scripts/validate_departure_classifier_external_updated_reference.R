#!/usr/bin/env Rscript
source(here::here("R", "wc_path.R"))
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# UPDATED-REFERENCE sensitivity analysis for the departure classifier.
#
# This is NOT the published external validation. That is
# scripts/validate_departure_classifier_external.R, frozen against the
# 2026-05-31 state-board registry snapshot and unchanged.
#
# On 2026-08-09 the upstream gold-standard registry was rebuilt: 36,070 -> 83,372
# rows, 35,536 -> 82,399 distinct NPIs. Re-validating against it moves URPS
# sensitivity 0.250 -> 0.188. That is a change in the REFERENCE STANDARD, not in
# the classifier, and the two are reported side by side rather than one silently
# replacing the other.
#
# The decomposition matters more than the headline. Of the 12 additional
# reference-departed URPS physicians, TEN are existing physicians whose board
# status changed active -> departed, and only TWO come from newly covered NPIs.
# The dominant effect is boards correcting the record over time.
#
# Both estimates rest on tiny denominators -- 4 and 16 reference-departed
# physicians -- so this script reports Wilson binomial intervals. A point
# sensitivity from 4 events is not evidence of anything on its own, and the
# apparent "decline" is well inside both intervals.
#
# OUTPUT: data/classifier_validation_external_updated_reference.csv
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(readr); library(dplyr); library(here)})

COHORT <- wc_path("cohort_csv")

FROZEN      <- wc_path("state_registry_frozen")
FROZEN_ID   <- "state_board_lifecycle_registry_2026-05-31_4a2c5e08"
FROZEN_SHA  <- "f95b29fdcd51a0ff7fce9f6652156a7dddaec3159caafaa7f98fb9184f4785d6"
UPDATED     <- wc_path("state_registry_updated")
UPDATED_ID  <- "state_board_lifecycle_registry_2026-08-09_26210996"
UPDATED_SHA <- "367cc9a9e80e55f3affcca0cec9693716f9d50f25901e42a4ceeba310b57a064"

stopifnot(file.exists(COHORT), file.exists(FROZEN), file.exists(UPDATED))
for (x in list(list(FROZEN, FROZEN_SHA, FROZEN_ID), list(UPDATED, UPDATED_SHA, UPDATED_ID))) {
  got <- unname(as.character(tools::sha256sum(x[[1]])))
  if (!identical(got, x[[2]]))
    stop("[updated-reference] ", x[[3]], " does not match its recorded hash.\n",
         "  expected: ", x[[2]], "\n  found:    ", got, call. = FALSE)
}
cat("both reference snapshots verified by sha256\n\n")

SUBS <- c(URPS = "Female Pelvic Medicine & Reconstructive Surgery",
          GO = "Gynecologic Oncology", MIGS = "MIGS")
DEFINITIVE <- c("retired", "revoked", "surrendered", "suspended")

coh <- read_csv(COHORT, show_col_types = FALSE, guess_max = READ_GUESS_MAX_ROWS) %>%
  filter(subspecialty %in% unname(SUBS)) %>%
  transmute(npi = as.character(npi),
            subspec = names(SUBS)[match(subspecialty, SUBS)],
            test_departed = as.logical(is_retired_for_cohorting)) %>%
  distinct(npi, .keep_all = TRUE) %>%
  filter(!is.na(subspec), !is.na(test_departed))

label <- function(path) {
  readRDS(path) %>%
    transmute(npi = as.character(npi), lifecycle_state = tolower(lifecycle_state)) %>%
    group_by(npi) %>% summarise(
      any_deceased = any(lifecycle_state == "deceased"),
      any_active   = any(lifecycle_state == "active"),
      any_defexit  = any(lifecycle_state %in% DEFINITIVE),
      any_inactive = any(lifecycle_state == "inactive"), .groups = "drop") %>%
    mutate(ref_label = case_when(any_deceased ~ "departed", any_active ~ "active",
                                 any_defexit ~ "departed", any_inactive ~ "ambiguous",
                                 TRUE ~ "ambiguous"),
           ref_departed = ref_label == "departed")
}

# Wilson score interval: the denominators here are 4 and 16, where a Wald
# interval is not merely imprecise but can leave [0, 1] entirely.
wilson <- function(x, n, conf = 0.95) {
  if (n == 0) return(c(NA_real_, NA_real_))
  z <- stats::qnorm(1 - (1 - conf) / 2)
  p <- x / n
  d <- 1 + z^2 / n
  centre <- (p + z^2 / (2 * n)) / d
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / d
  c(max(0, centre - half), min(1, centre + half))
}

rows <- list()
for (nm in c("frozen_2026_05_31", "updated_2026_08_09")) {
  ref <- label(if (nm == "frozen_2026_05_31") FROZEN else UPDATED)
  j <- inner_join(coh, ref, by = "npi") %>% filter(ref_label != "ambiguous")
  for (s in c("URPS", "GO", "MIGS", "ALL")) {
    d <- if (s == "ALL") j else j %>% filter(subspec == s)
    TP <- sum(d$test_departed & d$ref_departed); FN <- sum(!d$test_departed & d$ref_departed)
    FP <- sum(d$test_departed & !d$ref_departed); TN <- sum(!d$test_departed & !d$ref_departed)
    ci <- wilson(TP, TP + FN)
    rows[[length(rows) + 1]] <- data.frame(
      reference_basis = nm,
      reference_snapshot_id = if (nm == "frozen_2026_05_31") FROZEN_ID else UPDATED_ID,
      reference_sha256 = if (nm == "frozen_2026_05_31") FROZEN_SHA else UPDATED_SHA,
      subspec = s, n = nrow(d), TP = TP, FN = FN, FP = FP, TN = TN,
      ref_departed = TP + FN,
      sensitivity = if ((TP + FN) > 0) round(TP / (TP + FN), 3) else NA_real_,
      sens_ci95_lower = round(ci[1], 3), sens_ci95_upper = round(ci[2], 3),
      stringsAsFactors = FALSE)
  }
}
out <- bind_rows(rows)

cat("=== sensitivity with Wilson 95% intervals ===\n")
for (i in seq_len(nrow(out))) {
  r <- out[i, ]
  cat(sprintf("  %-18s %-5s  %d/%-2d = %.3f  [%.3f, %.3f]\n",
              r$reference_basis, r$subspec, r$TP, r$ref_departed,
              r$sensitivity, r$sens_ci95_lower, r$sens_ci95_upper))
}

write_csv(out, here::here("data", "classifier_validation_external_updated_reference.csv"))
cat("\nWrote data/classifier_validation_external_updated_reference.csv\n")
cat("The PUBLISHED validation remains the frozen 2026-05-31 basis in\n",
    "data/classifier_validation_external.csv; this file is a labelled\n",
    "sensitivity analysis, not a replacement.\n", sep = "")
