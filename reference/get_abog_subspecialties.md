# Get the Official 6 ABOG Subspecialty Codes

Returns a character vector of the 6 standard ABOG (American Board of
Obstetrics and Gynecology) subspecialty abbreviation codes. These are
the canonical codes used throughout the pipeline for subspecialty
classification, factor ordering, and validation.

## Usage

``` r
get_abog_subspecialties()
```

## Value

\[character vector\] of length 6 containing the standard ABOG
subspecialty codes in canonical order.

## Details

\- \*\*Pipeline step:\*\* Reference data (used by standardize/validate
functions) - \*\*Inputs:\*\* None (returns constant from ABOG_SUBS
module-level variable) - \*\*Algorithm:\*\* Returns the package-level
ABOG_SUBS constant - \*\*Performance:\*\* O(1) constant-time lookup -
\*\*Reproducibility:\*\* Deterministic (fixed constant)

The 6 codes are: FPMRS (Female Pelvic Medicine and Reconstructive
Surgery), GO (Gynecologic Oncology), MFM (Maternal-Fetal Medicine), REI
(Reproductive Endocrinology and Infertility), MIG (Minimally Invasive
Gynecology), PAG (Pediatric and Adolescent Gynecology).

## See also

\[get_abog_subspecialty_names()\], \[standardize_abog_subspecialty()\],
\[validate_subspecialty_data()\]
