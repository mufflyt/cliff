# PORTED FROM THE ISOCHRONES MONOREPO (2026-08-14), commit ef8a0cdb6.
# R/infer_fellowship_training.R came across in the extraction; this file, which
# provides the five functions it calls, did not. Two EXPORTED functions were
# therefore calling undefined functions and would error on any call:
#   add_fellowship_to_table1  -> classify_us_region
#   infer_fellowship_training -> load_training_crosswalk, inference_output_columns,
#                                infer_from_abog_neighbors, validate_inference_qa
# R CMD check reported this as "no visible global function definition", inside a
# NOTE rather than a WARNING, which is why it survived this long.
#
# Changes on porting:
#   * file-scope library() calls removed; the package declares its imports in
#     NAMESPACE, and adding new attaches here would work against that
#   * source("R/utils/spatial_distance.R") dropped: R sources all of R/ , and
#     that file is now R/spatial_distance.R (R does not source R/ subdirectories)

#' @title FREIDA Program Loader
#'
#' @description
#' Load FREIDA residency/fellowship program data and provide a shared
#' \code{find_nearest_program()} implementation used by both residency and
#' fellowship inference modules.
#'
#' @family data-ingestion
#' @name freida_program_loader
NULL

#!/usr/bin/env Rscript
# =============================================================================
# FREIDA PROGRAM LOADER — Shared FREIDA Data Access + Nearest Program Matching
# =============================================================================
#
# Purpose: Load FREIDA residency/fellowship program data and provide a shared
#          find_nearest_program() implementation used by both residency and
#          fellowship inference modules.
#
# Data Sources:
#   - freida_otolaryngology_residency_details_cleaned.csv (304 ACGME residency programs)
#   - freida_otolaryngology_fellowship_details_cleaned.csv (339 fellowship programs)
#
# Path Resolution (resolve_freida_dir):
#   1. FREIDA_DATA_DIR env var
#   2. config/paths.yml freida_data_dir key
#   3. data/freida/ (project-local fallback)
#
# Author: Tyler Muffly
# Date: 2026-03-07
# =============================================================================

# Source spatial distance utilities (haversine_distance returns km)


# =============================================================================
# PATH RESOLUTION
# =============================================================================

#' Resolve FREIDA data directory
#'
#' Checks three locations in priority order:
#'   1. FREIDA_DATA_DIR environment variable
#'   2. freida_data_dir key in config/paths.yml
#'   3. data/freida/ (project-local copy)
#'
#' @return Character path to directory containing FREIDA CSVs
#' @export
resolve_freida_dir <- function() {
  # 1. Environment variable
  env_dir <- Sys.getenv("FREIDA_DATA_DIR", "")
  if (nzchar(env_dir) && dir.exists(env_dir)) {
    return(env_dir)
  }

  # 2. config/paths.yml
  config_path <- here::here("config", "paths.yml")
  if (file.exists(config_path)) {
    paths <- tryCatch(
      yaml::read_yaml(config_path),
      error = function(e) list()
    )
    if (!is.null(paths$freida_data_dir) && dir.exists(paths$freida_data_dir)) {
      return(paths$freida_data_dir)
    }
  }

  # 3. Project-local fallback
  local_dir <- here::here("data", "freida")
  if (dir.exists(local_dir)) {
    return(local_dir)
  }

  stop(
    "FREIDA data directory not found. Checked:\n",
    "  1. FREIDA_DATA_DIR env var\n",
    "  2. config/paths.yml freida_data_dir\n",
    "  3. data/freida/\n",
    "Copy CSVs to data/freida/ or set FREIDA_DATA_DIR."
  )
}


# =============================================================================
# PROGRAM LOADING
# =============================================================================

#' Load FREIDA Programs (Residency or Fellowship)
#'
#' Reads the cleaned FREIDA CSV and standardizes columns for use in
#' training inference. Both residency and fellowship CSVs share the
#' same column schema.
#'
#' @inheritParams shared_params_cohort
#' @inheritParams shared_params_execution
#' @param program_type Character: "residency" or "fellowship"
#' @param freida_dir Character path to directory with CSVs, or NULL to
#'   auto-resolve
#' @return Data frame with standardized columns:
#'   program_name, institution, city, state, lat, lon, acgme_program_id,
#'   specialty, primary_teaching_hospital, annual_births, nicu_beds,
#'   total_beds, trauma_center, program_type
#' @export
load_freida_programs <- function(program_type = c("residency", "fellowship"),
                                 freida_dir = NULL) {
  program_type <- match.arg(program_type)

  if (is.null(freida_dir)) {
    freida_dir <- resolve_freida_dir()
  }

  csv_file <- switch(program_type,
    residency  = "freida_otolaryngology_residency_details_cleaned.csv",
    fellowship = "freida_otolaryngology_fellowship_details_cleaned.csv"
  )

  csv_path <- file.path(freida_dir, csv_file)
  if (!file.exists(csv_path)) {
    stop("FREIDA ", program_type, " CSV not found at: ", csv_path)
  }

  raw_data <- readr::read_csv(csv_path, show_col_types = FALSE)

  # Validate required CSV columns exist before transmute
  required_csv_cols <- c("pgm_title", "inst_title",
                         "pgm_field_address_locality",
                         "pgm_field_address_administrative_area",
                         "pgm_field_program_id", "Specialty")
  missing_cols <- setdiff(required_csv_cols, names(raw_data))
  if (length(missing_cols) > 0) {
    stop("FREIDA ", program_type, " CSV missing required columns: ",
         paste(missing_cols, collapse = ", "),
         "\nAvailable columns: ", paste(head(names(raw_data), 20), collapse = ", "))
  }

  # At least one coordinate column pair must exist
  has_contact_coords <- all(c("contact_field_geolocation_lat",
                               "contact_field_geolocation_lon") %in% names(raw_data))
  has_pgm_coords <- all(c("pgm_field_geolocation_lat",
                            "pgm_field_geolocation_lon") %in% names(raw_data))
  if (!has_contact_coords && !has_pgm_coords) {
    stop("FREIDA ", program_type, " CSV has no coordinate columns. ",
         "Need contact_field_geolocation_lat/lon or pgm_field_geolocation_lat/lon.")
  }

  programs <- raw_data %>%
    dplyr::transmute(
      program_name       = pgm_title,
      institution        = inst_title,
      city               = pgm_field_address_locality,
      state              = pgm_field_address_administrative_area,
      # Prefer contact geolocation, fall back to program geolocation
      lat = as.numeric(dplyr::coalesce(
        as.character(contact_field_geolocation_lat),
        as.character(pgm_field_geolocation_lat)
      )),
      lon = as.numeric(dplyr::coalesce(
        as.character(contact_field_geolocation_lon),
        as.character(pgm_field_geolocation_lon)
      )),
      acgme_program_id   = as.character(pgm_field_program_id),
      specialty          = Specialty,
      primary_teaching_hospital = primary_teaching_title,
      annual_births      = as.numeric(primary_teaching_field_annual_births),
      nicu_beds          = as.numeric(primary_teaching_field_neonatal_icu),
      total_beds         = as.numeric(primary_teaching_field_number_beds),
      trauma_center      = primary_teaching_field_trauma_center,
      # New columns for hierarchical matching
      first_year_positions = as.numeric(survey_field_first_year_positions),
      program_zip          = primary_teaching_field_address_postal_code,
      program_address      = primary_teaching_field_address_address_line1,
      program_type       = !!program_type
    ) %>%
    # Validate coordinates: must be numeric and in range
    dplyr::filter(
      !is.na(lat) & !is.na(lon),
      lat >= -90 & lat <= 90,
      lon >= -180 & lon <= 180
    )

  # Guard: must have programs after coordinate filtering

  if (nrow(programs) == 0) {
    stop("FREIDA ", program_type, " CSV yielded 0 programs after coordinate filtering. ",
         "Check that lat/lon columns contain valid numeric values.")
  }

  # Sanity check: ACGME has ~290 residency and ~330 fellowship programs
  expected_min <- switch(program_type, residency = 200, fellowship = 200)
  if (nrow(programs) < expected_min) {
    warning("FREIDA ", program_type, " loaded only ", nrow(programs),
            " programs (expected >= ", expected_min, "). ",
            "Check CSV completeness.")
  }

  # --- Training environment plausibility checks ---
  # Clamp implausible values to NA with warning
  if (any(!is.na(programs$annual_births) & (programs$annual_births < 0 | programs$annual_births > 20000))) {
    n_bad <- sum(!is.na(programs$annual_births) & (programs$annual_births < 0 | programs$annual_births > 20000))
    warning(sprintf("FREIDA %s: %d programs have implausible annual_births (outside [0, 20000]); clamped to NA",
                    program_type, n_bad))
    programs$annual_births[!is.na(programs$annual_births) &
                            (programs$annual_births < 0 | programs$annual_births > 20000)] <- NA_real_
  }
  if (any(!is.na(programs$nicu_beds) & (programs$nicu_beds < 0 | programs$nicu_beds > 500))) {
    n_bad <- sum(!is.na(programs$nicu_beds) & (programs$nicu_beds < 0 | programs$nicu_beds > 500))
    warning(sprintf("FREIDA %s: %d programs have implausible nicu_beds (outside [0, 500]); clamped to NA",
                    program_type, n_bad))
    programs$nicu_beds[!is.na(programs$nicu_beds) &
                        (programs$nicu_beds < 0 | programs$nicu_beds > 500)] <- NA_real_
  }
  if (any(!is.na(programs$total_beds) & (programs$total_beds < 0 | programs$total_beds > 5000))) {
    n_bad <- sum(!is.na(programs$total_beds) & (programs$total_beds < 0 | programs$total_beds > 5000))
    warning(sprintf("FREIDA %s: %d programs have implausible total_beds (outside [0, 5000]); clamped to NA",
                    program_type, n_bad))
    programs$total_beds[!is.na(programs$total_beds) &
                         (programs$total_beds < 0 | programs$total_beds > 5000)] <- NA_real_
  }

  cat(sprintf("Loaded %d ACGME OB/GYN %s programs from FREIDA\n",
              nrow(programs), program_type))
  cat(sprintf("  Coverage: %d states/territories\n",
              dplyr::n_distinct(programs$state, na.rm = TRUE)))
  cat(sprintf("  Training environment: annual_births=%.0f%%, nicu_beds=%.0f%%, total_beds=%.0f%%, trauma_center=%.0f%%\n",
              100 * mean(!is.na(programs$annual_births)),
              100 * mean(!is.na(programs$nicu_beds)),
              100 * mean(!is.na(programs$total_beds)),
              100 * mean(!is.na(programs$trauma_center) & programs$trauma_center != "")))

  return(programs)
}


