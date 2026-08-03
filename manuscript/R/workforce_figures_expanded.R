# Extended figures for the workforce-cliff manuscript.
#
# These functions use the repository artifacts already consumed by the
# manuscript. They fail loudly when a downstream artifact does not match the
# current workforce_projections_consolidated.csv single source of truth.
#
# Intended location:
#   manuscript/R/workforce_figures_expanded.R

.wc_check_packages <- function() {
  packages <- c(
    "dplyr",
    "ggplot2",
    "here",
    "patchwork",
    "readr",
    "scales",
    "tibble",
    "tidyr"
  )

  missing_packages <- packages[
    !vapply(
      packages,
      requireNamespace,
      quietly = TRUE,
      FUN.VALUE = logical(1)
    )
  ]

  if (length(missing_packages) > 0L) {
    base::stop(
      "Install these packages before building the figures: ",
      base::paste(missing_packages, collapse = ", "),
      call. = FALSE
    )
  }

  base::invisible(TRUE)
}


.wc_read_csv <- function(path) {
  base::message("Reading: ", path)

  if (!base::file.exists(path)) {
    base::stop("Required file does not exist: ", path, call. = FALSE)
  }

  readr::read_csv(
    file = path,
    show_col_types = FALSE,
    progress = FALSE
  )
}


.wc_assert_columns <- function(tbl, required, label) {
  missing_columns <- base::setdiff(required, base::names(tbl))

  if (length(missing_columns) > 0L) {
    base::stop(
      label,
      " is missing required columns: ",
      base::paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  base::invisible(TRUE)
}


.wc_scalar <- function(tbl, column, label) {
  values <- tbl[[column]]

  if (length(values) != 1L || is.na(values)) {
    base::stop(
      label,
      " must contain exactly one nonmissing value.",
      call. = FALSE
    )
  }

  values[[1]]
}


.wc_theme <- function(base_size = 11) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      axis.title = ggplot2::element_text(size = ggplot2::rel(0.9)),
      legend.position = "top",
      legend.title = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      plot.title.position = "plot",
      strip.text = ggplot2::element_text(face = "bold")
    )
}


.wc_palette <- c(
  "URPS headcount" = "#d1495b",
  "Productivity-adjusted capacity" = "#7a5195",
  "Women aged 65 years or older" = "#1b6ca8",
  "Women with a pelvic floor disorder" = "#2a9d8f"
)


.wc_ssot_urps <- function(ssot_path) {
  ssot_tbl <- .wc_read_csv(ssot_path)

  .wc_assert_columns(
    tbl = ssot_tbl,
    required = c(
      "subspecialty_abbrev",
      "baseline_2025",
      "annual_entrants",
      "replacement_ratio"
    ),
    label = "Workforce SSOT"
  )

  urps_tbl <- ssot_tbl |>
    dplyr::filter(.data$subspecialty_abbrev == "URPS")

  if (nrow(urps_tbl) != 1L) {
    base::stop(
      "The workforce SSOT must contain exactly one URPS row.",
      call. = FALSE
    )
  }

  urps_tbl
}


.wc_assert_close <- function(
    observed,
    expected,
    label,
    tolerance = 0.01) {
  difference <- base::abs(observed - expected)

  if (difference > tolerance) {
    base::stop(
      label,
      " mismatch: observed ",
      scales::comma(observed),
      " but expected ",
      scales::comma(expected),
      ". Rebuild the downstream artifact from the current SSOT before ",
      "rendering this figure.",
      call. = FALSE
    )
  }

  base::invisible(TRUE)
}


