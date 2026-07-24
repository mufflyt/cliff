#' @title Fellowship Training Inference Module
#'
#' @description
#' Infers where physicians completed their OB/GYN fellowship training based
#' on their first practice location after board certification.
#'
#' @details
#' Uses a multi-phase spatial matching algorithm against the ACGME FREIDA
#' database to approximate training locations when self-reported data is absent.
#'
#' @family data-enrichment
#' @name infer_fellowship_training
NULL

#!/usr/bin/env Rscript
# =============================================================================
# FELLOWSHIP TRAINING INFERENCE MODULE
# =============================================================================
#
# Purpose: Infer where physicians completed their OB/GYN fellowship training
#          based on their first practice location after board certification
#
# Methodology:
#   1. Get ABOG certification year (indicates fellowship completion)
#   2. Find physician's location in year of certification from temporal NPPES
#   3. Match to nearest ACGME OB/GYN fellowship program
#   4. Assign confidence based on distance and program uniqueness
#
# Data Sources:
#   - ACGME-accredited OB/GYN fellowship programs (compiled from public data)
#   - Temporal NPPES (physician locations by year)
#   - ABOG certification dates
#   - Doximity fellowship completion year (when available)
#
# Output:
#   - Inferred fellowship program name
#   - Inferred fellowship city/state
#   - Confidence score (0-1)
#   - Inference method used
#
# Author: Tyler Muffly
# Date: 2025-12-02
# =============================================================================

# --- AUTO-INSERTED 2026-05-22 (yaml::read_yaml -> load_paths sweep) ---
# Ensure load_paths() is in scope. Idempotent: only sources
# R/utils/load_paths.R if load_paths is not already defined upstream
# (e.g. by the orchestrator). load_paths() reads config/paths.yml AND
# applies the MufflySamsung volume-name corrector at
# R/utils/load_paths.R:101. See test-regression-integrate-retirement
# -load-paths-2026-05-22.R for the original bug that motivated this.
if (!base::exists("load_paths", mode = "function")) {
  source(here::here("R", "utils", "load_paths.R"))
}

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(here)
})

# Source shared FREIDA loader (provides load_freida_programs + find_nearest_program)
source(here::here("R", "freida_program_loader.R"))

# Bug #6 (audit, 2026-05-19): the historical-address scan reads
# nber_all.plocstatename (full state name) and aliases it AS state, but
# downstream fellowship-state inference and FREIDA program joins expect
# 2-letter USPS codes. Without normalisation, joins fail silently.
source(here::here("R", "utils", "sql_state_normalize.R"))

# =============================================================================
# SECTION 1: ACGME Otolaryngology FELLOWSHIP PROGRAMS LOOKUP TABLE
# =============================================================================
# Compiled from recently scraped FREIDA data.

#' Create ACGME OB/GYN Fellowship Programs Lookup Table from FREIDA CSV
#'
#' Thin wrapper around load_freida_programs("fellowship").
#' @return Data frame with all ACGME-accredited OB/GYN fellowship programs
#' @export
create_otolaryngology_fellowship_programs <- function() {
  load_freida_programs("fellowship")
}

# =============================================================================
# SECTION 2: FELLOWSHIP INFERENCE ALGORITHM
# =============================================================================

# Note: find_nearest_program() is now provided by R/freida_program_loader.R
# It returns distance_km (not distance_miles) and includes training environment columns.


