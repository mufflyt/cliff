# Vectorized Pure-R Haversine Distance in Kilometers (mean-radius family)

Canonical home for the pure-R, vectorized, mean-Earth-radius haversine
that was copy-pasted across the pipeline (\`.vbo_hav_km\`,
\`.vps_haversine_km\`, \`haversine_km\`, \`.haversine_km\`, ...). Uses
the IUGG mean radius R = 6371.0088 km and an inline great-circle formula
with a \`pmin(1, .)\` clamp for near-antipodal float safety. Fully
vectorized over its inputs.

## Usage

``` r
haversine_km_vec(lat1, lon1, lat2, lon2)
```

## Arguments

- lat1, lon1:

  \`numeric\`: latitude/longitude of point 1 (degrees).

- lat2, lon2:

  \`numeric\`: latitude/longitude of point 2 (degrees).

## Value

Numeric vector of great-circle distances in kilometers.

## Details

**NOT interchangeable with**
[`haversine_distance`](https://mufflyt.github.io/cliff/reference/haversine_distance.md)
/
[`haversine_distance_vectorized`](https://mufflyt.github.io/cliff/reference/haversine_distance_vectorized.md):
those call
[`geosphere::distHaversine`](https://rdrr.io/pkg/geosphere/man/distHaversine.html),
which uses the WGS84 equatorial radius (6378137 m) and so returns values
~0.11% LARGER. Migrating a pure-R caller to the geosphere family (or
vice-versa) silently shifts distances that feed the 5 km clustering
threshold (CLAUDE.md \#17) and the 100-mile secondary filter. Pick
deliberately; do not cross families in a "cleanup".

## See also

[`haversine_distance`](https://mufflyt.github.io/cliff/reference/haversine_distance.md)
(geosphere/WGS84 scalar, km)

Other geospatial-utils:
[`spatial_distance_module`](https://mufflyt.github.io/cliff/reference/spatial_distance_module.md)
