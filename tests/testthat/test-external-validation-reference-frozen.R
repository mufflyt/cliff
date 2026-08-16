# GATE: an external-validation artifact must declare an immutable reference
# standard, by snapshot id AND cryptographic hash.
#
# This exists because of one adjudicated failure, not as general policy.
# data/classifier_validation_external.csv validates the departure classifier
# against a state medical-board registry that is gitignored upstream and was
# reached through a MUTABLE SYMLINK (gold/ -> whatever was last built). That
# symlink was rewritten on 2026-08-09 and the committed artifact stopped
# reproducing -- URPS n=415 -> 499, sensitivity 0.250 -> 0.188 -- while the
# generator and the cohort were byte-identical throughout. Nothing was wrong and
# nothing could be reproduced.
#
# A validation result means nothing without a stated reference standard. The
# generator now pins a dated snapshot and refuses to run if its bytes differ.
# These tests keep it that way.
#
# Adjudication: docs/adjudication/classifier_validation_external.md

skip_if_no_repo()

GEN <- file.path(cliff_repo_root(), "scripts",
                 "validate_departure_classifier_external.R")
UPD <- file.path(cliff_repo_root(), "scripts",
                 "validate_departure_classifier_external_updated_reference.R")

test_that("the published external validation pins a hashed reference snapshot", {
  skip_if_not(file.exists(GEN), "generator not present")
  src <- readLines(GEN, warn = FALSE)
  code <- src[!grepl("^\\s*#", src)]

  # a 64-hex sha256 constant, and an actual verification against it
  expect_true(any(grepl("[0-9a-f]{64}", code)),
              info = "no sha256 recorded for the reference standard")
  expect_true(any(grepl("sha256sum", code)),
              info = "the recorded hash is never verified at run time")
  expect_true(any(grepl("state_registry_frozen", code)),
              info = "the generator does not resolve the FROZEN registry key")
})

test_that("the published external validation does NOT read the mutable registry", {
  skip_if_not(file.exists(GEN), "generator not present")
  src <- readLines(GEN, warn = FALSE)
  code <- src[!grepl("^\\s*#", src)]
  # wc_path("state_registry") resolves through the symlink that moved.
  expect_false(any(grepl('wc_path\\(\\s*["\']state_registry["\']\\s*\\)', code)),
               info = paste("the generator resolves the MUTABLE state_registry key.",
                            "It must use state_registry_frozen; a moving gold",
                            "standard is what made this artifact unreproducible."))
})

test_that("the frozen reference snapshot still matches its recorded hash", {
  skip_if_not(file.exists(GEN), "generator not present")
  src <- readLines(GEN, warn = FALSE)
  sha <- regmatches(src, regexpr("[0-9a-f]{64}", src))
  sha <- sha[nzchar(sha)][1]
  skip_if_not(!is.na(sha), "no sha256 found in the generator")

  wp <- file.path(cliff_repo_root(), "R", "wc_path.R")
  skip_if_not(file.exists(wp), "wc_path not present")
  e <- new.env(); sys.source(wp, e)
  p <- tryCatch(e$wc_path("state_registry_frozen"), error = function(...) NA_character_)
  skip_if_not(!is.na(p) && file.exists(p),
              "the frozen registry snapshot is not available in this environment")

  expect_equal(unname(as.character(tools::sha256sum(p))), sha,
               info = paste("the frozen reference standard has changed on disk.",
                            "It is frozen by design: a refresh is a new versioned",
                            "analysis, not an edit to the published one."))
})

test_that("the updated-reference analysis is a separate, labelled artifact", {
  skip_if_not(file.exists(UPD), "updated-reference script not present")
  # The refreshed basis must never overwrite the published one.
  out_published <- file.path(cliff_repo_root(), "data",
                             "classifier_validation_external.csv")
  out_updated <- file.path(cliff_repo_root(), "data",
                           "classifier_validation_external_updated_reference.csv")
  expect_true(file.exists(out_published))
  if (file.exists(out_updated)) {
    d <- utils::read.csv(out_updated, stringsAsFactors = FALSE)
    # it must carry BOTH bases, each stamped with its snapshot and hash
    expect_true(all(c("reference_basis", "reference_snapshot_id",
                      "reference_sha256") %in% names(d)))
    expect_gte(length(unique(d$reference_basis)), 2L)
    expect_true(all(nchar(d$reference_sha256) == 64L))
    # and it must report uncertainty: these denominators are 4 and 16
    expect_true(all(c("sens_ci95_lower", "sens_ci95_upper") %in% names(d)))
    ok <- !is.na(d$sensitivity)
    expect_true(all(d$sens_ci95_lower[ok] <= d$sensitivity[ok]))
    expect_true(all(d$sens_ci95_upper[ok] >= d$sensitivity[ok]))
  }
})

test_that("the published sensitivity is unchanged by the freeze", {
  # The point of freezing was reproducibility, NOT a new result.
  p <- file.path(cliff_repo_root(), "data", "classifier_validation_external.csv")
  skip_if_not(file.exists(p), "artifact not present")
  d <- utils::read.csv(p, stringsAsFactors = FALSE)
  u <- d[d$subspec == "URPS", , drop = FALSE]
  expect_equal(nrow(u), 1L)
  expect_equal(as.integer(u$n), 415L)
  expect_equal(as.numeric(u$sensitivity), 0.25)
})