# =============================================================================
# MATCHING HELPER FUNCTIONS
# =============================================================================

# Generic medical terms that don't help disambiguate programs in dense markets
.GENERIC_ORG_WORDS <- c(
  "HOSPITAL", "MEDICAL", "CENTER", "UNIVERSITY", "HEALTH",
  "SYSTEM", "NEW", "YORK", "CITY", "DEPARTMENT", "OBSTETRICS",
  "GYNECOLOGY", "PROGRAM", "CLINIC", "HEALTHCARE", "MEDICINE",
  "SCHOOL", "COLLEGE", "INSTITUTE"
)


#' Normalize Organization Name for Matching
#'
#' Strips punctuation, removes function words (the, of, at, etc.),
#' uppercases. Keeps generic medical terms — they are downweighted
#' in token scoring but not removed during normalization.
#'
#' @param name Character scalar
#' @return Normalized uppercase string, or "" if NA/empty
#' @keywords internal
normalize_org_name <- function(name) {
  if (is.na(name) || !nzchar(trimws(name))) return("")
  name <- toupper(name)
  name <- gsub("[^A-Z0-9 ]", " ", name)
  # Remove ONLY function words, NOT generic medical terms
  name <- gsub("\\b(THE|OF|AT|AND|FOR|IN|A|AN)\\b", "", name)
  name <- gsub("\\s+", " ", trimws(name))
  name
}


#' Count Meaningful (Non-Generic) Tokens in a String
#'
#' @param s Normalized uppercase string
#' @return Integer count of tokens not in the generic list
#' @keywords internal
.count_meaningful_tokens <- function(s) {
  if (is.na(s) || s == "") return(0L)
  tokens <- unique(strsplit(s, " ")[[1]])
  tokens <- tokens[nchar(tokens) > 0]
  sum(!(tokens %in% .GENERIC_ORG_WORDS))
}


#' Weighted Token Similarity Between Two Org Names
#'
#' Shared tokens are weighted: non-generic words count 1.0,
#' generic words count 0.25. Returns weighted overlap / total union.
#'
#' @param a Normalized uppercase string
#' @param b Normalized uppercase string
#' @return Numeric in [0, 1]
#' @keywords internal
weighted_token_similarity <- function(a, b) {
  if (is.na(a) || is.na(b) || a == "" || b == "") return(0)
  words_a <- unique(strsplit(a, " ")[[1]])
  words_b <- unique(strsplit(b, " ")[[1]])
  words_a <- words_a[nchar(words_a) > 0]
  words_b <- words_b[nchar(words_b) > 0]
  if (length(words_a) == 0 || length(words_b) == 0) return(0)

  shared <- intersect(words_a, words_b)
  if (length(shared) == 0) return(0)
  weight <- ifelse(shared %in% .GENERIC_ORG_WORDS, 0.25, 1.0)
  weighted_overlap <- sum(weight)
  total <- length(union(words_a, words_b))
  weighted_overlap / total
}


#' Normalize a Street Address for Comparison
#'
#' Strips suite/apt/floor, uppercases, normalizes common abbreviations.
#' Extracts street number and key street tokens for matching.
#'
#' @param addr Character scalar street address
#' @return Named list with: normalized (full string), street_number,
#'   street_tokens
#' @keywords internal
normalize_street_address <- function(addr) {
  empty <- list(normalized = "", street_number = "", street_tokens = character(0))
  if (is.na(addr) || !nzchar(trimws(addr))) return(empty)

  addr <- toupper(addr)
  # Remove suite/apt/floor designations
  addr <- gsub("\\b(STE|SUITE|APT|APARTMENT|FLOOR|FL|RM|ROOM|UNIT|DEPT|DEPARTMENT)\\b[[:space:]#]*[A-Z0-9]*", "", addr)
  # Remove PO Box patterns
  addr <- gsub("\\bP\\.?\\s*O\\.?\\s*BOX\\s+[0-9]+", "", addr)
  # Normalize common abbreviations
  addr <- gsub("\\bST\\b", "STREET", addr)
  addr <- gsub("\\bAVE\\b", "AVENUE", addr)
  addr <- gsub("\\bBLVD\\b", "BOULEVARD", addr)
  addr <- gsub("\\bDR\\b", "DRIVE", addr)
  addr <- gsub("\\bRD\\b", "ROAD", addr)
  addr <- gsub("\\bPKWY\\b", "PARKWAY", addr)
  addr <- gsub("\\bLN\\b", "LANE", addr)
  addr <- gsub("\\bCT\\b", "COURT", addr)
  addr <- gsub("\\bPL\\b", "PLACE", addr)
  # Strip non-alphanumeric
  addr <- gsub("[^A-Z0-9 ]", " ", addr)
  addr <- gsub("\\s+", " ", trimws(addr))

  tokens <- strsplit(addr, " ")[[1]]
  tokens <- tokens[nchar(tokens) > 0]

  # Extract street number (first token that is numeric)
  street_number <- ""
  street_tokens <- character(0)
  if (length(tokens) > 0) {
    if (grepl("^[0-9]+$", tokens[1])) {
      street_number <- tokens[1]
      street_tokens <- tokens[-1]
    } else {
      street_tokens <- tokens
    }
  }

  list(
    normalized     = addr,
    street_number  = street_number,
    street_tokens  = street_tokens
  )
}


#' Match Street Addresses
#'
#' Compares physician address to program address. Returns TRUE if
#' street number matches AND at least one key street token matches.
#'
#' @param phys_addr Normalized address list (from normalize_street_address)
#' @param prog_addr Normalized address list (from normalize_street_address)
#' @return Logical
#' @keywords internal
match_street_address <- function(phys_addr, prog_addr) {
  # Both must have a street number

  if (phys_addr$street_number == "" || prog_addr$street_number == "") return(FALSE)
  # Street numbers must match
  if (phys_addr$street_number != prog_addr$street_number) return(FALSE)
  # At least one key street token must match
  shared <- intersect(phys_addr$street_tokens, prog_addr$street_tokens)
  length(shared) >= 1
}


#' Build a Standardized Result Row
#'
#' DRY helper — constructs the 1-row data.frame returned by
#' find_nearest_program().
#'
#' @param program_row 1-row data.frame from programs
#' @param confidence Numeric in [0, 1]
#' @param method Character inference method label
#' @param distance_km Numeric distance or NA
#' @param programs_within Integer count or NA
#' @param source [character]: Provenance label for the matched record.
#' @return 1-row data.frame with all inference columns
#' @keywords internal
build_result <- function(program_row, confidence, method,
                         distance_km = NA_real_, programs_within = NA_integer_,
                         source = "nppes_inference") {
  data.frame(
    inferred_program        = program_row$program_name,
    inferred_institution    = program_row$institution,
    inferred_city           = program_row$city,
    inferred_state          = program_row$state,
    inferred_acgme_id       = if ("acgme_program_id" %in% names(program_row)) program_row$acgme_program_id else NA_character_,
    distance_km             = round(distance_km, 1),
    programs_within_radius  = programs_within,
    inference_confidence    = confidence,
    inference_method        = method,
    inference_source        = source,
    training_annual_births  = if ("annual_births" %in% names(program_row)) program_row$annual_births else NA_real_,
    training_nicu_beds      = if ("nicu_beds" %in% names(program_row)) program_row$nicu_beds else NA_real_,
    training_total_beds     = if ("total_beds" %in% names(program_row)) program_row$total_beds else NA_real_,
    training_trauma_center  = if ("trauma_center" %in% names(program_row)) as.character(program_row$trauma_center) else NA_character_,
    stringsAsFactors = FALSE
  )
}