#' Build the integrated supply-and-demand manuscript figure.
#'
#' @param supply_path National supply-and-demand trajectory CSV.
#' @param capacity_path Productivity-adjusted capacity trajectory CSV.
#' @param ssot_path Current workforce projection SSOT CSV.
#' @param baseline_year Index baseline year.
#' @param modeled_end_year End of the near-term modeled horizon.
#' @param strict_baseline Stop when downstream baselines differ from the SSOT.
#' @return A patchwork figure.
fig_supply_demand_integrated <- function(
    supply_path = here::here(
      "data",
      "urps_supply_demand_national_2026-07-23.csv"
    ),
    capacity_path = here::here(
      "data",
      "urps_module_a_effective_supply_2026-07-23.csv"
    ),
    ssot_path = here::here(
      "data",
      "workforce_projections_consolidated.csv"
    ),
    baseline_year = 2025L,
    modeled_end_year = 2029L,
    strict_baseline = TRUE) {
  .wc_check_packages()

  base::message("Building integrated supply-and-demand figure.")
  base::message("Supply path: ", supply_path)
  base::message("Capacity path: ", capacity_path)
  base::message("SSOT path: ", ssot_path)

  supply_tbl <- .wc_read_csv(supply_path)
  capacity_tbl <- .wc_read_csv(capacity_path)
  urps_ssot <- .wc_ssot_urps(ssot_path)

  .wc_assert_columns(
    tbl = supply_tbl,
    required = c(
      "YEAR",
      "supply",
      "supply_lo",
      "supply_hi",
      "women_65plus",
      "women_with_pfd",
      "urogyn_per_100k_w65",
      "per100k_lo",
      "per100k_hi",
      "women_pfd_per_urogyn"
    ),
    label = "Supply-and-demand trajectory"
  )

  .wc_assert_columns(
    tbl = capacity_tbl,
    required = c(
      "YEAR",
      "headcount",
      "effective",
      "effective_index"
    ),
    label = "Productivity-adjusted capacity trajectory"
  )

  ssot_baseline <- .wc_scalar(
    tbl = urps_ssot,
    column = "baseline_2025",
    label = "URPS SSOT baseline"
  )

  supply_baseline <- supply_tbl |>
    dplyr::filter(.data$YEAR == baseline_year) |>
    dplyr::pull(.data$supply)

  capacity_baseline <- capacity_tbl |>
    dplyr::filter(.data$YEAR == baseline_year) |>
    dplyr::pull(.data$headcount)

  if (strict_baseline) {
    .wc_assert_close(
      observed = supply_baseline,
      expected = ssot_baseline,
      label = "Long-horizon supply baseline"
    )

    .wc_assert_close(
      observed = capacity_baseline,
      expected = ssot_baseline,
      label = "Capacity-module headcount baseline"
    )
  }

  base::message("Rebasing every trajectory to ", baseline_year, " = 100.")

  indexed_tbl <- supply_tbl |>
    dplyr::left_join(
      capacity_tbl |>
        dplyr::select(
          .data$YEAR,
          .data$effective,
          .data$effective_index
        ),
      by = "YEAR"
    ) |>
    dplyr::mutate(
      supply_index_calc = 100 * .data$supply / supply_baseline,
      supply_lo_index_calc = 100 * .data$supply_lo / supply_baseline,
      supply_hi_index_calc = 100 * .data$supply_hi / supply_baseline,
      women65_index_calc = 100 * .data$women_65plus /
        .data$women_65plus[.data$YEAR == baseline_year],
      pfd_index_calc = 100 * .data$women_with_pfd /
        .data$women_with_pfd[.data$YEAR == baseline_year]
    )

  trajectory_tbl <- indexed_tbl |>
    dplyr::select(
      .data$YEAR,
      `URPS headcount` = .data$supply_index_calc,
      `Productivity-adjusted capacity` = .data$effective_index,
      `Women aged 65 years or older` = .data$women65_index_calc,
      `Women with a pelvic floor disorder` = .data$pfd_index_calc
    ) |>
    tidyr::pivot_longer(
      cols = -.data$YEAR,
      names_to = "series",
      values_to = "index"
    ) |>
    dplyr::mutate(
      series = base::factor(
        .data$series,
        levels = base::names(.wc_palette)
      )
    )

  endpoint_year <- base::max(trajectory_tbl$YEAR)

  endpoint_tbl <- trajectory_tbl |>
    dplyr::filter(.data$YEAR == endpoint_year) |>
    dplyr::mutate(
      label = scales::number(.data$index, accuracy = 1),
      label_y = .data$index +
        dplyr::case_when(
          .data$series == "URPS headcount" ~ 2.0,
          .data$series == "Productivity-adjusted capacity" ~ -2.0,
          .data$series == "Women aged 65 years or older" ~ 1.2,
          TRUE ~ -1.2
        )
    )

  panel_a <- ggplot2::ggplot(
    trajectory_tbl,
    ggplot2::aes(
      x = .data$YEAR,
      y = .data$index,
      colour = .data$series
    )
  ) +
    ggplot2::annotate(
      geom = "rect",
      xmin = modeled_end_year,
      xmax = Inf,
      ymin = -Inf,
      ymax = Inf,
      fill = "grey80",
      alpha = 0.18
    ) +
    ggplot2::geom_ribbon(
      data = indexed_tbl,
      ggplot2::aes(
        x = .data$YEAR,
        ymin = .data$supply_lo_index_calc,
        ymax = .data$supply_hi_index_calc
      ),
      inherit.aes = FALSE,
      fill = .wc_palette[["URPS headcount"]],
      alpha = 0.12
    ) +
    ggplot2::geom_vline(
      xintercept = modeled_end_year,
      linetype = "dashed",
      colour = "grey40"
    ) +
    ggplot2::geom_line(linewidth = 1.05) +
    ggplot2::geom_text(
      data = endpoint_tbl,
      ggplot2::aes(
        x = .data$YEAR + 0.5,
        y = .data$label_y,
        label = .data$label
      ),
      hjust = 0,
      size = 2.8,
      show.legend = FALSE
    ) +
    ggplot2::annotate(
      geom = "text",
      x = modeled_end_year + 0.4,
      y = Inf,
      label = "Long-horizon extrapolation",
      hjust = 0,
      vjust = 1.4,
      size = 3
    ) +
    ggplot2::scale_colour_manual(values = .wc_palette) +
    ggplot2::scale_x_continuous(
      breaks = base::seq(baseline_year, endpoint_year, 5L),
      limits = c(baseline_year, endpoint_year + 7)
    ) +
    ggplot2::scale_y_continuous(
      labels = scales::label_number(accuracy = 1),
      expand = ggplot2::expansion(mult = c(0.04, 0.12))
    ) +
    ggplot2::labs(
      x = NULL,
      y = base::paste0("Index, ", baseline_year, " = 100")
    ) +
    .wc_theme()

  panel_b <- ggplot2::ggplot(
    indexed_tbl,
    ggplot2::aes(
      x = .data$YEAR,
      y = .data$urogyn_per_100k_w65
    )
  ) +
    ggplot2::annotate(
      geom = "rect",
      xmin = modeled_end_year,
      xmax = Inf,
      ymin = -Inf,
      ymax = Inf,
      fill = "grey80",
      alpha = 0.18
    ) +
    ggplot2::geom_ribbon(
      ggplot2::aes(
        ymin = .data$per100k_lo,
        ymax = .data$per100k_hi
      ),
      fill = .wc_palette[["URPS headcount"]],
      alpha = 0.12
    ) +
    ggplot2::geom_line(
      colour = .wc_palette[["URPS headcount"]],
      linewidth = 1.05
    ) +
    ggplot2::geom_vline(
      xintercept = modeled_end_year,
      linetype = "dashed",
      colour = "grey40"
    ) +
    ggplot2::scale_x_continuous(
      breaks = base::seq(baseline_year, endpoint_year, 5L)
    ) +
    ggplot2::scale_y_continuous(
      labels = scales::label_number(accuracy = 0.1)
    ) +
    ggplot2::labs(
      x = "Year",
      y = "Urogynecologists per\n100,000 women aged 65+"
    ) +
    .wc_theme() +
    ggplot2::theme(legend.position = "none")

  panel_c <- ggplot2::ggplot(
    indexed_tbl,
    ggplot2::aes(
      x = .data$YEAR,
      y = .data$women_pfd_per_urogyn
    )
  ) +
    ggplot2::annotate(
      geom = "rect",
      xmin = modeled_end_year,
      xmax = Inf,
      ymin = -Inf,
      ymax = Inf,
      fill = "grey80",
      alpha = 0.18
    ) +
    ggplot2::geom_line(
      colour = .wc_palette[["Women with a pelvic floor disorder"]],
      linewidth = 1.05
    ) +
    ggplot2::geom_vline(
      xintercept = modeled_end_year,
      linetype = "dashed",
      colour = "grey40"
    ) +
    ggplot2::scale_x_continuous(
      breaks = base::seq(baseline_year, endpoint_year, 5L)
    ) +
    ggplot2::scale_y_continuous(labels = scales::label_comma()) +
    ggplot2::labs(
      x = "Year",
      y = "Women with a pelvic floor\ndisorder per urogynecologist"
    ) +
    .wc_theme() +
    ggplot2::theme(legend.position = "none")

  base::message("Combining indexed and clinical-coverage panels.")

  panel_a /
    (panel_b | panel_c) +
    patchwork::plot_layout(heights = c(1.7, 1))
}


