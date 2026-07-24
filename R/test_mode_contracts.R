# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Test-mode contracts — shared helpers for is_test_mode() detection.
# Sourced unconditionally at the top of pipeline scripts so TEST_MODE stubs
# are available even when main() has not yet been called.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' TRUE when the current run is a TEST_MODE invocation.
#' Reads the TEST_MODE environment variable (set by the test harness or CI).
is_test_mode <- function() {
  identical(Sys.getenv("TEST_MODE"), "1") || identical(Sys.getenv("TEST_MODE"), "true")
}
