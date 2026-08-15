#!/usr/bin/env Rscript
# Machine-readable reproducibility class for every generator in docs/PIPELINE.md.
#
# The point of gate 57: nothing may simply "not run in CI". Every generator gets
# an explicit class saying WHY, so the set of things CI cannot prove is itself
# reviewable rather than implicit.
#
#   clean_checkout   no external input; CI must run it and compare its artifact
#   frozen_snapshot  needs a committed/pinned snapshot (v3.0.0 parquet)
#   upstream_repo    needs the isochrones checkout (CLIFF_ISOCHRONES_ROOT)
#   credentialed     needs the DuckDB credentials database
#   contract_pkg     needs mufflyaccess installed
#
# A generator with several requirements takes the most restrictive class, since
# that is what actually gates running it.
#
#   Rscript scripts/ci/classify_generators.R            # table + counts
#   Rscript scripts/ci/classify_generators.R --json     # machine-readable
#   Rscript scripts/ci/classify_generators.R --list clean_checkout

args <- commandArgs(trailingOnly = TRUE)
as_json <- "--json" %in% args
want <- if ("--list" %in% args) args[[which(args == "--list") + 1L]] else NA_character_

root <- Sys.getenv("CLIFF_ROOT", ".")
setwd(root)
map <- file.path("docs", "PIPELINE.md")
if (!file.exists(map)) { cat("no", map, "- run scripts/build_pipeline_map.R\n"); quit(status = 1) }

ln <- readLines(map, warn = FALSE)
rows <- grep("^\\|", ln, value = TRUE)
rows <- rows[!grepl("^\\|\\s*-+", rows)]                 # separator
rows <- rows[!grepl("^\\|\\s*Generator\\s*\\|", rows)]   # header

cells <- lapply(rows, function(r) {
  p <- strsplit(sub("^\\|", "", sub("\\|$", "", r)), "\\|")[[1]]
  trimws(p)
})
cells <- Filter(function(x) length(x) >= 4, cells)

classify <- function(req, generator) {
  # Archival material is kept for the record, not for reproduction. Re-running
  # it would rewrite artifacts nothing current consumes.
  if (grepl("(^|/)archived?/", generator))  return("archival_only")
  r <- tolower(req)
  if (grepl("duckdb", r))               return("credentialed")
  if (grepl("isochrones", r))           return("upstream_repo")
  if (grepl("parquet|snapshot", r))     return("frozen_snapshot")
  if (grepl("mufflyaccess", r))         return("contract_pkg")
  "clean_checkout"
}

gen  <- vapply(cells, function(x) gsub("`", "", x[[1]]), "")
wrt  <- vapply(cells, function(x) gsub("`", "", x[[2]]), "")
req  <- vapply(cells, function(x) gsub("`", "", x[[4]]), "")
cls  <- mapply(classify, req, gen, USE.NAMES = FALSE)

keep <- nzchar(gen) & gen != "Generator"
gen <- gen[keep]; wrt <- wrt[keep]; req <- req[keep]; cls <- cls[keep]

if (!is.na(want)) {
  for (g in unique(gen[cls == want])) cat(g, "\n")
  quit(status = 0)
}

if (as_json) {
  esc <- function(x) gsub('"', '\\\\"', x)
  cat("[\n")
  cat(paste0('  {"generator": "', esc(gen), '", "class": "', cls,
             '", "requires": "', esc(req), '"}'), sep = ",\n")
  cat("\n]\n")
  quit(status = 0)
}

tab <- sort(table(cls), decreasing = TRUE)
cat("== generator reproducibility classes ==\n")
cat("  rows in pipeline map:", length(gen), "\n")
cat("  distinct generators :", length(unique(gen)), "\n\n")
for (n in names(tab))
  cat(sprintf("  %-16s %3d rows  %3d generators\n", n, tab[[n]],
              length(unique(gen[cls == n]))))
cat("\nCI can reproduce the clean_checkout class unaided; every other class is\n",
    "an explicit, reviewable reason CI cannot prove that artifact.\n", sep = "")
