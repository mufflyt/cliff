# Calculate Haversine Distance in Meters

Same as haversine_distance() but returns meters instead of kilometers.
Useful for clustering algorithms that expect meter-scale distances.

## Usage

``` r
haversine_distance_m(lat1, lon1, lat2, lon2)
```

## Arguments

- lat1:

  \`numeric\`: - latitude of first point (degrees)

- lon1:

  \`numeric\`: - longitude of first point (degrees)

- lat2:

  \`numeric\`: - latitude of second point (degrees)

- lon2:

  \`numeric\`: - longitude of second point (degrees)

## Value

Numeric - distance in meters

## See also

[`haversine_distance`](https://mufflyt.github.io/cliff/reference/haversine_distance.md)
for kilometers,
[`haversine_distance_vectorized`](https://mufflyt.github.io/cliff/reference/haversine_distance_vectorized.md)
for vectors

Other spatial-distance:
[`calculate_haversine_distance()`](https://mufflyt.github.io/cliff/reference/calculate_haversine_distance.md),
[`haversine_distance()`](https://mufflyt.github.io/cliff/reference/haversine_distance.md),
[`haversine_distance_vectorized()`](https://mufflyt.github.io/cliff/reference/haversine_distance_vectorized.md)

## Examples

``` r
if (requireNamespace("geosphere", quietly = TRUE)) {
  # Distance in meters (for clustering thresholds)
  print(haversine_distance_m(39.7392, -104.9903, 40.0150, -105.2705))
}
#> [1] 38930.62
```
