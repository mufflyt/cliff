#!/usr/bin/env Rscript
# Canonical SSOT regeneration.
#
# PROVENANCE.md names data/workforce_projections_consolidated.csv the single
# source of truth and scripts/rebuild_ssot_revised.R its canonical producer.
# That is currently a documentation claim. This makes it an executable one:
# run the producer and require the result to equal what is committed.
#
# If this fails, one of three things is true, and all of them matter:
#   - the committed SSOT was hand-edited,
#   - the producer changed without the artifact being regenerated,
#   - the producer is not deterministic.
#
# The producer writes to here::here("data", ...) in place, so the committed file
# is copied aside and copied back. It is NOT restored with `git checkout --`:
# a mutation-test script once did that and destroyed uncommitted work in the
# same run.
#
#   Rscript scripts/ci/regenerate_ssot.R

root <- Sys.getenv("CLIFF_ROOT", ".")
setwd(root)

target <- file.path("data", "workforce_projections_consolidated.csv")
gen    <- file.path("scripts", "rebuild_ssot_revised.R")

if (!file.exists(target)) { cat("no committed SSOT at", target, "\n"); quit(status = 1) }
if (!file.exists(gen))    { cat("no producer at", gen, "\n");          quit(status = 1) }

backup <- tempfile(fileext = ".csv")
file.copy(target, backup, overwrite = TRUE)

restore <- function() {
  if (file.exists(backup)) file.copy(backup, target, overwrite = TRUE)
}
on.exit(restore(), add = TRUE)

cat("== regenerating the SSOT ==\n")
cat("  producer :", gen, "\n")
cat("  target   :", target, "\n\n")

ok <- tryCatch({
  # A fresh environment: the producer must not depend on anything this script
  # happens to have loaded.
  sys.source(gen, envir = new.env(parent = globalenv()))
  TRUE
}, error = function(e) {
  cat("PRODUCER FAILED:", conditionMessage(e), "\n"); FALSE
})
if (!ok) quit(status = 1)

committed <- readLines(backup, warn = FALSE)
regened   <- readLines(target, warn = FALSE)

if (identical(committed, regened)) {
  cat("\n== SSOT reproduces byte-for-byte ==\n")
  quit(status = 0)
}

# Not identical. Distinguish a formatting difference from a numeric one, since
# they call for very different responses.
cat("\n== SSOT DIFFERS FROM ITS PRODUCER ==\n")
cat("  committed lines:", length(committed), "\n")
cat("  regenerated    :", length(regened), "\n\n")

n <- max(length(committed), length(regened))
shown <- 0L
for (i in seq_len(n)) {
  a <- if (i <= length(committed)) committed[i] else "<absent>"
  b <- if (i <= length(regened))   regened[i]   else "<absent>"
  if (!identical(a, b)) {
    shown <- shown + 1L
    if (shown > 6L) { cat("  ... further differences suppressed\n"); break }
    cat(sprintf("  line %d\n    committed: %s\n    regenerated: %s\n", i,
                substr(a, 1, 160), substr(b, 1, 160)))
  }
}

cat("\nThe committed SSOT is not what its canonical producer emits. Either\n",
    "regenerate and commit the artifact, or fix the producer -- do not\n",
    "hand-edit the CSV, which is how the two drifted apart before.\n", sep = "")
quit(status = 1)
