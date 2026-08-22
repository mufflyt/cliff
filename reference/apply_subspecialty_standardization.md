# Apply Subspecialty Standardization to a Data Frame

Adds a new column with standardized ABOG subspecialty codes to the input
data frame by applying \[standardize_abog_subspecialty()\] to the
specified subspecialty column. Optionally converts recognized ABOG codes
to an ordered factor for consistent sorting in plots and tables.

## Usage

``` r
apply_subspecialty_standardization(
  data,
  subspecialty_col = "subspecialty_name",
  new_col = "subspecialty_standardized"
)
```

## Arguments

- data:

  \[data.frame\]: Data frame containing subspecialty information to
  standardize.

- subspecialty_col:

  \[character\]: Name of the input subspecialty column (default:
  "subspecialty_name").

- new_col:

  \[character\]: Name for the new standardized column (default:
  "subspecialty_standardized").

## Value

\[data.frame\] with the original columns plus a new column (named by
new_col) containing standardized subspecialty codes. The new column is
an ordered factor if all non-NA values map to ABOG codes, otherwise
character.

## Details

\- \*\*Pipeline step:\*\* Data transformation (typically called after
ABOG data ingestion, before analysis and manuscript generation) -
\*\*Inputs:\*\* Data frame with raw subspecialty labels -
\*\*Algorithm:\*\* 1. Apply standardize_abog_subspecialty() to create
new column, 2. Convert ABOG codes to ordered factor (FPMRS, GO, MFM,
REI, MIG, PAG) if all non-NA values are ABOG codes, 3. Run hygiene
checks: log found ABOG codes, warn on unrecognized labels, assert no
drift from canonical ABOG_SUBS constant - \*\*Performance:\*\* O(n) for
n rows (vectorized dplyr::mutate) - \*\*Reproducibility:\*\*
Deterministic (fixed mapping + factor ordering)

Includes a hard assertion (stopifnot) that prevents subspecialty drift:
any ABOG code found in the data must be a member of the canonical
ABOG_SUBS constant.

## See also

\[standardize_abog_subspecialty()\], \[validate_subspecialty_data()\],
\[get_abog_subspecialties()\]

## Examples

``` r
if (FALSE) { # \dontrun{
  df <- data.frame(subspecialty_name = c("Gyn Onc", "MFM", "REI"))
  result <- apply_subspecialty_standardization(df)
  levels(result$subspecialty_standardized)
  # [1] "FPMRS" "GO" "MFM" "REI" "MIG" "PAG"
} # }
```
