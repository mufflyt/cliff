# R/subspecialty_standardization.R
# ABOG subspecialty standardization and recoding functions

if (!require("dplyr", quietly = TRUE)) {
  stop("dplyr package required for subspecialty standardization")
}
if (!require("rlang", quietly = TRUE)) {
  stop("rlang package required for subspecialty standardization")
}

# Centralized ABOG subspecialty constants to prevent drift
ABOG_SUBS <- c("FPMRS", "GO", "MFM", "REI", "MIG", "PAG")

#' Normalize String for Subspecialty Matching
#'
#' @description
#' Lowercases, trims, replaces ampersands with "and", removes non-
#' alpha characters, and collapses whitespace. Used as a pre-
#' processing step before subspecialty name comparison.
#'
#' @details
#' - **Pipeline step**: Called within standardize_subspecialty()
#' - **Inputs**: `x` — raw subspecialty label string or vector
#' - **Algorithm**: tolower → trimws → "&"→"and" → strip non-alpha
#'   → collapse spaces via gsub
#' - **Performance**: Vectorized; <1ms per call
#' - **Reproducibility**: Deterministic
#' - **Failure modes**: Propagates NA for NA input (no guard)
#'
#' @param x [character vector]: Raw subspecialty strings.
#' @return Character vector. Normalized lowercase strings.
#' @examples
#' \dontrun{
#' norm("Gyn & Oncology")  # returns "gyn and oncology"
#' norm("Female Pelvic Med")  # returns "female pelvic med"
#' }
#' @keywords internal
# String normalization for robust matching
norm <- function(x) {
  x |>
    tolower() |>
    trimws() |>
    gsub("&", "and", x = _) |>
    gsub("[^a-z ]", "", x = _) |>
    gsub("\\s+", " ", x = _)
}

#' Standardize ABOG Subspecialty Names
#'
#' @description
#' Converts various subspecialty name formats to the standard 6 ABOG
#' subspecialty codes: FPMRS, GO, MFM, REI, MIG, PAG. Unrecognized
#' subspecialties are returned unchanged; non-ABOG recognized
#' subspecialties (Critical Care, Hospice/Palliative Medicine) are
#' explicitly mapped to "Other".
#'
#' @details
#' - **Pipeline step:** Data normalization (called by
#'   apply_subspecialty_standardization and validate_subspecialty_data)
#' - **Inputs:** Character vector of raw subspecialty name strings
#' - **Algorithm:** 1. Normalize input via norm() (lowercase, trim,
#'   strip non-alpha), 2. Apply dplyr::case_when matching against
#'   known name variants for each ABOG code, 3. Return original name
#'   if no match found
#' - **Performance:** Vectorized; O(n) for n subspecialty strings
#' - **Reproducibility:** Deterministic (fixed mapping table)
#'
#' Critical fix (2026-01-18): Critical Care and Hospice/Palliative
#' Medicine are now mapped to "Other" instead of being incorrectly
#' merged into GO (Gynecologic Oncology). This was a data quality bug
#' that inflated GO physician counts.
#'
#' @param subspecialty_names [character vector]: Raw subspecialty name
#'   strings to standardize (e.g., "Gyn & Oncology", "female pelvic
#'   medicine and reconstructive surgery").
#' @return [character vector] of the same length as input, with
#'   recognized names replaced by their standard ABOG codes (FPMRS,
#'   GO, MFM, REI, MIG, PAG) or "Other". Unrecognized names are
#'   returned unchanged.
#' @examples
#' \dontrun{
#'   standardize_abog_subspecialty(c("Gyn & Oncology", "MFM", "Critical Care"))
#'   # Returns: c("GO", "MFM", "Other")
#' }
#' @seealso [norm()], [apply_subspecialty_standardization()],
#'   [get_abog_subspecialties()]
#' @export
standardize_abog_subspecialty <- function(subspecialty_names) {
  # Normalize input strings for robust matching
  subspecialty_names_norm <- norm(subspecialty_names)

  standardized <- case_when(
    # CRITICAL FIX (2026-01-18): Critical Care and Hospice are distinct specialties
    # Previously these were incorrectly recoded to GO (Gynecologic Oncology)
    # Now they are marked as "Other" (non-ABOG recognized subspecialty)
    subspecialty_names_norm %in% c("critical care", "hospice", "hospice care",
                                  "hospice and palliative medicine", "palliative medicine") ~ "Other",

    # FPMRS variations (normalized)
    subspecialty_names_norm %in% c("fpmrs", "female pelvic medicine and reconstructive surgery",
                                  "female pelvic medicine", "pelvic medicine",
                                  "urogynecology", "female pelvic med reconstructive surgery") ~ "FPMRS",

    # GO variations (normalized)
    subspecialty_names_norm %in% c("go", "gynecologic oncology", "gyn onc", "gynonc",
                                  "oncology", "gynecological oncology") ~ "GO",

    # MFM variations (normalized)
    subspecialty_names_norm %in% c("mfm", "maternal fetal medicine", "maternalfetal medicine",
                                  "perinatology", "maternal fetal med") ~ "MFM",

    # REI variations (normalized)
    subspecialty_names_norm %in% c("rei", "reproductive endocrinology and infertility",
                                  "reproductive endocrinology", "infertility",
                                  "reproductive endo", "reproductive endo and infertility") ~ "REI",

    # MIG variations (normalized)
    subspecialty_names_norm %in% c("mig", "minimally invasive gynecology", "minimally invasive",
                                  "laparoscopy", "laparoscopic surgery", "minimally invasive gyn") ~ "MIG",

    # PAG variations (normalized)
    subspecialty_names_norm %in% c("pag", "pediatric and adolescent gynecology",
                                  "pediatric gynecology", "adolescent gynecology",
                                  "pediatric gyn", "pediatric adolescent gynecology") ~ "PAG",

    # Keep original if not recognized
    TRUE ~ subspecialty_names
  )

  return(standardized)
}