#' Build an expected age-structured workforce trajectory.
#'
#' @param baseline_ages Integer vector of baseline physician ages.
#' @param hazard_tbl Table with age_band and annual_hazard columns.
#' @param annual_entrants Expected annual fellowship entrants.
#' @param start_year First projection year.
#' @param end_year Last projection year.
#' @param entry_age Age assigned to each entrant cohort.
#' @param hazard_breaks Breaks corresponding to hazard age bands.
#' @return A named list containing age_year, flows, and totals tables.
build_age_projection <- function(
    baseline_ages,
    hazard_tbl,
    annual_entrants,
    start_year = 2025L,
    end_year = 2050L,
    entry_age = 34L,
    hazard_breaks = c(0, 45, 50, 55, 60, 65, 70, Inf)) {
  .wc_check_packages()

  base::message(
    "Building age projection from ",
    scales::comma(length(baseline_ages)),
    " baseline physicians."
  )
  base::message(
    "Projection years: ",
    start_year,
    " through ",
    end_year,
    "."
  )
  base::message("Annual entrants: ", annual_entrants)
  base::message("Entrant age: ", entry_age)

  .wc_assert_columns(
    tbl = hazard_tbl,
    required = c("age_band", "annual_hazard"),
    label = "Age-band hazard table"
  )

  hazard_labels <- hazard_tbl$age_band

  if (length(hazard_breaks) != length(hazard_labels) + 1L) {
    base::stop(
      "hazard_breaks must have one more value than hazard age bands.",
      call. = FALSE
    )
  }

  current_tbl <- tibble::tibble(
    age = base::as.integer(baseline_ages)
  ) |>
    dplyr::count(.data$age, name = "physicians") |>
    dplyr::mutate(physicians = base::as.numeric(.data$physicians))

  age_year_rows <- base::list()
  flow_rows <- base::list()

  for (year_value in base::seq.int(start_year, end_year)) {
    age_year_rows[[length(age_year_rows) + 1L]] <- current_tbl |>
      dplyr::mutate(year = year_value)

    if (year_value == end_year) {
      next
    }

    transition_tbl <- current_tbl |>
      dplyr::mutate(
        age_band = base::as.character(
          base::cut(
            .data$age,
            breaks = hazard_breaks,
            labels = hazard_labels,
            right = FALSE
          )
        )
      ) |>
      dplyr::left_join(hazard_tbl, by = "age_band")

    if (any(is.na(transition_tbl$annual_hazard))) {
      base::stop(
        "At least one physician age did not receive a departure hazard.",
        call. = FALSE
      )
    }

    departures <- base::sum(
      transition_tbl$physicians * transition_tbl$annual_hazard
    )

    survivor_tbl <- transition_tbl |>
      dplyr::transmute(
        age = .data$age + 1L,
        physicians = .data$physicians *
          (1 - .data$annual_hazard)
      )

    entrant_tbl <- tibble::tibble(
      age = entry_age,
      physicians = base::as.numeric(annual_entrants)
    )

    current_tbl <- dplyr::bind_rows(
      survivor_tbl,
      entrant_tbl
    ) |>
      dplyr::group_by(.data$age) |>
      dplyr::summarise(
        physicians = base::sum(.data$physicians),
        .groups = "drop"
      )

    flow_rows[[length(flow_rows) + 1L]] <- tibble::tibble(
      year = year_value + 1L,
      entrants = base::as.numeric(annual_entrants),
      departures = departures
    )
  }

  base::message("Collapsing physician ages into display age bands.")

  age_year_tbl <- dplyr::bind_rows(age_year_rows) |>
    dplyr::mutate(
      display_age_band = base::cut(
        .data$age,
        breaks = c(0, 45, 55, 65, 70, Inf),
        labels = c("<45", "45-54", "55-64", "65-69", "70+"),
        right = FALSE
      )
    ) |>
    dplyr::group_by(.data$year, .data$display_age_band) |>
    dplyr::summarise(
      physicians = base::sum(.data$physicians),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      display_age_band = base::factor(
        .data$display_age_band,
        levels = c("<45", "45-54", "55-64", "65-69", "70+")
      )
    )

  flows_tbl <- dplyr::bind_rows(flow_rows)

  totals_tbl <- age_year_tbl |>
    dplyr::group_by(.data$year) |>
    dplyr::summarise(
      physicians = base::sum(.data$physicians),
      .groups = "drop"
    )

  base::message(
    "Age projection complete: ",
    nrow(age_year_tbl),
    " year-by-band rows."
  )

  base::list(
    age_year = age_year_tbl,
    flows = flows_tbl,
    totals = totals_tbl
  )
}


