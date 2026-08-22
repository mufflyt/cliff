# Load and Validate ABOG Workforce Data

Reproducible, validated loader for ABOG certification data with explicit
path checking, column/type validation, deterministic coercion, and fatal
errors on structural integrity violations (e.g., duplicate identifiers).

This function implements fail-fast validation to prevent silent failures
and ensure the pipeline operates on structurally valid data before
expensive downstream operations (NPI matching, geocoding, isochrone
generation).

## Usage

``` r
load_abog_workforce_data(
  abog_file,
  required_columns = c("physician_name", "city", "state", "first", "last"),
  allow_duplicates = FALSE,
  verbose = TRUE
)
```

## Arguments

- abog_file:

  \`character\`: Path to the ABOG CSV file. Must exist.

- required_columns:

  \`character vector\`: Columns that must be present in the ABOG data.
  Defaults to critical columns for NPI matching.

- allow_duplicates:

  \`logical\`: If FALSE (default), duplicates on the

- verbose:

  \[logical\]: Emit progress messages while loading. primary identifier
  (\`physician_name\` + \`city\` + \`state\`) trigger a fatal error with
  example rows. Set TRUE only for exploratory analysis.

## Value

A data frame with validated ABOG physician data. Column names are
lowercased for consistency.

## Details

Validation steps performed: 1. \*\*Path existence\*\*: File must exist
at the specified path 2. \*\*Readability\*\*: File must be readable with
standard CSV parsing 3. \*\*Column presence\*\*: Required columns must
exist in the data 4. \*\*Column types\*\*: Critical columns coerced to
expected types 5. \*\*Duplicate detection\*\*: Fatal error if duplicate
identifiers found 6. \*\*State code validation\*\*: Auto-corrects common
typos, excludes non-US 7. \*\*Data completeness\*\*: Reports missing
values in critical columns

The function is deterministic: given the same input file, it will always
produce the same output or fail with the same error message.

## Critical Column Types

\- \`physician_name\`: character (trimmed, non-empty) - \`city\`:
character (trimmed, may be NA for some records) - \`state\`: character
(2-letter US state/territory code) - \`first\`, \`last\`, \`middle\`:
character (name components) - \`certification_year\`: integer (year of
initial certification)

## Duplicate Detection

Duplicates are identified by the composite key: \`(physician_name, city,
state)\`. If duplicates are found, the function stops with an error
showing: - Total number of duplicate groups - Total number of affected
rows - Up to 5 example duplicate groups with all their rows

This prevents downstream issues where: - One physician matches multiple
NPIs (ambiguous many-to-many) - Geocoding produces multiple locations
for "same" physician - Isochrone coverage double-counts the same
provider

## State Code Auto-Correction

Common typos are automatically corrected: - "PU" → "PR" (Puerto Rico) -
"UM" → "PR" (Puerto Rico)

Non-US locations are excluded with warning: - Canadian provinces (ON,
AB, BC, QC, etc.) - International state codes (HR = Haryana, India; OT =
Otago, NZ)

## See also

`canonical_abog_npi_pipeline_STABLE()` for the full matching pipeline
`validate_pipeline_inputs()` for broader input validation

## Examples

``` r
if (FALSE) { # \dontrun{
# Standard usage with all validation
abog_data <- load_abog_workforce_data("data/abog_certification_2023.csv")

# Allow duplicates for exploratory analysis (NOT RECOMMENDED)
abog_data_unvalidated <- load_abog_workforce_data(
  "data/abog_certification_2023.csv",
  allow_duplicates = TRUE
)

# Minimal required columns for specialized workflows
abog_names_only <- load_abog_workforce_data(
  "data/abog_certification_2023.csv",
  required_columns = c("physician_name", "certification_year")
)
} # }
```
