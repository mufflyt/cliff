#!/usr/bin/env Rscript
# Gate 23: source hygiene -- hidden machine assumptions and load-time side effects.
#
# This gate exists because of a concrete failure. config/cliff_paths.yml carried
# eleven absolute paths into one developer's home directory and an external USB
# volume. Nine generators resolved them only on that machine, were classified
# "clean checkout reproducible", passed there, and failed everywhere else. It
# cost a full diagnostic cycle to find. A grep would have caught it on the day it
# was committed.
#
# What is checked, and why each one bites:
#
#   absolute user paths   /Users/<name>, /home/<name>, /Volumes/... anywhere but
#                         the sanctioned `roots:` block of cliff_paths.yml. One
#                         place to declare machine specifics; nowhere else.
#   setwd()               in R/: changes the caller's working directory, so a
#                         library function silently breaks every relative path
#                         its caller was using.
#   install.packages()    in R/: a package must never install software when it
#                         is loaded.
#   quit()/q()            in R/: kills the caller's session, and in a test run
#                         it looks exactly like a pass.
#   .libPaths(...) <-     in R/: repoints the library search path for everything
#                         downstream.
#
# Known exceptions live in scripts/ci/source_hygiene_debt.txt. CI fails when the
# set GROWS, so pre-existing items stay visible without holding the gate red --
# in particular the seven file-scope library() calls, which are a deliberate
# decision, not an oversight.
#
#   Rscript scripts/ci/check_source_hygiene.R
#   Rscript scripts/ci/check_source_hygiene.R --write-debt

args <- commandArgs(trailingOnly = TRUE)
write_debt <- "--write-debt" %in% args
root <- Sys.getenv("CLIFF_ROOT", ".")
setwd(root)

debt_path <- file.path("scripts", "ci", "source_hygiene_debt.txt")

r_files <- list.files("R", pattern = "[.]R$", full.names = TRUE)
scan_files <- c(
  r_files,
  list.files("scripts", pattern = "[.]R$", full.names = TRUE, recursive = TRUE),
  list.files("config", pattern = "[.](yml|yaml)$", full.names = TRUE)
)
scan_files <- scan_files[!grepl("^scripts/ci/", scan_files)]   # this file names the patterns

findings <- character(0)
note <- function(file, line, what) {
  findings <<- c(findings, sprintf("%s:%d: %s", file, line, what))
}

# The one sanctioned place for machine-specific absolute paths.
in_roots_block <- function(lines, i) {
  for (j in seq(i, 1L)) {
    if (grepl("^roots:\\s*$", lines[j])) return(TRUE)
    if (grepl("^[A-Za-z]", lines[j]) && !grepl("^roots:", lines[j])) return(FALSE)
  }
  FALSE
}

ABS_PATH <- "(/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+|/Volumes/[A-Za-z0-9._ -]+)"

for (f in scan_files) {
  lines <- readLines(f, warn = FALSE)
  is_yaml <- grepl("[.](yml|yaml)$", f)

  for (i in seq_along(lines)) {
    l <- lines[i]
    # Strip comments AND string literals before the code checks. Without this,
    # a helpful error message -- stop("... install.packages(\"geosphere\")") --
    # is flagged as package code installing software at load time.
    code <- sub("#.*$", "", l)
    code <- gsub('"(\\\\.|[^"\\\\])*"', '""', code)
    code <- gsub("'(\\\\.|[^'\\\\])*'", "''", code)

    if (grepl(ABS_PATH, l) && !grepl("^\\s*#", l)) {
      if (!(is_yaml && in_roots_block(lines, i)))
        note(f, i, paste("absolute machine path:", trimws(l)))
    }

    if (!is_yaml) {
      if (grepl("\\bsetwd\\s*\\(", code) && startsWith(f, "R/"))
        note(f, i, "setwd() in package code")
      if (grepl("\\binstall\\.packages\\s*\\(", code) && startsWith(f, "R/"))
        note(f, i, "install.packages() in package code")
      if (grepl("(^|[^.\\w])q(uit)?\\s*\\(", code) && startsWith(f, "R/") &&
          !grepl("\\b(seq|unique|require|sqrt)\\b", code))
        note(f, i, "quit()/q() in package code")
      if (grepl("\\.libPaths\\s*\\(.*\\)\\s*(<-|=[^=])", code) && startsWith(f, "R/"))
        note(f, i, ".libPaths() mutation in package code")
    }
  }
}

findings <- sort(unique(findings))

cat("== source hygiene ==\n")
cat("  files scanned:", length(scan_files), "\n")
cat("  findings     :", length(findings), "\n\n")
for (f in findings) cat("  !", substr(f, 1, 170), "\n")

if (write_debt) {
  writeLines(c(
    "# Known source-hygiene exceptions.",
    "#",
    "# CI fails when this set GROWS. Shrink it by fixing the source and deleting",
    "# the line; never add a line to make CI pass.",
    "#   Rscript scripts/ci/check_source_hygiene.R --write-debt",
    findings), debt_path)
  cat("\ndebt registry written ->", debt_path, "(", length(findings), "entries )\n")
  quit(status = 0)
}

known <- character(0)
if (file.exists(debt_path)) {
  known <- readLines(debt_path, warn = FALSE)
  known <- trimws(known[!grepl("^\\s*#", known) & nzchar(trimws(known))])
}
novel <- setdiff(findings, known)
fixed <- setdiff(known, findings)

if (length(fixed)) {
  cat("\n-- resolved (trim the debt registry) --\n")
  for (f in fixed) cat("  +", substr(f, 1, 150), "\n")
}
if (length(novel)) {
  cat("\n== NEW SOURCE-HYGIENE FINDINGS ==\n")
  for (f in novel) cat("  x", substr(f, 1, 170), "\n")
  cat("\nA machine-specific path or a load-time side effect was introduced.\n",
      "Absolute paths belong only in the `roots:` block of config/cliff_paths.yml.\n", sep = "")
  quit(status = 1)
}

cat("\n== no new source-hygiene findings ==\n")
quit(status = 0)
