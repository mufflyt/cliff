# Regression tests for training-inference data-flow bugs. These are deliberately
# small DuckDB fixtures: the production input tables are external and far too
# large for a package test.

library(testthat)

.make_fellowship_gt_table <- function(npi, fellowship_name) {
  gt <- data.frame(
    `NPI.Number` = npi,
    `Merged_Fellowship` = fellowship_name,
    `HG_Fellowship.Hospital.1...Name` = "",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  for (i in 1:10) {
    gt[[paste0("DOX_Training.", i, "...Type")]] <- ""
    gt[[paste0("DOX_Training.", i, "...Institution")]] <- ""
  }
  gt
}

.write_fellowship_crosswalk <- function(dir, approved = TRUE) {
  xwalk <- data.frame(
    source_name_raw = "Synthetic Fellowship Hospital",
    source_name_normalized = "SYNTHETIC FELLOWSHIP HOSPITAL",
    match_class = "exact_verified",
    freida_program_name = "Synthetic FREIDA Fellowship",
    freida_acgme_id = "P1",
    freida_state = "CO",
    approved_for_ground_truth = approved,
    stringsAsFactors = FALSE
  )
  utils::write.csv(xwalk, file.path(dir, "fellowship_name_crosswalk.csv"), row.names = FALSE)
  xwalk
}

.synthetic_programs <- function() {
  data.frame(
    acgme_program_id = "P1",
    institution = "Synthetic Program Institution",
    city = "Denver",
    state = "CO",
    annual_births = 100,
    nicu_beds = 10,
    total_beds = 200,
    trauma_center = "Yes",
    stringsAsFactors = FALSE
  )
}

test_that("approved_training_crosswalk keeps only explicit approvals", {
  xwalk <- data.frame(
    source_name_raw = c("approved", "unapproved", "missing"),
    approved_for_ground_truth = c(TRUE, FALSE, NA),
    stringsAsFactors = FALSE
  )
  expect_equal(approved_training_crosswalk(xwalk)$source_name_raw, "approved")

  xwalk$approved_for_ground_truth <- c("true", "FALSE", NA_character_)
  expect_equal(approved_training_crosswalk(xwalk)$source_name_raw, "approved")
})

test_that("phase 0 honors the explicit temporal DB and input location columns are optional", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")

  npi <- "1234567893"
  db_path <- tempfile(fileext = ".duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), db_path)
  DBI::dbWriteTable(con, "goba_dox_hg_medical_school",
                    .make_fellowship_gt_table(npi, "Synthetic Fellowship Hospital"))
  DBI::dbDisconnect(con, shutdown = TRUE)

  freida_dir <- tempfile("freida-")
  dir.create(freida_dir)
  .write_fellowship_crosswalk(freida_dir, approved = TRUE)
  old_freida_dir <- Sys.getenv("FREIDA_DATA_DIR", unset = NA_character_)
  Sys.setenv(FREIDA_DATA_DIR = freida_dir)
  on.exit({
    if (is.na(old_freida_dir)) Sys.unsetenv("FREIDA_DATA_DIR") else Sys.setenv(FREIDA_DATA_DIR = old_freida_dir)
    unlink(c(db_path, paste0(db_path, ".wal")), force = TRUE)
    unlink(freida_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  physicians <- data.frame(npi = npi, stringsAsFactors = FALSE)
  out <- infer_fellowship_training(
    physicians,
    programs = .synthetic_programs(),
    temporal_db_path = db_path
  )

  expect_equal(nrow(out), 1L)
  expect_equal(out$inferred_acgme_id, "P1")
  expect_equal(out$inferred_institution, "Synthetic Program Institution")
  expect_equal(out$inferred_city, "Denver")
  expect_equal(out$inferred_state, "CO")
  expect_equal(out$inference_method, "ground_truth_hg_dox")
})

test_that("ABOG neighbor votes do not use unapproved crosswalk rows", {
  skip_if_no_repo()
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")

  db_path <- tempfile(fileext = ".duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), db_path)
  DBI::dbExecute(con, "CREATE SCHEMA credentials")

  providers <- data.frame(
    abog_id = c(99L, 100L, 101L),
    npi = c(991L, 1001L, 1011L),
    physician_name = c("Neighbor One, M.D.", "Target Person, M.D.", "Neighbor Two, M.D."),
    stringsAsFactors = FALSE
  )
  matches <- data.frame(
    npi = c("2222222222", "1111111111", "3333333333"),
    match_name = c("Neighbor One", "Target Person", "Neighbor Two"),
    primary_cert_date = as.Date(c("2020-01-01", "2020-01-01", "2020-01-01")),
    stringsAsFactors = FALSE
  )
  goba <- data.frame(
    `NPI.Number` = c("1111111111", "2222222222", "3333333333"),
    `Merged_Residency` = c(NA_character_, "Unapproved Program", "Unapproved Program"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )

  DBI::dbWriteTable(con, DBI::Id(schema = "credentials", table = "abog_providers"), providers)
  DBI::dbWriteTable(con, DBI::Id(schema = "credentials", table = "abog_npi_matches"), matches)
  DBI::dbWriteTable(con, "goba_dox_hg_medical_school", goba)
  DBI::dbDisconnect(con, shutdown = TRUE)

  artifact <- here::here("artifacts", "audit", "abog_unmapped_vote_names.csv")
  had_artifact <- file.exists(artifact)
  old_artifact <- if (had_artifact) tempfile(fileext = ".csv") else NA_character_
  if (had_artifact) file.copy(artifact, old_artifact, overwrite = TRUE)
  on.exit({
    unlink(c(db_path, paste0(db_path, ".wal")), force = TRUE)
    if (had_artifact && file.exists(old_artifact)) {
      dir.create(dirname(artifact), recursive = TRUE, showWarnings = FALSE)
      file.copy(old_artifact, artifact, overwrite = TRUE)
    } else if (!had_artifact) {
      unlink(artifact, force = TRUE)
    }
  }, add = TRUE)

  xwalk <- data.frame(
    source_name_raw = "Unapproved Program",
    freida_program_name = "Unapproved FREIDA Program",
    freida_acgme_id = "P_BAD",
    freida_state = "CO",
    approved_for_ground_truth = FALSE,
    stringsAsFactors = FALSE
  )

  result <- infer_from_abog_neighbors(
    npis = "1111111111",
    db_path = db_path,
    crosswalk = xwalk,
    programs = data.frame(
      acgme_program_id = "P_BAD",
      institution = "Bad Institution",
      city = "Denver",
      state = "CO",
      annual_births = 1,
      nicu_beds = 1,
      total_beds = 1,
      trauma_center = "No",
      stringsAsFactors = FALSE
    ),
    window = 2L,
    min_neighbors = 2L,
    confidence = 0.70
  )

  expect_null(result)
})
