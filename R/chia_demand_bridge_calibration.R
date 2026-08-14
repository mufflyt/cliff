# CHIA all-payer demand-bridge CALIBRATION engine.
#
# WHY THIS EXISTS. R/chia_medicare_bridge.R ships the PROVISIONAL bridge
# contract (chia_bridge_contract(), calibration_status = "not_calibrated") and
# the refusing applier (bridge_medicare_to_all_payer()). Its docstring promises
# that "a real CHIA APCD / Medicare FFS extract ... sets calibration_status =
# 'calibrated'". This file is that extract path: it takes real CHIA claims plus
# population denominators, estimates an age-graded all-payer/Medicare-FFS demand
# bridge with bootstrap uncertainty, and only stamps "calibrated" when the fit
# clears explicit sufficiency gates. apply_chia_demand_bridge() then REFUSES to
# emit an absolute national demand estimate unless that status is "calibrated" --
# so an uncalibrated fit can never masquerade as an identified denominator.

#' Calibrate an all-payer demand bridge from CHIA claims
#'
#' Estimates age-specific VOLUME ratios of all-payer utilization to Medicare
#' FFS utilization (`all_workload / ffs_workload`), so the resulting
#' `bridge_multiplier` carries the same meaning as R/chia_medicare_bridge.R's
#' `1 / capture` multiplier and [apply_chia_demand_bridge()]'s
#' `ffs_workload * multiplier` recovers an all-payer VOLUME. Workload may be
#' measured using wRVUs, encounters, or patients.
#'
#' @param chia_claims Claims-level or summarized CHIA utilization.
#' @param population Population denominators by year, age band, and payer. Used
#'   for the informational `*_rate_per_1000` diagnostics only; the volume-ratio
#'   bridge multiplier does not depend on it.
#' @param year_col Column containing calendar year.
#' @param age_col Column containing patient age.
#' @param payer_col Column containing payer.
#' @param ffs_values Values identifying Medicare FFS.
#' @param specialty_col Optional specialty column.
#' @param specialty_values Optional specialty values to retain.
#' @param wrvu_col Optional work-RVU column.
#' @param encounter_col Optional encounter count column.
#' @param patient_col Optional patient identifier column.
#' @param population_year_col Population year column.
#' @param population_age_col Population age column.
#' @param population_payer_col Population payer column.
#' @param population_n_col Population denominator column.
#' @param age_band_width Width of age bands.
#' @param min_ffs_workload Minimum FFS workload for calibration.
#' @param min_all_workload Minimum all-payer workload for calibration.
#' @param n_boot Number of bootstrap replicates.
#' @param seed Random seed.
#' @param save_dir Optional directory for saved calibration artifacts.
#'
#' @return A named list containing bridge estimates, diagnostics, and status.
#' @export
calibrate_chia_demand_bridge <- function(
    chia_claims,
    population,
    year_col = "year",
    age_col = "age",
    payer_col = "payer",
    ffs_values = c("Medicare FFS", "MEDICARE_FFS"),
    specialty_col = NULL,
    specialty_values = NULL,
    wrvu_col = "wrvu",
    encounter_col = NULL,
    patient_col = NULL,
    population_year_col = "year",
    population_age_col = "age",
    population_payer_col = "payer",
    population_n_col = "population",
    age_band_width = 5L,
    min_ffs_workload = 50,
    min_all_workload = 100,
    n_boot = 1000L,
    seed = 20260813L,
    save_dir = NULL) {

  base::message("Starting CHIA demand-bridge calibration.")
  base::message(
    "CHIA input rows: ",
    scales::comma(base::nrow(chia_claims))
  )
  base::message(
    "Population input rows: ",
    scales::comma(base::nrow(population))
  )
  base::message("Age-band width: ", age_band_width)
  base::message("Bootstrap replicates: ", scales::comma(n_boot))

  required_claim_cols <- c(
    year_col,
    age_col,
    payer_col
  )

  missing_claim_cols <- base::setdiff(
    required_claim_cols,
    base::names(chia_claims)
  )

  if (base::length(missing_claim_cols) > 0L) {
    base::stop(
      "Missing CHIA columns: ",
      base::paste(missing_claim_cols, collapse = ", ")
    )
  }

  required_pop_cols <- c(
    population_year_col,
    population_age_col,
    population_payer_col,
    population_n_col
  )

  missing_pop_cols <- base::setdiff(
    required_pop_cols,
    base::names(population)
  )

  if (base::length(missing_pop_cols) > 0L) {
    base::stop(
      "Missing population columns: ",
      base::paste(missing_pop_cols, collapse = ", ")
    )
  }

  if (!is.null(specialty_col)) {
    if (!specialty_col %in% base::names(chia_claims)) {
      base::stop("specialty_col is not present in chia_claims.")
    }
  }

  has_wrvu <- wrvu_col %in% base::names(chia_claims)
  has_encounters <- !is.null(encounter_col) &&
    encounter_col %in% base::names(chia_claims)
  has_patient <- !is.null(patient_col) &&
    patient_col %in% base::names(chia_claims)

  if (!has_wrvu && !has_encounters && !has_patient) {
    base::stop(
      "Need wrvu_col, encounter_col, or patient_col to measure workload."
    )
  }

  workload_basis <- dplyr::case_when(
    has_wrvu ~ "wrvu",
    has_encounters ~ "encounters",
    has_patient ~ "unique_patients",
    TRUE ~ NA_character_
  )

  base::message("Selected workload basis: ", workload_basis)

  claims_prepared <- chia_claims |>
    dplyr::mutate(
      .bridge_year = base::as.integer(.data[[year_col]]),
      .bridge_age = base::as.numeric(.data[[age_col]]),
      .bridge_payer = base::as.character(.data[[payer_col]])
    ) |>
    dplyr::filter(
      !base::is.na(.data$.bridge_year),
      !base::is.na(.data$.bridge_age),
      .data$.bridge_age >= 0
    )

  if (!is.null(specialty_col) &&
      !is.null(specialty_values)) {
    claims_prepared <- claims_prepared |>
      dplyr::filter(
        .data[[specialty_col]] %in% specialty_values
      )

    base::message(
      "Rows after specialty restriction: ",
      scales::comma(base::nrow(claims_prepared))
    )
  }

  claims_prepared <- claims_prepared |>
    dplyr::mutate(
      age_band_lower = base::floor(
        .data$.bridge_age / age_band_width
      ) * age_band_width,
      age_band_upper = .data$age_band_lower +
        age_band_width - 1,
      age_band = base::paste0(
        .data$age_band_lower,
        "-",
        .data$age_band_upper
      ),
      is_medicare_ffs = .data$.bridge_payer %in% ffs_values
    )

  base::message(
    "Rows after age-band construction: ",
    scales::comma(base::nrow(claims_prepared))
  )

  if (workload_basis == "wrvu") {
    claims_prepared <- claims_prepared |>
      dplyr::mutate(
        workload = base::as.numeric(.data[[wrvu_col]])
      )
  }

  if (workload_basis == "encounters") {
    claims_prepared <- claims_prepared |>
      dplyr::mutate(
        workload = base::as.numeric(.data[[encounter_col]])
      )
  }

  if (workload_basis == "unique_patients") {
    claims_prepared <- claims_prepared |>
      dplyr::mutate(
        workload = 1
      )
  }

  population_prepared <- population |>
    dplyr::mutate(
      .bridge_year = base::as.integer(
        .data[[population_year_col]]
      ),
      .bridge_age = base::as.numeric(
        .data[[population_age_col]]
      ),
      .bridge_payer = base::as.character(
        .data[[population_payer_col]]
      ),
      population_n = base::as.numeric(
        .data[[population_n_col]]
      ),
      age_band_lower = base::floor(
        .data$.bridge_age / age_band_width
      ) * age_band_width,
      age_band_upper = .data$age_band_lower +
        age_band_width - 1,
      age_band = base::paste0(
        .data$age_band_lower,
        "-",
        .data$age_band_upper
      ),
      is_medicare_ffs = .data$.bridge_payer %in% ffs_values
    ) |>
    dplyr::filter(
      !base::is.na(.data$population_n),
      .data$population_n > 0
    )

  base::message("Aggregating CHIA workload by age and payer.")

  if (workload_basis == "unique_patients") {
    utilization_cells <- claims_prepared |>
      dplyr::group_by(
        .data$.bridge_year,
        .data$age_band_lower,
        .data$age_band_upper,
        .data$age_band,
        .data$is_medicare_ffs
      ) |>
      dplyr::summarise(
        workload = dplyr::n_distinct(
          .data[[patient_col]]
        ),
        .groups = "drop"
      )
  } else {
    utilization_cells <- claims_prepared |>
      dplyr::group_by(
        .data$.bridge_year,
        .data$age_band_lower,
        .data$age_band_upper,
        .data$age_band,
        .data$is_medicare_ffs
      ) |>
      dplyr::summarise(
        workload = base::sum(
          .data$workload,
          na.rm = TRUE
        ),
        .groups = "drop"
      )
  }

  population_cells <- population_prepared |>
    dplyr::group_by(
      .data$.bridge_year,
      .data$age_band_lower,
      .data$age_band_upper,
      .data$age_band,
      .data$is_medicare_ffs
    ) |>
    dplyr::summarise(
      population_n = base::sum(
        .data$population_n,
        na.rm = TRUE
      ),
      .groups = "drop"
    )

  rate_cells <- utilization_cells |>
    dplyr::left_join(
      population_cells,
      by = c(
        ".bridge_year",
        "age_band_lower",
        "age_band_upper",
        "age_band",
        "is_medicare_ffs"
      )
    ) |>
    dplyr::mutate(
      workload_per_1000 = 1000 * .data$workload /
        .data$population_n
    )

  base::message("Constructing all-payer denominators.")

  all_workload <- claims_prepared |>
    dplyr::group_by(
      .data$.bridge_year,
      .data$age_band_lower,
      .data$age_band_upper,
      .data$age_band
    ) |>
    dplyr::summarise(
      all_workload = base::sum(
        .data$workload,
        na.rm = TRUE
      ),
      .groups = "drop"
    )

  all_population <- population_prepared |>
    dplyr::group_by(
      .data$.bridge_year,
      .data$age_band_lower,
      .data$age_band_upper,
      .data$age_band
    ) |>
    dplyr::summarise(
      all_population = base::sum(
        .data$population_n,
        na.rm = TRUE
      ),
      .groups = "drop"
    )

  ffs_cells <- rate_cells |>
    dplyr::filter(.data$is_medicare_ffs) |>
    dplyr::transmute(
      .bridge_year = .data$.bridge_year,
      age_band_lower = .data$age_band_lower,
      age_band_upper = .data$age_band_upper,
      age_band = .data$age_band,
      ffs_workload = .data$workload,
      ffs_population = .data$population_n,
      ffs_rate_per_1000 = .data$workload_per_1000
    )

  bridge_cells <- all_workload |>
    dplyr::left_join(
      all_population,
      by = c(
        ".bridge_year",
        "age_band_lower",
        "age_band_upper",
        "age_band"
      )
    ) |>
    dplyr::left_join(
      ffs_cells,
      by = c(
        ".bridge_year",
        "age_band_lower",
        "age_band_upper",
        "age_band"
      )
    ) |>
    dplyr::mutate(
      all_rate_per_1000 = 1000 * .data$all_workload /
        .data$all_population,
      # SEMANTIC A (volume multiplier). The bridge multiplier is a VOLUME
      # ratio -- all-payer workload over Medicare-FFS workload -- so it means
      # exactly what R/chia_medicare_bridge.R's multiplier means (1 / capture)
      # and apply_chia_demand_bridge()'s `ffs_workload * multiplier` recovers
      # the all-payer VOLUME. It is population-free by construction; the
      # *_rate_per_1000 columns above are informational diagnostics only and
      # do NOT enter the ratio (a rate ratio would carry an ffs_pop/all_pop
      # factor and silently under-count volume downstream).
      bridge_ratio = .data$all_workload /
        .data$ffs_workload,
      eligible = (
        .data$ffs_workload >= min_ffs_workload &
          .data$all_workload >= min_all_workload &
          base::is.finite(.data$bridge_ratio) &
          .data$bridge_ratio > 0
      )
    )

  eligible_cells <- bridge_cells |>
    dplyr::filter(.data$eligible)

  base::message(
    "Eligible age-year calibration cells: ",
    scales::comma(base::nrow(eligible_cells)),
    " of ",
    scales::comma(base::nrow(bridge_cells))
  )

  if (base::nrow(eligible_cells) < 3L) {
    base::stop(
      "Fewer than three eligible age-year cells; bridge not calibrated."
    )
  }

  base::message("Fitting age-graded log-linear bridge.")

  bridge_fit <- stats::lm(
    base::log(bridge_ratio) ~
      splines::ns(age_band_lower, df = 3) +
      base::factor(.bridge_year),
    weights = ffs_workload,
    data = eligible_cells
  )

  prediction_ages <- bridge_cells |>
    dplyr::distinct(
      .data$age_band_lower,
      .data$age_band_upper,
      .data$age_band
    ) |>
    dplyr::arrange(.data$age_band_lower)

  reference_year <- eligible_cells |>
    dplyr::summarise(
      reference_year = base::max(.data$.bridge_year)
    ) |>
    dplyr::pull(.data$reference_year)

  prediction_frame <- prediction_ages |>
    dplyr::mutate(
      .bridge_year = reference_year
    )

  model_prediction <- stats::predict(
    bridge_fit,
    newdata = prediction_frame,
    se.fit = TRUE
  )

  calibrated_bridge <- prediction_frame |>
    dplyr::mutate(
      log_bridge = base::as.numeric(model_prediction$fit),
      log_bridge_se = base::as.numeric(model_prediction$se.fit),
      bridge_multiplier = base::exp(.data$log_bridge),
      bridge_low = base::exp(
        .data$log_bridge -
          stats::qnorm(0.975) * .data$log_bridge_se
      ),
      bridge_high = base::exp(
        .data$log_bridge +
          stats::qnorm(0.975) * .data$log_bridge_se
      )
    )

  base::message("Running bootstrap uncertainty calibration.")

  base::set.seed(seed)

  bootstrap_draws <- purrr::map_dfr(
    base::seq_len(n_boot),
    function(bootstrap_id) {

      sampled_cells <- eligible_cells |>
        dplyr::slice_sample(
          n = base::nrow(eligible_cells),
          replace = TRUE
        )

      sampled_years <- base::unique(
        sampled_cells$.bridge_year
      )

      if (base::length(sampled_years) < 2L) {
        return(tibble::tibble())
      }

      sampled_fit <- base::tryCatch(
        stats::lm(
          base::log(bridge_ratio) ~
            splines::ns(age_band_lower, df = 3) +
            base::factor(.bridge_year),
          weights = ffs_workload,
          data = sampled_cells
        ),
        error = function(e) NULL
      )

      if (base::is.null(sampled_fit)) {
        return(tibble::tibble())
      }

      sampled_prediction <- base::tryCatch(
        stats::predict(
          sampled_fit,
          newdata = prediction_frame
        ),
        error = function(e) NULL
      )

      if (base::is.null(sampled_prediction)) {
        return(tibble::tibble())
      }

      prediction_frame |>
        dplyr::transmute(
          bootstrap_id = bootstrap_id,
          age_band_lower = .data$age_band_lower,
          age_band_upper = .data$age_band_upper,
          age_band = .data$age_band,
          bridge_multiplier = base::exp(
            base::as.numeric(sampled_prediction)
          )
        )
    }
  )

  base::message(
    "Successful bootstrap rows: ",
    scales::comma(base::nrow(bootstrap_draws))
  )

  bootstrap_summary <- bootstrap_draws |>
    dplyr::group_by(
      .data$age_band_lower,
      .data$age_band_upper,
      .data$age_band
    ) |>
    dplyr::summarise(
      bridge_mean = base::mean(
        .data$bridge_multiplier,
        na.rm = TRUE
      ),
      bridge_sd = stats::sd(
        .data$bridge_multiplier,
        na.rm = TRUE
      ),
      bridge_p25 = stats::quantile(
        .data$bridge_multiplier,
        probs = 0.25,
        na.rm = TRUE,
        names = FALSE
      ),
      bridge_median = stats::median(
        .data$bridge_multiplier,
        na.rm = TRUE
      ),
      bridge_p75 = stats::quantile(
        .data$bridge_multiplier,
        probs = 0.75,
        na.rm = TRUE,
        names = FALSE
      ),
      bridge_boot_low = stats::quantile(
        .data$bridge_multiplier,
        probs = 0.025,
        na.rm = TRUE,
        names = FALSE
      ),
      bridge_boot_high = stats::quantile(
        .data$bridge_multiplier,
        probs = 0.975,
        na.rm = TRUE,
        names = FALSE
      ),
      n_boot_success = dplyr::n(),
      .groups = "drop"
    )

  calibrated_bridge <- calibrated_bridge |>
    dplyr::left_join(
      bootstrap_summary,
      by = c(
        "age_band_lower",
        "age_band_upper",
        "age_band"
      )
    )

  base::message("Running overlap and stability diagnostics.")

  overlap_summary <- eligible_cells |>
    dplyr::group_by(.data$age_band) |>
    dplyr::summarise(
      age_band_lower = base::min(.data$age_band_lower),
      n_years = dplyr::n_distinct(.data$.bridge_year),
      mean_ratio = base::mean(
        .data$bridge_ratio,
        na.rm = TRUE
      ),
      sd_ratio = stats::sd(
        .data$bridge_ratio,
        na.rm = TRUE
      ),
      median_ratio = stats::median(
        .data$bridge_ratio,
        na.rm = TRUE
      ),
      p25_ratio = stats::quantile(
        .data$bridge_ratio,
        0.25,
        na.rm = TRUE,
        names = FALSE
      ),
      p75_ratio = stats::quantile(
        .data$bridge_ratio,
        0.75,
        na.rm = TRUE,
        names = FALSE
      ),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      cv_ratio = .data$sd_ratio / .data$mean_ratio
    ) |>
    dplyr::arrange(.data$age_band_lower)

  n_eligible <- base::nrow(eligible_cells)
  n_age_bands <- dplyr::n_distinct(
    eligible_cells$age_band
  )
  n_years <- dplyr::n_distinct(
    eligible_cells$.bridge_year
  )

  bootstrap_completion <- base::ifelse(
    base::nrow(bootstrap_draws) == 0L,
    0,
    dplyr::n_distinct(
      bootstrap_draws$bootstrap_id
    ) / n_boot
  )

  stable_age_share <- overlap_summary |>
    dplyr::summarise(
      stable = base::mean(
        .data$cv_ratio <= 0.50 |
          base::is.na(.data$cv_ratio)
      )
    ) |>
    dplyr::pull(.data$stable)

  calibration_pass <- (
    n_eligible >= 3L &&
      n_age_bands >= 3L &&
      bootstrap_completion >= 0.80 &&
      stable_age_share >= 0.70
  )

  calibration_status <- tibble::tibble(
    component = "all_payer_demand_bridge",
    status = base::ifelse(
      calibration_pass,
      "calibrated",
      "not_calibrated"
    ),
    workload_basis = workload_basis,
    reference_year = reference_year,
    n_eligible_cells = n_eligible,
    n_age_bands = n_age_bands,
    n_years = n_years,
    bootstrap_completion = bootstrap_completion,
    stable_age_share = stable_age_share,
    min_ffs_workload = min_ffs_workload,
    min_all_workload = min_all_workload
  )

  trend_fit <- stats::lm(
    base::log(bridge_ratio) ~ age_band_lower,
    weights = ffs_workload,
    data = eligible_cells
  )

  trend_term <- broom::tidy(trend_fit) |>
    dplyr::filter(.data$term == "age_band_lower")

  trend_p <- trend_term |>
    dplyr::pull(.data$p.value)

  trend_beta <- trend_term |>
    dplyr::pull(.data$estimate)

  direction <- dplyr::case_when(
    trend_beta > 0 ~ "increased with age",
    trend_beta < 0 ~ "decreased with age",
    TRUE ~ "did not change with age"
  )

  year_range <- base::range(
    eligible_cells$.bridge_year,
    na.rm = TRUE
  )

  formatted_p <- dplyr::case_when(
    trend_p < 0.001 ~ "<0.001",
    TRUE ~ base::formatC(
      trend_p,
      format = "f",
      digits = 3
    )
  )

  summary_sentence <- base::paste0(
    "Using ",
    scales::comma(n_eligible),
    " eligible CHIA age-year cells from ",
    year_range[[1]],
    "–",
    year_range[[2]],
    ", the empirical all-payer/Medicare-FFS demand bridge ",
    direction,
    " (p ",
    formatted_p,
    "); calibration status was ",
    calibration_status$status[[1]],
    "."
  )

  base::message(summary_sentence)

  saved_paths <- base::character()

  if (!base::is.null(save_dir)) {
    base::dir.create(
      save_dir,
      recursive = TRUE,
      showWarnings = FALSE
    )

    timestamp <- base::format(
      base::Sys.time(),
      "%Y%m%d_%H%M%S"
    )

    bridge_path <- base::file.path(
      save_dir,
      base::paste0(
        "chia_demand_bridge_",
        timestamp,
        ".csv"
      )
    )

    cell_path <- base::file.path(
      save_dir,
      base::paste0(
        "chia_demand_bridge_cells_",
        timestamp,
        ".csv"
      )
    )

    status_path <- base::file.path(
      save_dir,
      base::paste0(
        "chia_demand_bridge_status_",
        timestamp,
        ".csv"
      )
    )

    readr::write_csv(
      calibrated_bridge,
      bridge_path
    )

    readr::write_csv(
      bridge_cells,
      cell_path
    )

    readr::write_csv(
      calibration_status,
      status_path
    )

    saved_paths <- c(
      bridge_path,
      cell_path,
      status_path
    )

    base::message(
      "Saved calibrated bridge: ",
      base::normalizePath(
        bridge_path,
        winslash = "/",
        mustWork = FALSE
      )
    )

    base::message(
      "Saved calibration cells: ",
      base::normalizePath(
        cell_path,
        winslash = "/",
        mustWork = FALSE
      )
    )

    base::message(
      "Saved calibration status: ",
      base::normalizePath(
        status_path,
        winslash = "/",
        mustWork = FALSE
      )
    )
  }

  base::message("CHIA demand-bridge calibration complete.")

  base::list(
    bridge = calibrated_bridge,
    observed_cells = bridge_cells,
    eligible_cells = eligible_cells,
    bootstrap_draws = bootstrap_draws,
    diagnostics = overlap_summary,
    status = calibration_status,
    model = bridge_fit,
    summary_sentence = summary_sentence,
    saved_paths = saved_paths
  )
}