#' Infer Fellowship Training Location for a Physician Cohort
#'
#' Matches physicians to ACGME-accredited Otolaryngology fellowship programs
#' using
#' the same multi-phase approach as \code{\link{infer_residency_training}}:
#' \enumerate{
#'   \item \strong{Phase 0:} Ground truth lookup from GOBA/DOX/Healthgrades
#'         data in DuckDB (if \code{temporal_db_path} provided).
#'   \item \strong{Phase 1:} Spatial proximity matching — compares each
#'         physician's first practice location to program coordinates using
#'         Haversine distance (km).
#'   \item \strong{Phase 2:} Temporal NPPES address history — checks
#'         addresses during fellowship window (cert_year - 2 to cert_year).
#' }
#'
#' @inheritParams shared_params_physician
#' @param programs Data frame or \code{NULL}. ACGME fellowship program
#'   data from \code{\link{create_otolaryngology_fellowship_programs}}. If
#'   \code{NULL}, loaded automatically via that function.
#' @param temporal_db_path Character scalar or \code{NULL}. Path to the
#'   temporal NPPES DuckDB database for Phase 0 ground truth lookup and
#'   Phase 2 address history. If \code{NULL}, those phases are skipped.
#'
#' @return Data frame with original physician columns plus inferred
#'   fellowship columns: \code{inferred_fellowship_program},
#'   \code{fellowship_distance_km}, \code{fellowship_inference_method},
#'   \code{fellowship_confidence}.
#'
#' @seealso [create_otolaryngology_fellowship_programs()],
#'   [infer_residency_training()] for the residency equivalent.
#' @export
infer_fellowship_training <- function(physicians, programs = NULL, temporal_db_path = NULL) {

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("FELLOWSHIP TRAINING INFERENCE\n")
  cat(strrep("=", 70), "\n\n")

  # Load programs if not provided
  if (is.null(programs)) {
    programs <- create_otolaryngology_fellowship_programs()
  }

  n_input <- nrow(physicians)
  cat(sprintf("Processing %s physicians...\n", format(n_input, big.mark = ",")))

  if (n_input == 0) {
    warning("infer_fellowship_training() received 0 physicians; returning empty data frame")
    return(physicians)
  }

  # Check required columns
  required_cols <- c("npi")
  missing <- setdiff(required_cols, names(physicians))
  if (length(missing) > 0) {
    stop("Missing required columns: ", paste(missing, collapse = ", "))
  }

  # INVARIANT: input NPIs must be unique. Fail fast.
  n_unique_npi <- dplyr::n_distinct(physicians$npi)
  if (n_unique_npi != n_input) {
    dup_npis <- physicians$npi[duplicated(physicians$npi)]
    stop(sprintf(
      "infer_fellowship_training(): %d duplicate NPIs detected (%d rows, %d unique). ",
      n_input - n_unique_npi, n_input, n_unique_npi),
      "Sample: ", paste(utils::head(unique(dup_npis), 5), collapse = ", "), ". ",
      "Deduplicate input before calling this function.")
  }
  # Assert NPI type and format
  if (!is.character(physicians$npi)) {
    stop(sprintf(
      "infer_fellowship_training(): NPI column is %s (expected character).",
      class(physicians$npi)[1]))
  }
  bad_npis <- physicians$npi[!grepl("^\\d{10}$", physicians$npi)]
  if (length(bad_npis) > 0) {
    stop(sprintf(
      "infer_fellowship_training(): %d NPIs have invalid format. ",
      length(bad_npis)),
      "Sample: ", paste(utils::head(bad_npis, 5), collapse = ", "))
  }

  # =====================================================================
  # PHASE 0: GROUND TRUTH LOOKUP (HG/DOX/Merged → FREIDA crosswalk)
  # =====================================================================
  crosswalk <- load_training_crosswalk("fellowship")
  gt_resolved <- NULL

  if (!is.null(crosswalk) && !is.null(temporal_db_path) && file.exists(temporal_db_path)) {
    cat("\n--- Phase 0: Ground Truth Fellowship Lookup ---\n")

    db_path_config <- load_paths(verbose = FALSE)$nber_duckdb_main
    gt_con <- DBI::dbConnect(duckdb::duckdb(), db_path_config, read_only = TRUE)
    on.exit(tryCatch(DBI::dbDisconnect(gt_con, shutdown = TRUE), error = function(e) NULL), add = TRUE)

    gt_raw <- DBI::dbGetQuery(gt_con, '
      SELECT
        CAST("NPI.Number" AS VARCHAR) AS npi,
        "Merged_Fellowship" AS gt_merged,
        "HG_Fellowship.Hospital.1...Name" AS gt_hg,
        CASE
          WHEN "DOX_Training.1...Type" IN (\'Fellowship\', \'PostDoctoralFellowship\') THEN "DOX_Training.1...Institution"
          WHEN "DOX_Training.2...Type" IN (\'Fellowship\', \'PostDoctoralFellowship\') THEN "DOX_Training.2...Institution"
          WHEN "DOX_Training.3...Type" IN (\'Fellowship\', \'PostDoctoralFellowship\') THEN "DOX_Training.3...Institution"
          WHEN "DOX_Training.4...Type" IN (\'Fellowship\', \'PostDoctoralFellowship\') THEN "DOX_Training.4...Institution"
          WHEN "DOX_Training.5...Type" IN (\'Fellowship\', \'PostDoctoralFellowship\') THEN "DOX_Training.5...Institution"
          WHEN "DOX_Training.6...Type" IN (\'Fellowship\', \'PostDoctoralFellowship\') THEN "DOX_Training.6...Institution"
          WHEN "DOX_Training.7...Type" IN (\'Fellowship\', \'PostDoctoralFellowship\') THEN "DOX_Training.7...Institution"
          WHEN "DOX_Training.8...Type" IN (\'Fellowship\', \'PostDoctoralFellowship\') THEN "DOX_Training.8...Institution"
          WHEN "DOX_Training.9...Type" IN (\'Fellowship\', \'PostDoctoralFellowship\') THEN "DOX_Training.9...Institution"
          WHEN "DOX_Training.10...Type" IN (\'Fellowship\', \'PostDoctoralFellowship\') THEN "DOX_Training.10...Institution"
        END AS gt_dox
      FROM goba_dox_hg_medical_school
    ')

    DBI::dbDisconnect(gt_con, shutdown = TRUE)

    gt_cohort <- gt_raw %>%
      filter(npi %in% as.character(physicians$npi))

    cat(sprintf("  GT coverage in cohort: %d/%d NPIs have any GT source\n",
                sum(!is.na(gt_cohort$gt_merged) | !is.na(gt_cohort$gt_hg) | !is.na(gt_cohort$gt_dox)),
                nrow(physicians)))

    xwalk_exact <- crosswalk %>%
      filter(match_class == "exact_verified", approved_for_ground_truth == TRUE)

    gt_cohort <- gt_cohort %>%
      mutate(
        gt_merged = if_else(gt_merged == "" | is.na(gt_merged), NA_character_, gt_merged),
        gt_hg     = if_else(gt_hg == "" | is.na(gt_hg), NA_character_, gt_hg),
        gt_dox    = if_else(gt_dox == "" | is.na(gt_dox), NA_character_, gt_dox),
        gt_fellowship_name = coalesce(gt_merged, gt_hg, gt_dox),
        gt_fellowship_source = case_when(
          !is.na(gt_merged) ~ "merged",
          !is.na(gt_hg)     ~ "hg",
          !is.na(gt_dox)    ~ "dox",
          TRUE               ~ NA_character_
        ),
        n_sources = (!is.na(gt_merged)) + (!is.na(gt_hg)) + (!is.na(gt_dox))
      )

    # Normalize for disagreement detection
    gt_cohort <- gt_cohort %>%
      mutate(
        norm_merged = sapply(gt_merged, normalize_org_name, USE.NAMES = FALSE),
        norm_hg     = sapply(gt_hg, normalize_org_name, USE.NAMES = FALSE),
        norm_dox    = sapply(gt_dox, normalize_org_name, USE.NAMES = FALSE)
      )

    # Crosswalk lookup for disagreement detection
    lookup_acgme <- function(raw_name, xwalk_df) {
      if (is.na(raw_name) || raw_name == "") return(NA_character_)
      match_row <- xwalk_df %>% filter(source_name_raw == raw_name) %>% slice(1)
      if (nrow(match_row) == 0) return(NA_character_)
      match_row$freida_acgme_id
    }
    all_xwalk <- crosswalk %>% filter(!is.na(freida_acgme_id))

    gt_cohort <- gt_cohort %>%
      mutate(
        acgme_merged = sapply(gt_merged, lookup_acgme, xwalk_df = all_xwalk, USE.NAMES = FALSE),
        acgme_hg     = sapply(gt_hg, lookup_acgme, xwalk_df = all_xwalk, USE.NAMES = FALSE),
        acgme_dox    = sapply(gt_dox, lookup_acgme, xwalk_df = all_xwalk, USE.NAMES = FALSE)
      )

    gt_cohort <- gt_cohort %>%
      rowwise() %>%
      mutate(
        acgme_ids = list(na.omit(c(acgme_merged, acgme_hg, acgme_dox))),
        gt_sources_agree = if (length(acgme_ids) <= 1) TRUE
                           else length(unique(acgme_ids)) == 1
      ) %>%
      ungroup() %>%
      select(-acgme_ids)

    n_multi_source <- sum(gt_cohort$n_sources >= 2, na.rm = TRUE)
    n_disagree <- sum(!gt_cohort$gt_sources_agree & gt_cohort$n_sources >= 2, na.rm = TRUE)
    cat(sprintf("  Source disagreement: %d/%d multi-source NPIs disagree (%.1f%%)\n",
                n_disagree, n_multi_source,
                if (n_multi_source > 0) 100 * n_disagree / n_multi_source else 0))

    gt_cohort <- gt_cohort %>%
      left_join(
        crosswalk %>%
          select(source_name_raw, match_class, freida_program_name,
                 freida_acgme_id, freida_state, approved_for_ground_truth),
        by = c("gt_fellowship_name" = "source_name_raw")
      )

    gt_cohort <- gt_cohort %>%
      mutate(
        gt_confidence = case_when(
          is.na(match_class) ~ NA_real_,
          match_class == "unmatched" ~ NA_real_,
          match_class == "exact_verified" & gt_sources_agree ~ 0.99,
          match_class == "exact_verified" & !gt_sources_agree ~ 0.90,
          match_class == "probable_match" ~ 0.80,
          TRUE ~ NA_real_
        ),
        gt_method = case_when(
          is.na(gt_confidence) ~ NA_character_,
          match_class == "exact_verified" ~ "ground_truth_hg_dox",
          match_class == "probable_match" ~ "ground_truth_probable",
          TRUE ~ NA_character_
        )
      )

    gt_assigned <- gt_cohort %>%
      filter(!is.na(gt_confidence)) %>%
      select(npi, gt_merged, gt_hg, gt_dox, gt_fellowship_name, gt_fellowship_source,
             gt_sources_agree, freida_program_name, freida_acgme_id, freida_state,
             gt_confidence, gt_method, match_class)

    # INVARIANT: gt_assigned must have unique NPIs. Fail fast.
    n_dup_gt <- nrow(gt_assigned) - dplyr::n_distinct(gt_assigned$npi)
    if (n_dup_gt > 0) {
      dup_sample <- gt_assigned %>%
        dplyr::group_by(npi) %>% dplyr::filter(dplyr::n() > 1) %>%
        dplyr::ungroup() %>% dplyr::slice_head(n = 6)
      cat(sprintf("  FATAL: %d duplicate NPIs in gt_assigned (fellowship). Sample:\n", n_dup_gt))
      for (j in seq_len(nrow(dup_sample))) {
        cat(sprintf("    NPI=%s program=%s\n", dup_sample$npi[j],
                    ifelse(is.na(dup_sample$freida_program_name[j]), "NA",
                           substr(dup_sample$freida_program_name[j], 1, 40))))
      }
      stop(sprintf(
        "Phase 0 GT (fellowship) INVARIANT VIOLATION: %d duplicate NPIs. ",
        n_dup_gt),
        "Fix the crosswalk CSV.")
    }

    n_gt_assigned <- nrow(gt_assigned)
    cat(sprintf("  GT assigned: %d NPIs (%.1f%% of cohort)\n",
                n_gt_assigned, 100 * n_gt_assigned / max(n_input, 1L)))

    if (n_gt_assigned > 0) {
      gt_conf_dist <- gt_assigned %>%
        count(gt_confidence) %>%
        mutate(pct = round(100 * n / sum(n), 1))
      for (j in seq_len(nrow(gt_conf_dist))) {
        cat(sprintf("    confidence=%.2f: %d (%.1f%%)\n",
                    gt_conf_dist$gt_confidence[j], gt_conf_dist$n[j], gt_conf_dist$pct[j]))
      }
    }

    gt_npi_set <- gt_assigned$npi
    physicians_for_nppes <- physicians %>% filter(!(as.character(npi) %in% gt_npi_set))
    physicians_gt <- physicians %>% filter(as.character(npi) %in% gt_npi_set)

    if (nrow(physicians_gt) > 0) {
      gt_results <- physicians_gt %>%
        mutate(npi_char = as.character(npi)) %>%
        left_join(gt_assigned, by = c("npi_char" = "npi")) %>%
        left_join(
          programs %>%
            select(acgme_program_id, institution, city, state,
                   annual_births, nicu_beds, total_beds, trauma_center),
          by = c("freida_acgme_id" = "acgme_program_id")
        ) %>%
        mutate(
          inferred_program       = freida_program_name,
          inferred_institution   = institution.y,
          inferred_city          = city.y,
          inferred_state         = state.y,
          inferred_acgme_id      = freida_acgme_id,
          distance_km            = NA_real_,
          programs_within_radius = NA_integer_,
          inference_confidence   = gt_confidence,
          inference_method       = gt_method,
          inference_source       = gt_method,
          training_annual_births = annual_births,
          training_nicu_beds     = nicu_beds,
          training_total_beds    = total_beds,
          training_trauma_center = as.character(trauma_center),
          gt_fellowship_merged   = gt_merged,
          gt_fellowship_hg       = gt_hg,
          gt_fellowship_dox      = gt_dox,
          gt_fellowship_name     = gt_fellowship_name,
          gt_fellowship_source   = gt_fellowship_source,
          gt_sources_agree       = gt_sources_agree
        ) %>%
        select(-npi_char, -matches("^institution\\."), -matches("^city\\."),
               -matches("^state\\."), -matches("^annual_births$"),
               -matches("^nicu_beds$"), -matches("^total_beds$"),
               -matches("^trauma_center$"), -freida_program_name,
               -freida_acgme_id, -freida_state, -gt_confidence,
               -gt_method, -match_class, -gt_merged, -gt_hg, -gt_dox)

      gt_resolved <- gt_results
    }

    physicians <- physicians_for_nppes
    cat(sprintf("  Remaining for NPPES inference: %d physicians\n", nrow(physicians)))
  }

  # =====================================================================
  # PHASE 0.5: ABOG NEIGHBOR MAJORITY VOTE
  # =====================================================================
  # For physicians not resolved by GT crosswalk, try ABOG sequential
  # clustering. ABOG assigns IDs by program registration → co-residents
  # have nearby IDs. Majority vote within +/-5 window, confidence=0.70.
  #
  # Audit invariants:
  #   1. No NPI appears in both gt_resolved and Phase 0.5 output
  #   2. Row count is preserved: gt_resolved + physicians == n_input
  #   3. ABOG results schema matches inference_output_columns()

  n_physicians_pre_abog <- nrow(physicians)
  n_gt_pre_abog <- if (!is.null(gt_resolved)) nrow(gt_resolved) else 0L

  if (nrow(physicians) > 0 && !is.null(crosswalk)) {
    cat("\n--- Phase 0.5: ABOG Neighbor Majority Vote (Fellowship) ---\n")

    db_path_abog <- tryCatch(
      load_paths(verbose = FALSE)$nber_duckdb_main,
      error = function(e) NULL
    )

    if (!is.null(db_path_abog) && file.exists(db_path_abog)) {
      abog_results <- tryCatch(
        infer_from_abog_neighbors(
          npis = as.character(physicians$npi),
          db_path = db_path_abog,
          crosswalk = crosswalk,
          programs = programs,
          window = 5L,
          min_neighbors = 2L,
          confidence = 0.70
        ),
        error = function(e) {
          warning("Phase 0.5 ABOG neighbor vote (fellowship) failed: ", e$message,
                  "\nFalling through to NPPES inference.")
          NULL
        }
      )

      if (!is.null(abog_results) && nrow(abog_results) > 0) {
        # --- Guard: validate ABOG results schema before merge ---
        abog_required_cols <- inference_output_columns()
        abog_missing_cols <- setdiff(abog_required_cols, names(abog_results))
        if (length(abog_missing_cols) > 0) {
          warning(sprintf("Phase 0.5 (fellowship): ABOG results missing columns: %s — skipping ABOG merge",
                          paste(abog_missing_cols, collapse = ", ")))
          abog_results <- NULL
        }
      }

      if (!is.null(abog_results) && nrow(abog_results) > 0) {
        # --- STRICT: no overlap between GT-resolved and ABOG-resolved NPIs ---
        # ABOG was called with physicians AFTER GT removal, so overlap = pipeline bug.
        abog_npi_set <- as.character(abog_results$npi)
        if (!is.null(gt_resolved)) {
          gt_npi_set <- as.character(gt_resolved$npi)
          overlap_npis <- intersect(abog_npi_set, gt_npi_set)
          if (length(overlap_npis) > 0) {
            stop(sprintf(
              "Phase 0.5 OVERLAP VIOLATION (fellowship): %d NPIs in both GT and ABOG sets. ",
              length(overlap_npis)),
              "Sample: ", paste(utils::head(overlap_npis, 5), collapse = ", "), ". ",
              "ABOG was called on physicians AFTER GT removal — overlap = pipeline bug.")
          }
        }

        if (nrow(abog_results) > 0) {
          # --- STRICT: ABOG NPIs must be subset of current physicians set ---
          physician_npi_set <- as.character(physicians$npi)
          rogue_abog <- setdiff(abog_npi_set, physician_npi_set)
          if (length(rogue_abog) > 0) {
            stop(sprintf(
              "Phase 0.5 SUBSET VIOLATION (fellowship): %d ABOG NPIs not in physicians set. ",
              length(rogue_abog)),
              "Sample: ", paste(utils::head(rogue_abog, 5), collapse = ", "), ". ",
              "infer_from_abog_neighbors() returned NPIs outside the input set.")
          }
        }

        if (nrow(abog_results) > 0) {
          # Split physicians into ABOG-resolved and remaining
          physicians_abog <- physicians %>%
            dplyr::filter(as.character(npi) %in% abog_npi_set) %>%
            dplyr::mutate(npi_char = as.character(npi)) %>%
            dplyr::left_join(abog_results, by = c("npi_char" = "npi"))

          # INVARIANT: left_join must not fan out. ABOG results have unique
          # NPIs (enforced by infer_from_abog_neighbors). Fan-out means physicians
          # table has duplicate NPIs — which we already rejected at input.
          if (nrow(physicians_abog) != length(abog_npi_set)) {
            stop(sprintf(
              "Phase 0.5 INVARIANT VIOLATION (fellowship): ABOG join fan-out %d rows for %d NPIs. ",
              nrow(physicians_abog), length(abog_npi_set)),
              "Input NPIs are not unique despite passing input validation.")
          }
          physicians_abog <- physicians_abog %>% dplyr::select(-npi_char)

          physicians <- physicians %>%
            dplyr::filter(!(as.character(npi) %in% abog_npi_set))

          # Add GT source columns as NA for schema compatibility
          if (!is.null(gt_resolved)) {
            gt_only_cols <- setdiff(names(gt_resolved), names(physicians_abog))
            for (col in gt_only_cols) {
              physicians_abog[[col]] <- NA
            }
          }

          # Append ABOG results to gt_resolved
          if (is.null(gt_resolved)) {
            gt_resolved <- physicians_abog
          } else {
            abog_only_cols <- setdiff(names(physicians_abog), names(gt_resolved))
            for (col in abog_only_cols) {
              gt_resolved[[col]] <- NA
            }
            gt_resolved <- dplyr::bind_rows(gt_resolved, physicians_abog)
          }

          cat(sprintf("  Phase 0.5: %d physicians assigned via ABOG neighbor vote\n",
                      nrow(physicians_abog)))
          cat(sprintf("  Remaining for NPPES inference: %d physicians\n", nrow(physicians)))
        }
      }
    } else {
      cat("  Skipping ABOG neighbor vote (DuckDB path not available)\n")
    }
  }

  # --- Phase 0/0.5 row-count invariant (STRICT — stop on violation) ---
  n_gt_post_abog <- if (!is.null(gt_resolved)) nrow(gt_resolved) else 0L
  n_physicians_post_abog <- nrow(physicians)
  row_sum <- n_gt_post_abog + n_physicians_post_abog
  expected_sum <- n_input

  cat(sprintf("\n--- Phase Partition (fellowship) ---\n"))
  cat(sprintf("  Input:          %d NPIs\n", n_input))
  cat(sprintf("  GT assigned:    %d (%.1f%%)\n", n_gt_pre_abog, 100 * n_gt_pre_abog / max(n_input, 1L)))
  cat(sprintf("  ABOG assigned:  %d (%.1f%%)\n", n_gt_post_abog - n_gt_pre_abog,
              100 * (n_gt_post_abog - n_gt_pre_abog) / max(n_input, 1L)))
  cat(sprintf("  NPPES pending:  %d (%.1f%%)\n", n_physicians_post_abog,
              100 * n_physicians_post_abog / max(n_input, 1L)))
  cat(sprintf("  Partition sum:  %d (expected %d)\n", row_sum, expected_sum))

  if (row_sum != expected_sum) {
    stop(sprintf(
      "Phase 0/0.5 (fellowship) row-count INVARIANT VIOLATION: gt_resolved(%d) + physicians(%d) = %d != n_input(%d). %d rows %s.",
      n_gt_post_abog, n_physicians_post_abog, row_sum, expected_sum,
      abs(row_sum - expected_sum),
      if (row_sum > expected_sum) "GAINED (fan-out)" else "LOST (dropped)"
    ))
  }

  # --- Overlap check: GT-resolved vs NPPES-pending NPIs ---
  if (!is.null(gt_resolved) && n_physicians_post_abog > 0) {
    resolved_npis <- as.character(gt_resolved$npi)
    pending_npis <- as.character(physicians$npi)
    overlap <- intersect(resolved_npis, pending_npis)
    if (length(overlap) > 0) {
      stop(sprintf(
        "Phase partition OVERLAP (fellowship): %d NPIs appear in both gt_resolved AND physicians (double-assignment). ",
        length(overlap)),
        "Sample: ", paste(utils::head(overlap, 5), collapse = ", "))
    }
  }

  # If all physicians were GT-resolved, skip NPPES inference
  if (nrow(physicians) == 0 && !is.null(gt_resolved)) {
    cat("\nAll physicians resolved via GT — skipping NPPES inference.\n")
    results <- gt_resolved
    if (!"inference_source" %in% names(results)) {
      results$inference_source <- "ground_truth_hg_dox"
    }
    if (nrow(results) != n_input) {
      warning(sprintf(
        "infer_fellowship_training() row count changed: input=%d, output=%d. ",
        n_input, nrow(results)),
        "Likely caused by join fan-out or dropped rows during unnest.")
    }
    return(results)
  }

  # Get certification year (proxy for fellowship completion)
  if ("startDate" %in% names(physicians)) {
    # FIX 2026-05-22 (batch-50 R3): use shared extract_year_safely()
    # helper instead of substr(date, 1, 4). Handles MM/DD/YYYY, text
    # dates, etc. — same Round-28 bug class.
    if (!exists("extract_year_safely", mode = "function", inherits = TRUE)) {
      source(here::here("R", "utils", "extract_year_safely.R"))
    }
    physicians <- physicians %>%
      mutate(cert_year = extract_year_safely(startDate))
  } else if ("last_year_fellowship" %in% names(physicians)) {
    physicians <- physicians %>%
      mutate(cert_year = as.integer(last_year_fellowship))
  } else {
    cat("WARNING: No certification/fellowship year available. Using current location.\n")
    physicians$cert_year <- NA_integer_
  }

  # Get practice location DURING FELLOWSHIP from nber_all
  #
  # CRITICAL: nber_all has historical addresses back to 2005, including:
  #   - Medical school addresses
  #   - Fellowship program addresses
  #   - Fellowship addresses
  #
  # KEY INSIGHT: NPIs are obtained during medical school (MS3/MS4) or early fellowship.
  # The EARLIEST address records in nber_all are typically from fellowship, before
  # the physician moves for fellowship or first job.
  #
  # APPROACH: Use the EARLIEST address records (first 1-2 years after NPI enumeration)
  # rather than calculating backwards from certification year, because:
  #   1. Certification may occur years after fellowship (esp. for fellows)
  #   2. Earliest NPPES records capture where they were during training
  #   3. Address lines often contain "Fellowship Program" text as confirmation
  #
  # TIMELINE (typical):
  #   - Year 0: NPI enumeration (during medical school or intern year)
  #   - Years 0-4 after enum: Fellowship period
  #   - Years 4-7 after enum: Fellowship (if applicable) or first job
  #   - Board certification: 0-2 years after final training

  if (!is.null(temporal_db_path) && file.exists(temporal_db_path)) {
    cat("Fetching practice locations DURING FELLOWSHIP from nber_all...\n")
    cat("  (Using EARLIEST address records - typically fellowship location)\n")
    cat("  (nber_all has historical addresses back to 2005)\n")

    con <- DBI::dbConnect(duckdb::duckdb(), temporal_db_path, read_only = TRUE)
    on.exit(tryCatch(DBI::dbDisconnect(con, shutdown = TRUE), error = function(e) NULL), add = TRUE)

    # Query nber_all for historical addresses with enumeration date
    # Note: lastupdatestr in nber_all is already a DATE type
    # Includes porgname and ploczip for hierarchical matching
    all_locations <- DBI::dbGetQuery(con, sprintf("
      SELECT
        CAST(npi AS VARCHAR) AS npi,
        ploccityname AS city,
        -- Bug #6 fix: normalise full state name to 2-letter USPS code
        %s,
        plocline1 AS address,
        porgname AS org_name,
        ploczip AS zip_code,
        lastupdatestr,
        -- Extract year directly from DATE column
        CAST(EXTRACT(YEAR FROM lastupdatestr) AS INTEGER) AS address_year,
        -- Row number to identify earliest records per NPI
        ROW_NUMBER() OVER (PARTITION BY npi ORDER BY lastupdatestr) AS record_seq
      FROM nber_all
      WHERE plocstatename IS NOT NULL
        AND lastupdatestr IS NOT NULL
    ", sql_state_normalize("plocstatename", alias = "state")))

    DBI::dbDisconnect(con, shutdown = TRUE)
    on.exit(NULL)  # clear the on.exit since we disconnected successfully

    cat(sprintf("  Loaded %s historical address records from nber_all\n",
                format(nrow(all_locations), big.mark = ",")))
    cat(sprintf("  Date range: %d to %d\n",
                min(all_locations$address_year, na.rm = TRUE),
                max(all_locations$address_year, na.rm = TRUE)))

    # Join physicians
    physicians <- physicians %>%
      mutate(npi_char = as.character(npi))

    # For each physician, get their EARLIEST address records
    # Priority: 1st record (likely fellowship) > 2nd record > 3rd record
    # Also boost addresses containing "Fellowship" or "Medical Center" keywords
    fellowship_locations <- physicians %>%
      select(npi_char) %>%
      left_join(all_locations, by = c("npi_char" = "npi")) %>%
      mutate(
        # Boost addresses that explicitly mention "Fellowship"
        has_fellowship_keyword = grepl("FELLOWSHIP|RESIDENT|MEDICAL CENTER|UNIVERSITY|HOSPITAL",
                                      address, ignore.case = TRUE),
        # Priority: earliest records first, with keyword boost
        priority = case_when(
          record_seq == 1 & has_fellowship_keyword ~ 1,   # 1st record with keyword - best
          record_seq == 2 & has_fellowship_keyword ~ 2,   # 2nd record with keyword
          record_seq == 1 ~ 3,                            # 1st record without keyword
          record_seq == 2 ~ 4,                            # 2nd record
          record_seq == 3 & has_fellowship_keyword ~ 5,   # 3rd with keyword
          record_seq == 3 ~ 6,                            # 3rd record
          TRUE ~ 10 + record_seq                          # Later records
        )
      ) %>%
      # Only consider first few records (most likely to be fellowship period)
      filter(record_seq <= 3) %>%
      group_by(npi_char) %>%
      arrange(priority) %>%
      slice(1) %>%
      ungroup() %>%
      select(npi_char, cert_location_city = city, cert_location_state = state,
             cert_location_address = address, cert_location_org = org_name,
             cert_location_zip = zip_code, location_year = address_year,
             record_sequence = record_seq, had_keyword = has_fellowship_keyword)

    # Report matching statistics
    match_summary <- fellowship_locations %>%
      mutate(
        match_type = case_when(
          is.na(location_year) ~ "No location found",
          had_keyword & record_sequence == 1 ~ "1st record (with fellowship keyword)",
          had_keyword & record_sequence == 2 ~ "2nd record (with fellowship keyword)",
          record_sequence == 1 ~ "1st record",
          record_sequence == 2 ~ "2nd record",
          record_sequence == 3 ~ "3rd record",
          TRUE ~ "Other"
        )
      ) %>%
      count(match_type)

    cat("  Location match quality (by record sequence):\n")
    for (i in seq_len(nrow(match_summary))) {
      cat(sprintf("    %s: %s\n", match_summary$match_type[i],
                  format(match_summary$n[i], big.mark = ",")))
    }

    # Join back to physicians
    physicians <- physicians %>%
      left_join(fellowship_locations %>% select(-record_sequence, -had_keyword),
                by = "npi_char") %>%
      select(-npi_char)

    # Use earliest location for inference (fallback to current state/city)
    physicians <- physicians %>%
      mutate(
        inference_state = coalesce(cert_location_state, state),
        inference_city = coalesce(cert_location_city, city)
      )

  } else if ("npi_city" %in% names(physicians) && "npi_state" %in% names(physicians)) {
    # Use current location if temporal not available
    cat("Using current practice location (temporal NPPES not available)\n")
    physicians <- physicians %>%
      mutate(
        inference_city = npi_city,
        inference_state = npi_state
      )
  } else {
    # Use ABOG city/state as fallback
    cat("Using ABOG city/state as fallback\n")
    physicians <- physicians %>%
      mutate(
        inference_city = city,
        inference_state = state
      )
  }

  # --- ZIP normalization and QA ---
  if ("cert_location_zip" %in% names(physicians)) {
    physicians <- physicians %>%
      mutate(
        cert_location_zip = stringr::str_extract(cert_location_zip, "^\\d{5}"),
        zip_valid = !is.na(cert_location_zip) & nchar(cert_location_zip) == 5
      )
    zip_coverage <- mean(physicians$zip_valid, na.rm = TRUE)
    cat(sprintf("  ZIP coverage: %.1f%% of physicians have valid 5-digit ZIP\n",
                100 * zip_coverage))
    if (zip_coverage < 0.5) {
      warning("ZIP coverage below 50% -- ZIP centroid geocoding may have limited value")
    }
  }

  # --- Geocoding: ZIP centroid -> state centroid fallback chain ---
  zip_centroid_path <- here::here("data", "freida", "zip_centroids.csv")
  has_zip_centroids <- file.exists(zip_centroid_path)
  if (has_zip_centroids) {
    zip_centroids <- readr::read_csv(zip_centroid_path, col_types = "cdd")
    cat(sprintf("  Loaded %s ZIP centroids for geocoding\n",
                format(nrow(zip_centroids), big.mark = ",")))
  }

  state_coords <- data.frame(
    inference_state = c("AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI","ID","IL","IN","IA",
              "KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM",
              "NY","NC","ND","OH","OK","OR","PA","PR","RI","SC","SD","TN","TX","UT","VT","VA",
              "WA","WV","WI","WY"),
    state_lat = c(32.32,64.20,34.05,35.20,36.78,39.55,41.60,38.91,38.91,27.66,32.16,19.90,
                  44.07,40.63,40.27,41.88,39.01,37.84,30.98,45.25,39.05,42.41,44.31,46.73,
                  32.35,37.96,46.88,41.49,38.80,43.19,40.06,34.52,43.30,35.76,47.55,40.42,
                  35.47,43.80,41.20,18.22,41.58,33.84,43.97,35.52,31.97,39.32,44.56,37.43,
                  47.75,38.60,43.78,43.08),
    state_lon = c(-86.90,-153.49,-111.09,-91.83,-119.42,-105.78,-73.09,-75.53,-77.04,-81.52,
                  -82.90,-155.58,-114.74,-89.40,-86.13,-93.10,-98.48,-84.27,-91.96,-69.45,
                  -76.64,-71.38,-84.54,-94.69,-89.40,-91.83,-110.36,-99.90,-116.42,-71.56,
                  -74.41,-105.87,-74.95,-79.02,-101.00,-82.91,-97.09,-120.55,-77.19,-66.59,
                  -71.48,-81.16,-100.34,-86.58,-99.90,-111.09,-72.58,-78.17,-120.74,-80.45,
                  -89.50,-107.29),
    stringsAsFactors = FALSE
  )

  # Build geocoding fallback chain: ZIP centroid -> state centroid
  if (has_zip_centroids && "cert_location_zip" %in% names(physicians)) {
    physicians <- physicians %>%
      left_join(zip_centroids, by = c("cert_location_zip" = "zip")) %>%
      rename(zip_lat = lat, zip_lon = lon) %>%
      left_join(state_coords, by = "inference_state") %>%
      mutate(
        practice_lat = dplyr::coalesce(zip_lat, state_lat),
        practice_lon = dplyr::coalesce(zip_lon, state_lon),
        geocode_method = dplyr::case_when(
          !is.na(zip_lat) ~ "zip_centroid",
          !is.na(state_lat) ~ "state_centroid",
          TRUE ~ "none"
        )
      )
  } else {
    physicians <- physicians %>%
      left_join(state_coords, by = "inference_state") %>%
      mutate(
        practice_lat = state_lat,
        practice_lon = state_lon,
        geocode_method = dplyr::if_else(!is.na(state_lat), "state_centroid", "none")
      )
  }

  # Log geocode method distribution
  cat("  Geocode method distribution:\n")
  geocode_dist <- table(physicians$geocode_method, useNA = "ifany")
  for (nm in names(geocode_dist)) {
    cat(sprintf("    %s: %s (%.1f%%)\n", nm, geocode_dist[nm],
                100 * geocode_dist[nm] / sum(geocode_dist)))
  }

  # Ensure optional columns exist for hierarchical matching
  if (!"cert_location_org" %in% names(physicians)) {
    physicians$cert_location_org <- NA_character_
  }
  if (!"cert_location_address" %in% names(physicians)) {
    physicians$cert_location_address <- NA_character_
  }
  if (!"cert_location_zip" %in% names(physicians)) {
    physicians$cert_location_zip <- NA_character_
  }

  # Infer fellowship for each physician (with hierarchical matching)
  cat("Inferring fellowship training locations...\n")

  results <- physicians %>%
    rowwise() %>%
    mutate(
      inference = list(find_nearest_program(
        physician_lat = practice_lat,
        physician_lon = practice_lon,
        programs = programs,
        physician_org = cert_location_org,
        physician_address = cert_location_address,
        physician_zip = cert_location_zip
      ))
    ) %>%
    ungroup() %>%
    unnest(inference)

  # Add inference_source for NPPES-inferred results
  if (!"inference_source" %in% names(results)) {
    results$inference_source <- "nppes_inference"
  }

  # --- Merge GT-resolved + NPPES-inferred results ---
  if (!is.null(gt_resolved) && nrow(gt_resolved) > 0) {
    gt_only_cols <- setdiff(names(gt_resolved), names(results))
    for (col in gt_only_cols) {
      results[[col]] <- NA
    }
    nppes_only_cols <- setdiff(names(results), names(gt_resolved))
    for (col in nppes_only_cols) {
      gt_resolved[[col]] <- NA
    }
    results <- bind_rows(gt_resolved, results)
    cat(sprintf("\nMerged: %d GT-resolved + %d NPPES-inferred = %d total\n",
                nrow(gt_resolved), nrow(results) - nrow(gt_resolved), nrow(results)))
  }

  # --- Output schema validation ---
  expected_cols <- inference_output_columns()
  missing_inference_cols <- setdiff(expected_cols, names(results))
  if (length(missing_inference_cols) > 0) {
    warning("infer_fellowship_training(): unnest produced unexpected schema. Missing: ",
            paste(missing_inference_cols, collapse = ", "))
  }

  # --- Inference QA ---
  validate_inference_qa(results, context = "fellowship")

  # Summarize results
  cat("\n")
  cat(strrep("-", 50), "\n")
  cat("INFERENCE RESULTS SUMMARY\n")
  cat(strrep("-", 50), "\n")

  conf_summary <- results %>%
    mutate(
      confidence_tier = case_when(
        inference_confidence >= 0.9 ~ "High (>=90%)",
        inference_confidence >= 0.7 ~ "Medium (70-89%)",
        inference_confidence >= 0.5 ~ "Low (50-69%)",
        inference_confidence > 0 ~ "Very Low (<50%)",
        TRUE ~ "Unable to infer"
      )
    ) %>%
    count(confidence_tier) %>%
    mutate(pct = round(100 * n / sum(n), 1))

  for (i in seq_len(nrow(conf_summary))) {
    cat(sprintf("  %s: %s (%.1f%%)\n",
                conf_summary$confidence_tier[i],
                format(conf_summary$n[i], big.mark = ","),
                conf_summary$pct[i]))
  }

  # Top inferred programs
  cat("\nTop 10 Inferred Fellowship Programs:\n")
  top_programs <- results %>%
    filter(!is.na(inferred_program)) %>%
    count(inferred_program, inferred_state) %>%
    arrange(desc(n)) %>%
    head(10)

  for (i in seq_len(nrow(top_programs))) {
    cat(sprintf("  %d. %s (%s): %s\n",
                i,
                top_programs$inferred_program[i],
                top_programs$inferred_state[i],
                format(top_programs$n[i], big.mark = ",")))
  }

  # Row-count preservation check
  if (nrow(results) != n_input) {
    warning(sprintf(
      "infer_fellowship_training() row count changed: input=%d, output=%d. ",
      n_input, nrow(results)),
      "Likely caused by join fan-out or dropped rows during unnest.")
  }

  # FINAL INVARIANT: output NPIs must be unique. All phases enforce uniqueness,
  # so duplicates here indicate a merge bug between GT/ABOG/NPPES results.
  n_dup_final <- nrow(results) - dplyr::n_distinct(results$npi)
  if (n_dup_final > 0) {
    dup_npis <- results$npi[duplicated(results$npi)]
    dup_sample <- results %>%
      dplyr::filter(npi %in% utils::head(unique(dup_npis), 5))

    # Write audit artifact before failing
    audit_dir <- here::here("artifacts", "audit")
    if (!dir.exists(audit_dir)) dir.create(audit_dir, recursive = TRUE)
    utils::write.csv(dup_sample,
                     file.path(audit_dir, "fellowship_duplicate_npi_report.csv"),
                     row.names = FALSE)

    stop(sprintf(
      "infer_fellowship_training() FINAL INVARIANT VIOLATION: %d duplicate NPIs in output. ",
      n_dup_final),
      "Sample: ", paste(utils::head(unique(dup_npis), 5), collapse = ", "), ". ",
      "Audit artifact written to artifacts/audit/fellowship_duplicate_npi_report.csv")
  }

  # --- Final phase partition summary ---
  n_gt_final <- sum(results$inference_source %in% c("ground_truth_hg_dox", "ground_truth_probable"), na.rm = TRUE)
  n_abog_final <- sum(results$inference_source == "abog_neighbor_vote", na.rm = TRUE)
  n_nppes_final <- sum(results$inference_source == "nppes_inference", na.rm = TRUE)
  n_other_final <- nrow(results) - n_gt_final - n_abog_final - n_nppes_final

  cat(sprintf("\n--- Final Phase Partition (fellowship) ---\n"))
  cat(sprintf("  GT:        %d (%.1f%%)\n", n_gt_final, 100 * n_gt_final / max(nrow(results), 1L)))
  cat(sprintf("  ABOG:      %d (%.1f%%)\n", n_abog_final, 100 * n_abog_final / max(nrow(results), 1L)))
  cat(sprintf("  NPPES:     %d (%.1f%%)\n", n_nppes_final, 100 * n_nppes_final / max(nrow(results), 1L)))
  if (n_other_final > 0) {
    cat(sprintf("  Other:     %d (%.1f%%)\n", n_other_final, 100 * n_other_final / max(nrow(results), 1L)))
  }
  cat(sprintf("  Total:     %d (input was %d)\n", nrow(results), n_input))

  return(results)
}


#' Add fellowship inference to Table 1 pipeline
#' @param temporal_db_path Path to temporal NPPES database
#' @return Enhanced data frame with fellowship inference columns
#' @export
add_fellowship_to_table1 <- function(physicians, temporal_db_path = NULL) {
  n_input <- nrow(physicians)

  # Load paths from config if not provided
  if (is.null(temporal_db_path)) {
    paths <- load_paths(verbose = FALSE)
    # Use nber_duckdb_main which contains the temporal tables
    temporal_db_path <- paths$nber_duckdb_main
  }

  # Create programs lookup
  programs <- create_otolaryngology_fellowship_programs()

  # Run inference
  results <- infer_fellowship_training(
    physicians = physicians,
    programs = programs,
    temporal_db_path = temporal_db_path
  )

  # --- Fellowship subspecialty lookup (safe, pre-computed) ---
  # Build lookup vector: prefer ACGME ID match (unique) over program name (may have dups)
  has_acgme <- "acgme_program_id" %in% names(programs)
  if (has_acgme) {
    acgme_lookup <- stats::setNames(as.character(programs$specialty),
                                     programs$acgme_program_id)
  }
  name_lookup <- stats::setNames(as.character(programs$specialty),
                                  programs$program_name)

  # Create Table 1 categories
  results <- results %>%
    mutate(
      # Fellowship region category (uses shared canonical classifier)
      fellowship_region = classify_us_region(inferred_state),

      # Confidence category for Table 1
      fellowship_inference_quality = case_when(
        inference_confidence >= 0.7 ~ "High confidence",
        inference_confidence >= 0.4 ~ "Moderate confidence",
        inference_confidence > 0 ~ "Low confidence",
        TRUE ~ "Unable to infer"
      ),

      # Binary: trained in same state as practicing?
      trained_in_practice_state = case_when(
        is.na(inferred_state) | is.na(state) ~ NA_character_,
        inferred_state == state ~ "Yes",
        TRUE ~ "No"
      ),

      # Geographic plausibility flag
      geo_plausible = case_when(
        is.na(inferred_state) | is.na(inference_state) ~ NA,
        inferred_state == inference_state ~ TRUE,
        TRUE ~ FALSE
      ),

      # Fellowship subspecialty from matched program
      # ACGME ID is unique → safer than program_name which may have duplicates
      fellowship_subspecialty = dplyr::if_else(
        !is.na(inferred_acgme_id) & has_acgme,
        unname(acgme_lookup[inferred_acgme_id]),
        dplyr::if_else(
          !is.na(inferred_program),
          unname(name_lookup[inferred_program]),
          NA_character_
        )
      ),

      # Training environment variables from FREIDA
      fellowship_birth_volume = training_annual_births,
      fellowship_nicu_beds    = training_nicu_beds,
      fellowship_total_beds   = training_total_beds,
      fellowship_trauma_center = case_when(
        is.na(training_trauma_center) | training_trauma_center == "" ~ "Unknown",
        grepl("^(Yes|Level)", training_trauma_center, ignore.case = TRUE) ~ "Yes",
        grepl("^No", training_trauma_center, ignore.case = TRUE) ~ "No",
        TRUE ~ "Unknown"
      )
    )

  # Row-count preservation check
  if (nrow(results) != n_input) {
    warning(sprintf(
      "add_fellowship_to_table1() row count changed: input=%d, output=%d",
      n_input, nrow(results)))
  }

  return(results)
}


# =============================================================================
# MAIN EXECUTION (when run as script)
# =============================================================================

if (!interactive()) {
  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("FELLOWSHIP TRAINING INFERENCE MODULE\n")
  cat(strrep("=", 70), "\n\n")

  # Create and save programs lookup
  programs <- create_otolaryngology_fellowship_programs()

  # Save lookup table
  output_dir <- here("data", "fellowship_lookup")
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  saveRDS(programs, file.path(output_dir, "acgme_otolaryngology_programs.rds"))
  write.csv(programs, file.path(output_dir, "acgme_otolaryngology_programs.csv"), row.names = FALSE)

  cat(sprintf("\nSaved programs lookup to: %s\n", output_dir))
  cat("\nTo use in Table 1 pipeline, add:\n")
  cat("  source(here('R', 'infer_fellowship_training.R'))\n")
  cat("  physicians <- add_fellowship_to_table1(physicians)\n")
}
