#!/usr/bin/env Rscript
# R CMD check NOTE fingerprinting.
#
# cliff deliberately does not chase 0/0/0. It carries known NOTEs (NSE globals,
# issue #35; installed size, issue #36) that are tracked rather than suppressed.
# But "NOTEs are allowed" and "any NOTE is allowed" are different policies, and
# only the first is useful: under the second, a genuinely new problem arrives
# silently in a job that was already yellow.
#
# Each NOTE is reduced to a stable fingerprint -- its check name plus a
# normalised body with sizes, counts, paths, versions and timings stripped --
# and compared against a committed baseline. A NEW fingerprint fails. A
# baseline fingerprint that no longer appears is reported, not failed, since
# fixing something should never break the build.
#
#   Rscript scripts/ci/check_note_fingerprint.R <path/to/00check.log>
#   Rscript scripts/ci/check_note_fingerprint.R <log> --write-baseline

args <- commandArgs(trailingOnly = TRUE)
write_baseline <- "--write-baseline" %in% args
logs <- setdiff(args, "--write-baseline")
if (!length(logs)) { cat("usage: check_note_fingerprint.R <00check.log>\n"); quit(status = 2) }
log_path <- logs[[1]]
if (!file.exists(log_path)) { cat("no such log:", log_path, "\n"); quit(status = 2) }

root <- Sys.getenv("CLIFF_ROOT", ".")
baseline <- file.path(root, "scripts", "ci", "check_notes_baseline.txt")

ln <- readLines(log_path, warn = FALSE)

# Each "* checking X ... NOTE" opens a block that runs to the next "* checking"
# or "* DONE".
starts <- grep("^\\* checking .*\\.\\.\\..*NOTE\\s*$", ln)
bounds <- grep("^\\* (checking|DONE)", ln)

norm <- function(x) {
  x <- paste(x, collapse = " ")
  x <- gsub("\\s+", " ", x)
  x <- gsub("[0-9]+(\\.[0-9]+)?\\s*(Kb|Mb|Gb|bytes|s)\\b", "<size>", x, ignore.case = TRUE)
  x <- gsub("/[^ ]*", "<path>", x)          # absolute/relative paths
  x <- gsub("\\b[0-9]+\\b", "<n>", x)       # counts, line numbers
  trimws(x)
}

fps <- character(0)
labels <- character(0)
for (s in starts) {
  nxt <- bounds[bounds > s]
  e <- if (length(nxt)) min(nxt) - 1L else length(ln)
  name <- sub("^\\* checking ", "", sub("\\.\\.\\..*$", "", ln[s]))
  name <- trimws(name)
  body <- norm(ln[(s + 1L):e])
  # Keep the fingerprint readable rather than hashing it: a diff should tell a
  # human what changed, not just that something did.
  fps    <- c(fps, paste0(name, " :: ", substr(body, 1, 220)))
  labels <- c(labels, name)
}

cat("== R CMD check NOTEs ==\n")
cat("  log  :", log_path, "\n")
cat("  NOTEs:", length(fps), "\n\n")
for (f in fps) cat("  -", f, "\n")

if (write_baseline) {
  writeLines(c(
    "# Known, accepted R CMD check NOTEs, one normalised fingerprint per line.",
    "# A NEW fingerprint fails CI; a disappeared one is only reported.",
    "# Re-approve deliberately:",
    "#   Rscript scripts/ci/check_note_fingerprint.R <log> --write-baseline",
    fps), baseline)
  cat("\nbaseline written ->", baseline, "(", length(fps), "fingerprints )\n")
  quit(status = 0)
}

if (!file.exists(baseline)) {
  cat("\nno baseline at", baseline, "- create one with --write-baseline\n")
  quit(status = 0)
}

known <- readLines(baseline, warn = FALSE)
known <- known[!grepl("^\\s*#", known) & nzchar(trimws(known))]

novel <- setdiff(fps, known)
gone  <- setdiff(known, fps)

if (length(gone)) {
  cat("\n-- no longer present (good; trim the baseline) --\n")
  for (g in gone) cat("  ~", g, "\n")
}

if (length(novel)) {
  cat("\n== NEW R CMD check NOTE ==\n")
  for (n in novel) cat("  +", n, "\n")
  cat("\nA NOTE appeared that is not in the accepted baseline. Fix it, or if it\n",
      "is genuinely acceptable, re-approve it explicitly with --write-baseline\n",
      "so the next new one is still visible.\n", sep = "")
  quit(status = 1)
}

cat("\n== NOTE fingerprints unchanged ==\n")
quit(status = 0)
