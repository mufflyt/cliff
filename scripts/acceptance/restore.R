# Acceptance gate: restore the lockfile into a brand-new library under a
# target R. Driven by scripts/acceptance/run_gate.sh, which sets GATE (work
# directory), REPO, CLIFF_GATE_R and the compiler isolation.
GATE <- Sys.getenv("GATE")
if (!nzchar(GATE))
  stop("ABORT: GATE is unset; the library path would resolve to '/deplib'.", call. = FALSE)
lib  <- file.path(GATE, "deplib")
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(lib)

cat("R:        ", R.version.string, "\n")
cat("lib:      ", lib, "\n")
cat("lib empty:", length(list.files(lib)) == 0L, "\n")

# The 2026-08-15 abort: R was replaced underneath a 43-minute restore (an
# Installer.app run) and nothing noticed until the very end. Fail immediately
# rather than producing packages linked against the wrong libR.
want <- Sys.getenv("CLIFF_GATE_R", "4.5.3")
if (!grepl(want, R.version.string, fixed = TRUE))
  stop("ABORT: expected R ", want, ", got ", R.version.string, call. = FALSE)

cat("\nisolation in effect:\n")
for (v in c("R_MAKEVARS_USER", "RENV_CONFIG_CACHE_ENABLED",
            "RENV_CONFIG_INSTALL_SHORTCUTS"))
  cat(sprintf("  %-30s = %s\n", v, Sys.getenv(v, "<unset>")))
cat(sprintf("  %-30s = %s\n", "user Makevars exists",
            file.exists(Sys.getenv("R_MAKEVARS_USER", "/nonexistent"))))
cat("\n")

# renv must exist in this fresh library before it can restore into it.
if (!requireNamespace("renv", quietly = TRUE)) {
  cat("installing renv into the fresh library...\n")
  install.packages("renv", lib = lib, repos = "https://cloud.r-project.org", quiet = TRUE)
}
cat("renv:", as.character(packageVersion("renv", lib.loc = lib)), "\n\n")

repo <- Sys.getenv("REPO")
if (!nzchar(repo))
  stop("ABORT: REPO is unset; run this via scripts/acceptance/run_gate.sh.", call. = FALSE)
setwd(repo)
Sys.setenv(RENV_PATHS_LIBRARY = lib)
Sys.setenv(RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE")

# duckdb is 1802 .cpp files. Under renv's parallel installer it is killed by
# the per-worker timeout ("worker process timed out") after ~1 hour, twice now.
# Build it here, in the main process, where no worker timeout applies. restore()
# then sees the pinned version already satisfied and skips it.
cat("=== pre-building duckdb (MAKEFLAGS=", Sys.getenv("MAKEFLAGS"), ") ===\n", sep = "")
if (!"duckdb" %in% rownames(installed.packages(lib.loc = lib))) {
  t0 <- proc.time()[["elapsed"]]
  ok <- tryCatch({ renv::install("duckdb@1.5.4.3", library = lib, prompt = FALSE); TRUE },
                 error = function(e) { cat("  duckdb pre-build FAILED: ", conditionMessage(e), "\n"); FALSE })
  cat(sprintf("  duckdb pre-build: %s in %.1f min\n", if (ok) "OK" else "FAILED",
              (proc.time()[["elapsed"]] - t0) / 60))
} else {
  cat("  already present\n")
}

cat("\n=== renv::restore() ===\n")
renv::restore(library = lib, prompt = FALSE, clean = FALSE)

cat("\n=== restored ===\n")
ip <- installed.packages(lib.loc = lib)
cat("packages in the fresh library:", nrow(ip), "\n")

# GenSA was the reason issue #27 stayed open: its pin was believed not to
# compile on R >= 4.5. Under 4.5.3 it installs as a plain binary. Reported
# every run so a regression is visible rather than inferred.
cat("\n=== GenSA (issue #27) ===\n")
if ("GenSA" %in% rownames(ip)) {
  d <- packageDescription("GenSA", lib.loc = lib)
  cat("  Version:", d$Version, "\n")
  cat("  Built:  ", d$Built, "\n")
  cat("  loads:  ", requireNamespace("GenSA", quietly = TRUE), "\n")
} else {
  cat("  NOT INSTALLED\n")
}