# =============================================================================
# NEAREST PROGRAM MATCHING
# =============================================================================

#' Find Nearest OB/GYN Program to a Location (Hierarchical Matching)
#'
#' Shared implementation used by both residency and fellowship inference.
#' Uses a strict priority chain:
#'   1. Organization/hospital name match (strict: 2+ meaningful tokens or exact)
#'   2. Street address match (street number + street name tokens)
#'   3. ZIP proximity (same ZIP code, within 20 km)
#'   4. Distance-only nearest program (haversine)
#'   5. Program size tiebreaker (when top programs within 5 km of each other)
#'
#' @param physician_lat Numeric latitude of physician location
#' @param physician_lon Numeric longitude of physician location
#' @param programs Data frame of programs (from load_freida_programs)
#' @param max_distance_km Maximum distance in km to consider (default 160 km ~
#'   100 miles)
#' @param physician_org Character: physician's org name from NPPES (optional)
#' @param physician_address Character: physician's street address from NPPES
#'   (optional)
#' @param physician_zip Character: physician's 5-digit ZIP code from NPPES
#'   (optional)
#' @return Data frame with nearest program info, confidence, and training
#'   environment
#' @export
find_nearest_program <- function(physician_lat, physician_lon, programs,
                                 max_distance_km = 160,
                                 physician_org = NA_character_,
                                 physician_address = NA_character_,
                                 physician_zip = NA_character_) {

  # --- Input validation ---
  stopifnot(
    "`programs` must be a data.frame" = is.data.frame(programs),
    "`max_distance_km` must be a non-negative number" =
      is.numeric(max_distance_km) && length(max_distance_km) == 1 && max_distance_km >= 0
  )

  # Validate required columns in programs
  required_prog_cols <- c("program_name", "institution", "city", "state", "lat", "lon")
  missing_prog <- setdiff(required_prog_cols, names(programs))
  if (length(missing_prog) > 0) {
    stop("`programs` data frame missing required columns: ",
         paste(missing_prog, collapse = ", "))
  }

  # No-data sentinel (used for empty/NA returns)
  no_location_result <- build_result(
    data.frame(program_name = NA_character_, institution = NA_character_,
               city = NA_character_, state = NA_character_,
               stringsAsFactors = FALSE),
    confidence = 0, method = "no_location",
    distance_km = NA_real_, programs_within = NA_integer_
  )

  # Guard: empty programs table
  if (nrow(programs) == 0) {
    warning("Empty programs table passed to find_nearest_program(); returning no_location")
    no_location_result$programs_within_radius <- 0L
    return(no_location_result)
  }

  # Handle missing coordinates
  if (is.na(physician_lat) || is.na(physician_lon)) {
    return(no_location_result)
  }

  # Calculate distance to all programs (haversine_distance returns km)
  distances <- sapply(seq_len(nrow(programs)), function(i) {
    haversine_distance(physician_lat, physician_lon, programs$lat[i], programs$lon[i])
  })

  programs_with_dist <- programs %>%
    dplyr::mutate(distance = distances) %>%
    dplyr::arrange(distance)

  # Count programs within max_distance_km (used for confidence in distance tier)
  programs_within <- sum(programs_with_dist$distance <= max_distance_km)

  # =====================================================================
  # TIER 1: Organization / Hospital Name Match (strict)
  # =====================================================================
  if (!is.na(physician_org) && nchar(trimws(physician_org)) >= 3) {
    org_norm <- normalize_org_name(physician_org)
    org_meaningful <- .count_meaningful_tokens(org_norm)

    if (nzchar(org_norm) && org_meaningful >= 1) {
      # Normalize FREIDA hospital/institution names
      hospital_norms <- sapply(
        if ("primary_teaching_hospital" %in% names(programs_with_dist))
          programs_with_dist$primary_teaching_hospital
        else rep(NA_character_, nrow(programs_with_dist)),
        normalize_org_name, USE.NAMES = FALSE
      )
      institution_norms <- sapply(programs_with_dist$institution,
                                   normalize_org_name, USE.NAMES = FALSE)

      # Rule A: Substring match — only "definitive" if either:
      #   (a) exact normalized match, OR
      #   (b) substring match AND both sides have >= 2 meaningful non-generic tokens
      has_substring <- mapply(function(h, i) {
        h_ok <- nchar(h) >= 3
        i_ok <- nchar(i) >= 3
        h_match <- h_ok && (grepl(h, org_norm, fixed = TRUE) ||
                            grepl(org_norm, h, fixed = TRUE))
        i_match <- i_ok && (grepl(i, org_norm, fixed = TRUE) ||
                            grepl(org_norm, i, fixed = TRUE))
        h_match || i_match
      }, hospital_norms, institution_norms)

      substring_idx <- which(has_substring)

      if (length(substring_idx) > 0) {
        # Check quality of each substring match
        qualified_idx <- integer(0)
        for (idx in substring_idx) {
          h <- hospital_norms[idx]
          i <- institution_norms[idx]
          # "Definitive" if exact match OR matched phrase has 2+ meaningful tokens
          is_exact <- (org_norm == h) || (org_norm == i)
          # Determine which side matched
          matched_str <- if (nchar(h) > 0 &&
                            (grepl(h, org_norm, fixed = TRUE) ||
                             grepl(org_norm, h, fixed = TRUE))) h else i
          meaningful_in_match <- .count_meaningful_tokens(matched_str)

          if (is_exact || (min(meaningful_in_match, org_meaningful) >= 2)) {
            qualified_idx <- c(qualified_idx, idx)
          }
        }

        if (length(qualified_idx) == 1) {
          match_row <- programs_with_dist[qualified_idx, ]
          return(build_result(match_row, confidence = 0.95,
                              method = "org_name_match",
                              distance_km = match_row$distance,
                              programs_within = programs_within))
        } else if (length(qualified_idx) > 1) {
          match_rows <- programs_with_dist[qualified_idx, ]
          nearest_match <- match_rows[which.min(match_rows$distance), ]
          return(build_result(nearest_match, confidence = 0.90,
                              method = "org_name_match",
                              distance_km = nearest_match$distance,
                              programs_within = programs_within))
        }
        # Unqualified substring matches (only generic tokens) fall through
      }

      # Rule B: Weighted token overlap >= 0.6 AND within 20 km
      token_scores <- pmax(
        mapply(weighted_token_similarity, org_norm, hospital_norms),
        mapply(weighted_token_similarity, org_norm, institution_norms)
      )

      token_match_idx <- which(token_scores >= 0.6 &
                               programs_with_dist$distance <= 20)
      if (length(token_match_idx) > 0) {
        best_idx <- token_match_idx[order(
          -token_scores[token_match_idx],
          programs_with_dist$distance[token_match_idx]
        )][1]
        match_row <- programs_with_dist[best_idx, ]
        return(build_result(match_row, confidence = 0.85,
                            method = "org_name_match",
                            distance_km = match_row$distance,
                            programs_within = programs_within))
      }
    }
  }

  # =====================================================================
  # TIER 2: Street Address Match
  # =====================================================================
  if (!is.na(physician_address) && nchar(trimws(physician_address)) >= 5 &&
      "program_address" %in% names(programs_with_dist)) {

    phys_addr <- normalize_street_address(physician_address)

    if (phys_addr$street_number != "") {
      # Only check programs within 50 km to avoid spurious street matches
      nearby_idx <- which(programs_with_dist$distance <= 50)

      if (length(nearby_idx) > 0) {
        street_matches <- integer(0)
        for (idx in nearby_idx) {
          prog_addr_raw <- programs_with_dist$program_address[idx]
          if (!is.na(prog_addr_raw) && nchar(trimws(prog_addr_raw)) >= 5) {
            prog_addr <- normalize_street_address(prog_addr_raw)
            if (match_street_address(phys_addr, prog_addr)) {
              street_matches <- c(street_matches, idx)
            }
          }
        }

        if (length(street_matches) == 1) {
          match_row <- programs_with_dist[street_matches, ]
          return(build_result(match_row, confidence = 0.90,
                              method = "street_address_match",
                              distance_km = match_row$distance,
                              programs_within = programs_within))
        } else if (length(street_matches) > 1) {
          match_rows <- programs_with_dist[street_matches, ]
          nearest_match <- match_rows[which.min(match_rows$distance), ]
          return(build_result(nearest_match, confidence = 0.85,
                              method = "street_address_match",
                              distance_km = nearest_match$distance,
                              programs_within = programs_within))
        }
      }
    }
  }

  # =====================================================================
  # TIER 3: ZIP Proximity Match
  # =====================================================================
  if (!is.na(physician_zip) && nchar(physician_zip) == 5 &&
      "program_zip" %in% names(programs_with_dist)) {

    prog_zips <- stringr::str_extract(
      as.character(programs_with_dist$program_zip), "^\\d{5}"
    )

    zip_match_idx <- which(
      !is.na(prog_zips) & prog_zips == physician_zip &
      programs_with_dist$distance <= 20
    )

    if (length(zip_match_idx) == 1) {
      match_row <- programs_with_dist[zip_match_idx, ]
      return(build_result(match_row, confidence = 0.80, method = "zip_match",
                          distance_km = match_row$distance,
                          programs_within = programs_within))
    } else if (length(zip_match_idx) > 1) {
      match_rows <- programs_with_dist[zip_match_idx, ]
      if ("first_year_positions" %in% names(match_rows)) {
        match_rows <- match_rows %>%
          dplyr::arrange(distance,
                         dplyr::desc(dplyr::coalesce(first_year_positions, 0)))
      }
      nearest_match <- match_rows[1, ]
      return(build_result(nearest_match, confidence = 0.70, method = "zip_match",
                          distance_km = nearest_match$distance,
                          programs_within = programs_within))
    }
  }

  # =====================================================================
  # TIER 4: Distance-Based Nearest Program + Size Tiebreaker
  # =====================================================================
  nearest <- programs_with_dist[1, ]
  nearest_dist <- nearest$distance

  # Program size tiebreaker: if top programs within 5 km, prefer larger
  if ("first_year_positions" %in% names(programs_with_dist)) {
    top_cluster <- programs_with_dist %>%
      dplyr::filter(distance <= nearest_dist + 5)
    if (nrow(top_cluster) > 1) {
      top_cluster <- top_cluster %>%
        dplyr::arrange(distance,
                       dplyr::desc(dplyr::coalesce(first_year_positions, 0)))
      nearest <- top_cluster[1, ]
      nearest_dist <- nearest$distance
    }
  }

  # Confidence based on distance and uniqueness
  confidence <- dplyr::case_when(
    nearest_dist > max_distance_km ~ 0.0,
    programs_within == 1 & nearest_dist <= 40  ~ 0.95,
    programs_within == 1 & nearest_dist <= 80  ~ 0.90,
    programs_within == 1                       ~ 0.80,
    programs_within == 2 & nearest_dist <= 40  ~ 0.75,
    programs_within == 2                       ~ 0.60,
    programs_within <= 5 & nearest_dist <= 40  ~ 0.50,
    programs_within <= 5                       ~ 0.40,
    TRUE                                       ~ 0.25
  )

  return(build_result(nearest, confidence = confidence,
                      method = "nearest_program",
                      distance_km = nearest_dist,
                      programs_within = programs_within))
}


