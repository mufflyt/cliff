# Build a Standardized Result Row

DRY helper — constructs the 1-row data.frame returned by
find_nearest_program().

## Usage

``` r
build_result(
  program_row,
  confidence,
  method,
  distance_km = NA_real_,
  programs_within = NA_integer_,
  source = "nppes_inference"
)
```

## Arguments

- program_row:

  1-row data.frame from programs

- confidence:

  Numeric in \[0, 1\]

- method:

  Character inference method label

- distance_km:

  Numeric distance or NA

- programs_within:

  Integer count or NA

- source:

  \[character\]: Provenance label for the matched record.

## Value

1-row data.frame with all inference columns
