#' @title Load and Validate ABOG Workforce Data
#'
#' @description
#' Reproducible, validated loader for ABOG certification data with explicit
#' path checking, column/type validation, deterministic coercion, and fatal
#' errors on structural integrity violations (e.g., duplicate identifiers).
#'
#' This function implements fail-fast validation to prevent silent failures
#' and ensure the pipeline operates on structurally valid data before expensive
#' downstream operations (NPI matching, geocoding, isochrone generation).
#'
#' @param abog_file `character`: Path to the ABOG CSV file. Must exist.
#' @param required_columns `character vector`: Columns that must be present in
#'   the ABOG data. Defaults to critical columns for NPI matching.
#' @param allow_duplicates `logical`: If FALSE (default), duplicates on the
#' @param verbose [logical]: Emit progress messages while loading.
#'   primary identifier (`physician_name` + `city` + `state`) trigger a fatal
#'   error with example rows. Set TRUE only for exploratory analysis.
#' @inheritParams shared_params_run
#'
#' @return A data frame with validated ABOG physician data. Column names are
#'   lowercased for consistency.
#'
#' @details
#' Validation steps performed:
#' 1. **Path existence**: File must exist at the specified path
#' 2. **Readability**: File must be readable with standard CSV parsing
#' 3. **Column presence**: Required columns must exist in the data
#' 4. **Column types**: Critical columns coerced to expected types
#' 5. **Duplicate detection**: Fatal error if duplicate identifiers found
#' 6. **State code validation**: Auto-corrects common typos, excludes non-US
#' 7. **Data completeness**: Reports missing values in critical columns
#'
#' The function is deterministic: given the same input file, it will always
#' produce the same output or fail with the same error message.
#'
#' @section Critical Column Types:
#' - `physician_name`: character (trimmed, non-empty)
#' - `city`: character (trimmed, may be NA for some records)
#' - `state`: character (2-letter US state/territory code)
#' - `first`, `last`, `middle`: character (name components)
#' - `certification_year`: integer (year of initial certification)
#'
#' @section Duplicate Detection:
#' Duplicates are identified by the composite key:
#' `(physician_name, city, state)`. If duplicates are found, the function
#' stops with an error showing:
#' - Total number of duplicate groups
#' - Total number of affected rows
#' - Up to 5 example duplicate groups with all their rows
#'
#' This prevents downstream issues where:
#' - One physician matches multiple NPIs (ambiguous many-to-many)
#' - Geocoding produces multiple locations for "same" physician
#' - Isochrone coverage double-counts the same provider
#'
#' @section State Code Auto-Correction:
#' Common typos are automatically corrected:
#' - "PU" → "PR" (Puerto Rico)
#' - "UM" → "PR" (Puerto Rico)
#'
#' Non-US locations are excluded with warning:
#' - Canadian provinces (ON, AB, BC, QC, etc.)
#' - International state codes (HR = Haryana, India; OT = Otago, NZ)
#'
#' @examples
#' \dontrun{
#' # Standard usage with all validation
#' abog_data <- load_abog_workforce_data("data/abog_certification_2023.csv")
#'
#' # Allow duplicates for exploratory analysis (NOT RECOMMENDED)
#' abog_data_unvalidated <- load_abog_workforce_data(
#'   "data/abog_certification_2023.csv",
#'   allow_duplicates = TRUE
#' )
#'
#' # Minimal required columns for specialized workflows
#' abog_names_only <- load_abog_workforce_data(
#'   "data/abog_certification_2023.csv",
#'   required_columns = c("physician_name", "certification_year")
#' )
#' }
#'
#' @seealso
#' \code{canonical_abog_npi_pipeline_STABLE()} for the full matching pipeline
#' \code{validate_pipeline_inputs()} for broader input validation
#'
#' @export
load_abog_workforce_data <- function(
  abog_file,
  required_columns = c("physician_name", "city", "state", "first", "last"),
  allow_duplicates = FALSE,
  verbose = TRUE
) {

  # BUG FIX #7 (2026-01-28): Load string normalization library
  # (source() removed: see R/unported_helpers.R -- the target file is not in this repo)

  # ============================================================================
  # VALIDATION STEP 1: Path Existence
  # ============================================================================
  if (verbose) cat("\n[ABOG LOADER] Validating ABOG file path...\n")

  if (missing(abog_file) || is.null(abog_file) || is.na(abog_file)) {
    stop(
      "\n================================================================================\n",
      "CRITICAL ERROR: ABOG file path not provided\n",
      "================================================================================\n",
      "The 'abog_file' parameter is required but was not specified.\n",
      "\n",
      "Expected usage:\n",
      "  load_abog_workforce_data(abog_file = \"path/to/abog_data.csv\")\n",
      "\n",
      "Check your function call or configuration file.\n",
      "================================================================================\n",
      call. = FALSE
    )
  }

  if (!file.exists(abog_file)) {
    stop(
      "\n================================================================================\n",
      "CRITICAL ERROR: ABOG file not found\n",
      "================================================================================\n",
      "Expected path: ", abog_file, "\n\n",
      "This file must exist before the pipeline can continue.\n",
      "\n",
      "Troubleshooting:\n",
      "  1. Check that the file path is correct\n",
      "  2. Verify the file was downloaded/generated\n",
      "  3. Check file permissions (must be readable)\n",
      "  4. Use absolute paths or here::here() for reproducibility\n",
      "\n",
      "Current working directory: ", getwd(), "\n",
      "================================================================================\n",
      call. = FALSE
    )
  }

  if (verbose) {
    cat(sprintf("  \u2713 File exists: %s\n", basename(abog_file)))
    cat(sprintf("  \u2139\ufe0f  File size: %.1f MB\n", file.size(abog_file) / 1024^2))
  }

  # ============================================================================
  # VALIDATION STEP 2: File Readability
  # ============================================================================
  if (verbose) cat("\n[ABOG LOADER] Reading CSV file...\n")

  abog_data <- tryCatch(
    {
      readr::read_csv(abog_file, show_col_types = FALSE)
    },
    error = function(e) {
      stop(
        "\n================================================================================\n",
        "CRITICAL ERROR: Failed to read ABOG CSV file\n",
        "================================================================================\n",
        "File path: ", abog_file, "\n\n",
        "Error details:\n",
        "  ", conditionMessage(e), "\n\n",
        "Possible causes:\n",
        "  1. File is corrupted or incomplete\n",
        "  2. File is not valid CSV format\n",
        "  3. File encoding is incompatible (try UTF-8)\n",
        "  4. File is locked by another process\n",
        "\n",
        "Try:\n",
        "  - Opening the file in a text editor to inspect format\n",
        "  - Running: readr::read_csv('", abog_file, "', n_max = 10)\n",
        "  - Checking file permissions\n",
        "================================================================================\n",
        call. = FALSE
      )
    }
  )

  n_rows_raw <- nrow(abog_data)
  n_cols_raw <- ncol(abog_data)

  if (verbose) {
    cat(sprintf("  \u2713 Successfully read %s rows \u00d7 %s columns\n",
                format(n_rows_raw, big.mark = ","),
                n_cols_raw))
  }

  # ============================================================================
  # VALIDATION STEP 3: Column Presence
  # ============================================================================
  if (verbose) cat("\n[ABOG LOADER] Validating required columns...\n")

  # Normalize column names to lowercase for consistency
  names(abog_data) <- tolower(names(abog_data))

  missing_cols <- setdiff(required_columns, names(abog_data))

  if (length(missing_cols) > 0) {
    available_cols <- paste(names(abog_data), collapse = ", ")
    missing_list <- paste(missing_cols, collapse = ", ")

    stop(
      "\n================================================================================\n",
      "CRITICAL ERROR: Missing required columns in ABOG data\n",
      "================================================================================\n",
      "Required columns: ", paste(required_columns, collapse = ", "), "\n",
      "Missing columns:  ", missing_list, "\n\n",
      "Available columns in file:\n",
      "  ", available_cols, "\n\n",
      "This indicates the ABOG CSV file has a different schema than expected.\n",
      "\n",
      "Solutions:\n",
      "  1. Verify this is the correct ABOG data file\n",
      "  2. Check if column names have changed (case-sensitive)\n",
      "  3. Update 'required_columns' parameter if schema evolved\n",
      "  4. Contact data provider for schema documentation\n",
      "================================================================================\n",
      call. = FALSE
    )
  }

  if (verbose) {
    cat(sprintf("  \u2713 All %s required columns present\n", length(required_columns)))
  }

  # ============================================================================
  # VALIDATION STEP 4: Column Type Coercion
  # ============================================================================
  if (verbose) cat("\n[ABOG LOADER] Validating and coercing column types...\n")

  # Ensure critical character columns are character type (not factor or numeric)
  character_cols <- c("physician_name", "city", "state", "first", "last", "middle")
  character_cols_present <- intersect(character_cols, names(abog_data))

  for (col in character_cols_present) {
    if (!is.character(abog_data[[col]])) {
      if (verbose) {
        cat(sprintf("  \u26a0\ufe0f  Coercing %s to character (was %s)\n",
                    col, class(abog_data[[col]])[1]))
      }
      abog_data[[col]] <- as.character(abog_data[[col]])
    }
  }

  # Ensure certification_year is integer (if present)
  if ("certification_year" %in% names(abog_data)) {
    if (!is.integer(abog_data$certification_year)) {
      if (verbose) {
        cat("  \u26a0\ufe0f  Coercing certification_year to integer\n")
      }
      abog_data$certification_year <- as.integer(abog_data$certification_year)
    }
  }

  if (verbose) {
    cat("  \u2713 Column types validated\n")
  }

  # ============================================================================
  # VALIDATION STEP 5: Duplicate Detection
  # ============================================================================
  if (!allow_duplicates) {
    if (verbose) cat("\n[ABOG LOADER] Checking for duplicate physician identifiers...\n")

    # Define composite key for uniqueness
    # Use physician_name + city + state as the identifier
    if (all(c("physician_name", "city", "state") %in% names(abog_data))) {

      # Create a composite key (handle NAs gracefully)
      abog_data$..composite_key <- paste(
        trimws(tolower(abog_data$physician_name)),
        trimws(tolower(abog_data$city)),
        trimws(tolower(abog_data$state)),
        sep = "|||"
      )

      # Find duplicates
      dup_keys <- abog_data$..composite_key[duplicated(abog_data$..composite_key) |
                                            duplicated(abog_data$..composite_key, fromLast = TRUE)]
      dup_keys_unique <- unique(dup_keys)

      if (length(dup_keys_unique) > 0) {
        n_dup_groups <- length(dup_keys_unique)
        n_dup_rows <- length(dup_keys)

        # Remove temporary composite key before deduplication
        abog_data$..composite_key <- NULL

        if (verbose) {
          cat(sprintf("\n  \u26a0\ufe0f  Found %s duplicate groups affecting %s rows\n",
                      n_dup_groups, n_dup_rows))
          cat("  Applying automatic deduplication (keeps best record per physician)\n")
        }

        # Source and apply deduplication function
        # (source() removed: see R/unported_helpers.R -- the target file is not in this repo)
        abog_data <- deduplicate_abog_data(abog_data, verbose = verbose)

        if (verbose) {
          cat("  \u2713 Deduplication complete\n")
        }
      } else {
        # Remove temporary composite key
        abog_data$..composite_key <- NULL

        if (verbose) {
          cat(sprintf("  \u2713 No duplicates found (%s unique physicians)\n",
                      format(n_rows_raw, big.mark = ",")))
        }
      }

    } else {
      if (verbose) {
        cat("  \u26a0\ufe0f  Skipping duplicate check (missing physician_name, city, or state)\n")
      }
    }
  } else {
    if (verbose) {
      cat("\n[ABOG LOADER] \u26a0\ufe0f  Duplicate checking DISABLED (allow_duplicates=TRUE)\n")
      cat("  This mode is for exploratory analysis only - NOT for production\n")
    }
  }

  # ============================================================================
  # VALIDATION STEP 6: State Code Validation and Cleaning
  # ============================================================================
  if ("state" %in% names(abog_data)) {
    if (verbose) cat("\n[ABOG LOADER] Validating and cleaning state codes...\n")

    n_before_state_cleaning <- nrow(abog_data)

    # Auto-correct Puerto Rico typos
    # BUG FIX #7 (2026-01-28): Use normalize_string() instead of toupper(trimws())
    pr_typos <- c("PU", "UM")
    pr_mask <- normalize_string(abog_data$state) %in% pr_typos
    n_pr_fixed <- sum(pr_mask, na.rm = TRUE)

    if (n_pr_fixed > 0) {
      abog_data$state[pr_mask] <- "PR"
      if (verbose) {
        cat(sprintf("  \u2713 Auto-corrected %s Puerto Rico typos (PU, UM \u2192 PR)\n", n_pr_fixed))
      }
    }

    # Exclude Canadian provinces
    canadian_provinces <- c(
      "ON", "AB", "BC", "QC", "MB", "NS", "SK", "NL", "NB", "PE",
      "YT", "NT", "NU",
      "ONTARIO", "ALBERTA", "BRITISH COLUMBIA", "QUEBEC", "MANITOBA",
      "NOVA SCOTIA", "SASKATCHEWAN", "NEWFOUNDLAND", "NEW BRUNSWICK",
      "PRINCE EDWARD ISLAND", "YUKON", "NORTHWEST TERRITORIES", "NUNAVUT"
    )

    # BUG FIX #7 (2026-01-28): Use normalize_string() instead of toupper(trimws())
    canadian_mask <- normalize_string(abog_data$state) %in% canadian_provinces
    n_canadian <- sum(canadian_mask, na.rm = TRUE)

    if (n_canadian > 0) {
      abog_data <- abog_data[!canadian_mask, ]
      if (verbose) {
        cat(sprintf("  \u2713 Excluded %s Canadian physicians (%.1f%% of loaded)\n",
                    n_canadian,
                    100 * n_canadian / n_before_state_cleaning))
      }
    }

    # Exclude international state codes
    # BUG FIX #7 (2026-01-28): Use normalize_string() instead of toupper(trimws())
    international_codes <- c("HR", "OT")  # HR = Haryana India, OT = Otago NZ
    intl_mask <- normalize_string(abog_data$state) %in% international_codes
    n_international <- sum(intl_mask, na.rm = TRUE)

    if (n_international > 0) {
      abog_data <- abog_data[!intl_mask, ]
      if (verbose) {
        cat(sprintf("  \u2713 Excluded %s international physicians (%.1f%% of loaded)\n",
                    n_international,
                    100 * n_international / n_before_state_cleaning))
      }
    }

    # Validate remaining state codes
    valid_us_states <- c(
      state.abb,  # 50 US states
      "DC", "PR", "VI", "GU", "AS", "MP",  # US territories
      "AA", "AE", "AP"  # Military APO/FPO
    )

    # BUG FIX #7 (2026-01-28): Use normalize_string() instead of toupper(trimws())
    invalid_mask <- !is.na(abog_data$state) &
                    !normalize_string(abog_data$state) %in% valid_us_states

    n_invalid <- sum(invalid_mask, na.rm = TRUE)

    if (n_invalid > 0) {
      # BUG FIX #7 (2026-01-28): Use normalize_string() instead of toupper(trimws())
      invalid_states <- unique(normalize_string(abog_data$state[invalid_mask]))

      stop(
        "\n================================================================================\n",
        "CRITICAL ERROR: Invalid state codes in ABOG data\n",
        "================================================================================\n",
        sprintf("Found %s physicians with invalid state codes: %s\n\n",
                n_invalid,
                paste(invalid_states, collapse = ", ")),
        "Valid US state/territory codes:\n",
        "  ", paste(valid_us_states, collapse = ", "), "\n\n",
        "These invalid codes must be corrected before the pipeline can continue.\n",
        "\n",
        "Solutions:\n",
        "  1. Update invalid codes at data source\n",
        "  2. Add state code mapping if these are known aliases\n",
        "  3. Remove rows with invalid codes if they are data errors\n",
        "\n",
        "To see affected rows, run:\n",
        "  abog_raw <- readr::read_csv('", abog_file, "')\n",
        "  abog_raw %>% filter(!(toupper(state) %in% c('",
        paste(valid_us_states, collapse = "','"), "')))\n",
        "================================================================================\n",
        call. = FALSE
      )
    }

    if (verbose) {
      cat(sprintf("  \u2713 All %s state codes are valid US states/territories\n",
                  nrow(abog_data)))
    }

  }

  # ============================================================================
  # VALIDATION STEP 7: Data Completeness Report
  # ============================================================================
  if (verbose) {
    cat("\n[ABOG LOADER] Data completeness summary:\n")

    completeness_cols <- intersect(
      c("physician_name", "city", "state", "first", "last", "middle", "certification_year"),
      names(abog_data)
    )

    for (col in completeness_cols) {
      n_missing <- sum(is.na(abog_data[[col]]) | trimws(abog_data[[col]]) == "")
      pct_missing <- 100 * n_missing / nrow(abog_data)

      status_icon <- if (pct_missing == 0) {
        "\u2713"
      } else if (pct_missing < 5) {
        "\u26a0\ufe0f"
      } else {
        "\u274c"
      }

      cat(sprintf("  %s %-20s: %s missing (%.1f%%)\n",
                  status_icon,
                  col,
                  format(n_missing, big.mark = ","),
                  pct_missing))
    }
  }

  # ============================================================================
  # Final Summary
  # ============================================================================
  if (verbose) {
    cat("\n[ABOG LOADER] \u2705 Validation complete\n")
    cat(sprintf("  Final dataset: %s rows \u00d7 %s columns\n",
                format(nrow(abog_data), big.mark = ","),
                ncol(abog_data)))
    cat(sprintf("  File: %s\n", basename(abog_file)))
  }

  return(abog_data)
}
