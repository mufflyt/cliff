#!/usr/bin/env Rscript
# Monte Carlo Workforce Projection Simulation
# ===========================================
# 5-year probabilistic forecasting using discrete-time hazard model

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(viridis)
  library(readr)
  library(patchwork)
  library(tidyr)
  library(tibble)
})

# --- Fellowship plan loader ---------------------------------------------------
# Expects CSV with columns like: subspecialty (text), year (int), n_grads (int)
load_fellowship_plan <- function(path, start_year, projection_years, mode = "avg") {
  if (!file.exists(path)) {
    warning(sprintf("Fellowship CSV not found at '%s'; assuming no entrants.", path))
    # Return empty plan
    years <- seq.int(start_year, by = 1L, length.out = projection_years)
    return(tidyr::crossing(
      year = years,
      subspecialty_f = factor(c("Gynecologic Oncology",
                               "Female Pelvic Medicine & Reconstructive Surgery",
                               "MIG"))
    ) %>% dplyr::mutate(n_new = 0L))
  }

  raw <- readr::read_csv(path, show_col_types = FALSE)

  # Basic normalization
  df <- raw %>%
    dplyr::rename_with(tolower) %>%
    dplyr::rename(
      subspecialty = dplyr::any_of(c("subspecialty","field","track")),
      year         = dplyr::any_of(c("year")),
      n_grads      = dplyr::any_of(c("n_grads","grads","graduates","n"))
    ) %>%
    dplyr::filter(!is.na(subspecialty), !is.na(n_grads))

  # Map to factor levels used in modeling
  df <- df %>%
    dplyr::mutate(
      subspecialty_f = dplyr::case_when(
        subspecialty %in% c("Female Pelvic Medicine & Reconstructive Surgery","FPMRS","URPS") ~
          "Female Pelvic Medicine & Reconstructive Surgery",
        subspecialty %in% c("Gynecologic Oncology","GO","Gyn Onc") ~
          "Gynecologic Oncology",
        subspecialty %in% c("MIG","MIGS","Minimally Invasive Gynecologic Surgery") ~
          "MIG",
        TRUE ~ subspecialty
      )
    )

  # Average by subspecialty across historical years
  grads <- df %>%
    dplyr::group_by(subspecialty_f) %>%
    dplyr::summarise(avg_n = mean(n_grads, na.rm = TRUE), .groups = "drop")

  # Build a plan over the projection horizon
  years <- seq.int(start_year, by = 1L, length.out = projection_years)
  tidyr::crossing(
    year = years,
    subspecialty_f = grads$subspecialty_f
  ) %>%
    dplyr::left_join(grads, by = "subspecialty_f") %>%
    dplyr::transmute(
      year,
      subspecialty_f = factor(subspecialty_f),
      n_new = as.integer(round(avg_n))
    )
}

