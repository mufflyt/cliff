#!/bin/bash
# ---------------------------------------------------------------------------
# SessionStart hook: make R available for Claude Code on the web sessions.
#
# cliff is an renv-managed R package (see .Rprofile -> renv/activate.R,
# renv.lock). This hook installs base R if the image lacks it, then restores
# the pinned package library. The renv restore is best-effort: if the session's
# network policy blocks CRAN, base R is still available for base-R scripts and
# the session start is not aborted.
# ---------------------------------------------------------------------------
set -euo pipefail

# Web (remote) sessions only; local machines already have their own toolchain.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

# 1) Base R (Ubuntu main archive) -------------------------------------------
if ! command -v Rscript >/dev/null 2>&1; then
  echo "[session-start] installing r-base-core ..."
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -qq || true
  $SUDO apt-get install -y --no-install-recommends r-base-core
fi

# 2) Restore the pinned renv library (best-effort) --------------------------
# Rscript run from the repo root sources .Rprofile -> renv/activate.R, which
# bootstraps renv before restore(). Cached in the container image afterwards,
# so subsequent starts are fast.
if command -v Rscript >/dev/null 2>&1 && [ -f renv.lock ]; then
  echo "[session-start] restoring R packages via renv (this can take a while on first run) ..."
  Rscript -e 'tryCatch(renv::restore(prompt = FALSE), error = function(e) message("renv::restore failed: ", conditionMessage(e)))' \
    || echo "[session-start] renv::restore skipped (CRAN unreachable under this network policy); base R is available."
fi

echo "[session-start] R $(Rscript --vanilla -e 'cat(as.character(getRversion()))' 2>/dev/null || echo '?') ready."