# =============================================================================
# TRAINING NAME CROSSWALK LOADER
# =============================================================================

#' Load Training Name Crosswalk (Residency or Fellowship)
#'
#' Reads the pre-built crosswalk CSV that maps HG/DOX/Merged hospital names
#' to FREIDA ACGME programs. Only exact_verified entries with
#' approved_for_ground_truth=TRUE are used for high-confidence GT assignment.
#'
#' @param program_type Character: "residency" or "fellowship"
#' @param freida_dir Character path to directory with crosswalk CSVs, or NULL to
#'   auto-resolve
#' @return Data frame with crosswalk mappings, or NULL if file not found
#' @export
load_training_crosswalk <- function(program_type = c("residency", "fellowship"),
                                     freida_dir = NULL) {
  program_type <- match.arg(program_type)

  if (is.null(freida_dir)) {
    freida_dir <- resolve_freida_dir()
  }

  csv_file <- paste0(program_type, "_name_crosswalk.csv")
  csv_path <- file.path(freida_dir, csv_file)

  if (!file.exists(csv_path)) {
    warning("Training crosswalk not found at: ", csv_path,
            "\nRun scripts/build_training_name_crosswalk.R first.")
    return(NULL)
  }

  crosswalk <- readr::read_csv(csv_path, show_col_types = FALSE)

  # Validate required columns
  required <- c("source_name_raw", "source_name_normalized", "match_class",
                 "freida_program_name", "freida_acgme_id", "freida_state",
                 "approved_for_ground_truth")
  missing_cols <- setdiff(required, names(crosswalk))
  if (length(missing_cols) > 0) {
    warning("Crosswalk CSV missing columns: ", paste(missing_cols, collapse = ", "))
    return(NULL)
  }

  n_exact <- sum(crosswalk$match_class == "exact_verified", na.rm = TRUE)
  n_probable <- sum(crosswalk$match_class == "probable_match", na.rm = TRUE)
  n_unmatched <- sum(crosswalk$match_class == "unmatched", na.rm = TRUE)

  cat(sprintf("Loaded %s crosswalk: %d exact_verified, %d probable_match, %d unmatched\n",
              program_type, n_exact, n_probable, n_unmatched))

  crosswalk
}


# =============================================================================
# ABOG NEIGHBOR MAJORITY VOTE INFERENCE
# =============================================================================

#' Normalize physician name for ABOG table joining
#'
#' Strips M.D., D.O., Jr., Sr., III, II, IV suffixes and lowercases.
#' Used to join `credentials.abog_providers` (has "Tyler M. Muffly, M.D.")
#' with `credentials.abog_npi_matches` (has "Tyler M. Muffly").
#'
#' @param x Character vector of physician names
#' @return Character vector of normalized names
#' @keywords internal
normalize_abog_name <- function(x) {
  # Guard: NA and empty string pass through
  if (length(x) == 0) return(character(0))
  x %>%
    stringr::str_remove_all(",?\\s*(M\\.?D\\.?|D\\.?O\\.?|Jr\\.?|Sr\\.?|III|II|IV)$") %>%
    stringr::str_remove_all(",?\\s*(M\\.?D\\.?|D\\.?O\\.?|Jr\\.?|Sr\\.?|III|II|IV)$") %>%
    stringr::str_trim() %>%
    stringr::str_to_lower()
}