#' Monte Carlo simulation for 5-year workforce projections
monte_carlo_workforce_projection <- function(hazard_results,
                                             n_simulations = 1000,
                                             projection_years = 5,
                                             start_year = as.integer(format(Sys.Date(), "%Y")) + 1,
                                             entrants_plan = NULL) {

  cat("3. MONTE CARLO WORKFORCE PROJECTIONS\n")
  cat("Simulations:", n_simulations, "| Years:", projection_years, "| Start year:", start_year, "\n")

  # Active at baseline (not retired)
  active_workforce <- hazard_results$data %>%
    dplyr::filter(retired_binary == 0) %>%
    dplyr::select(npi, subspecialty_f, age_band_f, gender_f, years_inactive, nppes_deact)

  cat("Active workforce:", nrow(active_workforce), "physicians\n")

  # Normalize entrants plan
  ep <- NULL
  if (!is.null(entrants_plan) && nrow(entrants_plan) > 0) {
    ep <- entrants_plan %>%
      dplyr::mutate(
        year = as.integer(year),
        subspecialty_f = factor(subspecialty_f, levels = levels(hazard_results$data$subspecialty_f))
      )
  }

  sim_out <- vector("list", n_simulations)

  for (sim in seq_len(n_simulations)) {
    if (sim %% 100 == 0) cat("  … simulation", sim, "of", n_simulations, "\n")

    sim_workforce <- active_workforce
    annual <- vector("list", projection_years)

    for (t in seq_len(projection_years)) {
      current_year <- start_year + t - 1L

      # (A) Add entrants for this year (before retirements), if any
      if (!is.null(ep)) {
        adds <- ep %>%
          dplyr::filter(year == current_year, n_new > 0)
        if (nrow(adds) > 0) {
          # Create synthetic rows for new entrants
          new_rows <- vector("list", nrow(adds))
          for (i in seq_len(nrow(adds))) {
            row <- adds[i, ]
            new_rows[[i]] <- tibble::tibble(
              npi = paste0("NEW_", current_year, "_", i, "_", seq_len(row$n_new)),
              subspecialty_f = row$subspecialty_f,
              # New grads are typically early career and active
              age_band_f = factor("Under_40", levels = levels(hazard_results$data$age_band_f), ordered = TRUE),
              gender_f = factor("Male", levels = levels(hazard_results$data$gender_f)), # unknown → pick a level
              years_inactive = 0,
              nppes_deact = 0
            )
          }
          sim_workforce <- dplyr::bind_rows(sim_workforce, dplyr::bind_rows(new_rows))
        }
      }

      # (B) Advance inactivity one year
      sim_workforce$years_inactive <- sim_workforce$years_inactive + 1L

      # (C) Predict retirement with factor level matching to avoid rank-deficient warnings
      # Ensure factor levels in simulation match the training data
      lvl_sub  <- levels(hazard_results$data$subspecialty_f)
      lvl_age  <- levels(hazard_results$data$age_band_f)
      lvl_sex  <- levels(hazard_results$data$gender_f)

      sim_workforce$subspecialty_f <- factor(sim_workforce$subspecialty_f, levels = lvl_sub)
      sim_workforce$age_band_f     <- factor(sim_workforce$age_band_f,     levels = lvl_age, ordered = is.ordered(hazard_results$data$age_band_f))
      sim_workforce$gender_f       <- factor(sim_workforce$gender_f,       levels = lvl_sex)

      # Handle different model types
      if (hazard_results$model$type %in% c("literature_calibrated", "empirical_medicare_based", "comprehensive_5source_empirical", "comprehensive_6source_empirical")) {
        # Use lookup table for calibrated rates (5-source empirical, Medicare, or literature)
        lookup_table <- hazard_results$model$coefficients

        # Match subspecialty and age band to get retirement probability
        retirement_probs <- sim_workforce %>%
          left_join(lookup_table, by = c("subspecialty_f", "age_band_f")) %>%
          pull(annual_prob)

        # Handle any missing matches with default rate
        retirement_probs[is.na(retirement_probs)] <- 0.02

      } else {
        # Standard GLM prediction
        # Extract just the RHS of the formula (predictors only)
        model_formula <- formula(hazard_results$model)
        rhs_formula <- as.formula(paste("~", as.character(model_formula)[3]))

        X <- stats::model.matrix(rhs_formula, sim_workforce)
        kept <- colnames(X) %in% names(coef(hazard_results$model))
        if (any(!kept)) X <- X[, kept, drop = FALSE]

        retirement_probs <- stats::plogis(drop(X %*% coef(hazard_results$model)[colnames(X)]))
      }

      # Safety: replace non-finite with 0, clamp to [0,1]
      probs <- retirement_probs
      probs[!is.finite(probs)] <- 0
      probs <- pmin(pmax(probs, 0), 1)
      retires <- stats::rbinom(n = nrow(sim_workforce), size = 1L, prob = probs)

      # (D) Record
      annual[[t]] <- sim_workforce %>%
        dplyr::mutate(
          simulation = sim,
          year = current_year,
          retirement_prob = probs,
          retired_this_year = retires
        ) %>%
        dplyr::group_by(subspecialty_f) %>%
        dplyr::summarise(
          simulation      = dplyr::first(simulation),
          year            = dplyr::first(year),
          active_start    = dplyr::n(),
          retired_count   = sum(retired_this_year),
          retirement_rate = mean(retirement_prob),
          active_end      = active_start - retired_count,
          .groups = "drop"
        )

      # (E) Remove retirees
      sim_workforce <- sim_workforce[retires == 0L, ]

      if (nrow(sim_workforce) == 0L) break
    }

    sim_out[[sim]] <- dplyr::bind_rows(annual)
  }

  all_sim <- dplyr::bind_rows(sim_out)

  summary <- all_sim %>%
    dplyr::group_by(subspecialty_f, year) %>%
    dplyr::summarise(
      n_sims             = dplyr::n(),
      mean_active        = mean(active_end),
      median_active      = stats::median(active_end),
      q25_active         = stats::quantile(active_end, 0.25),
      q75_active         = stats::quantile(active_end, 0.75),
      q05_active         = stats::quantile(active_end, 0.05),
      q95_active         = stats::quantile(active_end, 0.95),
      mean_retired_annual= mean(retired_count),
      mean_retirement_rate = mean(retirement_rate),
      .groups = "drop"
    )

  cat("Projection complete!\n\n")
  list(
    raw_simulations     = all_sim,
    summary             = summary,
    baseline_workforce  = nrow(active_workforce),
    entrants_plan       = ep
  )
}

