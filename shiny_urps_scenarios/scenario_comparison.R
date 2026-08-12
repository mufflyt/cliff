# ==============================================================================
# scenario_comparison.R -- UNC/Sheps-style multi-scenario comparison module.
#
# A self-contained Shiny module (NS-isolated) that renders the hardened contract
# v3.0.0 scenario analysis as an overlaid, comparable set of projection lines
# with a per-line "Model Parameter Summary" table carrying full provenance, a
# confidence-interval toggle, Download Data / Download Image, (i) tooltips, and a
# Methods/citation panel. Reads only the frozen CSVs produced by
# scripts/urps_baseline_scenarios/urps_baseline_scenarios_v3_hardened.R (bundled
# into data/), so it never re-derives a workforce number.
# ==============================================================================

.sc_data_dir <- function() {
  for (d in c("data", file.path("shiny_urps_scenarios", "data")))
    if (file.exists(file.path(d, "scenario_trajectories.csv"))) return(d)
  "data"
}

.sc_read <- function(dir = .sc_data_dir()) {
  rd <- function(f) utils::read.csv(file.path(dir, f), stringsAsFactors = FALSE, check.names = FALSE)
  list(t1 = rd("scenario_table1.csv"), t2 = rd("scenario_table2.csv"),
       traj = rd("scenario_trajectories.csv"), decomp = rd("scenario_decomposition.csv"))
}

# combined per-line parameter summary (published + controlled), shared columns
.sc_param_table <- function(D) {
  keep <- c("scenario_id","observed_or_synthetic","source_artifact","source_year",
            "index_year","target_year","horizon","baseline_count","projected_count",
            "ci95_lower","ci95_upper","avg_annual_retirements","replacement_ratio",
            "engine_version","seed","mc_draws","frozen_or_recalculated","note")
  pick <- function(df) { for (k in setdiff(keep, names(df))) df[[k]] <- NA; df[, keep, drop = FALSE] }
  rbind(pick(D$t1), pick(D$t2))
}

.sc_info <- function(label, tip) {
  bslib::tooltip(shiny::span(label, " ", shiny::icon("circle-info")), tip, placement = "right")
}

scenario_comparison_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::card(
    bslib::card_header("Scenario comparison — contract v3.0.0 (baseline choice × same engine)"),
    bslib::card_body(
      shiny::p(shiny::HTML(
        "Each line is one projection run through the <b>same</b> age-structured engine ",
        "(<code>wc_project</code>), horizon 4, so differences reflect the baseline/cohort, ",
        "not the model. The <b>published legacy</b> line is the frozen SGS result, retained ",
        "for reproducibility and <i>not</i> recalculated.")),
      shiny::fluidRow(
        shiny::column(7, shiny::uiOutput(ns("scenario_picker"))),
        shiny::column(5,
          shiny::checkboxInput(ns("ci"), "Show confidence intervals", TRUE),
          .sc_info("Baseline count is an estimate; the band is the 95% Monte Carlo interval (fixed seed).",
                   "Wider for smaller cohorts and later years."))),
      shiny::plotOutput(ns("overlay"), height = "420px"),
      shiny::h5("Model parameter summary"),
      shiny::div(style = "overflow-x:auto;", shiny::tableOutput(ns("params"))),
      shiny::fluidRow(
        shiny::column(6, shiny::downloadButton(ns("dl_data"), "Download data (provenance CSV)")),
        shiny::column(6, shiny::downloadButton(ns("dl_img"),  "Download image (PNG)"))),
      shiny::hr(),
      shiny::h5("Methods and provenance"),
      shiny::htmlOutput(ns("methods"))))
}

