#!/usr/bin/env Rscript
# Frozen-evidence integrity: SHA256SUMS verification and coverage audit.
#
# Two directions, because each misses what the other catches:
#
#   VERIFY   every path listed in SHA256SUMS still hashes to its recorded
#            value. Catches silent edits to frozen scientific inputs.
#
#   COVER    every frozen input in scope is actually listed. Catches a new
#            data file appearing with no integrity boundary at all --
#            invisible to verification, because verification only looks at
#            what is already listed.
#
# Coverage cannot be blocking from a standing start: 23 files under data/ are
# currently unlisted. Failing outright would leave a permanently red job, which
# trains people to ignore it. Instead the current gap is recorded in
# scripts/ci/data_hash_debt.txt and CI fails when the gap GROWS. Debt shrinks
# by deleting lines from that file as inputs are hashed.
#
# Usage:
#   Rscript scripts/ci/verify_hashes.R
#   Rscript scripts/ci/verify_hashes.R --write-debt   # re-baseline the gap

args <- commandArgs(trailingOnly = TRUE)
write_debt <- "--write-debt" %in% args
root <- Sys.getenv("CLIFF_ROOT", ".")
setwd(root)

sums_path <- "SHA256SUMS"
debt_path <- file.path("scripts", "ci", "data_hash_debt.txt")

# Scope: what PROVENANCE.md treats as frozen scientific input.
scope_dirs <- c("data", "data-raw", "inst/extdata")
scope_ext  <- "\\.(csv|tsv|rds|parquet|xlsx|json)$"

if (!file.exists(sums_path)) { cat("no SHA256SUMS\n"); quit(status = 1) }

if (!requireNamespace("digest", quietly = TRUE)) {
  cat("ERROR: the 'digest' package is required\n"); quit(status = 1)
}

# ---- parse SHA256SUMS ----------------------------------------------------
raw <- readLines(sums_path, warn = FALSE)
raw <- raw[nzchar(trimws(raw))]
m <- regmatches(raw, regexec("^([0-9a-fA-F]{64})\\s+\\*?(.+)$", raw))
ok_parse <- vapply(m, length, 0L) == 3L

malformed <- raw[!ok_parse]
listed <- data.frame(
  hash = tolower(vapply(m[ok_parse], `[`, "", 2)),
  path =        vapply(m[ok_parse], `[`, "", 3),
  stringsAsFactors = FALSE
)

cat("== SHA256SUMS ==\n")
cat("  entries        :", nrow(listed), "\n")
cat("  malformed lines:", length(malformed), "\n")

fail <- character(0)
for (l in malformed) fail <- c(fail, paste("malformed SHA256SUMS line:", l))

dup <- listed$path[duplicated(listed$path)]
for (p in unique(dup)) fail <- c(fail, paste("duplicate entry in SHA256SUMS:", p))

# ---- verify --------------------------------------------------------------
missing <- mismatch <- unreadable <- character(0)
for (i in seq_len(nrow(listed))) {
  p <- listed$path[i]
  if (!file.exists(p)) { missing <- c(missing, p); next }
  got <- tryCatch(digest::digest(p, algo = "sha256", file = TRUE),
                  error = function(e) NA_character_)
  if (is.na(got)) { unreadable <- c(unreadable, p); next }
  if (!identical(tolower(got), listed$hash[i])) mismatch <- c(mismatch, p)
}

cat("  verified OK    :", nrow(listed) - length(missing) - length(mismatch) - length(unreadable), "\n")
cat("  missing        :", length(missing), "\n")
cat("  MISMATCHED     :", length(mismatch), "\n")
cat("  unreadable     :", length(unreadable), "\n")

for (p in missing)    fail <- c(fail, paste("listed in SHA256SUMS but absent:", p))
for (p in unreadable) fail <- c(fail, paste("listed but unreadable:", p))
for (p in mismatch)   fail <- c(fail, paste("HASH MISMATCH (frozen input changed):", p))

# ---- coverage audit ------------------------------------------------------
present <- character(0)
for (d in scope_dirs) {
  if (!dir.exists(d)) next
  present <- c(present, list.files(d, pattern = scope_ext, recursive = TRUE,
                                   full.names = TRUE, ignore.case = TRUE))
}
present <- sort(sub("^\\./", "", present))
uncovered <- sort(setdiff(present, listed$path))

cat("\n== coverage ==\n")
cat("  in-scope files :", length(present), "\n")
cat("  hashed         :", length(present) - length(uncovered), "\n")
cat("  UNHASHED       :", length(uncovered), "\n")

if (write_debt) {
  writeLines(c(
    "# Frozen inputs that are not yet in SHA256SUMS.",
    "# CI fails when this set GROWS. Shrink it by hashing the file and",
    "# deleting its line here; never add a line to make CI pass.",
    "#",
    "# Regenerate deliberately with:",
    "#   Rscript scripts/ci/verify_hashes.R --write-debt",
    uncovered), debt_path)
  cat("  debt registry written ->", debt_path, "(", length(uncovered), "entries )\n")
} else {
  known <- character(0)
  if (file.exists(debt_path)) {
    known <- readLines(debt_path, warn = FALSE)
    known <- trimws(known[!grepl("^\\s*#", known) & nzchar(trimws(known))])
  }
  novel <- setdiff(uncovered, known)
  fixed <- setdiff(known, uncovered)

  cat("  known debt     :", length(known), "\n")
  cat("  NEW unhashed   :", length(novel), "\n")
  if (length(fixed))
    cat("  newly hashed   :", length(fixed), " (shrink the registry)\n")

  for (p in novel)
    fail <- c(fail, paste("new frozen input with no hash coverage:", p))
}

# ---- report --------------------------------------------------------------
if (length(fail)) {
  cat("\n== FAILURES ==\n")
  for (f in fail) cat("  x", f, "\n")
  quit(status = 1)
}
cat("\n== frozen evidence intact ==\n")
quit(status = 0)