#' Create comprehensive visualization of projections (+ entrants panel)
create_projection_visualization <- function(projection_results,
                                            fellowship_data = NULL,
                                            show_entrants_panel = TRUE) {

  cat("4. CREATING PROJECTION VISUALIZATIONS\n")

  # Prepare data for visualization
  plot_data <- projection_results$summary %>%
    dplyr::mutate(
      subspecialty_clean = dplyr::case_when(
        subspecialty_f == "Female Pelvic Medicine & Reconstructive Surgery" ~ "FPMRS/URPS",
        subspecialty_f == "Gynecologic Oncology" ~ "Gynecologic Oncology",
        subspecialty_f == "MIG" ~ "MIG",
        TRUE ~ as.character(subspecialty_f)
      ),
      # Approximate per-subspecialty baseline (if you later compute true baselines per subspec, swap here)
      baseline = projection_results$baseline_workforce / 3,
      pct_loss = (1 - mean_active / baseline) * 100
    )

  # Main projection plot
  p1 <- ggplot(plot_data, aes(x = year, y = mean_active, color = subspecialty_clean)) +
    geom_ribbon(aes(ymin = q05_active, ymax = q95_active, fill = subspecialty_clean),
                alpha = 0.2, color = NA) +
    geom_ribbon(aes(ymin = q25_active, ymax = q75_active, fill = subspecialty_clean),
                alpha = 0.3, color = NA) +
    geom_line(linewidth = 1.1, alpha = 0.85) +
    geom_point(size = 2, alpha = 0.9) +
    scale_color_viridis_d(name = "Subspecialty", option = "plasma", end = 0.8) +
    scale_fill_viridis_d(name = "Subspecialty", option = "plasma", end = 0.8) +
    scale_x_continuous(name = "Year", breaks = seq(min(plot_data$year), max(plot_data$year), 1)) +
    scale_y_continuous(name = "Active Workforce Size",
                       labels = scales::comma_format()) +
    labs(
      title = "5-Year Workforce Projections for Gynecologic Surgeons",
      subtitle = "Monte Carlo simulation with 90% and 50% confidence intervals",
      caption = sprintf("Based on Medicare claims data (2013–2021) • Generated: %s",
                        format(Sys.time(), "%Y-%m-%d"))
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 12),
      legend.position = "bottom",
      panel.background = element_rect(fill = "white", color = NA),
      plot.background = element_rect(fill = "white", color = NA)
    )

  # Annual retirement rate plot
  p2 <- ggplot(plot_data, aes(x = year, y = mean_retirement_rate * 100, color = subspecialty_clean)) +
    geom_line(linewidth = 1.1, alpha = 0.85) +
    geom_point(size = 2, alpha = 0.9) +
    scale_color_viridis_d(name = "Subspecialty", option = "plasma", end = 0.8) +
    scale_x_continuous(name = "Year", breaks = seq(min(plot_data$year), max(plot_data$year), 1)) +
    scale_y_continuous(name = "Annual Retirement Rate (%)",
                       labels = function(x) sprintf("%.1f%%", x)) +
    labs(
      title = "Projected Annual Retirement Rates",
      subtitle = "Expected retirement probability by year and subspecialty"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(size = 14, face = "bold"),
      plot.subtitle = element_text(size = 12),
      legend.position = "bottom",
      panel.background = element_rect(fill = "white", color = NA),
      plot.background = element_rect(fill = "white", color = NA)
    )

  # ---- Entrants panel (bars), if available ----
  have_entrants <- show_entrants_panel &&
                   !is.null(projection_results$entrants_plan) &&
                   nrow(projection_results$entrants_plan) > 0

  p3 <- NULL
  if (have_entrants) {
    entrants <- projection_results$entrants_plan %>%
      dplyr::mutate(
        subspecialty_clean = dplyr::case_when(
          subspecialty_f == "Female Pelvic Medicine & Reconstructive Surgery" ~ "FPMRS/URPS",
          subspecialty_f == "Gynecologic Oncology" ~ "Gynecologic Oncology",
          subspecialty_f == "MIG" ~ "MIG",
          TRUE ~ as.character(subspecialty_f)
        )
      )

    p3 <- ggplot(entrants, aes(x = year, y = n_new, fill = subspecialty_clean)) +
      geom_col(position = "dodge", alpha = 0.9) +
      scale_fill_viridis_d(name = "Subspecialty", option = "plasma", end = 0.8) +
      scale_x_continuous(name = "Year", breaks = sort(unique(entrants$year))) +
      scale_y_continuous(name = "New Entrants (fellows per year)") +
      labs(
        title = "Fellowship Entrants per Year",
        subtitle = "Annual new subspecialists added to the workforce"
      ) +
      theme_minimal(base_size = 12) +
      theme(
        plot.title = element_text(size = 14, face = "bold"),
        plot.subtitle = element_text(size = 12),
        legend.position = "bottom",
        panel.background = element_rect(fill = "white", color = NA),
        plot.background = element_rect(fill = "white", color = NA)
      )
  }

  # Combine plots
  combined_plot <-
    if (have_entrants) {
      (p1 / p2 / p3) + patchwork::plot_layout(guides = "collect") & theme(legend.position = "bottom")
    } else {
      (p1 / p2) + patchwork::plot_layout(guides = "collect") & theme(legend.position = "bottom")
    }

  list(
    workforce_projection = p1,
    retirement_rates = p2,
    entrants_panel = p3,
    combined = combined_plot
  )
}

