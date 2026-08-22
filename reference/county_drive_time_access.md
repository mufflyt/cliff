# Population-weighted county roll-up of the tract access surface

Aggregates the tract-level drive-time access to counties by
population-weighted mean: county access \`= sum(access_i \* pop_i) /
sum(pop_i)\` over its tracts. The county GEOID is the first five digits
of the 11-digit tract GEOID. Higher access is better (it is the E2SFCA
accessibility, not a distance), so it is the drive-time complement of
Module D's straight-line \`miles_to_nearest\` (lower is better).

## Usage

``` r
county_drive_time_access(surface, min_population = 0)
```

## Arguments

- surface:

  a \[read_access_surface()\] result, or its \`\$data\` frame.

- min_population:

  drop tracts with population below this. Default \`0\`.

## Value

data.frame(\`GEOID\`, \`drive_time_access\`, \`n_tracts\`,
\`population\`), one row per county, ordered by GEOID.