#' Build the age projection from current repository artifacts.
#'
#' @param model_path Canonical URPS model-data snapshot.
#' @param hazard_path Pooled versus unpooled hazard CSV.
#' @param ssot_path Current workforce projection SSOT CSV.
#' @param end_year Last projection year.
#' @param strict_baseline Stop when the age vector differs from the SSOT.
#' @return A named projection list from build_age_projection().
build_age_projection_from_repo <- function(
    model_path = here::here(
      "shiny_urps_scenarios",
      "urps_model_data.R"
    ),
    hazard_path = here::here(
      "data",
      "hazard_by_band_pooled_vs_unpooled.csv"
    ),
    ssot_path = here::here(
      "data",
      "workforce_projections_consolidated.csv"
    ),
    end_year = 2050L,
    strict_baseline = TRUE) {
  .wc_check_packages()

  base::message("Loading canonical URPS age snapshot: ", model_path)

  if (!base::file.exists(model_path)) {
    base::stop("Model-data file does not exist: ", model_path)
  }

  # parent = globalenv() (not baseenv) so the sourced model-data file can resolve
  # functions from attached packages, e.g. stats::setNames used in urps_model_data.R.
  model_env <- base::new.env(parent = base::globalenv())
  base::sys.source(model_path, envir = model_env)

  required_objects <- c(
    "URPS_AGES",
    "BAND_LABELS",
    "BANDS",
    "GRAD_URPS"
  )

  missing_objects <- required_objects[
    !vapply(
      required_objects,
      base::exists,
      envir = model_env,
      inherits = FALSE,
      FUN.VALUE = logical(1)
    )
  ]

  if (length(missing_objects) > 0L) {
    base::stop(
      "Model-data snapshot is missing: ",
      base::paste(missing_objects, collapse = ", "),
      call. = FALSE
    )
  }

  hazard_source_tbl <- .wc_read_csv(hazard_path)

  .wc_assert_columns(
    tbl = hazard_source_tbl,
    required = c("band", "pooled_hazard"),
    label = "Pooled hazard artifact"
  )

  hazard_tbl <- hazard_source_tbl |>
    dplyr::transmute(
      age_band = .data$band,
      annual_hazard = .data$pooled_hazard
    )

  urps_ssot <- .wc_ssot_urps(ssot_path)

  ssot_baseline <- .wc_scalar(
    tbl = urps_ssot,
    column = "baseline_2025",
    label = "URPS SSOT baseline"
  )

  age_snapshot_baseline <- length(model_env$URPS_AGES)

  if (strict_baseline) {
    .wc_assert_close(
      observed = age_snapshot_baseline,
      expected = ssot_baseline,
      label = "URPS age-vector baseline"
    )
  }

  annual_entrants <- .wc_scalar(
    tbl = urps_ssot,
    column = "annual_entrants",
    label = "URPS annual entrants"
  )

  build_age_projection(
    baseline_ages = model_env$URPS_AGES,
    hazard_tbl = hazard_tbl,
    annual_entrants = annual_entrants,
    start_year = 2025L,
    end_year = end_year,
    entry_age = 34L,
    hazard_breaks = model_env$BANDS
  )
}


