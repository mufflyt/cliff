#!/usr/bin/env Rscript
# Dependency-pin drift check.
#
# cliff pins its non-CRAN dependencies in TWO places that nothing kept in
# agreement:
#
#   DESCRIPTION  Remotes:  mufflyt/mufflyaccess@<sha>
#   renv.lock    Packages$mufflyaccess$RemoteSha
#
# On 2026-08-15 they disagreed: DESCRIPTION was pinned eight days behind the
# lockfile. Which one takes effect depends on how the dependency is installed
# (`remotes::install_deps()` reads DESCRIPTION; `renv::restore()` reads the
# lockfile), so CI and a developer's machine could silently run different
# versions of the SSOT package that cliff's numbers are validated against.
#
# Usage:
#   Rscript scripts/ci/check_pins.R              # local: compare the two files
#   Rscript scripts/ci/check_pins.R --upstream   # also report drift vs the
#                                                # remote's default branch
#                                                # (informational; never fails)
#
# Exit 0 clean, 1 on drift between the two pinned files.

args <- commandArgs(trailingOnly = TRUE)
check_upstream <- "--upstream" %in% args
root <- Sys.getenv("CLIFF_ROOT", ".")

fail <- character(0)
note <- character(0)

# ---- DESCRIPTION Remotes ---------------------------------------------------
dcf <- read.dcf(file.path(root, "DESCRIPTION"))
remotes_field <- if ("Remotes" %in% colnames(dcf)) dcf[1, "Remotes"] else ""
remotes <- trimws(strsplit(remotes_field, ",")[[1]])
remotes <- remotes[nzchar(remotes)]

parse_remote <- function(x) {
  # user/repo@ref  ->  list(pkg, user, ref)
  ref <- if (grepl("@", x, fixed = TRUE)) sub(".*@", "", x) else NA_character_
  slug <- sub("@.*", "", x)
  list(pkg = basename(slug), user = dirname(slug), ref = ref, raw = x)
}
desc_pins <- lapply(remotes, parse_remote)
names(desc_pins) <- vapply(desc_pins, `[[`, "", "pkg")

# ---- renv.lock -------------------------------------------------------------
lock_path <- file.path(root, "renv.lock")
lock <- jsonlite::fromJSON(lock_path, simplifyVector = FALSE)
lock_pkgs <- lock$Packages
gh_pkgs <- Filter(function(p) identical(p$Source, "GitHub"), lock_pkgs)

cat("== non-CRAN dependency pins ==\n\n")

all_pkgs <- union(names(desc_pins), names(gh_pkgs))
if (!length(all_pkgs)) cat("  (none)\n")

for (pkg in sort(all_pkgs)) {
  d <- desc_pins[[pkg]]
  l <- gh_pkgs[[pkg]]

  d_ref <- if (is.null(d)) NA_character_ else d$ref
  l_sha <- if (is.null(l)) NA_character_ else l$RemoteSha
  l_ver <- if (is.null(l)) NA_character_ else l$Version

  cat(sprintf("  %s\n", pkg))
  cat(sprintf("    DESCRIPTION Remotes : %s\n",
              if (is.na(d_ref)) "<absent>" else substr(d_ref, 1, 12)))
  cat(sprintf("    renv.lock RemoteSha : %s%s\n",
              if (is.na(l_sha)) "<absent>" else substr(l_sha, 1, 12),
              if (is.na(l_ver)) "" else paste0("  (v", l_ver, ")")))

  if (is.null(d)) {
    fail <- c(fail, sprintf(
      "%s is a GitHub dependency in renv.lock but has no DESCRIPTION Remotes entry", pkg))
  } else if (is.null(l)) {
    fail <- c(fail, sprintf(
      "%s is pinned in DESCRIPTION Remotes but absent from renv.lock", pkg))
  } else if (!is.na(d_ref) && !is.na(l_sha) && !identical(d_ref, l_sha)) {
    # A DESCRIPTION ref that is a branch/tag rather than a SHA is a different
    # (looser) problem; flag it separately rather than as a mismatch.
    if (grepl("^[0-9a-f]{40}$", d_ref)) {
      fail <- c(fail, sprintf(
        "%s: DESCRIPTION pins %s but renv.lock records %s",
        pkg, substr(d_ref, 1, 12), substr(l_sha, 1, 12)))
    } else {
      note <- c(note, sprintf(
        "%s: DESCRIPTION pins the mutable ref '%s'; renv.lock records %s. A ref that moves cannot be reproduced.",
        pkg, d_ref, substr(l_sha, 1, 12)))
    }
  }

  if (check_upstream && !is.null(l) && !is.null(l$RemoteUsername)) {
    url <- sprintf("https://api.github.com/repos/%s/%s/commits/%s",
                   l$RemoteUsername, l$RemoteRepo,
                   if (!is.null(l$RemoteRef)) l$RemoteRef else "HEAD")
    # Unauthenticated GitHub API calls are rate-limited to 60/hour per IP and
    # return 401/403 from shared CI runners. GITHUB_PAT is set by the workflow.
    pat <- Sys.getenv("GITHUB_PAT", Sys.getenv("GITHUB_TOKEN", ""))
    up <- tryCatch({
      con <- if (nzchar(pat)) {
        url(url, headers = c(Authorization = paste("Bearer", pat),
                             "User-Agent" = "cliff-ci"))
      } else {
        url(url, headers = c("User-Agent" = "cliff-ci"))
      }
      on.exit(try(close(con), silent = TRUE), add = TRUE)
      jsonlite::fromJSON(readLines(con, warn = FALSE), simplifyVector = FALSE)
    }, error = function(e) NULL)
    if (!is.null(up$sha)) {
      same <- identical(up$sha, l_sha)
      cat(sprintf("    upstream %-10s : %s%s\n",
                  if (!is.null(l$RemoteRef)) l$RemoteRef else "HEAD",
                  substr(up$sha, 1, 12),
                  if (same) "  (current)" else "  <- lockfile is behind"))
      if (!same)
        note <- c(note, sprintf("%s: lockfile is behind %s (%s)", pkg,
                                l$RemoteRef, substr(up$sha, 1, 12)))
    }
  }
  cat("\n")
}

if (length(note)) {
  cat("-- notes (not failures) --\n")
  for (n in note) cat("  *", n, "\n")
  cat("\n")
}

if (length(fail)) {
  cat("== PIN DRIFT ==\n")
  for (f in fail) cat("  x", f, "\n")
  cat("\nDESCRIPTION and renv.lock must agree: remotes::install_deps() reads the\n",
      "former and renv::restore() reads the latter, so a disagreement means CI\n",
      "and a developer machine can run different code.\n", sep = "")
  quit(status = 1)
}

cat("== pins agree ==\n")
quit(status = 0)
