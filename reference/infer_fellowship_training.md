# Fellowship Training Inference Module

Infers where physicians completed their OB/GYN fellowship training based
on their first practice location after board certification.

Matches physicians to ACGME-accredited Otolaryngology fellowship
programs using the same multi-phase approach as
`infer_residency_training()`:

1.  **Phase 0:** Ground truth lookup from GOBA/DOX/Healthgrades data in
    DuckDB (if `temporal_db_path` provided).

2.  **Phase 1:** Spatial proximity matching — compares each physician's
    first practice location to program coordinates using Haversine
    distance (km).

3.  **Phase 2:** Temporal NPPES address history — checks addresses
    during fellowship window (cert_year - 2 to cert_year).

## Usage

``` r
infer_fellowship_training(physicians, programs = NULL, temporal_db_path = NULL)
```

## Arguments

- physicians:

  \[data.frame\]: Physician records to infer fellowship training for.
  temporal NPPES DuckDB database for Phase 0 ground truth lookup and
  Phase 2 address history. If `NULL`, those phases are skipped.

- programs:

  Data frame or `NULL`. ACGME fellowship program data from
  [`create_otolaryngology_fellowship_programs`](https://mufflyt.github.io/cliff/reference/create_otolaryngology_fellowship_programs.md).
  If `NULL`, loaded automatically via that function.

- temporal_db_path:

  Character scalar or `NULL`. Path to the

## Value

Data frame with original physician columns plus inferred fellowship
columns: `inferred_fellowship_program`, `fellowship_distance_km`,
`fellowship_inference_method`, `fellowship_confidence`.

## Details

Uses a multi-phase spatial matching algorithm against the ACGME FREIDA
database to approximate training locations when self-reported data is
absent.

## See also

\[create_otolaryngology_fellowship_programs()\],
\[infer_residency_training()\] for the residency equivalent.
