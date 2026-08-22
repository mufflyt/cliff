# Get ABOG Subspecialty Full Names

Returns a named character vector mapping the 6 standard ABOG
subspecialty abbreviation codes to their full descriptive names. Used
for display labels in tables, figures, and reports.

## Usage

``` r
get_abog_subspecialty_names()
```

## Value

\[named character vector\] with 6 entries where names are ABOG codes
(FPMRS, GO, MFM, REI, MIG, PAG) and values are the corresponding full
subspecialty names.

## Details

\- \*\*Pipeline step:\*\* Reference data (used for labeling in
manuscript tables and figures) - \*\*Inputs:\*\* None (returns
hard-coded mapping) - \*\*Algorithm:\*\* Returns a pre-defined named
character vector - \*\*Performance:\*\* O(1) constant-time -
\*\*Reproducibility:\*\* Deterministic (fixed mapping)

## See also

\[get_abog_subspecialties()\], \[standardize_abog_subspecialty()\]
