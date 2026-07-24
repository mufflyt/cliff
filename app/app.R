#!/usr/bin/env Rscript
# Standalone Shiny app: Gynecologic Subspecialty Retirement Cliff
# Extracted from isochrones/app/app.R — cliff-specific tab only
#
# Run: Rscript -e "shiny::runApp('app')"

library(shiny)
library(shinydashboard)
library(ggplot2)
library(dplyr)
library(scales)
library(purrr)
library(sf)
library(maps)
library(here)

source(here("app", "R", "helpers_retirement_cliff.R"))

# Load seed data
workforce_data <- tryCatch(
  readr::read_csv(here("data", "workforce_projections_consolidated.csv"),
                  show_col_types = FALSE),
  error = function(e) NULL
)

ui <- dashboardPage(
  dashboardHeader(title = "Workforce Cliff"),
  dashboardSidebar(
    sidebarMenu(
      menuItem("Retirement Cliff", tabName = "cliff", icon = icon("chart-line")),
      menuItem("Workforce Projections", tabName = "projections", icon = icon("table"))
    )
  ),
  dashboardBody(
    tabItems(
      # ── Retirement Cliff Tab ─────────────────────────────────────────────
      tabItem(tabName = "cliff",
        fluidRow(
          box(width = 12, title = "Retirement Cliff Simulation",
            p("Simulates how population coverage declines as the oldest physicians retire first.
               A steep drop indicates a 'retirement cliff' — concentrated retirement risk."),
            sliderInput("retire_age", "Retire physicians aged ≥:",
                        min = 55, max = 75, value = 65, step = 1),
            selectInput("subspec_filter", "Subspecialty:",
                        choices = c("All", "Urogynecology (FPMRS)", "Gynecologic Oncology", "MIGS"),
                        selected = "All"),
            selectInput("drive_minutes", "Drive-time band (minutes):",
                        choices = c("30", "60", "90", "120"),
                        selected = "60")
          )
        ),
        fluidRow(
          box(width = 8, plotOutput("cliff_plot", height = "400px")),
          box(width = 4,
            h4("Impact Summary"),
            verbatimTextOutput("cliff_summary"),
            p(em("Uses synthetic demo data. Real isochrones require MufflySamsung drive."))
          )
        )
      ),

      # ── Workforce Projections Tab ─────────────────────────────────────────
      tabItem(tabName = "projections",
        fluidRow(
          box(width = 12, title = "Monte Carlo Workforce Projections (2025–2029)",
            if (!is.null(workforce_data)) {
              DT::dataTableOutput("workforce_table")
            } else {
              p("workforce_projections_consolidated.csv not found. Run code/00_RUN_ALL.R first.")
            }
          )
        ),
        fluidRow(
          box(width = 12, title = "Supply Trajectory: FPMRS",
            plotOutput("supply_plot", height = "350px"))
        )
      )
    )
  )
)

server <- function(input, output, session) {

  # ── Demo data ──────────────────────────────────────────────────────────────
  demo_payload <- reactive({
    load_or_create_retirement_demo(data_dir = NULL, seed = 42L)
  })

  providers_filtered <- reactive({
    p <- demo_payload()$providers
    if (input$subspec_filter != "All") {
      p <- filter(p, subspecialty == input$subspec_filter)
    }
    p
  })

  # ── Cliff curve ────────────────────────────────────────────────────────────
  cliff_curve <- reactive({
    prov  <- providers_filtered()
    trcts <- demo_payload()$tracts
    drive <- as.numeric(input$drive_minutes)
    age_thresh <- input$retire_age

    full_cov <- tryCatch({
      isos <- make_demo_isochrones(prov, drive)
      stats <- compute_coverage_stats(trcts, isos)
      stats$pct_covered
    }, error = function(e) NA_real_)

    prov_active <- filter(prov, age < age_thresh)
    reduced_cov <- tryCatch({
      if (nrow(prov_active) == 0) return(0)
      isos <- make_demo_isochrones(prov_active, drive)
      stats <- compute_coverage_stats(trcts, isos)
      stats$pct_covered
    }, error = function(e) NA_real_)

    list(
      n_total   = nrow(prov),
      n_retired = nrow(prov) - nrow(prov_active),
      pct_workforce = 100 * (nrow(prov) - nrow(prov_active)) / nrow(prov),
      full_cov  = full_cov,
      reduced_cov = reduced_cov,
      delta_cov = full_cov - reduced_cov
    )
  })

  output$cliff_summary <- renderPrint({
    r <- cliff_curve()
    cat(sprintf("Retiring %d physicians (age ≥ %d)\n", r$n_retired, input$retire_age))
    cat(sprintf("%.1f%% of workforce removed\n\n", r$pct_workforce))
    cat(sprintf("Coverage before: %.1f%%\n", r$full_cov * 100))
    cat(sprintf("Coverage after:  %.1f%%\n", r$reduced_cov * 100))
    cat(sprintf("Coverage loss:   %.1f pp\n", r$delta_cov * 100))
  })

  output$cliff_plot <- renderPlot({
    prov  <- providers_filtered()
    trcts <- demo_payload()$tracts
    drive <- as.numeric(input$drive_minutes)

    curve_data <- tryCatch(
      compute_cliff_curve(trcts, prov, drive),
      error = function(e) tibble(removed_pct = numeric(0), covered_pct = numeric(0))
    )

    if (nrow(curve_data) == 0) {
      plot(0, type = "n", main = "Unable to compute cliff curve"); return()
    }

    ggplot(curve_data, aes(x = removed_pct * 100, y = covered_pct * 100)) +
      geom_area(fill = "#D62728", alpha = 0.15) +
      geom_line(color = "#D62728", linewidth = 1.4) +
      geom_point(color = "#D62728", size = 3) +
      scale_x_continuous(labels = function(x) paste0(x, "%")) +
      scale_y_continuous(labels = function(x) paste0(x, "%"), limits = c(0, 100)) +
      labs(x = "% of Workforce Retired (oldest first)",
           y = "Population Coverage (%)",
           title = "Retirement Cliff: Coverage vs. Workforce Removal",
           subtitle = paste0(input$subspec_filter, " | ", input$drive_minutes, "-min drive time")) +
      theme_minimal(base_size = 13) +
      theme(panel.grid.minor = element_blank())
  })

  # ── Workforce projections table ─────────────────────────────────────────────
  if (!is.null(workforce_data)) {
    output$workforce_table <- DT::renderDataTable({
      workforce_data |>
        select(Subspecialty = subspecialty_abbrev,
               `2025 Baseline` = baseline_2025,
               `2029 Projected` = projected_2029,
               `95% CI Lower` = ci95_lower,
               `95% CI Upper` = ci95_upper,
               `% Change` = percent_change,
               `Replacement Ratio` = replacement_ratio,
               Assessment = replacement_assessment) |>
        DT::datatable(options = list(dom = "t", paging = FALSE))
    })
  }

  # ── FPMRS supply plot ───────────────────────────────────────────────────────
  output$supply_plot <- renderPlot({
    hist_df <- tibble(
      year   = 2013:2024,
      supply = round(1196 - (2024 - (2013:2024)) * 4.4),
      phase  = "Observed"
    )
    proj_df <- tibble(
      year   = 2025:2029,
      supply = round(1283 + (1301 - 1283) * (0:4) / 4),
      lower  = round(seq(1283 - 15.2 * 1.96, 1271, length.out = 5)),
      upper  = round(seq(1283 + 15.2 * 1.96, 1330, length.out = 5)),
      phase  = "Projected"
    )

    ggplot() +
      geom_ribbon(data = proj_df,
                  aes(x = year, ymin = lower, ymax = upper),
                  fill = "#D62728", alpha = 0.15) +
      geom_line(data = hist_df, aes(x = year, y = supply),
                color = "#D62728", linewidth = 1.4) +
      geom_line(data = proj_df, aes(x = year, y = supply),
                color = "#D62728", linewidth = 1.4, linetype = "dashed") +
      geom_vline(xintercept = 2024.5, linetype = "dotted", color = "grey50") +
      scale_x_continuous(breaks = c(2013, 2016, 2019, 2022, 2025, 2029)) +
      scale_y_continuous(labels = comma) +
      labs(x = "Year", y = "Active FPMRS Physicians",
           title = "FPMRS Supply: Observed 2013–2024 | Projected 2025–2029") +
      theme_minimal(base_size = 12) +
      theme(panel.grid.minor = element_blank())
  })
}

shinyApp(ui, server)