#' Plot the age composition, entrants, and departures.
#'
#' @param projection A list returned by build_age_projection().
#' @param modeled_end_year End of the near-term modeled horizon.
#' @return A patchwork figure.
fig_age_conveyor <- function(
    projection = build_age_projection_from_repo(),
    modeled_end_year = 2029L) {
  .wc_check_packages()

  base::message("Building age-composition and workforce-flow figure.")

  age_year_tbl <- projection$age_year
  flows_tbl <- projection$flows
  totals_tbl <- projection$totals

  .wc_assert_columns(
    tbl = age_year_tbl,
    required = c("year", "display_age_band", "physicians"),
    label = "Age-year projection"
  )

  .wc_assert_columns(
    tbl = flows_tbl,
    required = c("year", "entrants", "departures"),
    label = "Entrant-departure projection"
  )

  flow_long_tbl <- flows_tbl |>
    tidyr::pivot_longer(
      cols = c(.data$entrants, .data$departures),
      names_to = "flow",
      values_to = "physicians"
    ) |>
    dplyr::mutate(
      signed_physicians = dplyr::if_else(
        .data$flow == "departures",
        -.data$physicians,
        .data$physicians
      ),
      flow = dplyr::recode(
        .data$flow,
        entrants = "Entrants",
        departures = "Departures"
      )
    )

  age_palette <- c(
    "<45" = "#264653",
    "45-54" = "#2a9d8f",
    "55-64" = "#e9c46a",
    "65-69" = "#f4a261",
    "70+" = "#e76f51"
  )

  panel_a <- ggplot2::ggplot(
    age_year_tbl,
    ggplot2::aes(
      x = .data$year,
      y = .data$physicians,
      fill = .data$display_age_band
    )
  ) +
    ggplot2::annotate(
      geom = "rect",
      xmin = modeled_end_year,
      xmax = Inf,
      ymin = -Inf,
      ymax = Inf,
      fill = "grey80",
      alpha = 0.18
    ) +
    ggplot2::geom_area(alpha = 0.92) +
    ggplot2::geom_line(
      data = totals_tbl,
      ggplot2::aes(
        x = .data$year,
        y = .data$physicians
      ),
      inherit.aes = FALSE,
      colour = "black",
      linewidth = 0.9
    ) +
    ggplot2::geom_vline(
      xintercept = modeled_end_year,
      linetype = "dashed",
      colour = "grey30"
    ) +
    ggplot2::scale_fill_manual(values = age_palette) +
    ggplot2::scale_x_continuous(
      breaks = base::seq(
        base::min(age_year_tbl$year),
        base::max(age_year_tbl$year),
        5L
      )
    ) +
    ggplot2::scale_y_continuous(labels = scales::label_comma()) +
    ggplot2::labs(
      x = NULL,
      y = "Expected active urogynecologists",
      fill = "Age"
    ) +
    .wc_theme()

  flow_palette <- c(
    "Entrants" = "#2a9d8f",
    "Departures" = "#e76f51"
  )

  panel_b <- ggplot2::ggplot(
    flow_long_tbl,
    ggplot2::aes(
      x = .data$year,
      y = .data$signed_physicians,
      fill = .data$flow
    )
  ) +
    ggplot2::annotate(
      geom = "rect",
      xmin = modeled_end_year,
      xmax = Inf,
      ymin = -Inf,
      ymax = Inf,
      fill = "grey80",
      alpha = 0.18
    ) +
    ggplot2::geom_col(position = "identity", width = 0.8) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey35") +
    ggplot2::geom_vline(
      xintercept = modeled_end_year,
      linetype = "dashed",
      colour = "grey30"
    ) +
    ggplot2::scale_fill_manual(values = flow_palette) +
    ggplot2::scale_x_continuous(
      breaks = base::seq(
        base::min(flow_long_tbl$year),
        base::max(flow_long_tbl$year),
        5L
      )
    ) +
    ggplot2::scale_y_continuous(
      labels = function(values) scales::comma(base::abs(values))
    ) +
    ggplot2::labs(
      x = "Year",
      y = "Physicians per year"
    ) +
    .wc_theme()

  panel_a / panel_b +
    patchwork::plot_layout(heights = c(2.1, 1))
}