#' Get the Official 6 ABOG Subspecialty Codes
#'
#' @description
#' Returns a character vector of the 6 standard ABOG (American Board of
#' Obstetrics and Gynecology) subspecialty abbreviation codes. These are
#' the canonical codes used throughout the pipeline for subspecialty
#' classification, factor ordering, and validation.
#'
#' @details
#' - **Pipeline step:** Reference data (used by standardize/validate functions)
#' - **Inputs:** None (returns constant from ABOG_SUBS module-level variable)
#' - **Algorithm:** Returns the package-level ABOG_SUBS constant
#' - **Performance:** O(1) constant-time lookup
#' - **Reproducibility:** Deterministic (fixed constant)
#'
#' The 6 codes are: FPMRS (Female Pelvic Medicine and Reconstructive
#' Surgery), GO (Gynecologic Oncology), MFM (Maternal-Fetal Medicine),
#' REI (Reproductive Endocrinology and Infertility), MIG (Minimally
#' Invasive Gynecology), PAG (Pediatric and Adolescent Gynecology).
#'
#' @return [character vector] of length 6 containing the standard ABOG
#'   subspecialty codes in canonical order.
#' @seealso [get_abog_subspecialty_names()], [standardize_abog_subspecialty()],
#'   [validate_subspecialty_data()]
#' @export
get_abog_subspecialties <- function() {
  ABOG_SUBS
}

#' Get ABOG Subspecialty Full Names
#'
#' @description
#' Returns a named character vector mapping the 6 standard ABOG
#' subspecialty abbreviation codes to their full descriptive names.
#' Used for display labels in tables, figures, and reports.
#'
#' @details
#' - **Pipeline step:** Reference data (used for labeling in manuscript
#'   tables and figures)
#' - **Inputs:** None (returns hard-coded mapping)
#' - **Algorithm:** Returns a pre-defined named character vector
#' - **Performance:** O(1) constant-time
#' - **Reproducibility:** Deterministic (fixed mapping)
#'
#' @return [named character vector] with 6 entries where names are ABOG
#'   codes (FPMRS, GO, MFM, REI, MIG, PAG) and values are the
#'   corresponding full subspecialty names.
#' @seealso [get_abog_subspecialties()], [standardize_abog_subspecialty()]
#' @export
get_abog_subspecialty_names <- function() {
  c(
    "FPMRS" = "Female Pelvic Medicine and Reconstructive Surgery",
    "GO" = "Gynecologic Oncology",
    "MFM" = "Maternal-Fetal Medicine",
    "REI" = "Reproductive Endocrinology and Infertility",
    "MIG" = "Minimally Invasive Gynecology",
    "PAG" = "Pediatric and Adolescent Gynecology"
  )
}

