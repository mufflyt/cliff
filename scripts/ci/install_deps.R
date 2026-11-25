#!/usr/bin/env Rscript
# Install cliff's dependencies without pak.
#
# remotes::install_deps() reads DESCRIPTION Remotes and installs the pinned
# GitHub packages, but it does not reliably hydrate those packages' own CRAN
# Imports before installing them. mysterycall/mysteryroster then fail their
# load test and R CMD check reports the GitHub packages themselves as absent.
# Install each pinned GitHub remote explicitly first -- with its hard
# dependencies -- and only then hydrate cliff's own dependency tree.
#
# Set CLIFF_DEP_MODE=hard to install only Depends/Imports/LinkingTo for cliff;
# the default includes Suggests so the test and documentation tiers run fully.

hard <- identical(Sys.getenv("CLIFF_DEP_MODE"), "hard")
dependencies <- if (hard) c("Depends", "Imports", "LinkingTo") else TRUE

if (!requireNamespace("remotes", quietly = TRUE)) {
  install.packages("remotes")
}

dcf <- read.dcf("DESCRIPTION")
remotes_field <- if ("Remotes" %in% colnames(dcf)) dcf[1, "Remotes"] else ""
specs <- trimws(strsplit(remotes_field, ",", fixed = TRUE)[[1]])
specs <- specs[nzchar(specs)]

hard_deps <- c("Depends", "Imports", "LinkingTo")
for (spec in specs) {
  cat("installing pinned remote:", spec, "\n")
  remotes::install_github(spec, dependencies = hard_deps, upgrade = "never")
  pkg <- sub(".*/([^@/]+)(@.*)?$", "\\1", spec)
  desc <- suppressWarnings(utils::packageDescription(pkg))
  expected_sha <- if (grepl("@", spec, fixed = TRUE)) sub("^.*@", "", spec) else NA_character_
  installed_sha <- if (is.list(desc) && !is.null(desc$RemoteSha)) unname(desc$RemoteSha) else NA_character_
  if (!is.list(desc) || !isTRUE(nzchar(desc$Version)) ||
      (!is.na(expected_sha) && !identical(installed_sha, expected_sha))) {
    stop("failed to install pinned remote ", spec,
         " (installed sha: ", if (is.na(installed_sha)) "<none>" else installed_sha, ")",
         call. = FALSE)
  }
  cat(sprintf("  %s %s RemoteSha=%s\n", pkg, desc$Version, installed_sha))
}

remotes::install_deps(dependencies = dependencies, upgrade = "never")
