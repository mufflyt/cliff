# tests/testthat/test-mufflyaccess-version.R
library(testthat)
test_that("cliff uses an approved mufflyaccess version", {
  skip_if_not_installed("mufflyaccess")
  installed <- utils::packageVersion(
    "mufflyaccess"
  )
  minimum_approved <- package_version(
    "0.1.0"
  )
  expect_gte(
    installed,
    minimum_approved
  )
})
test_that("mufflyaccess is recorded in renv.lock", {
  # resolve from the repo root (testthat's wd is tests/testthat/, not the root)
  lockfile <- tryCatch(here::here("renv.lock"), error = function(e) "renv.lock")
  skip_if_not(file.exists(lockfile))
  lock <- jsonlite::read_json(
    lockfile,
    simplifyVector = FALSE
  )
  expect_true(
    "mufflyaccess" %in%
      names(lock$Packages),
    info = paste(
      "mufflyaccess must be pinned in renv.lock",
      "rather than installed ad hoc"
    )
  )
  record <- lock$Packages$mufflyaccess
  expect_true(
    record$Source %in% c(
      "GitHub",
      "Repository"
    )
  )
  if (identical(record$Source, "GitHub")) {
    expect_identical(
      record$RemoteUsername,
      "mufflyt"
    )
    expect_identical(
      record$RemoteRepo,
      "mufflyaccess"
    )
    expect_match(
      record$RemoteSha,
      "^[0-9a-f]{40}$"
    )
  }
})