#' Apply a CHIA demand bridge to national Medicare FFS workload
#'
#' @param medicare_ffs National Medicare FFS utilization by age.
#' @param chia_bridge Output from calibrate_chia_demand_bridge().
#' @param age_col Age or lower bound of an age band.
#' @param workload_col Medicare FFS workload column.
#' @param population_col Medicare FFS population denominator.
#' @param age_band_width Width used in the CHIA calibration.
#'
#' @return Age-specific calibrated national all-payer demand estimates.
#' @export
apply_chia_demand_bridge <- function(
    medicare_ffs,
    chia_bridge,
    age_col = "age",
    workload_col = "wrvu",
    population_col = "population",
    age_band_width = 5L) {

  base::message("Applying CHIA bridge to national Medicare FFS demand.")
  base::message(
    "Medicare input rows: ",
    scales::comma(base::nrow(medicare_ffs))
  )

  bridge_status <- chia_bridge$status$status[[1]]

  if (!base::identical(bridge_status, "calibrated")) {
    base::stop(
      "CHIA bridge status is '",
      bridge_status,
      "'. Refusing absolute demand calibration."
    )
  }

  required_cols <- c(
    age_col,
    workload_col,
    population_col
  )

  missing_cols <- base::setdiff(
    required_cols,
    base::names(medicare_ffs)
  )

  if (base::length(missing_cols) > 0L) {
    base::stop(
      "Missing Medicare columns: ",
      base::paste(missing_cols, collapse = ", ")
    )
  }

  base::message("Constructing Medicare age bands.")

  medicare_prepared <- medicare_ffs |>
    dplyr::mutate(
      age_numeric = base::as.numeric(.data[[age_col]]),
      age_band_lower = base::floor(
        .data$age_numeric / age_band_width
      ) * age_band_width,
      ffs_workload = base::as.numeric(
        .data[[workload_col]]
      ),
      ffs_population = base::as.numeric(
        .data[[population_col]]
      )
    ) |>
    dplyr::group_by(.data$age_band_lower) |>
    dplyr::summarise(
      ffs_workload = base::sum(
        .data$ffs_workload,
        na.rm = TRUE
      ),
      ffs_population = base::sum(
        .data$ffs_population,
        na.rm = TRUE
      ),
      .groups = "drop"
    )

  base::message("Joining empirically calibrated age bridge.")

  calibrated_demand <- medicare_prepared |>
    dplyr::left_join(
      chia_bridge$bridge |>
        dplyr::select(
          "age_band_lower",
          "age_band",
          "bridge_multiplier",
          "bridge_boot_low",
          "bridge_boot_high",
          "bridge_mean",
          "bridge_sd"
        ),
      by = "age_band_lower"
    ) |>
    dplyr::mutate(
      ffs_rate_per_1000 = 1000 *
        .data$ffs_workload /
        .data$ffs_population,
      all_payer_rate_per_1000 =
        .data$ffs_rate_per_1000 *
        .data$bridge_multiplier,
      all_payer_rate_low =
        .data$ffs_rate_per_1000 *
        .data$bridge_boot_low,
      all_payer_rate_high =
        .data$ffs_rate_per_1000 *
        .data$bridge_boot_high,
      calibrated_all_payer_workload =
        .data$ffs_workload *
        .data$bridge_multiplier
    )

  n_missing <- calibrated_demand |>
    dplyr::filter(
      base::is.na(.data$bridge_multiplier)
    ) |>
    base::nrow()

  if (n_missing > 0L) {
    base::warning(
      scales::comma(n_missing),
      " Medicare age bands lack a calibrated CHIA bridge."
    )
  }

  base::message(
    "Calibrated age bands: ",
    scales::comma(
      base::sum(
        !base::is.na(
          calibrated_demand$bridge_multiplier
        )
      )
    ),
    " of ",
    scales::comma(base::nrow(calibrated_demand))
  )

  base::message("National all-payer demand calibration complete.")

  calibrated_demand
}
