#!/usr/bin/env bash
# ==============================================================================
# download_enrichment_inputs.sh
#
# Fetch the two LARGE public datasets the roster-enrichment scripts need, so they
# never again live only in an ephemeral session scratchpad. Both are public and
# re-downloadable; neither is committed to the repo (too big — see .gitignore).
#
# Outputs (default DEST = data/enrichment_inputs/):
#   hpsa_shp/HPSA_CMPPC_SHP_DET_CUR_VX.shp   (+ sidecars)  -> enrich_rosters_hpsa_point_in_polygon
#   medicare_prov_svc_2024.csv                             -> enrich_rosters_medicare_procedures_2024_refresh
#
# Usage:  scripts/download_enrichment_inputs.sh [DEST_DIR]
# Override the Medicare URL if CMS changes it: MEDICARE_2024_URL=... scripts/download_enrichment_inputs.sh
# ==============================================================================
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # repo root
DEST="${1:-data/enrichment_inputs}"
mkdir -p "$DEST"

# ---- 1. HRSA primary-care HPSA polygons (stable direct URL, ~272 MB) ----------
# Complete Modeled Primary Care HPSA (current); ~25,480 polygons.
# Consumed by scripts/enrich_rosters_hpsa_point_in_polygon_2026-07-23.R
HPSA_URL="https://data.hrsa.gov/DataDownload/DD_Files/HPSA_CMPPC_SHP.zip"
HPSA_SHP="$DEST/hpsa_shp/HPSA_CMPPC_SHP_DET_CUR_VX.shp"
if [ -f "$HPSA_SHP" ]; then
  echo "[hpsa] already present: $HPSA_SHP"
else
  echo "[hpsa] downloading $HPSA_URL ..."
  curl -fL --retry 3 -o "$DEST/HPSA_CMPPC_SHP.zip" "$HPSA_URL" \
    && mkdir -p "$DEST/hpsa_shp" \
    && unzip -o "$DEST/HPSA_CMPPC_SHP.zip" -d "$DEST/hpsa_shp" >/dev/null \
    && rm -f "$DEST/HPSA_CMPPC_SHP.zip" \
    && echo "[hpsa] OK -> $DEST/hpsa_shp/" \
    || echo "[hpsa] FAILED (fetch $HPSA_URL manually into $DEST/hpsa_shp/)"
fi

# ---- 2. CMS Medicare Physician & Other Practitioners, by Provider and Service --
# CY2024 Public Use File, released 2026-05. File: PHY_R26_P05_V10_D24_Prov_Svc.csv
# (~3.25 GB). Consumed by enrich_rosters_medicare_procedures_2024_refresh.R.
# Source (dataset landing page; grab the CSV "Download" link — CMS serves the file
# from a per-release path that changes each vintage, so it is not hard-coded here):
#   https://data.cms.gov/provider-summary-by-type-of-service/medicare-physician-other-practitioners/medicare-physician-other-practitioners-by-provider-and-service
# The CMS metastore API also exposes the current distribution URL:
#   https://data.cms.gov/data-api/v1/dataset-search?... (query "by Provider and Service")
MED_CSV="$DEST/medicare_prov_svc_2024.csv"
MED_URL="${MEDICARE_2024_URL:-}"
if [ -f "$MED_CSV" ]; then
  echo "[medicare] already present: $MED_CSV"
elif [ -n "$MED_URL" ]; then
  echo "[medicare] downloading (override URL) ..."
  curl -fL --retry 3 -o "$MED_CSV" "$MED_URL" && echo "[medicare] OK -> $MED_CSV" || echo "[medicare] FAILED"
else
  cat <<MSG
[medicare] NOT auto-downloaded (no stable per-vintage URL).
  1) Open the CMS dataset page:
     https://data.cms.gov/provider-summary-by-type-of-service/medicare-physician-other-practitioners/medicare-physician-other-practitioners-by-provider-and-service
  2) Select the CY2024 release and copy the CSV download link, then:
     MEDICARE_2024_URL="<link>" scripts/download_enrichment_inputs.sh "$DEST"
  Expected file: PHY_R26_P05_V10_D24_Prov_Svc.csv (~3.25 GB) -> saved as $MED_CSV
MSG
fi

echo "=== done. DEST=$DEST ==="
ls -lh "$DEST" 2>/dev/null | sed 's/^/  /'
