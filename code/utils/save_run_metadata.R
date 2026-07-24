# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Save Run Metadata
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Purpose: Archive outputs from pipeline runs with complete metadata
#
# Creates timestamped directory with:
#   - metadata.json (run parameters, git info, timestamps)
#   - figures/ (all generated figures)
#   - data/ (consolidated data file)
#
# Author: Tyler Muffly, MD / Claude Code
# Date: 2026-01-12
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

save_run_metadata <- function(scenario_name = "default",
                               runtime_seconds = NA,
                               additional_metadata = list()) {

  suppressPackageStartupMessages({
    library(jsonlite)
    library(here)
  })

  # Create timestamp for this run
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  run_dir <- here("outputs/runs", timestamp)

  # Create directory structure
  dir.create(file.path(run_dir, "figures"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(run_dir, "data"), recursive = TRUE, showWarnings = FALSE)

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Collect Git Information
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  git_info <- list(
    commit = NA,
    branch = NA,
    status = NA,
    remote = NA
  )

  tryCatch({
    git_info$commit <- system("git rev-parse HEAD", intern = TRUE, ignore.stderr = TRUE)[1]
    git_info$branch <- system("git rev-parse --abbrev-ref HEAD", intern = TRUE, ignore.stderr = TRUE)[1]
    git_info$status <- system("git status --short", intern = TRUE, ignore.stderr = TRUE)
    git_info$remote <- system("git config --get remote.origin.url", intern = TRUE, ignore.stderr = TRUE)[1]
  }, error = function(e) {
    # Git info optional - continue if not available
  })

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Load Fellowship Assumptions
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  fellowship_assumptions <- list()
  config_file <- here("config/fellowship_assumptions.yml")

  if (file.exists(config_file)) {
    config <- yaml::read_yaml(config_file)
    if (scenario_name %in% names(config)) {
      fellowship_assumptions <- config[[scenario_name]]
    }
  }

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Create Metadata Object
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  metadata <- list(
    run_info = list(
      timestamp = timestamp,
      datetime = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      scenario = scenario_name,
      runtime_seconds = runtime_seconds,
      r_version = paste(R.version$major, R.version$minor, sep = "."),
      platform = R.version$platform
    ),

    fellowship_assumptions = fellowship_assumptions,

    git = git_info,

    files = list(
      data = "data/workforce_projections_consolidated.csv",
      figures = c(
        "figures/figure1_workforce_trajectories.png",
        "figures/figure1_workforce_trajectories.tiff",
        "figures/figure2_replacement_gap.png",
        "figures/figure2_replacement_gap.tiff",
        "figures/workforce_crisis_abstract.png",
        "figures/workforce_crisis_abstract.tiff"
      )
    ),

    additional = additional_metadata
  )

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Save Metadata JSON
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  metadata_file <- file.path(run_dir, "metadata.json")
  write_json(metadata, metadata_file, pretty = TRUE, auto_unbox = TRUE)

  cat(sprintf("  ✓ Saved metadata: %s\n", metadata_file))

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Copy Data Files
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  data_source <- here("data/workforce_projections_consolidated.csv")
  if (file.exists(data_source)) {
    data_dest <- file.path(run_dir, "data", "workforce_projections_consolidated.csv")
    file.copy(data_source, data_dest, overwrite = TRUE)
    cat(sprintf("  ✓ Archived data: %s\n", basename(data_dest)))
  }

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Copy Figures
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  figure_dir <- here("figures")
  if (dir.exists(figure_dir)) {
    figure_files <- list.files(figure_dir,
                                pattern = "\\.(png|tiff)$",
                                full.names = TRUE)

    for (fig_file in figure_files) {
      fig_dest <- file.path(run_dir, "figures", basename(fig_file))
      file.copy(fig_file, fig_dest, overwrite = TRUE)
    }

    cat(sprintf("  ✓ Archived %d figures\n", length(figure_files)))
  }

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Create README
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  readme_content <- sprintf("# Pipeline Run: %s

## Run Information
- **Timestamp:** %s
- **Scenario:** %s
- **Runtime:** %.1f seconds
- **Git Commit:** %s
- **Git Branch:** %s

## Fellowship Assumptions
- **FPMRS:** %d fellows/year
- **GO:** %d fellows/year
- **MIG:** %d fellows/year

## Outputs
- Data: `data/workforce_projections_consolidated.csv`
- Figures: 6 files in `figures/` directory
- Metadata: `metadata.json`

## Files Archived
%s
",
    timestamp,
    metadata$run_info$datetime,
    scenario_name,
    runtime_seconds,
    ifelse(is.na(git_info$commit), "N/A", substr(git_info$commit, 1, 8)),
    ifelse(is.na(git_info$branch), "N/A", git_info$branch),
    fellowship_assumptions$FPMRS %||% 0,
    fellowship_assumptions$GO %||% 0,
    fellowship_assumptions$MIG %||% 0,
    paste("- ", list.files(file.path(run_dir, "figures")), collapse = "\n")
  )

  readme_file <- file.path(run_dir, "README.md")
  writeLines(readme_content, readme_file)
  cat(sprintf("  ✓ Created README: %s\n", basename(readme_file)))

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Return Information
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  cat(sprintf("\n✓ Run archived to: %s\n", run_dir))

  return(invisible(list(
    run_dir = run_dir,
    timestamp = timestamp,
    metadata_file = metadata_file
  )))
}

# Helper operator for default values
`%||%` <- function(x, y) if (is.null(x)) y else x
