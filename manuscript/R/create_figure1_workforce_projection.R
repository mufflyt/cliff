# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Figure 1 — Projected gynecologic surgical subspecialty workforce, 2025-2029
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Builds the workforce-projection trajectory figure DIRECTLY from the SSOT
# (cliff/data/workforce_projections_consolidated.csv) via the data contract, so
# the figure can never drift from Tables 1-2. Trust-a-number (CLAUDE.md #19):
# the only inputs are the contract-validated columns; nothing is hand-entered.
#
# What the figure shows, and what it does NOT claim:
#   * LINE  = the dynamic-model net-flow workforce path, workforce(t) =
#             baseline + t*(graduates - mean annual departures). Because the SSOT
#             stores avg_annual_retirements as the dynamic model's 4-year mean,
#             at t = horizon this equals projected_2029 exactly; the near-linear
#             segment is a faithful summary of the age-structured path.
#   * RIBBON = the terminal-year Monte Carlo 95% PREDICTION interval (stored as
#             ci95_lower/ci95_upper) fanned back to zero width at the 2025 baseline
#             via sqrt(t/horizon) variance accumulation. It is the departure-process
#             uncertainty envelope, NOT a set of per-year empirical MC intervals.
#
# Author: Tyler Muffly, MD / Claude Code   Date: 2026-07-18
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(scales)
  library(here)
})

# Contract (SSOT loader + constants) and shared publication styling.
source(here::here("manuscript", "R", "workforce_data_contract.R"))
source(here::here("R", "theme_publication.R"))

#' Build the per-year projection trajectory table from the SSOT summary.
#'
#' @param workforce_summary A validated workforce table (as returned by
#'   `load_workforce_data()`), one row per subspecialty.
#' @return A long tibble with one row per (subspecialty, year): columns
#'   `subspecialty`, `subspecialty_abbrev`, `year`, `workforce`, `lower`, `upper`.
build_projection_trajectory <- function(workforce_summary) {
  horizon <- WORKFORCE_PROJECTION_HORIZON_YEARS
  base_year <- 2025L

  workforce_summary %>%
    dplyr::mutate(
      annual_delta = annual_entrants - avg_annual_retirements,
      terminal_hw  = (ci95_upper - ci95_lower) / 2
    ) %>%
    dplyr::rowwise() %>%
    dplyr::reframe(
      subspecialty       = subspecialty,
      subspecialty_abbrev = subspecialty_abbrev,
      t                  = 0:horizon,
      year               = base_year + 0:horizon,
      workforce          = baseline_2025 + (0:horizon) * annual_delta,
      # Variance accumulates linearly with independent annual increments, so the
      # half-width scales with sqrt(t); 0 at baseline, terminal_hw at the horizon.
      hw                 = terminal_hw * sqrt((0:horizon) / horizon)
    ) %>%
    dplyr::mutate(
      lower = workforce - hw,
      upper = workforce + hw
    )
}

#' Create Figure 1: workforce projection trajectories with terminal-CI fan.
#'
#' @param workforce_summary Optional pre-loaded/validated SSOT table. Defaults to
#'   `load_workforce_data()` so the figure is self-sourcing.
#' @param label_abbrev Logical; label lines with the subspecialty abbreviation at
#'   the terminal year.
#' @param show_title Logical; draw the in-figure title. Default FALSE for
#'   Obstetrics & Gynecology submission — the journal requires the title/legend
#'   in the manuscript text, not embedded in the figure file.
#' @return A ggplot object.
create_figure1_workforce_projection <- function(workforce_summary = load_workforce_data(),
                                                label_abbrev = TRUE,
                                                show_title = FALSE) {
  traj <- build_projection_trajectory(workforce_summary)

  # Order the legend/colour by 2025 baseline (largest first) for a stable key.
  lvl <- workforce_summary %>%
    dplyr::arrange(dplyr::desc(baseline_2025)) %>%
    dplyr::pull(subspecialty_abbrev)
  traj <- dplyr::mutate(
    traj,
    subspecialty_abbrev = factor(subspecialty_abbrev, levels = lvl)
  )

  end_pts <- dplyr::filter(traj, year == max(year))

  p <- ggplot(traj, aes(x = year, y = workforce,
                        colour = subspecialty_abbrev, fill = subspecialty_abbrev)) +
    geom_ribbon(aes(ymin = lower, ymax = upper),
                alpha = 0.15, colour = NA) +
    geom_line(linewidth = 0.9) +
    geom_point(data = dplyr::filter(traj, year %in% range(traj$year)),
               size = 1.8) +
    scale_color_green_journal() +
    scale_fill_green_journal() +
    scale_x_continuous(breaks = sort(unique(traj$year)),
                       guide = guide_axis(check.overlap = TRUE)) +
    scale_y_continuous(labels = scales::label_comma()) +
    labs(
      x = NULL,
      y = "Active subspecialists (n)",
      colour = "Subspecialty",
      fill = "Subspecialty",
      # Green Journal: no embedded title; the legend/title lives in the caption.
      title = if (isTRUE(show_title))
        "Projected gynecologic surgical subspecialty workforce, 2025-2029" else NULL
    ) +
    theme_green_journal() +
    theme(
      plot.title = element_text(size = rel(1.1)),
      plot.title.position = "plot",
      legend.position = "bottom"
    )

  if (label_abbrev) {
    p <- p +
      geom_text(
        data = end_pts,
        aes(label = paste0(subspecialty_abbrev, " (",
                           format(round(workforce), big.mark = ",", trim = TRUE), ")")),
        hjust = 0, nudge_x = 0.08, size = 12, size.unit = "pt",
        show.legend = FALSE
      ) +
      # Room for the terminal labels.
      expand_limits(x = max(traj$year) + 1.1)
  }

  p
}

#' Save Figure 1 at Obstetrics & Gynecology submission specifications.
#'
#' Writes a title-less TIFF at 300 DPI, 6.88 in (double-column) width, LZW
#' compression, white background — the journal's figure-file requirements. Also
#' writes a PNG companion for on-screen/HTML preview.
#'
#' @param out_dir Output directory (created if absent).
#' @return Named character vector of written paths (invisible).
save_figure1_green_journal <- function(out_dir = here::here("manuscript", "figures")) {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  fig <- create_figure1_workforce_projection(show_title = FALSE)
  tiff_path <- file.path(out_dir, "figure1_workforce_projection.tiff")
  png_path  <- file.path(out_dir, "figure1_workforce_projection.png")
  # 6.88 in double-column; 300 DPI; LZW lossless; white background.
  ggsave(tiff_path, fig, width = 6.88, height = 4.5, dpi = 300,
         units = "in", bg = "white", device = "tiff", compression = "lzw")
  ggsave(png_path, fig, width = 6.88, height = 4.5, dpi = 300,
         units = "in", bg = "white")
  invisible(c(tiff = tiff_path, png = png_path))
}

# Allow `Rscript manuscript/R/create_figure1_workforce_projection.R` to write the
# submission-spec figure files (title-less TIFF + PNG preview).
if (identical(environment(), globalenv()) && !interactive() &&
    sys.nframe() == 0L) {
  paths <- save_figure1_green_journal()
  cat("Wrote", paths[["tiff"]], "and", paths[["png"]], "\n")
}