# Execute if run directly
if(!interactive()) {
  # Load hazard model results
  hazard_files <- list.files("results", pattern = "hazard_model_results_.*\\.rds$", full.names = TRUE)
  if(length(hazard_files) == 0) {
    stop("No hazard_model_results.rds files found in results/. Run retirement_hazard_model.R first.")
  }

  # Use most recent file
  hazard_file <- hazard_files[which.max(file.mtime(hazard_files))]
  cat("Loading hazard results from:", hazard_file, "\n")
  hazard_results <- readRDS(hazard_file)

  # Load fellowship plan with flexible path
  fellowship_path <- if (file.exists("inputs/fellowship_grads_2022_2024.csv")) {
    "inputs/fellowship_grads_2022_2024.csv"
  } else {
    "../../inputs/fellowship_grads_2022_2024.csv"
  }
  entrants <- load_fellowship_plan(
    path = fellowship_path,
    start_year = 2025,
    projection_years = 5,
    mode = "avg"
  )

  # Run Monte Carlo simulation
  projection_results <- monte_carlo_workforce_projection(
    hazard_results,
    n_simulations = 1000,
    projection_years = 5,
    start_year = 2025,
    entrants_plan = entrants
  )

  # Create visualizations
  viz_results <- create_projection_visualization(projection_results)

  # Save results with timestamp
  ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
  saveRDS(projection_results, file.path("results", sprintf("projection_results_%s.rds", ts)))
  saveRDS(viz_results, file.path("results", sprintf("visualization_results_%s.rds", ts)))

  # Save CSV summary
  readr::write_csv(projection_results$summary, file.path("results", sprintf("workforce_projection_summary_%s.csv", ts)))

  # Save PNG visualizations
  if (!is.null(viz_results$combined)) {
    ggplot2::ggsave(file.path("results", sprintf("workforce_projection_combined_%s.png", ts)),
                    viz_results$combined, width = 12, height = 14, dpi = 300, bg = "white")
  }

  if (!is.null(viz_results$entrants_panel)) {
    ggplot2::ggsave(file.path("results", sprintf("entrants_per_year_%s.png", ts)),
                    viz_results$entrants_panel, width = 10, height = 4.5, dpi = 300, bg = "white")
  }

  cat("Monte Carlo simulation complete. Results saved with timestamp:", ts, "\n")
}
