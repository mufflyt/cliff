#!/usr/bin/env Rscript
# Gate 43/44: determinism and RNG discipline.
#
# Two independent R sessions, identical inputs and seeds, must produce identical
# output. Running twice inside ONE session would not prove this: state left
# behind by the first run -- a cached config, a warmed .Random.seed, an attached
# namespace -- is exactly what makes a result reproducible in place and not
# reproducible anywhere else.
#
# Three things are checked:
#
#   SSOT           the canonical producer, run twice, must emit identical bytes.
#   ENGINE SEED    wc_project_micro(seed = k) must give identical draws in two
#                  fresh sessions.
#   RNG HYGIENE    the engine takes seed = NULL so a caller can own the stream.
#                  A caller's unrelated RNG activity before the call must not
#                  change a SEEDED result -- if it does, the seed is not
#                  actually controlling the draws.
#
#   Rscript scripts/ci/check_determinism.R

root <- Sys.getenv("CLIFF_ROOT", ".")
setwd(root)

RS <- file.path(R.home("bin"), "Rscript")
run <- function(code) {
  f <- tempfile(fileext = ".R"); on.exit(unlink(f), add = TRUE)
  writeLines(code, f)
  out <- suppressWarnings(system2(RS, c("--no-init-file", shQuote(f)),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status"); if (is.null(st)) st <- 0L
  list(out = out, status = st)
}

fail <- character(0)

# ---- 1. the engine, seeded, in two fresh sessions --------------------------
cat("== engine determinism (two independent sessions) ==\n")
engine_code <- '
suppressMessages(library(cliff))
L  <- c("<45","45-49","50-54","55-59","60-64","65-69","70+")
hz <- setNames(c(0.004,0.008,0.015,0.03,0.07,0.14,0.28), L)
pop <- c(34L,44L,45L,50L,60L,65L,70L,71L,80L)
m <- cliff::wc_project_micro(pop, entrants = 16, hz = hz, horizon = 4L,
                             n_sims = 200L, seed = 99L, stochastic_entry = TRUE)
cat(sprintf("%.10f|%.10f|%s\\n", m$active_2029, m$departures_4yr,
            paste(m$active_draws, collapse = ",")))
'
a <- run(engine_code); b <- run(engine_code)
if (a$status != 0L || b$status != 0L) {
  fail <- c(fail, "engine determinism: a session failed to run")
  cat("  session error:\n"); cat(paste0("    ", utils::tail(a$out, 5), collapse = "\n"), "\n")
} else {
  ka <- utils::tail(a$out, 1); kb <- utils::tail(b$out, 1)
  same <- identical(ka, kb)
  cat("  identical across sessions:", same, "\n")
  if (!same) fail <- c(fail, "wc_project_micro(seed=99) differs between sessions")
}

# ---- 2. a caller's RNG activity must not change a seeded result -----------
cat("\n== RNG hygiene (caller's stream must not leak in) ==\n")
polluted <- sub("suppressMessages\\(library\\(cliff\\)\\)",
                "suppressMessages(library(cliff))\nset.seed(4242); invisible(runif(1000)); invisible(rnorm(50))",
                engine_code)
c3 <- run(polluted)
if (c3$status != 0L) {
  fail <- c(fail, "RNG hygiene: session failed to run")
} else {
  same <- identical(utils::tail(a$out, 1), utils::tail(c3$out, 1))
  cat("  unaffected by unrelated caller RNG:", same, "\n")
  if (!same)
    fail <- c(fail, paste("a seeded projection changed when the caller consumed RNG first;",
                          "seed does not fully control the draws"))
}

# ---- 3. the SSOT producer, twice --------------------------------------------
cat("\n== SSOT producer determinism ==\n")
target <- file.path("data", "workforce_projections_consolidated.csv")
if (!file.exists(target)) {
  cat("  (no committed SSOT; skipping)\n")
} else {
  backup <- tempfile(fileext = ".csv")
  file.copy(target, backup, overwrite = TRUE)
  on.exit(file.copy(backup, target, overwrite = TRUE), add = TRUE)

  gen_code <- 'sys.source("scripts/rebuild_ssot_revised.R", envir = new.env(parent = globalenv()))'
  r1 <- run(gen_code); h1 <- if (file.exists(target)) tools::md5sum(target) else NA
  r2 <- run(gen_code); h2 <- if (file.exists(target)) tools::md5sum(target) else NA

  if (r1$status != 0L || r2$status != 0L) {
    cat("  producer failed to run; skipping comparison\n")
  } else {
    same <- identical(unname(h1), unname(h2))
    cat("  identical across runs:", same, "\n")
    if (!same) fail <- c(fail, "rebuild_ssot_revised.R is not deterministic")
  }
}

if (length(fail)) {
  cat("\n== DETERMINISM FAILURES ==\n")
  for (f in fail) cat("  x", f, "\n")
  quit(status = 1)
}
cat("\n== deterministic ==\n")
quit(status = 0)
