#!/usr/bin/env Rscript
# setup_renv.R — create the definitive renv.lock IN THIS repo's clean environment.
# The DESCRIPTION already declares the dependencies; this snapshots pinned versions.
#
#   Rscript setup_renv.R
#
# Do NOT run this in a polluted/shared library — the whole point is a lock that
# matches the versions that actually produce the manuscript numbers.
if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
renv::init(bare = TRUE, restart = FALSE)   # sets up renv/ + activates the project
renv::install()                            # install DESCRIPTION Imports into the project lib
renv::snapshot(prompt = FALSE)             # write renv.lock pinned to those versions
cat("\nrenv.lock written. Commit it. Rebuild elsewhere with: renv::restore()\n")
