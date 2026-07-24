# ABU (urology-pathway) URPS/FPMRS pipeline — re-run runbook

Captures the urology-pathway female-pelvic (Urogynecology & Reconstructive Pelvic
Surgery) physicians the OB/GYN (ABOG-only) FPMRS cohort excludes, and quantifies
their access contribution as a sensitivity arm. All outputs land in `data/abu_urology/`.

All scripts are **re-run safe** (2026-07-14 hardening): they discover the latest
dated input via `list.files()` (no hardcoded dates), resolve the NPPES DuckDB via
`load_paths()` (no hardcoded external-drive path), and pick the newest NPPES gender
table dynamically. Run them in order:

| # | Script | Does | Notes / gotchas fixed |
|---|--------|------|-----------------------|
| 1 | `abu_scraper.r` | scrape ABU public portal → full registry + urogyn subset | paginate `?page=N`; ~12.5k urologists, 370 URPS |
| 2 | `abu_npi.r` | NPI-match the urogyn subset (NPPES 3-tier + urology taxonomy) | ~96% |
| 3 | `abu_npi_recover.r` | recover unmatched | humaniformat (strip credential first); accepts unique name match even if NPPES taxonomy isn't urology (Firoozi = 174400000X) |
| 4 | `abu_urps_finalize.r` | drop retired + attach NPPES gender | needs the NPPES DuckDB (via `load_paths()` → `nppes_db_path`); picks latest `npi_*` gender table |
| 5 | `abu_fetch_addresses.r` | NPPES LOCATION addresses for net-new | ~2 min |
| 6 | `abu_geocode_coverage.r` | Census batch geocode + 5 km isochrone coverage | ~87% geocode |
| 7 | `abu_geocode_recover.r` | recover ungeocoded | tidygeocoder cascade (`drop=FALSE` — earlier bug); arcgis got the rest → 100% |
| 8 | `abog_fpmrs_geocode.r` | geocode the ABOG FPMRS cohort (union target) | NPPES addresses + Census/arcgis; ~9 min |
| 9 | `abu_footprint_expansion.r` | proximity: how many net-new expand the footprint | 78/268 at 5 km |
| 10 | `fpmrs_overlap_sensitivity.r` | access sensitivity (baseline vs augmented) | **30/60-min local** (default `FPMRS_BANDS=30,60`); incremental writes; **120/180 need EC2** (836 MB @180 OOMs a 16 GB box) |

Comparison table: `obgyn_vs_urology_urps_comparison_*.csv` (regenerate ad-hoc).

## EC2 top-up (manuscript-grade) — caveats learned 2026-07-14
The Valhalla AMI (`valhalla-host-*`) is a **bare base** — Valhalla runs via Docker
but the container isn't started and tiles aren't loaded. A launched instance needs:
1. `aws s3 sync s3://tyler-valhalla-tiles/valhalla_tiles/ /data/valhalla_tiles/` **on the instance** (~19.8 GB, intra-region, ~20-30 min).
2. `serve_config.json` from `s3://tyler-valhalla-tiles/serve_config.json`.
3. Start the Valhalla Docker container against those tiles + config.
4. Stage the repo via an **S3 tarball** (NOT rsync/scp — broken Mac→EC2; TRANSPORT RULE).
5. `Rscript scripts/generate_isochrones_standalone.R --cohort_path <coords.csv> --bands 30,60,120,180`.

Inputs staged: `data/abu_urology/abu_uncovered_iso_cohort.csv` (29 coords needing new isochrones),
`abu_fpmrs_temporal_cohort.rds` (per-year membership by cert_year).
`launch_isochrone_generation.sh` / `ec2_deploy_hardened.sh` are the canonical drivers but
default to rsync transfer — prefer the S3-based flow above. Always `terminate-instances` when done.
