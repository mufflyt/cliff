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

# Which wc_path() keys resolve OUTSIDE the repository?
#
# docs/PIPELINE.md's Requires column is derived from explicit markers
# (CLIFF_ISOCHRONES_ROOT, the v3.0.0 parquet, DuckDB). It cannot see a
# dependency reached through wc_path(), because that indirection resolves via
# config/cliff_paths.yml -- where every single path is an ABSOLUTE path on one
# developer's machine:
#
#   cohort_csv     /Users/<dev>/isochrones/manuscript/tables/...
#   signals_duckdb /Volumes/<external drive>/DuckDB/...
#   access_surface /Users/<dev>/simulation/dpmm_outputs/...
#
# Six generators were therefore classified clean_checkout and "worked" only on
# the machine where those files happen to exist. In CI they failed reading a
# path that cannot exist. Resolve the indirection here so the classification
# reflects what a generator actually needs.
external_path_keys <- function() {
  cfg_path <- file.path("config", "cliff_paths.yml")
  if (!file.exists(cfg_path)) return(list())
  ln <- readLines(cfg_path, warn = FALSE)
  keys <- list(); cur <- NA_character_
  for (l in ln) {
    k <- regmatches(l, regexec("^([A-Za-z][A-Za-z0-9_.]*):\\s*$", l))[[1]]
    if (length(k) == 2L) { cur <- k[2]; next }
    pth <- regmatches(l, regexec("^\\s+path:\\s*(.+?)\\s*$", l))[[1]]
    if (length(pth) == 2L && !is.na(cur)) {
      v <- gsub('^["\']|["\']$', "", pth[2])
      # Outside the repo if it is absolute, home-relative, or resolved through a
      # ${ROOT} variable. The ${...} form matters: config paths were converted
      # from absolute to root-relative, and a check for "/" alone would silently
      # reclassify every external input as clean_checkout again.
      if (grepl("^(/|~|\\$\\{)", v)) keys[[cur]] <- v
    }
  }
  keys
}

EXTERNAL_KEYS <- external_path_keys()

# What does an external path actually require?
external_class <- function(path) {
  if (grepl("\\.duckdb$", path, ignore.case = TRUE))          return("credentialed")
  if (grepl("^/Volumes/|EXTERNAL_MEDIA", path))                 return("credentialed")
  if (grepl("/isochrones/|ISOCHRONES_ROOT", path))              return("upstream_repo")
  "frozen_snapshot"
}

# R/ defines constants straight from wc_path(), e.g.
#   WC_COHORT_CSV <- wc_path("cohort_csv")
# and accessor functions read those constants. A generator can therefore reach
# an external path three ways, and only the first is a literal wc_path() call:
#   wc_path("cohort_csv")   |   WC_COHORT_CSV   |   wc_load_cohort()
# All seven generators that failed in CI used one of the latter two.
constant_key_map <- function() {
  m <- list()
  for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) {
    for (l in readLines(f, warn = FALSE)) {
      g <- regmatches(l, regexec('^([A-Z][A-Z0-9_]*)\\s*<-\\s*wc_path\\(\\s*["\']([^"\']+)["\']', l))[[1]]
      if (length(g) == 3L) m[[g[2]]] <- g[3]
    }
  }
  m
}
CONST_KEYS <- constant_key_map()

# Functions whose body reads one of those constants, mapped to the key they pull.
ACCESSOR_KEYS <- list(wc_load_cohort = "cohort_csv")

# Keys a generator reaches for, by any of the three routes.
generator_external_class <- function(generator) {
  if (!file.exists(generator)) return(NA_character_)
  txt <- paste(readLines(generator, warn = FALSE), collapse = "\n")
  hit <- NA_character_
  bump <- function(hit, cls) {
    rank <- c(credentialed = 3L, upstream_repo = 2L, frozen_snapshot = 1L)
    if (is.na(hit) || rank[[cls]] > rank[[hit]]) cls else hit
  }

  for (cn in names(CONST_KEYS)) {
    k <- CONST_KEYS[[cn]]
    if (!is.null(EXTERNAL_KEYS[[k]]) && grepl(paste0("\\b", cn, "\\b"), txt))
      hit <- bump(hit, external_class(EXTERNAL_KEYS[[k]]))
  }
  for (fn in names(ACCESSOR_KEYS)) {
    k <- ACCESSOR_KEYS[[fn]]
    if (!is.null(EXTERNAL_KEYS[[k]]) && grepl(paste0("\\b", fn, "\\s*\\("), txt))
      hit <- bump(hit, external_class(EXTERNAL_KEYS[[k]]))
  }
  for (k in names(EXTERNAL_KEYS)) {
    if (grepl(sprintf('wc_path\\(\\s*["\']%s["\']', k), txt)) {
      hit <- bump(hit, external_class(EXTERNAL_KEYS[[k]]))
    }
  }
  hit
}

classify <- function(req, generator) {
  # Archival material is kept for the record, not for reproduction. Re-running
  # it would rewrite artifacts nothing current consumes.
  if (grepl("(^|/)archived?/", generator))  return("archival_only")
  r <- tolower(req)
  if (grepl("duckdb", r))               return("credentialed")
  if (grepl("isochrones", r))           return("upstream_repo")
  if (grepl("parquet|snapshot", r))     return("frozen_snapshot")
  if (grepl("mufflyaccess", r))         return("contract_pkg")
  # Nothing in the Requires column, but it may still reach outside the repo
  # through wc_path().
  ext <- generator_external_class(generator)
  if (!is.na(ext)) return(ext)
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
