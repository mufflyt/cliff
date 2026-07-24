# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# RStudio Helper: Run Workforce Analysis Pipeline
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# This helper file automatically sets the correct working directory and
# runs the complete pipeline. Just source this file from RStudio!
#
# Usage in RStudio:
#   1. Open this file (cliff/RUN_FROM_RSTUDIO.R)
#   2. Click "Source" button, or press Cmd+Shift+S (Mac) / Ctrl+Shift+S (Windows)
#   3. Watch the pipeline run!
#
# Or from console:
#   source("~/isochrones/cliff/RUN_FROM_RSTUDIO.R")
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Find the isochrones project directory
# This works whether you source from any location
script_path <- normalizePath(sys.frame(1)$ofile, mustWork = FALSE)

# If ofile doesn't work (when using Source button), try alternative methods
if (!file.exists(script_path) || script_path == "") {
  # Try to find it using common project indicators
  if (file.exists("code/00_RUN_ALL.R")) {
    # Already in the right directory
    project_dir <- getwd()
  } else if (file.exists("~/isochrones/code/00_RUN_ALL.R")) {
    # Standard location
    project_dir <- "~/isochrones"
  } else {
    stop("\n❌ ERROR: Cannot locate isochrones project directory!\n",
         "   Please ensure you are in /Users/tmuffly/cliff\n",
         "   Or run: setwd('/Users/tmuffly/cliff')\n")
  }
} else {
  # Script path is valid, navigate to project root
  project_dir <- dirname(dirname(script_path))
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
