#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# docs/PIPELINE.md -- which script produces which artifact, generated not written
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# The knowledge this file records is exactly what was missing when cliff was
# extracted from the isochrones monorepo: the extraction carried artifact OUTPUTS
# across without the code that produces them, and for months nothing recorded
# which script owned which CSV. Recovering that map by hand took a full session
# and produced four separate false "this artifact has no generator" conclusions.
#
# So the map is GENERATED. A hand-written one would drift the same way the
# numbers did, and PROVENANCE.md is the proof: its central claim, that no
# committed script regenerates the SSOT, was true when written and is now false.
#
# Guarded by tests/testthat/test-pipeline-map-current.R, which regenerates and
# compares, so a new or renamed generator fails the suite until the map is rebuilt.
#
# Usage: Rscript scripts/build_pipeline_map.R
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
suppressPackageStartupMessages({library(here)})

WRITE_FNS <- "write[._]csv|fwrite|write_delim|write_tsv|write\\.table|saveRDS|write_json"
READ_FNS  <- "read[._]csv|fread|read_delim|read_tsv|read\\.table|readRDS|read_parquet|read_json"

# radix sort = C collation, so the order does not depend on the caller's locale.
# A locale-dependent order makes the guard in test-pipeline-map-current.R flap.
# Scan every directory that can write into data/, not just scripts/. code/ holds
# the legacy pipeline, and it contains a second writer of the SSOT; a map that
# only looked at scripts/ hid that.
# Every directory that contains a writer. Determined by searching, not assumed:
# scripts/ and code/ hold the pipelines, R/ the package, and the Shiny apps,
# analysis/ and benchmark/ each write too. A map that scans a subset hides
# writers, which is how an unlocked SSOT writer in code/ went unnoticed.
SRC_DIRS <- c("scripts", "code", "R", "shiny_urps_adequacy", "shiny_urps_scenarios",
              "analysis", "benchmark", "manuscript/R", "demand_lifecourse",
              "augs_application", "data-raw")
scripts <- sort(unlist(lapply(SRC_DIRS, function(d) {
  p <- here::here(d)
  if (dir.exists(p)) list.files(p, pattern = "[.]R$", recursive = TRUE, full.names = TRUE)
  else character(0)
})), method = "radix")
rd <- function(p) paste(readLines(p, warn = FALSE), collapse = "\n")

# Resolve one level of variable indirection: OUT <- here::here("data","x.csv")
# then write.csv(tbl, OUT). Without this, generators that write through a
# variable look like they write nothing.
# Line-scoped: an R write/read call and its filename are on the same line, or on
# the next when the call wraps. Matching across the whole file with a permissive
# span misattributes a later read as a write, which it did on the first attempt.
csv_in_call <- function(lines, fns) {
  out <- character(0)
  csvs_on <- function(i) {
    seg <- paste(lines[i:min(i + 1L, length(lines))], collapse = " ")
    m <- regmatches(seg, gregexpr('"[A-Za-z0-9_./\\-]+\\.csv"', seg, perl = TRUE))[[1]]
    basename(gsub('"', "", m))
  }
  for (i in seq_along(lines)) {
    if (!grepl(sprintf("(%s)\\s*\\(", fns), lines[i], perl = TRUE)) next
    out <- c(out, csvs_on(i))
  }
  # one level of indirection: OUT <- here::here("data","x.csv") ... write.csv(t, OUT)
  for (i in seq_along(lines)) {
    a <- regmatches(lines[i], regexpr('^\\s*[A-Za-z._][A-Za-z0-9._]*\\s*<-[^\\n]*"[A-Za-z0-9_./\\-]+\\.csv"',
                                      lines[i], perl = TRUE))
    if (!length(a)) next
    if (grepl(sprintf("(%s)\\s*\\(", READ_FNS), lines[i], perl = TRUE)) next  # it is a read
    v <- trimws(sub("\\s*<-.*", "", a))
    f <- basename(sub('.*"([A-Za-z0-9_./\\-]+\\.csv)".*', "\\1", a, perl = TRUE))
    if (any(grepl(sprintf("(%s)\\s*\\([^)]{0,120}?(?<![A-Za-z0-9._])%s(?![A-Za-z0-9._])",
                          fns, v), lines, perl = TRUE))) out <- c(out, f)
  }
  unique(out[nzchar(out) & !grepl("[(){}]", out)])
}

rows <- list()
for (s in scripts) {
  txt <- rd(s)
  lns <- readLines(s, warn = FALSE)
  writes <- csv_in_call(lns, WRITE_FNS)
  if (!length(writes)) next
  reads <- setdiff(csv_in_call(lns, READ_FNS), writes)
  needs <- c(
    if (grepl("CLIFF_ISOCHRONES_ROOT", txt)) "isochrones checkout",
    if (grepl("CLIFF_URPS_SNAPSHOT", txt))   "v3.0.0 parquet",
    if (grepl("duckdb|DuckDB", txt))         "DuckDB",
    if (grepl("mufflyaccess::", txt))        "mufflyaccess")
  rows[[length(rows) + 1]] <- list(
    script = sub(paste0("^", here::here(), "/"), "", s),
    writes = sort(writes, method = "radix"), reads = sort(reads, method = "radix"),
    needs = needs)
}

fmt <- function(x, empty = "--") if (!length(x)) empty else paste0("`", x, "`", collapse = "<br>")
lines <- c(
  "# Pipeline map: script to artifact",
  "",
  "**Generated by `scripts/build_pipeline_map.R`. Do not edit by hand.**",
  "Guarded by `tests/testthat/test-pipeline-map-current.R`.",
  "",
  "This repository was extracted from the isochrones monorepo, which carried",
  "artifact outputs across without the code that produces them. This table is the",
  "record of which script owns which artifact, so that gap cannot reopen silently.",
  "",
  "Requirements column: *isochrones checkout* means the script reads monorepo",
  "inputs under `CLIFF_ISOCHRONES_ROOT` (default `~/isochrones`); *v3.0.0 parquet*",
  "means `CLIFF_URPS_SNAPSHOT`; *DuckDB* means the external credentials database.",
  "Scripts with no requirements run from a clean checkout.",
  "",
  sprintf("%d generators writing %d artifacts.",
          length(rows), length(unique(unlist(lapply(rows, `[[`, "writes"))))),
  "",
  paste("Sources scanned:", paste(sprintf("`%s/`", SRC_DIRS), collapse = ", ")),
  "",
  "| Generator | Writes | Reads | Requires |",
  "|---|---|---|---|")
for (r in rows)
  lines <- c(lines, sprintf("| `%s` | %s | %s | %s |",
                            r$script, fmt(r$writes), fmt(r$reads), fmt(r$needs)))

out <- here::here("docs", "PIPELINE.md")
dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
writeLines(lines, out)
cat("wrote docs/PIPELINE.md:", length(rows), "generators\n")