#' Infer residency from ABOG sequential ID neighbor majority vote
#'
#' ABOG assigns IDs sequentially by program registration, creating
#' clusters of co-residents with nearby IDs. For physicians without
#' GT resolution, this function looks at their ABOG ID neighbors
#' (within +/-5) and assigns the majority residency program.
#'
#' Validated agreement: ~24% at +/-1 window (vs ~1-2% random chance).
#'
#' ## Audit trail columns in output
#' - `abog_vote_name`: Raw residency name from goba (what neighbors said)
#' - `abog_vote_count`: How many neighbors voted for the winning program
#' - `abog_vote_total`: Total neighbors with known residency in window
#' - `abog_vote_share`: vote_count / vote_total (0-1)
#' - `abog_vote_runner_up`: Second-place program name (for contested votes)
#' - `abog_vote_runner_up_count`: How many voted for runner-up
#' - `abog_id`: The physician's ABOG sequential ID
#' - `abog_neighbor_npi_list`: Pipe-delimited NPIs of voting neighbors
#'
#' ## Confidence calibration
#' Base confidence is scaled by vote share:
#' - vote_share >= 0.75: confidence * 1.00 (strong consensus)
#' - vote_share >= 0.50: confidence * 0.90
#' - vote_share >= 0.33: confidence * 0.80
#' - vote_share < 0.33:  confidence * 0.70 (weak plurality)
#'
#' @inheritParams shared_params_db
#' @param crosswalk Data frame from load_training_crosswalk("residency")
#' @param programs Data frame from load_freida_programs("residency")
#' @param window Integer: ABOG ID neighbor window size (default 5)
#' @param min_neighbors Integer: minimum neighbors with known residency (default
#'   2)
#' @param confidence Numeric: base confidence score for voted results (default
#' @param npis [character]: NPIs to infer training for.
#' @param db_path [character]: Path to the temporal NPPES DuckDB used for neighbour lookup.
#'   0.70)
#' @return Data frame with columns matching inference_output_columns() plus
#'         abog_vote_* audit trail columns, or NULL if no ABOG data available.
#'         Output NPIs are guaranteed unique and a subset of input NPIs.
#' @export
infer_from_abog_neighbors <- function(npis, db_path, crosswalk, programs,
                                       window = 5L, min_neighbors = 2L,
                                       confidence = 0.70) {

  # --- Input validation ---
  if (length(npis) == 0) return(NULL)
  stopifnot(is.character(npis) || is.numeric(npis))
  npis <- as.character(npis)
  stopifnot(is.character(db_path), length(db_path) == 1)
  stopifnot(is.data.frame(crosswalk))
  stopifnot(is.data.frame(programs))
  stopifnot(is.numeric(window), window >= 1L, window <= 50L)
  stopifnot(is.numeric(min_neighbors), min_neighbors >= 1L)
  stopifnot(is.numeric(confidence), confidence > 0, confidence <= 1)

  n_input_npis <- length(unique(npis))

  # --- DuckDB connection ---
  con <- tryCatch(
    DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE),
    error = function(e) {
      warning("ABOG neighbor vote: cannot connect to DuckDB: ", e$message)
      return(NULL)
    }
  )
  if (is.null(con)) return(NULL)
  on.exit(tryCatch(DBI::dbDisconnect(con, shutdown = TRUE), error = function(e) NULL))

  # --- Step 1: ABOG providers (abog_id + internal npi + name) ---
  abog_prov <- tryCatch(
    DBI::dbGetQuery(con, "SELECT abog_id, npi AS abog_internal_id, physician_name
                          FROM credentials.abog_providers ORDER BY abog_id"),
    error = function(e) {
      warning("ABOG neighbor vote: cannot query credentials.abog_providers: ", e$message)
      return(NULL)
    }
  )
  if (is.null(abog_prov) || nrow(abog_prov) == 0) {
    cat("  ABOG neighbor vote: SKIP \u2014 credentials.abog_providers empty or unavailable\n")
    return(NULL)
  }
  cat(sprintf("  ABOG data: %s providers loaded\n",
              format(nrow(abog_prov), big.mark = ",")))

  # --- Step 2: ABOG NPI matches (real 10-digit NPIs) ---
  abog_npi <- tryCatch(
    DBI::dbGetQuery(con, "SELECT npi, physician_name AS match_name, primary_cert_date
                          FROM credentials.abog_npi_matches WHERE npi IS NOT NULL"),
    error = function(e) {
      warning("ABOG neighbor vote: cannot query credentials.abog_npi_matches: ", e$message)
      return(NULL)
    }
  )
  if (is.null(abog_npi) || nrow(abog_npi) == 0) {
    cat("  ABOG neighbor vote: SKIP \u2014 credentials.abog_npi_matches empty or unavailable\n")
    return(NULL)
  }
  # Force NPI to character to prevent type mismatch (critical: abog_npi.npi
  # comes from DuckDB as double, but goba NPI is VARCHAR)
  abog_npi$npi <- as.character(abog_npi$npi)

  # Validate NPI format: must be 10-digit numeric strings
  valid_npi_mask <- grepl("^\\d{10}$", abog_npi$npi)
  n_invalid_npi <- sum(!valid_npi_mask)
  if (n_invalid_npi > 0) {
    cat(sprintf("  ABOG neighbor vote: WARNING \u2014 %d/%d abog_npi_matches have invalid NPI format (dropped)\n",
                n_invalid_npi, nrow(abog_npi)))
    abog_npi <- abog_npi[valid_npi_mask, ]
  }
  cat(sprintf("  ABOG data: %s NPI matches loaded\n",
              format(nrow(abog_npi), big.mark = ",")))

  # --- Step 3: Known residencies from goba ---
  goba_res <- tryCatch(
    DBI::dbGetQuery(con, '
      SELECT CAST("NPI.Number" AS VARCHAR) AS npi,
             "Merged_Residency" AS merged_residency
      FROM goba_dox_hg_medical_school
      WHERE "Merged_Residency" IS NOT NULL
    '),
    error = function(e) {
      warning("ABOG neighbor vote: cannot query goba_dox_hg_medical_school: ", e$message)
      return(NULL)
    }
  )
  if (is.null(goba_res) || nrow(goba_res) == 0) {
    cat("  ABOG neighbor vote: SKIP \u2014 goba_dox_hg_medical_school empty or unavailable\n")
    return(NULL)
  }

  DBI::dbDisconnect(con, shutdown = TRUE)
  on.exit(NULL)

  cat(sprintf("  ABOG data: %s goba residencies loaded\n",
              format(nrow(goba_res), big.mark = ",")))

  # --- Step 4: Join abog_providers → abog_npi_matches by normalized name ---
  abog_prov$name_norm <- normalize_abog_name(abog_prov$physician_name)
  abog_npi$name_norm <- normalize_abog_name(abog_npi$match_name)

  n_pre_join <- nrow(abog_prov)
  joined <- abog_prov %>%
    dplyr::inner_join(abog_npi, by = "name_norm", relationship = "many-to-many")

  # Fan-out audit: how much did the many-to-many inflate?
  fan_out_ratio <- nrow(joined) / max(n_pre_join, 1L)
  if (fan_out_ratio > 5) {
    warning(sprintf("ABOG neighbor vote: join fan-out ratio=%.1f (%d\u2192%d rows). Check name normalization.",
                    fan_out_ratio, n_pre_join, nrow(joined)))
  }

  # Deduplicate: one NPI per abog_id (prefer rows with cert date)
  joined <- joined %>%
    dplyr::mutate(has_cert_date = !is.na(primary_cert_date)) %>%
    dplyr::arrange(abog_id, dplyr::desc(has_cert_date)) %>%
    dplyr::distinct(abog_id, .keep_all = TRUE)

  # Also deduplicate by NPI: one abog_id per NPI (prefer lower abog_id = earlier registration)
  joined <- joined %>%
    dplyr::arrange(npi, abog_id) %>%
    dplyr::distinct(npi, .keep_all = TRUE)

  cat(sprintf("  ABOG join: %s providers \u2192 %s unique abog_id\u2194NPI pairs (fan-out ratio=%.1f)\n",
              format(n_pre_join, big.mark = ","),
              format(nrow(joined), big.mark = ","),
              fan_out_ratio))

  # --- Step 5: Join to goba for known residencies ---
  # Assert NPI type before join (prevents silent 0-match)
  stopifnot("NPI must be character before goba join" = is.character(joined$npi))
  stopifnot("NPI must be character in goba" = is.character(goba_res$npi))
  # Assert NPI format: no scientific notation damage
  sci_note <- sum(grepl("[eE]", joined$npi), na.rm = TRUE)
  if (sci_note > 0) {
    stop(sprintf("ABOG neighbor vote: %d NPIs contain scientific notation (numeric coercion damage)", sci_note))
  }

  # Deduplicate goba to one residency per NPI (take first non-NA)
  goba_res_dedup <- goba_res %>%
    dplyr::distinct(npi, .keep_all = TRUE)

  n_pre_goba <- nrow(joined)
  abog_full <- joined %>%
    dplyr::select(abog_id, npi, physician_name) %>%
    dplyr::left_join(goba_res_dedup, by = "npi", na_matches = "never")

  # INVARIANT: left_join must not change row count.
  # goba is deduplicated by NPI, so fan-out indicates duplicate NPIs in joined.
  if (nrow(abog_full) != n_pre_goba) {
    stop(sprintf(
      "ABOG neighbor vote INVARIANT VIOLATION: goba join fan-out %d\u2192%d rows. ",
      n_pre_goba, nrow(abog_full)),
      "Duplicate NPIs in joined table after dedup \u2014 logic error.")
  }
  abog_full <- abog_full %>% dplyr::arrange(abog_id)

  n_known <- sum(!is.na(abog_full$merged_residency))
  cat(sprintf("  ABOG data: %s/%s have known residency from goba (%.1f%%)\n",
              format(n_known, big.mark = ","),
              format(nrow(abog_full), big.mark = ","),
              100 * n_known / max(nrow(abog_full), 1L)))

  # --- Step 6: Filter to our cohort and identify unknowns ---
  target_npis <- unique(as.character(npis))
  # Assert: input NPIs must be 10-digit character strings
  bad_input_npis <- target_npis[!grepl("^\\d{10}$", target_npis)]
  if (length(bad_input_npis) > 0) {
    stop(sprintf(
      "ABOG neighbor vote: %d input NPIs have invalid format (not 10-digit). Sample: %s",
      length(bad_input_npis),
      paste(utils::head(bad_input_npis, 3), collapse = ", ")))
  }
  # Assert: NPI column in abog_full must be character
  stopifnot("NPI must be character before target filter" = is.character(abog_full$npi))

  target_with_abog <- abog_full %>%
    dplyr::filter(npi %in% target_npis)

  if (nrow(target_with_abog) == 0) {
    cat("  ABOG neighbor vote: 0 target NPIs found in ABOG data \u2014 SKIP\n")
    return(NULL)
  }

  # Guard: check for duplicate NPIs in target.
  # INTENDED TIE-BREAK: Same NPI can appear via multiple ABOG certifications (e.g.,

  # primary cert + subspecialty cert). We keep the row with the lowest abog_id
  # (earliest registration) since that corresponds to primary residency training.
  n_dup_target <- nrow(target_with_abog) - dplyr::n_distinct(target_with_abog$npi)
  if (n_dup_target > 0) {
    dup_sample <- target_with_abog %>%
      dplyr::group_by(npi) %>% dplyr::filter(dplyr::n() > 1) %>%
      dplyr::ungroup() %>% dplyr::slice_head(n = 6)
    cat(sprintf("  ABOG neighbor vote: %d duplicate NPIs in target set (keeping earliest abog_id). Sample:\n",
                n_dup_target))
    for (j in seq_len(nrow(dup_sample))) {
      cat(sprintf("    NPI=%s abog_id=%d\n", dup_sample$npi[j], dup_sample$abog_id[j]))
    }
    target_with_abog <- target_with_abog %>%
      dplyr::arrange(npi, abog_id) %>%
      dplyr::distinct(npi, .keep_all = TRUE)
  }

  # Already-known (from goba directly) — skip these, they should be GT-resolved
  target_unknown <- target_with_abog %>%
    dplyr::filter(is.na(merged_residency))

  cat(sprintf("  ABOG neighbor vote: %d target NPIs in ABOG, %d without known residency, %d already known\n",
              nrow(target_with_abog), nrow(target_unknown),
              nrow(target_with_abog) - nrow(target_unknown)))

  if (nrow(target_unknown) == 0) {
    cat("  ABOG neighbor vote: all target NPIs already have GT residency \u2014 SKIP\n")
    return(NULL)
  }

  # Known residencies for neighbor lookup
  known <- abog_full %>%
    dplyr::filter(!is.na(merged_residency))

  # --- Step 7: Majority vote for each unknown NPI ---
  vote_results <- lapply(seq_len(nrow(target_unknown)), function(i) {
    my_id <- target_unknown$abog_id[i]
    my_npi <- target_unknown$npi[i]

    # Find neighbors with known residency within window
    neighbors <- known %>%
      dplyr::filter(abs(abog_id - my_id) <= window)

    if (nrow(neighbors) < min_neighbors) {
      return(NULL)
    }

    # Majority vote with runner-up tracking
    vote_tbl <- sort(table(neighbors$merged_residency), decreasing = TRUE)
    top_name <- names(vote_tbl)[1]
    top_count <- as.integer(vote_tbl[1])
    total_neighbors <- nrow(neighbors)
    # Guard: div-by-zero (should be impossible given min_neighbors >= 1, but be safe)
    vote_share <- if (total_neighbors > 0) top_count / total_neighbors else 0

    # Runner-up for audit trail
    runner_up_name <- if (length(vote_tbl) >= 2) names(vote_tbl)[2] else NA_character_
    runner_up_count <- if (length(vote_tbl) >= 2) as.integer(vote_tbl[2]) else NA_integer_

    # Neighbor NPI list for full audit trail (pipe-delimited)
    neighbor_npi_list <- paste(neighbors$npi, collapse = "|")

    data.frame(
      npi = my_npi,
      abog_vote_name = top_name,
      abog_vote_count = top_count,
      abog_vote_total = total_neighbors,
      abog_vote_share = vote_share,
      abog_vote_runner_up = runner_up_name,
      abog_vote_runner_up_count = runner_up_count,
      abog_id = my_id,
      abog_neighbor_npi_list = neighbor_npi_list,
      stringsAsFactors = FALSE
    )
  })

  voted <- dplyr::bind_rows(vote_results)

  if (nrow(voted) == 0) {
    cat(sprintf("  ABOG neighbor vote: 0/%d NPIs had >= %d neighbors \u2014 SKIP\n",
                nrow(target_unknown), min_neighbors))
    return(NULL)
  }

  # INVARIANT: vote output NPIs must be unique. Each NPI is processed exactly
  # once in the lapply above. Duplicates indicate a logic error, not a data issue.
  n_dup_voted <- nrow(voted) - dplyr::n_distinct(voted$npi)
  if (n_dup_voted > 0) {
    dup_sample <- voted %>%
      dplyr::group_by(npi) %>% dplyr::filter(dplyr::n() > 1) %>%
      dplyr::ungroup() %>% dplyr::slice_head(n = 6)
    cat(sprintf("  FATAL: %d duplicate NPIs in vote output. Sample:\n", n_dup_voted))
    for (j in seq_len(nrow(dup_sample))) {
      cat(sprintf("    NPI=%s abog_id=%d vote_name=%s\n",
                  dup_sample$npi[j], dup_sample$abog_id[j], dup_sample$abog_vote_name[j]))
    }
    stop(sprintf("ABOG neighbor vote INVARIANT VIOLATION: %d duplicate NPIs in vote output (logic error)",
                 n_dup_voted))
  }

  # Audit: vote share distribution
  share_quartiles <- stats::quantile(voted$abog_vote_share, c(0.25, 0.50, 0.75), na.rm = TRUE)
  cat(sprintf("  ABOG neighbor vote: %d NPIs got a vote (share Q25=%.0f%%, median=%.0f%%, Q75=%.0f%%)\n",
              nrow(voted),
              100 * share_quartiles[1],
              100 * share_quartiles[2],
              100 * share_quartiles[3]))

  # Audit: contested vs unanimous votes
  n_unanimous <- sum(voted$abog_vote_share == 1, na.rm = TRUE)
  n_contested <- sum(!is.na(voted$abog_vote_runner_up), na.rm = TRUE)
  cat(sprintf("  ABOG neighbor vote: %d unanimous, %d contested (runner-up exists)\n",
              n_unanimous, n_contested))

  # --- Step 8: Crosswalk lookup ---
  # HARDENING: detect and exclude ambiguous crosswalk entries (same source_name_raw
  # mapping to multiple ACGME IDs). These cannot be assigned with high confidence.
  xwalk_with_acgme <- crosswalk %>%
    dplyr::filter(!is.na(freida_acgme_id)) %>%
    dplyr::select(source_name_raw, freida_program_name, freida_acgme_id, freida_state)

  # Detect ambiguous source_name_raw → multiple ACGME IDs
  ambiguous_names <- xwalk_with_acgme %>%
    dplyr::group_by(source_name_raw) %>%
    dplyr::summarise(n_acgme_ids = dplyr::n_distinct(freida_acgme_id), .groups = "drop") %>%
    dplyr::filter(n_acgme_ids > 1)

  if (nrow(ambiguous_names) > 0) {
    cat(sprintf("  ABOG crosswalk: %d ambiguous source names map to multiple ACGME IDs (excluded from assignment):\n",
                nrow(ambiguous_names)))
    for (j in seq_len(nrow(ambiguous_names))) {
      cat(sprintf("    '%s' \u2192 %d ACGME IDs\n",
                  ambiguous_names$source_name_raw[j], ambiguous_names$n_acgme_ids[j]))
    }
    # Write audit artifact
    audit_dir <- here::here("artifacts", "audit")
    if (!dir.exists(audit_dir)) dir.create(audit_dir, recursive = TRUE)
    utils::write.csv(ambiguous_names,
                     file.path(audit_dir, "abog_ambiguous_crosswalk.csv"),
                     row.names = FALSE)
    # Exclude ambiguous names
    xwalk_with_acgme <- xwalk_with_acgme %>%
      dplyr::filter(!(source_name_raw %in% ambiguous_names$source_name_raw))
  }

  xwalk_lookup <- xwalk_with_acgme %>%
    dplyr::distinct(source_name_raw, .keep_all = TRUE)

  # Assert NPI type before join
  stopifnot("NPI must be character before crosswalk join" = is.character(voted$npi))

  n_pre_xwalk <- nrow(voted)
  voted <- voted %>%
    dplyr::left_join(xwalk_lookup, by = c("abog_vote_name" = "source_name_raw"))

  # INVARIANT: crosswalk join must not change row count.
  # Since we deduplicated xwalk_lookup by source_name_raw, fan-out indicates
  # a logic error (duplicate source_name_raw survived dedup).
  if (nrow(voted) != n_pre_xwalk) {
    stop(sprintf(
      "ABOG neighbor vote INVARIANT VIOLATION: crosswalk join fan-out %d\u2192%d rows. ",
      n_pre_xwalk, nrow(voted)),
      "source_name_raw has duplicates after dedup \u2014 logic error in crosswalk build.")
  }

  # Audit: how many votes lost to crosswalk unmatch
  voted_mapped <- voted %>% dplyr::filter(!is.na(freida_acgme_id))
  voted_unmapped <- voted %>% dplyr::filter(is.na(freida_acgme_id))

  cat(sprintf("  ABOG neighbor vote: %d/%d votes mapped to FREIDA, %d unmapped (excluded)\n",
              nrow(voted_mapped), nrow(voted), nrow(voted_unmapped)))

  # Log ALL unmapped names and write audit artifact
  if (nrow(voted_unmapped) > 0) {
    all_unmapped <- voted_unmapped %>%
      dplyr::count(abog_vote_name, sort = TRUE)
    cat(sprintf("  ABOG neighbor vote: %d unique unmapped vote names:\n",
                nrow(all_unmapped)))
    for (j in seq_len(nrow(all_unmapped))) {
      cat(sprintf("    %d NPIs: %s\n", all_unmapped$n[j], all_unmapped$abog_vote_name[j]))
    }
    # Write audit artifact
    audit_dir <- here::here("artifacts", "audit")
    if (!dir.exists(audit_dir)) dir.create(audit_dir, recursive = TRUE)
    utils::write.csv(all_unmapped,
                     file.path(audit_dir, "abog_unmapped_vote_names.csv"),
                     row.names = FALSE)
  }

  if (nrow(voted_mapped) == 0) {
    cat("  ABOG neighbor vote: 0 votes mapped to FREIDA \u2014 SKIP\n")
    return(NULL)
  }

  # --- Step 9: Training environment lookup from programs ---
  # Cast ACGME IDs to character for join compatibility
  voted_mapped <- voted_mapped %>%
    dplyr::mutate(freida_acgme_id = as.character(freida_acgme_id))

  n_pre_prog <- nrow(voted_mapped)
  voted_final <- voted_mapped %>%
    dplyr::left_join(
      programs %>%
        dplyr::mutate(acgme_program_id = as.character(acgme_program_id)) %>%
        dplyr::select(acgme_program_id, institution, city, state,
                      annual_births, nicu_beds, total_beds, trauma_center),
      by = c("freida_acgme_id" = "acgme_program_id")
    )

  # INVARIANT: programs join must not change row count. ACGME program IDs
  # should be unique in the programs table. Fan-out indicates duplicate programs.
  if (nrow(voted_final) != n_pre_prog) {
    stop(sprintf(
      "ABOG neighbor vote INVARIANT VIOLATION: programs join fan-out %d\u2192%d rows. ",
      n_pre_prog, nrow(voted_final)),
      "acgme_program_id is not unique in programs table.")
  }

  # --- Step 10: Confidence calibration by vote share ---
  # Scale base confidence by vote quality
  voted_final <- voted_final %>%
    dplyr::mutate(
      confidence_multiplier = dplyr::case_when(
        abog_vote_share >= 0.75 ~ 1.00,   # strong consensus
        abog_vote_share >= 0.50 ~ 0.90,   # majority
        abog_vote_share >= 0.33 ~ 0.80,   # plurality
        TRUE                    ~ 0.70    # weak plurality
      ),
      calibrated_confidence = round(confidence * confidence_multiplier, 4)
    )

  # --- Step 10b: Verify all mapped rows have populated FREIDA IDs ---
  # Mapped rows (voted_mapped) have non-NA freida_acgme_id by construction.
  # Verify inferred_program will also be non-NA (crosswalk integrity).
  n_missing_prog <- sum(is.na(voted_mapped$freida_program_name))
  if (n_missing_prog > 0) {
    stop(sprintf(
      "ABOG neighbor vote INVARIANT VIOLATION: %d mapped rows have NA freida_program_name ",
      n_missing_prog),
      "despite non-NA freida_acgme_id \u2014 crosswalk has incomplete program name data.")
  }

  # --- Step 11: Build output with inference schema + audit trail ---
  voted_final <- voted_final %>%
    dplyr::transmute(
      npi                        = npi,
      inferred_program           = freida_program_name,
      inferred_institution       = institution,
      inferred_city              = city,
      inferred_state             = state,
      inferred_acgme_id          = freida_acgme_id,
      distance_km                = NA_real_,
      programs_within_radius     = NA_integer_,
      inference_confidence       = calibrated_confidence,
      inference_method           = "abog_neighbor_vote",
      inference_source           = "abog_neighbor_vote",
      training_annual_births     = annual_births,
      training_nicu_beds         = nicu_beds,
      training_total_beds        = total_beds,
      training_trauma_center     = as.character(trauma_center),
      # Audit trail columns
      audit_phase                = "phase_0.5_abog_neighbor",
      abog_vote_name             = abog_vote_name,
      abog_vote_count            = abog_vote_count,
      abog_vote_total            = abog_vote_total,
      abog_vote_share            = abog_vote_share,
      abog_vote_runner_up        = abog_vote_runner_up,
      abog_vote_runner_up_count  = abog_vote_runner_up_count,
      abog_id                    = abog_id,
      abog_neighbor_npi_list     = abog_neighbor_npi_list
    )

  # --- Step 11b: Verify all assigned rows have non-NA FREIDA ID and inference fields ---
  n_na_acgme <- sum(is.na(voted_final$inferred_acgme_id))
  if (n_na_acgme > 0) {
    stop(sprintf(
      "ABOG neighbor vote INVARIANT VIOLATION: %d assigned rows have NA inferred_acgme_id",
      n_na_acgme))
  }
  n_na_method <- sum(is.na(voted_final$inference_method) | voted_final$inference_method == "")
  if (n_na_method > 0) {
    stop(sprintf(
      "ABOG neighbor vote INVARIANT VIOLATION: %d assigned rows have empty inference_method",
      n_na_method))
  }
  n_na_source <- sum(is.na(voted_final$inference_source) | voted_final$inference_source == "")
  if (n_na_source > 0) {
    stop(sprintf(
      "ABOG neighbor vote INVARIANT VIOLATION: %d assigned rows have empty inference_source",
      n_na_source))
  }

  # --- Final invariant checks ---
  # 1. Output NPIs must be unique
  n_dup_final <- nrow(voted_final) - dplyr::n_distinct(voted_final$npi)
  if (n_dup_final > 0) {
    stop(sprintf("ABOG neighbor vote INVARIANT VIOLATION: %d duplicate NPIs in final output", n_dup_final))
  }

  # 2. Output NPIs must be a subset of input NPIs
  rogue_npis <- setdiff(voted_final$npi, npis)
  if (length(rogue_npis) > 0) {
    stop(sprintf("ABOG neighbor vote INVARIANT VIOLATION: %d output NPIs not in input set", length(rogue_npis)))
  }

  # 3. Confidence must be in valid range
  conf_range <- range(voted_final$inference_confidence, na.rm = TRUE)
  if (conf_range[1] < 0 || conf_range[2] > 1) {
    stop(sprintf("ABOG neighbor vote INVARIANT VIOLATION: confidence range [%.4f, %.4f] outside [0,1]",
                 conf_range[1], conf_range[2]))
  }

  # 4. All required inference columns must be present
  required_cols <- inference_output_columns()
  missing_cols <- setdiff(required_cols, names(voted_final))
  if (length(missing_cols) > 0) {
    stop(sprintf("ABOG neighbor vote INVARIANT VIOLATION: missing output columns: %s",
                 paste(missing_cols, collapse = ", ")))
  }

  # --- Phase partition summary (audit artifact) ---
  audit_dir <- here::here("artifacts", "audit")
  if (!dir.exists(audit_dir)) dir.create(audit_dir, recursive = TRUE)
  partition <- data.frame(
    metric = c("input_npis", "npis_in_abog", "npis_unknown_residency",
               "npis_with_vote", "npis_mapped_to_freida", "npis_unmapped",
               "npis_assigned_final"),
    count = c(n_input_npis, nrow(target_with_abog), nrow(target_unknown),
              nrow(voted), nrow(voted_mapped), nrow(voted_unmapped),
              nrow(voted_final)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(partition,
                   file.path(audit_dir, "abog_phase_partition.csv"),
                   row.names = FALSE)

  # --- Summary ---
  conf_dist <- voted_final %>%
    dplyr::mutate(conf_tier = dplyr::case_when(
      inference_confidence >= 0.60 ~ "high (>=0.60)",
      inference_confidence >= 0.45 ~ "medium (0.45-0.59)",
      TRUE ~ "low (<0.45)"
    )) %>%
    dplyr::count(conf_tier, sort = TRUE)

  cat(sprintf("  ABOG neighbor vote: %d physicians assigned, confidence range [%.2f, %.2f]\n",
              nrow(voted_final), conf_range[1], conf_range[2]))
  for (j in seq_len(nrow(conf_dist))) {
    cat(sprintf("    %s: %d\n", conf_dist$conf_tier[j], conf_dist$n[j]))
  }

  voted_final
}


# =============================================================================
# INFERENCE QA VALIDATION
# =============================================================================

#' Expected columns in find_nearest_program() output
#' @return Character vector of required column names
#' @keywords internal
inference_output_columns <- function() {
  c("inferred_program", "inferred_institution", "inferred_city",
    "inferred_state", "inferred_acgme_id", "distance_km",
    "programs_within_radius", "inference_confidence",
    "inference_method", "inference_source",
    "training_annual_births",
    "training_nicu_beds", "training_total_beds",
    "training_trauma_center")
}


#' Validate Inference Results Quality
#'
#' Comprehensive QA validation for inference output. Runs schema checks,
#' confidence bounds, phase-level breakdown, NPI uniqueness, distance
#' plausibility, and geographic consistency. Writes structured JSON
#' audit artifact to artifacts/audit/ on every call (pass or fail).
#'
#' @param results Data frame with inference columns (post-unnest)
#' @param write_artifact Logical; if TRUE (default), write JSON audit to
#' @param context [character]: Label used in QA messages and artefact names, e.g. "fellowship".
#'   artifacts/audit/
#' @return Invisible list with QA metrics; side-effect: warnings for issues,
#'         JSON audit artifact written to
#' \code{artifacts/audit/inference_qa_[context].json}
#' @export
validate_inference_qa <- function(results, context = "training", write_artifact = TRUE) {
  n <- nrow(results)
  if (n == 0) return(invisible(list(n = 0, pass = TRUE, checks = list())))

  issues <- character(0)
  checks <- list()

  # ── 1. Schema: output columns ──
  expected_cols <- inference_output_columns()
  missing_cols <- setdiff(expected_cols, names(results))
  checks$schema <- list(
    expected = length(expected_cols),
    present  = length(expected_cols) - length(missing_cols),
    missing  = missing_cols,
    pass     = length(missing_cols) == 0
  )
  if (length(missing_cols) > 0) {
    issues <- c(issues, sprintf("Missing inference columns: %s",
                                paste(missing_cols, collapse = ", ")))
  }

  # ── 2. NPI uniqueness ──
  if ("npi" %in% names(results)) {
    n_distinct_npi <- dplyr::n_distinct(results$npi)
    n_dup <- n - n_distinct_npi
    checks$npi_uniqueness <- list(
      n_rows    = n,
      n_unique  = n_distinct_npi,
      n_dups    = n_dup,
      pass      = n_dup == 0
    )
    if (n_dup > 0) {
      issues <- c(issues, sprintf(
        "%d duplicate NPIs in output (%d rows, %d unique)", n_dup, n, n_distinct_npi))
    }
  }

  # ── 3. NPI type and format ──
  if ("npi" %in% names(results)) {
    npi_is_char <- is.character(results$npi)
    bad_format <- if (npi_is_char) sum(!grepl("^\\d{10}$", results$npi)) else NA_integer_
    checks$npi_schema <- list(
      is_character = npi_is_char,
      bad_format   = bad_format,
      pass         = npi_is_char && (is.na(bad_format) || bad_format == 0)
    )
    if (!npi_is_char) {
      issues <- c(issues, sprintf("NPI column is %s (expected character)", class(results$npi)[1]))
    } else if (bad_format > 0) {
      issues <- c(issues, sprintf("%d NPIs have non-10-digit format", bad_format))
    }
  }

  # ── 4. Confidence bounds [0, 1] ──
  if ("inference_confidence" %in% names(results)) {
    conf <- results$inference_confidence
    conf_valid <- !is.na(conf)
    n_below_0 <- sum(conf[conf_valid] < 0)
    n_above_1 <- sum(conf[conf_valid] > 1)
    n_na <- sum(is.na(conf))
    pct_no_location <- 100 * mean(conf == 0, na.rm = TRUE)
    pct_high <- 100 * mean(conf >= 0.7, na.rm = TRUE)
    pct_medium <- 100 * mean(conf >= 0.4 & conf < 0.7, na.rm = TRUE)
    pct_low <- 100 * mean(conf > 0 & conf < 0.4, na.rm = TRUE)

    checks$confidence <- list(
      n_below_0     = n_below_0,
      n_above_1     = n_above_1,
      n_na          = n_na,
      pct_high      = round(pct_high, 1),
      pct_medium    = round(pct_medium, 1),
      pct_low       = round(pct_low, 1),
      pct_zero      = round(pct_no_location, 1),
      pass          = n_below_0 == 0 && n_above_1 == 0
    )

    if (n_below_0 > 0 || n_above_1 > 0) {
      issues <- c(issues, sprintf(
        "Confidence out of bounds [0,1]: %d below 0, %d above 1", n_below_0, n_above_1))
    }
    if (pct_no_location > 50) {
      issues <- c(issues, sprintf(
        "%.1f%% of inferences have confidence=0 (no_location); expected <50%%",
        pct_no_location))
    }

    cat(sprintf("  QA [%s]: confidence distribution: high(>=0.7)=%.0f%%, medium=%.0f%%, low=%.0f%%, zero=%.0f%%\n",
                context, pct_high, pct_medium, pct_low, pct_no_location))
  }

  # ── 5. Phase partition breakdown ──
  if ("inference_source" %in% names(results)) {
    source_tab <- as.data.frame(table(results$inference_source, useNA = "ifany"),
                                stringsAsFactors = FALSE)
    names(source_tab) <- c("source", "count")
    source_tab$pct <- round(100 * source_tab$count / n, 1)

    checks$phase_partition <- list(
      breakdown = as.list(stats::setNames(source_tab$count, source_tab$source)),
      n_total   = n,
      pass      = TRUE
    )

    cat(sprintf("  QA [%s]: phase partition:\n", context))
    for (i in seq_len(nrow(source_tab))) {
      cat(sprintf("    %s: %d (%.1f%%)\n", source_tab$source[i],
                  source_tab$count[i], source_tab$pct[i]))
    }
  }

  # ── 6. Single-program concentration (top program > 30% = suspicious) ──
  if ("inferred_program" %in% names(results)) {
    matched <- results$inferred_program[!is.na(results$inferred_program)]
    n_matched <- length(matched)
    top_program <- NA_character_
    top_pct <- 0
    if (n_matched > 10) {
      tab <- sort(table(matched), decreasing = TRUE)
      top_program <- names(tab)[1]
      top_pct <- round(100 * tab[1] / n_matched, 1)
    }
    checks$concentration <- list(
      n_matched    = n_matched,
      top_program  = top_program,
      top_pct      = top_pct,
      pass         = top_pct <= 30
    )
    if (top_pct > 30) {
      issues <- c(issues, sprintf(
        "Top inferred program '%s' accounts for %.1f%% of matches (>30%% is suspicious)",
        top_program, top_pct))
    }
  }

  # ── 7. Distance plausibility (>500 km matches are state-centroid artifacts) ──
  if ("distance_km" %in% names(results)) {
    far_matches <- sum(!is.na(results$distance_km) & results$distance_km > 500)
    pct_far <- if (n > 0) round(100 * far_matches / n, 1) else 0
    median_dist <- round(stats::median(results$distance_km, na.rm = TRUE), 1)
    checks$distance <- list(
      n_far_500km  = far_matches,
      pct_far      = pct_far,
      median_km    = median_dist,
      pass         = TRUE  # informational, not a failure
    )
    if (far_matches > 0) {
      cat(sprintf("  QA [%s]: %d matches (%.1f%%) have distance > 500 km (median=%.0f km)\n",
                  context, far_matches, pct_far, median_dist))
    }
  }

  # ── 8. Geographic plausibility: inferred_state vs geocoded state ──
  if (all(c("inferred_state", "inference_state") %in% names(results))) {
    both_known <- !is.na(results$inferred_state) & !is.na(results$inference_state)
    n_comparable <- sum(both_known)
    if (n_comparable > 0) {
      state_match_pct <- round(100 * mean(
        results$inferred_state[both_known] == results$inference_state[both_known]), 1)
      checks$geo_plausibility <- list(
        n_comparable     = n_comparable,
        state_match_pct  = state_match_pct,
        pass             = TRUE  # informational
      )
      cat(sprintf("  QA [%s]: inferred state matches geocoded state %.1f%% of the time (%d pairs)\n",
                  context, state_match_pct, n_comparable))
    }
  }

  # ── 9. Inference method coverage ──
  if ("inference_method" %in% names(results)) {
    n_no_method <- sum(is.na(results$inference_method) | results$inference_method == "")
    checks$method_coverage <- list(
      n_missing = n_no_method,
      pct_missing = round(100 * n_no_method / max(n, 1L), 1),
      pass = n_no_method == 0
    )
    if (n_no_method > 0) {
      issues <- c(issues, sprintf(
        "%d rows (%.1f%%) have missing inference_method", n_no_method,
        100 * n_no_method / n))
    }
  }

  # ── Emit warnings ──
  pass <- length(issues) == 0
  if (!pass) {
    warning(sprintf("Inference QA [%s]: %d issue(s):\n  - %s",
                    context, length(issues), paste(issues, collapse = "\n  - ")))
  }

  # ── Write structured JSON audit artifact ──
  if (write_artifact) {
    audit_dir <- here::here("artifacts", "audit")
    if (!dir.exists(audit_dir)) dir.create(audit_dir, recursive = TRUE)

    audit_payload <- list(
      validator  = "validate_inference_qa",
      context    = context,
      timestamp  = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
      n_rows     = n,
      pass       = pass,
      n_issues   = length(issues),
      issues     = issues,
      checks     = checks
    )

    audit_path <- file.path(audit_dir, sprintf("inference_qa_%s.json", context))
    tryCatch(
      jsonlite::write_json(audit_payload, audit_path, pretty = TRUE, auto_unbox = TRUE),
      error = function(e) {
        cat(sprintf("  QA [%s]: WARNING \u2014 failed to write audit JSON: %s\n", context, e$message))
      }
    )
    if (file.exists(audit_path)) {
      cat(sprintf("  QA [%s]: audit artifact written to %s\n", context, audit_path))
    }
  }

  invisible(list(
    n      = n,
    issues = issues,
    checks = checks,
    pass   = pass
  ))
}


#' Canonical US Census Region Classification
#'
#' Classifies a 2-character state abbreviation into Census regions.
#' Covers all 50 states + DC + PR. Returns "Unknown" for unrecognized values.
#'
#' @param state_abbr Character vector of 2-character state abbreviations
#' @return Character vector of region names
#' @export
classify_us_region <- function(state_abbr) {
  dplyr::case_when(
    state_abbr %in% c("CT","ME","MA","NH","RI","VT","NJ","NY","PA") ~ "Northeast",
    state_abbr %in% c("IL","IN","MI","OH","WI","IA","KS","MN","MO","NE","ND","SD") ~ "Midwest",
    state_abbr %in% c("DE","DC","FL","GA","MD","NC","SC","VA","WV",
                       "AL","KY","MS","TN","AR","LA","OK","TX") ~ "South",
    state_abbr %in% c("AZ","CO","ID","MT","NV","NM","UT","WY",
                       "AK","CA","HI","OR","WA") ~ "West",
    state_abbr == "PR" ~ "Puerto Rico",
    TRUE ~ "Unknown"
  )
}
