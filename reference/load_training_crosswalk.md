# Load Training Name Crosswalk (Residency or Fellowship)

Reads the pre-built crosswalk CSV that maps HG/DOX/Merged hospital names
to FREIDA ACGME programs. Only exact_verified entries with
approved_for_ground_truth=TRUE are used for high-confidence GT
assignment.

## Usage

``` r
load_training_crosswalk(
  program_type = c("residency", "fellowship"),
  freida_dir = NULL
)
```

## Arguments

- program_type:

  Character: "residency" or "fellowship"

- freida_dir:

  Character path to directory with crosswalk CSVs, or NULL to
  auto-resolve

## Value

Data frame with crosswalk mappings, or NULL if file not found
