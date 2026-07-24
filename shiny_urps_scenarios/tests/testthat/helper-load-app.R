# Test helpers shared across the URPS Shiny app test files.

# Directory containing app.R (two levels up from tests/testthat).
app_test_dir <- function() testthat::test_path("..", "..")

# Load the app's top-level definitions (model functions, constants, main_server,
# VALIDATION) into a fresh environment WITHOUT launching the Shiny app, so the pure
# functions and the server reactives can be unit-tested with testServer(). Sourcing
# runs with the working directory set to the app dir so app.R's
# source("urps_model_data.R") and the git/shasum provenance calls resolve.
.app_env_cache <- NULL
load_app_env <- function() {
  if (!is.null(.app_env_cache)) return(.app_env_cache)     # source app.R (+ gate MC) once
  e <- new.env(parent = globalenv())
  e$shinyApp <- function(ui, server) invisible(NULL)       # stub: do not launch
  withr::with_dir(app_test_dir(), {
    # app.R's own source("urps_model_data.R") uses local=FALSE (lands in globalenv);
    # pre-source it into `e` so the model-data constants (URPS_AGES, BAND_EV, ...) are
    # directly reachable as e$URPS_AGES in the tests.
    sys.source("urps_model_data.R", envir = e)
    sys.source("app.R", envir = e)
  })
  .app_env_cache <<- e
  e
}

# Standard inputs for the Best-estimate (primary) scenario, used by testServer tests.
best_estimate_inputs <- function() list(
  preset = "Best estimate", comp = 64, conv = 100, mult = 1.0, horizon = 4,
  win = "fully_obs", hz70 = "obs", mort = 0, entry = 34, draws = 300,
  fte_in = 0.9, fte_out = 1.0, demand = 1, reset = 0, go_explore = 0
)

# AppDriver factory for the browser (shinytest2) tests.
new_app <- function(name) {
  shinytest2::AppDriver$new(
    app_dir = app_test_dir(), name = name, width = 1400, height = 950,
    load_timeout = 60 * 1000, timeout = 30 * 1000
  )
}
