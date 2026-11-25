deduplicate_abog_data <- function(abog_data, verbose = TRUE) {
  if (verbose) {
    cat("\n[ABOG DEDUPLICATOR] Starting deduplication...\n")
    cat(sprintf("  Input rows: %s\n", format(nrow(abog_data), big.mark = ",")))
  }
  n_rows_original <- nrow(abog_data)
  required_cols <- c("physician_name", "city", "state")
  missing_cols <- setdiff(required_cols, names(abog_data))
  if (length(missing_cols) > 0) {
    stop("Cannot deduplicate - missing required columns: ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  npi_col <- intersect(c("npi", "NPI"), names(abog_data))
  npi_col <- if (length(npi_col)) npi_col[1L] else NULL
  conflict_col <- if ("subspecialty_name" %in% names(abog_data)) "subspecialty_name" else NULL

  quality_score <- rep(0, n_rows_original)
  if ("certStatus" %in% names(abog_data)) {
    cert_scores <- c("Non-Expiring" = 1000, "Active" = 900, "Certified" = 800,
                     "Active Candidate" = 500, "Not Certified" = 0)
    cert_key <- trimws(tolower(as.character(abog_data$certStatus)))
    for (status in names(cert_scores)) {
      idx <- which(cert_key == tolower(status))
      quality_score[idx] <- quality_score[idx] + cert_scores[[status]]
    }
  }
  if ("startDate" %in% names(abog_data)) {
    has_date <- !is.na(abog_data$startDate) & abog_data$startDate != "NA"
    quality_score[has_date] <- quality_score[has_date] + 100
  }
  has_complete_address <- !is.na(abog_data$city) & trimws(abog_data$city) != "" &
                          !is.na(abog_data$state) & trimws(abog_data$state) != ""
  quality_score[has_complete_address] <- quality_score[has_complete_address] + 50
  if (!is.null(conflict_col)) {
    sub <- trimws(as.character(abog_data[[conflict_col]]))
    has_sub <- !is.na(sub) & sub != "" & sub != "NA"
    quality_score[has_sub] <- quality_score[has_sub] + 25
  }

  out <- mysteryroster::deduplicate_roster(
    abog_data,
    key_cols = required_cols,
    npi_col = npi_col,
    score = quality_score,
    conflict_col = conflict_col,
    resolution_col = "duplicate_resolution"
  )

  if (verbose) {
    cat(sprintf("  Found %d duplicate groups affecting %d rows\n",
                out$counts$duplicate_groups, out$counts$duplicate_rows))
    cat(sprintf("  Removed %d duplicate rows; kept %s unique physicians\n",
                out$counts$removed_rows,
                format(out$counts$output_rows, big.mark = ",")))
    if (out$counts$conflict_groups > 0L) {
      cat(sprintf("  Flagged %d duplicate groups with conflicting subspecialty evidence\n",
                  out$counts$conflict_groups))
    }
  }

  res <- as.data.frame(out$data, stringsAsFactors = FALSE)
  attr(res, "deduplication_removed") <- out$removed
  attr(res, "deduplication_conflicts") <- out$conflicts
  attr(res, "deduplication_counts") <- out$counts
  res
}
