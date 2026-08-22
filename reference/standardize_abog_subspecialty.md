# Standardize ABOG Subspecialty Names

Converts various subspecialty name formats to the standard 6 ABOG
subspecialty codes: FPMRS, GO, MFM, REI, MIG, PAG. Unrecognized
subspecialties are returned unchanged; non-ABOG recognized
subspecialties (Critical Care, Hospice/Palliative Medicine) are
explicitly mapped to "Other".

## Usage

``` r
standardize_abog_subspecialty(subspecialty_names)
```

## Arguments

- subspecialty_names:

  \[character vector\]: Raw subspecialty name strings to standardize
  (e.g., "Gyn & Oncology", "female pelvic medicine and reconstructive
  surgery").

## Value

\[character vector\] of the same length as input, with recognized names
replaced by their standard ABOG codes (FPMRS, GO, MFM, REI, MIG, PAG) or
"Other". Unrecognized names are returned unchanged.

## Details

\- \*\*Pipeline step:\*\* Data normalization (called by
apply_subspecialty_standardization and validate_subspecialty_data) -
\*\*Inputs:\*\* Character vector of raw subspecialty name strings -
\*\*Algorithm:\*\* 1. Normalize input via norm() (lowercase, trim, strip
non-alpha), 2. Apply dplyr::case_when matching against known name
variants for each ABOG code, 3. Return original name if no match found -
\*\*Performance:\*\* Vectorized; O(n) for n subspecialty strings -
\*\*Reproducibility:\*\* Deterministic (fixed mapping table)

Critical fix (2026-01-18): Critical Care and Hospice/Palliative Medicine
are now mapped to "Other" instead of being incorrectly merged into GO
(Gynecologic Oncology). This was a data quality bug that inflated GO
physician counts.

## See also

\[norm()\], \[apply_subspecialty_standardization()\],
\[get_abog_subspecialties()\]

## Examples

``` r
if (FALSE) { # \dontrun{
  standardize_abog_subspecialty(c("Gyn & Oncology", "MFM", "Critical Care"))
  # Returns: c("GO", "MFM", "Other")
} # }
```