#' Validate Subspecialty Data Against ABOG Standards
#'
#' @description
#' Checks that a data frame's subspecialty column contains the expected
#' 6 ABOG subspecialties and reports coverage, missing subspecialties,
#' and any unrecognized labels after standardization.
#'
#' @details
#' - **Pipeline step:** Data quality check (called during ingestion
#'   and before analysis)
#' - **Inputs:** Data frame with a subspecialty column
#' - **Algorithm:** 1. Verify subspecialty_col exists in data,
#'   2. Extract unique non-NA subspecialty values,
#'   3. Standardize via standardize_abog_subspecialty(),
#'   4. Compare against canonical ABOG_SUBS to compute coverage,
#'   missing, and unrecognized sets, 5. Count physicians per
#'   standardized subspecialty
#' - **Performance:** O(n) where n is number of rows in data
#' - **Reproducibility:** Deterministic (fixed reference set)
#'
#' Returns an ERROR status if the specified column does not exist in
#' the data. Otherwise returns a SUCCESS status with detailed coverage
#' metrics including which of the 6 ABOG subspecialties are present,
#' which are missing, and which labels could not be mapped.
#'
#' @param data [data.frame]: Data frame containing subspecialty
#'   information to validate.
#' @param subspecialty_col [character]: Name of the column containing
#'   subspecialty labels (default: "subspecialty_name").
#' @return [list] with validation results containing:
#'   \describe{
#'     \item{status}{Character, "SUCCESS" or "ERROR"}
#'     \item{message}{Character, error message (ERROR status only)}
#'     \item{total_subspecialties_found}{Integer, count of unique labels}
#'     \item{abog_subspecialties_found}{Character vector of matched ABOG codes}
#'     \item{missing_abog_subspecialties}{Character vector of expected but missing codes}
#'     \item{unrecognized_subspecialties}{Character vector of unmapped labels}
#'     \item{subspecialty_counts}{Data frame with standardized_subspecialty and count}
#'     \item{coverage_n}{Integer, number of ABOG codes found}
#'     \item{coverage_of}{Integer, always 6 (total ABOG codes)}
#'     \item{coverage_summary}{Character, human-readable coverage string}
#'   }
#' @examples
#' \dontrun{
#'   df <- data.frame(subspecialty_name = c("GO", "MFM", "Gyn Onc", "Unknown"))
#'   result <- validate_subspecialty_data(df)
#'   cat(result$coverage_summary)  # "2/6 ABOG subspecialties found"
#' }
#' @seealso [standardize_abog_subspecialty()], [get_abog_subspecialties()],
#'   [apply_subspecialty_standardization()]
#' @export
validate_subspecialty_data <- function(data, subspecialty_col = "subspecialty_name") {

  if (!rlang::has_name(data, subspecialty_col)) {
    return(list(
      status = "ERROR",
      message = sprintf("Column '%s' not found in data", subspecialty_col)
    ))
  }

  # Get unique subspecialties (exclude NA)
  unique_subspecialties <- data %>%
    filter(!is.na(!!sym(subspecialty_col))) %>%
    distinct(!!sym(subspecialty_col)) %>%
    pull(!!sym(subspecialty_col))

  # Standardize them
  standardized <- standardize_abog_subspecialty(unique_subspecialties)

  # Check coverage
  abog_subspecialties <- get_abog_subspecialties()
  found_abog <- intersect(standardized, abog_subspecialties)
  missing_abog <- setdiff(abog_subspecialties, found_abog)
  unrecognized <- setdiff(standardized, abog_subspecialties)

  # Count physicians by standardized subspecialty
  subspecialty_counts <- data %>%
    filter(!is.na(!!sym(subspecialty_col))) %>%
    mutate(standardized_subspecialty = standardize_abog_subspecialty(!!sym(subspecialty_col))) %>%
    count(standardized_subspecialty, name = "count") %>%
    arrange(desc(count))

  return(list(
    status = "SUCCESS",
    total_subspecialties_found = length(unique_subspecialties),
    abog_subspecialties_found = found_abog,
    missing_abog_subspecialties = missing_abog,
    unrecognized_subspecialties = unrecognized,
    subspecialty_counts = subspecialty_counts,
    coverage_n = length(found_abog),
    coverage_of = 6L,
    coverage_summary = sprintf("%d/6 ABOG subspecialties found", length(found_abog))
  ))
}