#' Build the complete multidimensional robustness grid.
#'
#' @param window_path Departure-window sensitivity CSV.
#' @param ssot_path Current workforce projection SSOT CSV.
#' @param conversions Graduate-to-practice conversion values.
#' @param multipliers Departure-rate multipliers.
#' @param strict_primary Stop when primary window ratios differ from the SSOT.
#' @return A tidy sensitivity-grid tibble.
build_robustness_grid <- function(
    window_path = here::here(
      "data",
      "departure_window_sensitivity.csv"
    ),
    ssot_path = here::here(
      "data",
      "workforce_projections_consolidated.csv"
    ),
    conversions = c(0.70, 0.85, 1.00),
    multipliers = c(1, 2, 3),
    strict_primary = TRUE) {
  .wc_check_packages()

  base::message("Building the full robustness grid.")
  base::message("Window sensitivity path: ", window_path)
  base::message("SSOT path: ", ssot_path)

  window_tbl <- .wc_read_csv(window_path)
  ssot_tbl <- .wc_read_csv(ssot_path)

  .wc_assert_columns(
    tbl = window_tbl,
    required = c(
      "window",
      "label",
      "subspecialty_abbrev",
      "dynamic_ratio"
    ),
    label = "Departure-window sensitivity"
  )

  .wc_assert_columns(
    tbl = ssot_tbl,
    required = c(
      "subspecialty_abbrev",
      "replacement_ratio"
    ),
    label = "Workforce SSOT"
  )

  cohort_levels <- c("URPS", "GO")

  primary_tbl <- window_tbl |>
    dplyr::filter(
      .data$label == "fully_obs",
      .data$subspecialty_abbrev %in% cohort_levels
    ) |>
    dplyr::select(
      .data$subspecialty_abbrev,
      primary_ratio = .data$dynamic_ratio
    ) |>
    dplyr::left_join(
      ssot_tbl |>
        dplyr::filter(
          .data$subspecialty_abbrev %in% cohort_levels
        ) |>
        dplyr::select(
          .data$subspecialty_abbrev,
          ssot_ratio = .data$replacement_ratio
        ),
      by = "subspecialty_abbrev"
    )

  if (nrow(primary_tbl) != length(cohort_levels)) {
    base::stop(
      "Primary-ratio comparison did not return both URPS and GO.",
      call. = FALSE
    )
  }

  if (strict_primary) {
    purrr_needed <- requireNamespace("purrr", quietly = TRUE)

    if (!purrr_needed) {
      base::stop(
        "Package purrr is required for strict primary-ratio guards.",
        call. = FALSE
      )
    }

    purrr::pwalk(
      primary_tbl,
      function(subspecialty_abbrev, primary_ratio, ssot_ratio) {
        .wc_assert_close(
          observed = primary_ratio,
          expected = ssot_ratio,
          label = base::paste0(
            subspecialty_abbrev,
            " primary sensitivity ratio"
          )
        )
      }
    )
  }

  base::message(
    "Crossing ",
    length(conversions),
    " conversion values with ",
    length(multipliers),
    " departure multipliers."
  )

  tidyr::crossing(
    window_tbl |>
      dplyr::filter(
        .data$subspecialty_abbrev %in% cohort_levels
      ),
    conversion = conversions,
    departure_multiplier = multipliers
  ) |>
    dplyr::mutate(
      ratio = .data$dynamic_ratio * .data$conversion /
        .data$departure_multiplier,
      window_label = dplyr::recode(
        .data$label,
        drop2 = "2016-2019\nrestricted",
        fully_obs = "2016-2021\nprimary",
        full = "2016-2023\nprovisional"
      ),
      cohort = dplyr::recode(
        .data$subspecialty_abbrev,
        URPS = "Urogynecology",
        GO = "Gynecologic Oncology"
      ),
      balance = dplyr::case_when(
        .data$ratio < 0.95 ~ "Below replacement",
        .data$ratio <= 1.05 ~ "At replacement",
        TRUE ~ "Above replacement"
      )
    )
}


