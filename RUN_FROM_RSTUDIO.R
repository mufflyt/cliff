# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# RStudio Helper: Run Workforce Cliff Pipeline
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Usage in RStudio:
#   1. Open this file in RStudio
#   2. Click "Source" (Cmd+Shift+S on Mac / Ctrl+Shift+S on Windows)
#
# Or from the console:
#   source("~/cliff/RUN_FROM_RSTUDIO.R")
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

script_path <- normalizePath(sys.frame(1)$ofile, mustWork = FALSE)

if (!file.exists(script_path) || script_path == "") {
  if (file.exists("code/00_RUN_ALL.R")) {
    project_dir <- getwd()
  } else if (file.exists("~/cliff/code/00_RUN_ALL.R")) {
    project_dir <- "~/cliff"
  } else {
    stop("\nERROR: Cannot locate cliff project directory!\n",
         "   Please run: setwd('~/cliff')\n")
  }
} else {
  project_dir <- dirname(script_path)
}

# Expand tilde and normalize path
project_dir <- normalizePath(path.expand(project_dir), mustWork = TRUE)

# Change to project directory
cat(sprintf("Setting working directory to: %s\n", project_dir))
setwd(project_dir)

# Verify we're in the right place
if (!file.exists("code/00_RUN_ALL.R")) {
  stop("\n❌ ERROR: code/00_RUN_ALL.R not found!\n",
       "   Current directory: ", getwd(), "\n",
       "   Please check project structure.\n")
}

cat("✓ Working directory set correctly\n")
cat("✓ Starting pipeline...\n\n")

# Run the pipeline
source("code/00_RUN_ALL.R")