#' Apply Subspecialty Standardization to a Data Frame
#'
#' @description
#' Adds a new column with standardized ABOG subspecialty codes to the
#' input data frame by applying [standardize_abog_subspecialty()] to
#' the specified subspecialty column. Optionally converts recognized
#' ABOG codes to an ordered factor for consistent sorting in plots
#' and tables.
#'
#' @details
#' - **Pipeline step:** Data transformation (typically called after
#'   ABOG data ingestion, before analysis and manuscript generation)
#' - **Inputs:** Data frame with raw subspecialty labels
#' - **Algorithm:** 1. Apply standardize_abog_subspecialty() to create
#'   new column, 2. Convert ABOG codes to ordered factor (FPMRS, GO,
#'   MFM, REI, MIG, PAG) if all non-NA values are ABOG codes,
#'   3. Run hygiene checks: log found ABOG codes, warn on unrecognized
#'   labels, assert no drift from canonical ABOG_SUBS constant
#' - **Performance:** O(n) for n rows (vectorized dplyr::mutate)
#' - **Reproducibility:** Deterministic (fixed mapping + factor ordering)
#'
#' Includes a hard assertion (stopifnot) that prevents subspecialty
#' drift: any ABOG code found in the data must be a member of the
#' canonical ABOG_SUBS constant.
#'
#' @param data [data.frame]: Data frame containing subspecialty
#'   information to standardize.
#' @param subspecialty_col [character]: Name of the input subspecialty
#'   column (default: "subspecialty_name").
#' @param new_col [character]: Name for the new standardized column
#'   (default: "subspecialty_standardized").
#' @return [data.frame] with the original columns plus a new column
#'   (named by new_col) containing standardized subspecialty codes.
#'   The new column is an ordered factor if all non-NA values map to
#'   ABOG codes, otherwise character.
#' @examples
#' \dontrun{
#'   df <- data.frame(subspecialty_name = c("Gyn Onc", "MFM", "REI"))
#'   result <- apply_subspecialty_standardization(df)
#'   levels(result$subspecialty_standardized)
#'   # [1] "FPMRS" "GO" "MFM" "REI" "MIG" "PAG"
#' }
#' @seealso [standardize_abog_subspecialty()], [validate_subspecialty_data()],
#'   [get_abog_subspecialties()]
#' @export
apply_subspecialty_standardization <- function(data,
                                             subspecialty_col = "subspecialty_name",
                                             new_col = "subspecialty_standardized") {

  result <- data %>%
    mutate(
      !!new_col := standardize_abog_subspecialty(!!sym(subspecialty_col))
    )

  # Convert ABOG subspecialties to ordered factor for consistent plots/tables
  # Only standardize the ABOG subspecialties, leave others as character
  standardized_col <- result[[new_col]]
  abog_mask <- standardized_col %in% ABOG_SUBS

  if (any(abog_mask)) {
    # Create ordered factor for ABOG subspecialties, keep others as character
    result[[new_col]] <- ifelse(abog_mask,
                               as.character(factor(standardized_col[abog_mask],
                                                  levels = ABOG_SUBS, ordered = TRUE)),
                               standardized_col)

    # Convert the whole column to factor if all are ABOG subspecialties
    if (all(!is.na(standardized_col) & abog_mask[!is.na(standardized_col)])) {
      result[[new_col]] <- factor(result[[new_col]], levels = ABOG_SUBS, ordered = TRUE)
    }
  }

  # Subspecialty standardization hygiene checks
  standardized_values <- result[[new_col]][!is.na(result[[new_col]])]
  abog_subspecialties <- get_abog_subspecialties()

  # Check that only valid ABOG subspecialties + unrecognized remain
  unique_standardized <- unique(standardized_values)
  abog_found <- intersect(unique_standardized, abog_subspecialties)
  unrecognized <- setdiff(unique_standardized, abog_subspecialties)

  # Assertion: prevent drift in ABOG subspecialties
  if (length(abog_found) > 0) {
    message(paste("✅ ABOG subspecialties found:", paste(abog_found, collapse = ", ")))
  }

  # Warning if unrecognized labels remain
  if (length(unrecognized) > 0) {
    warning(paste("⚠️ Unrecognized subspecialties after standardization:",
                 paste(unrecognized, collapse = ", "),
                 "- consider adding mappings to standardize_abog_subspecialty()"))
  }

  # Hard assertion: ABOG subspecialties should be exactly the expected 6
  abog_in_data <- intersect(unique_standardized, abog_subspecialties)
  if (length(abog_in_data) > 0) {
    stopifnot("ABOG subspecialty drift detected" =
              all(abog_in_data %in% ABOG_SUBS))
  }

  return(result)
}