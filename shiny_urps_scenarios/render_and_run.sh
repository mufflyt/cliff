#!/usr/bin/env bash
# ============================================================================
# Render the manuscript AND the Shiny app together, in lockstep.
#
# Starting the app or rebuilding the manuscript must ALWAYS do both, so the
# paper a reader clicks through to can never drift from the numbers the app
# shows. This is the ONE entry point for either action. By default it also
# pushes the freshly rendered app + manuscript to shinyapps.io, so the hosted
# version never lags behind a local re-render.
#
#   bash render_and_run.sh              # render BOTH, update shinyapps.io, then serve locally
#   bash render_and_run.sh --no-deploy  # render BOTH, serve locally, do NOT touch shinyapps.io
#   bash render_and_run.sh --no-serve   # render BOTH, update shinyapps.io, do NOT launch local
#   bash render_and_run.sh --no-deploy --no-serve   # render + bundle only
#   RENDER_PORT=8080 bash render_and_run.sh
#   SHINYAPPS_ACCOUNT=mufflyt SHINYAPPS_APPNAME=urps-workforce-explorer bash render_and_run.sh
#   DEPLOY_SHINYAPPS=0 bash render_and_run.sh          # env equivalent of --no-deploy
#
# Steps:
#   1. Full render of manuscript_WORKFORCE_CLIFF.Rmd -> Word (from current data + code).
#   2. Refresh the app's bundled reading copy (www/*.docx + a self-contained *.html).
#   3. Consistency gate: the app's canonical numbers MUST appear in the fresh paper.
#   4. Deploy the updated app + bundled manuscript to shinyapps.io (unless disabled).
#   5. Launch the local Shiny app (which runs its own validate_model() gate on startup).
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
MS_RMD="$REPO/manuscript/manuscript_WORKFORCE_CLIFF.Rmd"
MS_DOCX="$REPO/manuscript/manuscript_WORKFORCE_CLIFF.docx"
WWW="$HERE/www"
PORT="${RENDER_PORT:-8714}"
TITLE="Estimated Near-Term Balance Between Fellowship Completions and Administratively Classified Clinical-Practice Departures in Gynecologic Oncology and Urogynecology, 2025-2029"

# shinyapps.io target (DEPLOY.R reads these; defaults match the live deployment).
: "${SHINYAPPS_ACCOUNT:=tyler-muffly}"
: "${SHINYAPPS_APPNAME:=urps-workforce-explorer}"
export SHINYAPPS_ACCOUNT SHINYAPPS_APPNAME

SERVE=1
DEPLOY="${DEPLOY_SHINYAPPS:-1}"
for arg in "$@"; do
  case "$arg" in
    --no-serve)  SERVE=0 ;;
    --no-deploy) DEPLOY=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

echo "==> [1/5] Full manuscript render (Word) ..."
Rscript -e 'suppressPackageStartupMessages({library(rmarkdown); library(here)});
            rmarkdown::render(commandArgs(TRUE)[1], output_file = "manuscript_WORKFORCE_CLIFF.docx", quiet = TRUE)' "$MS_RMD"

echo "==> [2/5] Refresh app bundle from the fresh render ..."
mkdir -p "$WWW"
cp "$MS_DOCX" "$WWW/manuscript_WORKFORCE_CLIFF.docx"
pandoc "$MS_DOCX" -f docx -t html --standalone --embed-resources --mathml \
  --metadata title="$TITLE" \
  -o "$WWW/manuscript_WORKFORCE_CLIFF.html"

echo "==> [3/5] Consistency gate: app numbers must appear in the fresh paper ..."
Rscript - "$WWW/manuscript_WORKFORCE_CLIFF.html" "$REPO/cliff/data/graduation_active_transition_projection.csv" <<'RS'
a <- commandArgs(TRUE); html <- readChar(a[1], file.info(a[1])$size)
p <- utils::read.csv(a[2], stringsAsFactors = FALSE)
u <- p[toupper(p$subspecialty_abbrev) == "URPS", , drop = FALSE]
want <- c(round(u$baseline), round(u$projected_2029_immediate), round(u$projected_2029_ramped))
fmt  <- format(want, big.mark = ",", trim = TRUE)
miss <- fmt[!vapply(fmt, function(x) grepl(x, html, fixed = TRUE), logical(1))]
if (length(miss)) stop("Bundled manuscript is missing app numbers: ", paste(miss, collapse = ", "),
                       ". The app and paper would disagree. Re-render before serving.")
cat("    OK: baseline", fmt[1], "/ immediate", fmt[2], "/ transition-adjusted", fmt[3], "present in the paper.\n")
RS

# Keep the bundled data/ CSVs in sync with the repo source of truth before deploying,
# so the hosted app reads the same numbers the gate just checked.
mkdir -p "$HERE/data"
cp "$REPO/cliff/data/graduation_active_transition_projection.csv" "$HERE/data/" 2>/dev/null || true
cp "$REPO/cliff/data/graduation_active_transition.csv" "$HERE/data/" 2>/dev/null || true

if [[ "$DEPLOY" -eq 1 ]]; then
  echo "==> [4/5] Deploy updated app + manuscript to shinyapps.io ($SHINYAPPS_ACCOUNT/$SHINYAPPS_APPNAME) ..."
  if ( cd "$HERE" && Rscript DEPLOY.R ); then
    echo "    shinyapps.io updated: https://$SHINYAPPS_ACCOUNT.shinyapps.io/$SHINYAPPS_APPNAME"
  else
    echo "    WARNING: shinyapps.io deploy FAILED (see log above). The LOCAL app is unaffected and will still start." >&2
  fi
else
  echo "==> [4/5] --no-deploy: shinyapps.io left unchanged."
fi

if [[ "$SERVE" -eq 1 ]]; then
  echo "==> [5/5] Launch local Shiny app on 0.0.0.0:$PORT ..."
  LAN=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
  echo "    Local:  http://127.0.0.1:$PORT"
  echo "    Phone:  http://$LAN:$PORT"
  exec Rscript -e "shiny::runApp('$HERE', host = '0.0.0.0', port = $PORT, launch.browser = FALSE)"
else
  echo "==> [5/5] --no-serve: bundle refreshed, local app not launched."
fi
