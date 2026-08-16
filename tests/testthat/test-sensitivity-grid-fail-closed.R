# BEHAVIOURAL REGRESSION TEST for the adjudicated sensitivity-grid defect.
#
# The contract, stated as the incident stated it:
#
#   Given source specialties    = {GO, URPS}
#   and requested specialties   = {GO, URPS, MIGS},
#   the publication generator must either
#     (a) error explicitly naming MIGS as unavailable, or
#     (b) intentionally emit only GO and URPS.
#   It must NEVER emit MIGS with NA scientific values.
#
# (a) is required here, not merely preferred. This is manuscript-producing code, and
# silent omission conceals exactly the same class of scientific-scope change that
# produced the incident: MIGS was withdrawn upstream, the generator did not adapt, and
# the result was a fabricated NA row bound for Appendix Table S17.
#
# This runs the REAL generator in a sandbox project, so it tests behaviour rather than
# the presence of a code pattern. It never touches the repository's own artifacts.
#
# Adjudication: docs/adjudication/sensitivity_grid.md

skip_if_no_repo()

ROOT <- cliff_repo_root()
GEN <- file.path(ROOT, "scripts", "sensitivity_grid.R")

# Build a minimal standalone project containing only what the generator needs.
.sandbox <- function(window_rows) {
  dir <- file.path(tempfile("gridsandbox"))
  dir.create(file.path(dir, "data"), recursive = TRUE)
  dir.create(file.path(dir, "scripts"), recursive = TRUE)
  dir.create(file.path(dir, "manuscript", "R"), recursive = TRUE)
  dir.create(file.path(dir, "R"), recursive = TRUE)
  file.create(file.path(dir, ".here"))            # anchors here::here() to the sandbox
  file.copy(GEN, file.path(dir, "scripts", "sensitivity_grid.R"))
  file.copy(file.path(ROOT, "manuscript", "R", "workforce_data_contract.R"),
            file.path(dir, "manuscript", "R", "workforce_data_contract.R"))
  file.copy(file.path(ROOT, "R", "workforce_constants.R"),
            file.path(dir, "R", "workforce_constants.R"))
  writeLines(
    c("window,label,subspecialty_abbrev,rate,dynamic_ratio,assessment", window_rows),
    file.path(dir, "data", "departure_window_sensitivity.csv"))
  dir
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Always run INSIDE the sandbox. Never invoke the generator with the repository as
# the working directory: it writes to data/ and would clobber the real artifact.
.run <- function(dir) {
  rscript <- file.path(R.home("bin"), "Rscript")
  # setwd, not a shell `cd`: system2() pastes its args without quoting, so
  # system2("sh", c("-c", cmd)) silently runs only the first word of cmd and the
  # generator executes in the CALLER's directory. on.exit restores unconditionally.
  old <- setwd(dir); on.exit(setwd(old), add = TRUE)
  out <- suppressWarnings(system2(rscript,
                                  c("--no-init-file", "scripts/sensitivity_grid.R"),
                                  stdout = TRUE, stderr = TRUE))
  list(status = attr(out, "status") %||% 0L, output = paste(out, collapse = "\n"))
}

TWO <- c("2016-2021,fully_obs,URPS,0.91,5.38,Above replacement",
         "2016-2019,drop2,URPS,0.85,5.75,Above replacement",
         "2016-2023,full,URPS,1.37,3.57,Above replacement",
         "2016-2021,fully_obs,GO,1,7.11,Above replacement",
         "2016-2019,drop2,GO,1.12,6.37,Above replacement",
         "2016-2023,full,GO,1.66,4.3,Above replacement")
THREE <- c(TWO,
           "2016-2021,fully_obs,MIGS,0.6,11.12,Above replacement",
           "2016-2019,drop2,MIGS,0.5,13.16,Above replacement",
           "2016-2023,full,MIGS,0.9,7.3,Above replacement")

test_that("a requested cohort absent from the source data FAILS CLOSED, naming it", {
  skip_if_not(file.exists(GEN), "generator not present")
  dir <- .sandbox(TWO)
  r <- .run(dir)

  expect_gt(r$status, 0L)                       # (a): it must error, not proceed
  expect_match(r$output, "MIGS", fixed = TRUE,
               info = "the error must name the unavailable cohort")

  # and it must not have written a partial or corrupt artifact on the way out
  out <- file.path(dir, "data", "sensitivity_grid_summary.csv")
  if (file.exists(out)) {
    d <- utils::read.csv(out, stringsAsFactors = FALSE, na.strings = c("NA", ""))
    expect_false(any(is.na(d$subspecialty_abbrev)))
  }
})

test_that("it NEVER emits a cohort with NA scientific values", {
  skip_if_not(file.exists(GEN), "generator not present")
  dir <- .sandbox(TWO)
  .run(dir)
  out <- file.path(dir, "data", "sensitivity_grid_summary.csv")

  # Two acceptable outcomes, asserted rather than skipped: either the fail-closed
  # path wrote nothing at all, or whatever it wrote contains no fabricated cohort.
  if (!file.exists(out)) {
    succeed()  # fail-closed: no artifact, so no fabricated row is possible
  } else {
    d <- utils::read.csv(out, stringsAsFactors = FALSE, na.strings = c("NA", ""))
    expect_false(any(is.na(d$subspecialty_abbrev)),
                 info = "a fabricated NA cohort row reached a publication artifact")
    expect_false(any(d$subspecialty_abbrev %in% "MIGS" & is.na(d$worst_ratio)))
  }
})

test_that("when every requested cohort IS present, it succeeds cleanly", {
  skip_if_not(file.exists(GEN), "generator not present")
  dir <- .sandbox(THREE)
  r <- .run(dir)
  expect_equal(r$status, 0L, info = r$output)

  out <- file.path(dir, "data", "sensitivity_grid_summary.csv")
  expect_true(file.exists(out))
  d <- utils::read.csv(out, stringsAsFactors = FALSE, na.strings = c("NA", ""))
  expect_setequal(d$subspecialty_abbrev, c("GO", "URPS", "MIGS"))
  expect_false(any(is.na(d$subspecialty_abbrev)))
  expect_equal(nrow(d), 3L)
})
