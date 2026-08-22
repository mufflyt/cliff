# Is a FIPS code in the contiguous United States?

\`TRUE\` for a state FIPS code, or the leading two characters of any
longer GEOID, that is \*\*not\*\* Alaska, Hawaii, Puerto Rico, Guam, the
US Virgin Islands, American Samoa or the Northern Mariana Islands.

## Usage

``` r
is_conus_fips(fips)
```

## Arguments

- fips:

  \`character\`/\`numeric\`: state FIPS codes or longer GEOIDs. Coerced
  with \`as.character()\`, so numeric input loses a leading zero — pass
  character for states below 10.

## Value

\`logical\` the same length as \`fips\`.

## Details

Vectorised, and works on exact 2-digit \`STATEFP\` as well as on county
(5-digit) and tract (11-digit) GEOIDs, because it tests the leading two
characters. Testing exclusion rather than membership means a new or
unrecognised code is treated as CONUS; if you need the opposite, test
against \[mufflyaccess::CONUS_STATE_FIPS\] instead.

The excluded set is validated at package load (\`CONUS_EXCLUDE_FIPS\`):
seven entries, all two-digit, no duplicates, with Alaska and Hawaii
present.

## See also

\[in_conus_bbox()\] for filtering raw coordinates.

Other geography:
[`in_conus_bbox()`](https://mufflyt.github.io/cliff/reference/in_conus_bbox.md)

## Examples

``` r
is_conus_fips(c("08", "02", "15", "36"))
#> [1]  TRUE FALSE FALSE  TRUE
#> TRUE FALSE FALSE TRUE

# Works on county and tract GEOIDs too
is_conus_fips(c("08031", "02020", "36061003800"))
#> [1]  TRUE FALSE  TRUE
#> TRUE FALSE TRUE
```
