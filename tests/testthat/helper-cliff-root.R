# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Anchor here() to THIS project, and say plainly when the repository is absent.
#
# Most of this suite reaches repository material through here::here(): manuscript
# sources, scripts/, data/, config/. That works under devtools::test(), where the
# working directory is inside the checkout, and silently misfires elsewhere.
#
# Under R CMD check the tests run from cliff.Rcheck/tests/testthat, which on this
# machine sits below /Users/tylermuffly. here() walks up, finds a stray
# /Users/tylermuffly/.here left over from 2020, and anchors the whole suite at
# HOME. Every repository path then resolves to /Users/tylermuffly/<something>,
# which does not exist: 93 of the ~100 distinct failures were a single
# "cannot open the connection" caused by that one marker file.
#
# here::i_am() is the sanctioned fix. It states where this file sits relative to
# the project root, so here() anchors from the file rather than from whatever
# marker happens to be nearest the working directory. That makes the source-tree
# runs immune to stray .here files anywhere above the checkout.
suppressWarnings(try(
  here::i_am("tests/testthat/helper-cliff-root.R"),
  silent = TRUE
))

# Is the SOURCE TREE available, as opposed to just an installed package?
#
# A built tarball contains R/, man/, tests/, data/ and inst/, but not scripts/,
# manuscript/ or code/. Tests that read those are repository integration tests and
# genuinely cannot run against an installed package; they are not failing, they
# are inapplicable. Distinguish the two rather than reporting inapplicable as
# broken.
cliff_repo_root <- function() {
  d <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  for (i in 1:10) {
    if (all(file.exists(file.path(d, c("DESCRIPTION", "scripts", "manuscript"))))) {
      desc <- tryCatch(read.dcf(file.path(d, "DESCRIPTION"))[1, "Package"],
                       error = function(e) NA_character_)
      if (identical(unname(desc), "cliff")) return(d)
    }
    p <- dirname(d)
    if (identical(p, d)) break
    d <- p
  }
  NA_character_
}

cliff_has_repo <- function() !is.na(cliff_repo_root())

#' Skip a test that needs the repository source tree, not just the package.
skip_if_no_repo <- function() {
  testthat::skip_if_not(
    cliff_has_repo(),
    "needs the repository source tree (scripts/, manuscript/); not present in an installed package"
  )
}
