# Load FREIDA Programs (Residency or Fellowship)

Reads the cleaned FREIDA CSV and standardizes columns for use in
training inference. Both residency and fellowship CSVs share the same
column schema.

## Usage

``` r
load_freida_programs(
  program_type = c("residency", "fellowship"),
  freida_dir = NULL
)
```

## Arguments

- program_type:

  Character: "residency" or "fellowship"

- freida_dir:

  Character path to directory with CSVs, or NULL to auto-resolve

## Value

Data frame with standardized columns: program_name, institution, city,
state, lat, lon, acgme_program_id, specialty, primary_teaching_hospital,
annual_births, nicu_beds, total_beds, trauma_center, program_type
