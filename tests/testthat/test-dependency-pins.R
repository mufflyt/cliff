# GATE: the two places cliff pins non-CRAN dependencies must agree.
#
# DESCRIPTION Remotes: is read by remotes::install_deps() (how CI and most
# collaborators install). renv.lock RemoteSha is read by renv::restore() (how
# the acceptance gate installs). On 2026-08-15 they disagreed by eight days of
# mufflyaccess commits, which means the SSOT package cliff validates its
# published numbers against could differ between two machines that both
# believed they were following the repo.
#
# The check itself lives in scripts/ci/check_pins.R so CI can report it
# legibly; this test drives that same script so the guard cannot pass locally
# while failing in CI, or vice versa.

test_that("GATE: DESCRIPTION Remotes and renv.lock agree on every GitHub pin", {
  skip_if_no_repo()
  skip_if_not_installed("jsonlite")

  root <- cliff_repo_root()
  script <- file.path(root, "scripts", "ci", "check_pins.R")
  skip_if_not(file.exists(script), "scripts/ci/check_pins.R not present")

  out <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"),
    c("--no-init-file", shQuote(script)),
    stdout = TRUE, stderr = TRUE,
    env = c(paste0("CLIFF_ROOT=", root))
  ))
  status <- attr(out, "status")
  if (is.null(status)) status <- 0L

  expect_equal(status, 0L,
               info = paste0(
                 "dependency pins disagree between DESCRIPTION and renv.lock:\n",
                 paste(out, collapse = "\n")))
})

test_that("every DESCRIPTION Remotes ref is an immutable 40-character SHA", {
  skip_if_no_repo()

  dcf <- read.dcf(file.path(cliff_repo_root(), "DESCRIPTION"))
  if (!"Remotes" %in% colnames(dcf)) succeed()

  remotes <- trimws(strsplit(dcf[1, "Remotes"], ",")[[1]])
  remotes <- remotes[nzchar(remotes)]
  skip_if_not(length(remotes) > 0, "no Remotes to check")

  for (r in remotes) {
    ref <- if (grepl("@", r, fixed = TRUE)) sub(".*@", "", r) else ""
    # A branch or tag moves. Pinning to one makes the build unreproducible:
    # two installs a week apart silently get different code.
    expect_match(ref, "^[0-9a-f]{40}$",
                 info = paste0("Remotes entry '", r,
                               "' must pin a full commit SHA, not a mutable ref"))
  }
})