#' Plot the complete robustness frontier.
#'
#' @param grid_tbl A table returned by build_robustness_grid().
#' @return A ggplot heatmap.
fig_robustness_frontier <- function(
    grid_tbl = build_robustness_grid()) {
  .wc_check_packages()

  base::message("Building the robustness-frontier heatmap.")

  .wc_assert_columns(
    tbl = grid_tbl,
    required = c(
      "conversion",
      "departure_multiplier",
      "ratio",
      "window_label",
      "cohort"
    ),
    label = "Robustness grid"
  )

  primary_marker_tbl <- grid_tbl |>
    dplyr::filter(
      .data$conversion == 1,
      .data$departure_multiplier == 1,
      .data$window_label == "2016-2021\nprimary"
    )

  ggplot2::ggplot(
    grid_tbl,
    ggplot2::aes(
      x = .data$conversion,
      y = .data$departure_multiplier,
      fill = .data$ratio
    )
  ) +
    ggplot2::geom_tile(
      colour = "white",
      linewidth = 0.8
    ) +
    ggplot2::geom_text(
      ggplot2::aes(
        label = scales::number(.data$ratio, accuracy = 0.1)
      ),
      size = 3
    ) +
    ggplot2::geom_point(
      data = primary_marker_tbl,
      shape = 8,
      size = 3.3,
      colour = "black",
      show.legend = FALSE
    ) +
    ggplot2::facet_grid(
      rows = ggplot2::vars(.data$cohort),
      cols = ggplot2::vars(.data$window_label)
    ) +
    ggplot2::scale_x_continuous(
      breaks = base::sort(base::unique(grid_tbl$conversion)),
      labels = scales::label_percent(accuracy = 1)
    ) +
    ggplot2::scale_y_continuous(
      breaks = base::sort(
        base::unique(grid_tbl$departure_multiplier)
      ),
      labels = function(values) base::paste0(values, "\u00d7")
    ) +
    ggplot2::scale_fill_gradient2(
      low = "#b2182b",
      mid = "#f7f7f7",
      high = "#2166ac",
      midpoint = 1,
      name = "Completion-to-\ndeparture ratio"
    ) +
    ggplot2::labs(
      x = "Graduate-to-practice conversion",
      y = "Departure-rate multiplier"
    ) +
    .wc_theme(base_size = 10) +
    ggplot2::theme(legend.position = "right")
}