scenario_comparison_server <- function(id, data_dir = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    D  <- if (is.null(data_dir)) .sc_read() else .sc_read(data_dir)
    scen <- unique(D$traj$scenario_id)
    params <- .sc_param_table(D)

    output$scenario_picker <- shiny::renderUI(
      shiny::checkboxGroupInput(ns("show"), "Scenarios to plot", choices = scen, selected = scen, inline = TRUE))

    sel <- shiny::reactive({ s <- input$show; if (is.null(s)) scen else s })

    overlay <- shiny::reactive({
      d <- D$traj[D$traj$scenario_id %in% sel(), , drop = FALSE]
      g <- ggplot2::ggplot(d, ggplot2::aes(year, active, color = scenario_id))
      if (isTRUE(input$ci))
        g <- g + ggplot2::geom_ribbon(
          ggplot2::aes(ymin = ci95_lower, ymax = ci95_upper, fill = scenario_id),
          alpha = 0.15, color = NA, na.rm = TRUE)
      g + ggplot2::geom_line(linewidth = 1) + ggplot2::geom_point(size = 1.6) +
        ggplot2::scale_x_continuous(breaks = sort(unique(d$year))) +
        ggplot2::labs(x = "Year", y = "Active urogynecologists (headcount)",
                      color = "Scenario", fill = "Scenario",
                      title = "URPS workforce projection by baseline scenario") +
        ggplot2::theme_minimal(base_size = 13) +
        ggplot2::theme(plot.title = ggplot2::element_text(size = ggplot2::rel(1.1)),
                       plot.title.position = "plot", legend.position = "bottom")
    })
    output$overlay <- shiny::renderPlot(overlay())

    output$params <- shiny::renderTable(
      params[params$scenario_id %in% sel(), , drop = FALSE], striped = TRUE, na = "")

    output$dl_data <- shiny::downloadHandler(
      filename = function() "urps_scenario_comparison_v3.0.0.csv",
      content  = function(file) utils::write.csv(params[params$scenario_id %in% sel(), ], file, row.names = FALSE))
    output$dl_img <- shiny::downloadHandler(
      filename = function() "urps_scenario_comparison_v3.0.0.png",
      content  = function(file) ggplot2::ggsave(file, overlay(), width = 9, height = 5, dpi = 150, bg = "white"))

    output$methods <- shiny::renderUI(shiny::HTML(paste0(
      "<p><b>Estimand (mufflyaccess contract v3.0.0):</b> 2023 board-certified active URPS = ",
      "<b>1,306</b> (national); 2025 roster snapshot = <b>1,339</b>. 1,332/1,329 are retired v2.1.0 cells.</p>",
      "<p><b>Engine:</b> <code>wc_project</code> (R/workforce_cliff_engine.R), horizon 4, ",
      "64 entrants/yr at age 34; 95% band from a Binomial Monte Carlo (seed 20260718, 4,000 draws).</p>",
      "<p><b>Age:</b> an <i>estimated proxy</i> derived from certification timing ",
      "(<code>age_proxy_from_cert</code>) — not observed age.</p>",
      "<p><b>legacy_primarycert_rerun (N=1,301):</b> best-effort reconstruction of the published ",
      "1,295 cohort (ABOG in-model 1,031 + ABU net-new 270); +6 vs published because the older ",
      "scrape's 6 non-datable exclusions are not encoded in the tracked rosters. The authoritative ",
      "legacy result is the frozen published line, not this rerun.</p>",
      "<p><b>Caveat:</b> the same-engine legacy rerun (ratio 4.97) differs from the published 5.61 at ",
      "nearly the same baseline, so the 5.61→~4.9 shift is driven by the engine/hazard ",
      "parameterization, not the baseline count.</p>",
      "<p style='color:#5f6673;font-size:12px;'>Source: cliff scenario-validity hardening, ",
      "urps_baseline_scenarios_v3_hardened.R. Accessed ", as.character(Sys.Date()), ".</p>",
      .sc_provenance_html())))
  })
}

# Compact data-lineage footer read from the bundled provenance record, so the app
# always displays the exact code/engine/SSOT/input hashes the tables were built from.
.sc_provenance_html <- function(dir = .sc_data_dir()) {
  p <- file.path(dir, "scenario_provenance.json")
  if (!file.exists(p) || !requireNamespace("jsonlite", quietly = TRUE)) return("")
  pv <- tryCatch(jsonlite::read_json(p, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(pv)) return("")
  short <- function(x) if (is.null(x) || is.na(x)) "n/a" else substr(x, 1, 12)
  paste0(
    "<details style='margin-top:8px;'><summary style='color:#5f6673;font-size:12px;cursor:pointer;'>",
    "Data lineage (provenance)</summary>",
    "<div style='color:#5f6673;font-size:11px;font-family:monospace;line-height:1.5;'>",
    "generated: ", pv$generated_at, "<br>",
    "code sha256: ", short(pv$producer$script_sha256), " | git ", short(pv$producer$git_commit), "<br>",
    "engine: ", pv$engine$fn, " sha256 ", short(pv$engine$file_sha256),
    " | wc_project equivalence max_abs ", pv$engine$equivalence_vs_reimplementation$max_abs, "<br>",
    "SSOT: mufflyaccess ", pv$ssot$installed_version, " contract ", pv$ssot$contract_version,
    " | cells active_2023=", pv$ssot$analysis_cells$active_2023_national,
    " roster_2025=", pv$ssot$analysis_cells$roster_2025_national,
    " | tie_verified ", pv$ssot$ssot_tie_verified, "<br>",
    "seed ", pv$parameters$mc_seed, " | draws ", pv$parameters$mc_draws,
    " | horizon ", pv$parameters$horizon,
    "</div></details>")
}
