#!/usr/bin/env Rscript
# Regenerate SHA256SUMS over every frozen input in scope.
#
# SHA256SUMS had no generator. It was written by hand on 2026-07-24 and then
# 21 commits touched data/ without it -- the reconciliation work, the recovered
# generators, the feminization rebuild. By 2026-08-15, 21 of its 78 entries no
# longer matched and 23 in-scope files were not listed at all, so the integrity
# boundary PROVENANCE.md describes was not actually holding.
#
# Run this ONLY when the artifacts have deliberately changed and the change has
# been reviewed. Re-hashing is how a drifted input gets blessed, so doing it
# reflexively defeats the whole mechanism. `verify_hashes.R` is the read-only
# check; this is the write.
#
#   Rscript scripts/ci/update_hashes.R           # show what would change
#   Rscript scripts/ci/update_hashes.R --apply   # write SHA256SUMS

args  <- commandArgs(trailingOnly = TRUE)
apply <- "--apply" %in% args
root  <- Sys.getenv("CLIFF_ROOT", ".")
setwd(root)

if (!requireNamespace("digest", quietly = TRUE)) {
  cat("ERROR: the 'digest' package is required\n"); quit(status = 1)
}

# Kept identical to verify_hashes.R on purpose; if these drift apart the audit
# stops meaning what it says.
scope_dirs <- c("data", "data-raw", "inst/extdata")
scope_ext  <- "\\.(csv|tsv|rds|parquet|xlsx|json)$"

files <- character(0)
for (d in scope_dirs) {
  if (!dir.exists(d)) next
  files <- c(files, list.files(d, pattern = scope_ext, recursive = TRUE,
                               full.names = TRUE, ignore.case = TRUE))
}
files <- sort(sub("^\\./", "", files))

old <- character(0)
if (file.exists("SHA256SUMS")) {
  raw <- readLines("SHA256SUMS", warn = FALSE)
  raw <- raw[nzchar(trimws(raw))]
  m <- regmatches(raw, regexec("^([0-9a-fA-F]{64})\\s+\\*?(.+)$", raw))
  keep <- vapply(m, length, 0L) == 3L
  old <- setNames(tolower(vapply(m[keep], `[`, "", 2)), vapply(m[keep], `[`, "", 3))
}

hashes <- vapply(files, function(f) digest::digest(f, algo = "sha256", file = TRUE), "")

added   <- setdiff(files, names(old))
removed <- setdiff(names(old), files)
common  <- intersect(files, names(old))
changed <- common[unname(hashes[common]) != unname(old[common])]

cat("== SHA256SUMS regeneration ==\n")
cat("  in scope :", length(files), "\n")
cat("  unchanged:", length(common) - length(changed), "\n")
cat("  CHANGED  :", length(changed), "\n")
cat("  ADDED    :", length(added), "\n")
cat("  REMOVED  :", length(removed), "\n\n")

if (length(changed)) { cat("-- changed --\n"); for (p in changed) cat("  ~", p, "\n") }
if (length(added))   { cat("-- added --\n");   for (p in added)   cat("  +", p, "\n") }
if (length(removed)) { cat("-- removed --\n"); for (p in removed) cat("  -", p, "\n") }

if (!apply) { cat("\nDRY RUN. Pass --apply to write SHA256SUMS.\n"); quit(status = 0) }

writeLines(sprintf("%s  %s", unname(hashes), files), "SHA256SUMS")
cat("\nwrote SHA256SUMS (", length(files), "entries )\n")