#' Save the three expanded manuscript figures with a timestamp.
#'
#' @param directory Destination directory.
#' @param width Figure width in inches.
#' @param dpi Figure resolution.
#' @return A tibble containing figure names and exact saved paths.
save_expanded_workforce_figures <- function(
    directory = here::here("figures", "expanded"),
    width = 9,
    dpi = 300) {
  .wc_check_packages()

  timestamp <- base::format(
    base::Sys.time(),
    "%Y%m%d_%H%M%S"
  )

  base::dir.create(
    directory,
    recursive = TRUE,
    showWarnings = FALSE
  )

  base::message("Saving expanded figures to: ", directory)

  integrated_plot <- fig_supply_demand_integrated()
  age_plot <- fig_age_conveyor()
  frontier_plot <- fig_robustness_frontier()

  file_tbl <- tibble::tibble(
    figure = c(
      "integrated_supply_demand",
      "age_conveyor",
      "robustness_frontier"
    ),
    path = base::file.path(
      directory,
      base::paste0(
        c(
          "integrated_supply_demand_",
          "age_conveyor_",
          "robustness_frontier_"
        ),
        timestamp,
        ".png"
      )
    ),
    height = c(8.0, 8.0, 6.5)
  )

  plot_list <- base::list(
    integrated_plot,
    age_plot,
    frontier_plot
  )

  for (index in base::seq_len(nrow(file_tbl))) {
    ggplot2::ggsave(
      filename = file_tbl$path[[index]],
      plot = plot_list[[index]],
      width = width,
      height = file_tbl$height[[index]],
      dpi = dpi,
      bg = "white"
    )

    base::message("Saved: ", file_tbl$path[[index]])
  }

  file_tbl
}


#' Create a dynamic manuscript summary sentence.
#'
#' @param supply_path National supply-and-demand trajectory CSV.
#' @param baseline_year First reporting year.
#' @return A single character sentence.
summarize_supply_demand_figure <- function(
    supply_path = here::here(
      "data",
      "urps_supply_demand_national_2026-07-23.csv"
    ),
    ssot_path = here::here(
      "data",
      "workforce_projections_consolidated.csv"
    ),
    baseline_year = 2025L,
    strict_baseline = TRUE) {
  .wc_check_packages()

  supply_tbl <- .wc_read_csv(supply_path)
  urps_ssot <- .wc_ssot_urps(ssot_path)

  .wc_assert_columns(
    tbl = supply_tbl,
    required = c(
      "YEAR",
      "supply",
      "women_65plus",
      "women_with_pfd"
    ),
    label = "Supply-and-demand trajectory"
  )

  ssot_baseline <- .wc_scalar(
    tbl = urps_ssot,
    column = "baseline_2025",
    label = "URPS SSOT baseline"
  )

  supply_baseline <- supply_tbl |>
    dplyr::filter(.data$YEAR == baseline_year) |>
    dplyr::pull("supply")

  if (strict_baseline) {
    .wc_assert_close(
      observed = supply_baseline,
      expected = ssot_baseline,
      label = "Long-horizon supply baseline"
    )
  }

  endpoint_year <- base::max(supply_tbl$YEAR)

  endpoint_tbl <- supply_tbl |>
    dplyr::filter(.data$YEAR %in% c(baseline_year, endpoint_year)) |>
    dplyr::arrange(.data$YEAR)

  if (nrow(endpoint_tbl) != 2L) {
    base::stop(
      "Could not identify both baseline and endpoint rows.",
      call. = FALSE
    )
  }

  supply_change <- 100 * (
    endpoint_tbl$supply[[2]] / endpoint_tbl$supply[[1]] - 1
  )
  older_change <- 100 * (
    endpoint_tbl$women_65plus[[2]] /
      endpoint_tbl$women_65plus[[1]] - 1
  )
  pfd_change <- 100 * (
    endpoint_tbl$women_with_pfd[[2]] /
      endpoint_tbl$women_with_pfd[[1]] - 1
  )

  direction <- dplyr::if_else(
    supply_change > base::max(older_change, pfd_change),
    "outpaced",
    "did not outpace"
  )

  base::sprintf(
    paste0(
      "From %d to %d, projected URPS supply increased %.1f%% and %s ",
      "growth in women aged 65 years or older (%.1f%%) and women with ",
      "pelvic floor disorders (%.1f%%). No P value was calculated ",
      "because this was a structural projection rather than a ",
      "sample-based hypothesis test."
    ),
    baseline_year,
    endpoint_year,
    supply_change,
    direction,
    older_change,
    pfd_change
  )
}
