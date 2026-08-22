# Normalise a Census GEOID that a CSV writer may have coerced to an integer

Left-pads pure-digit strings shorter than \`width\` with zeros (so
\`1001\` becomes \`01001\`), leaving already-correct or non-numeric ids
untouched. Pure.

## Usage

``` r
.as_geoid(x, width)
```

## Arguments

- x:

  character/numeric vector of GEOIDs.

- width:

  target width (11 for tracts, 5 for counties).

## Value

character vector.
