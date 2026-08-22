# Calculate Haversine Distance (Alternative Name)

Alias for haversine_distance_m() to match naming conventions in some
geocoding scripts.

## Usage

``` r
calculate_haversine_distance(lat1, lng1, lat2, lng2)
```

## Arguments

- lat1:

  \`numeric\`: - latitude of first point

- lng1:

  \`numeric\`: - longitude of first point (note: lng vs lon)

- lat2:

  \`numeric\`: - latitude of second point

- lng2:

  \`numeric\`: - longitude of second point

## Value

Numeric - distance in meters

## See also

[`haversine_distance_m`](https://mufflyt.github.io/cliff/reference/haversine_distance_m.md)

Other spatial-distance:
[`haversine_distance()`](https://mufflyt.github.io/cliff/reference/haversine_distance.md),
[`haversine_distance_m()`](https://mufflyt.github.io/cliff/reference/haversine_distance_m.md),
[`haversine_distance_vectorized()`](https://mufflyt.github.io/cliff/reference/haversine_distance_vectorized.md)
