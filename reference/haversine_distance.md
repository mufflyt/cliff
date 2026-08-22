# Calculate Haversine Distance Between Two Points

Computes the great-circle distance between two geographic coordinates
using the Haversine formula via the geosphere package.

## Usage

``` r
haversine_distance(lat1, lon1, lat2, lon2)
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

Numeric - distance in kilometers

## Details

Uses geosphere::distHaversine for consistency. The function expects
single coordinate values (not vectors). For vectorized operations, see
haversine_distance_vectorized().

## See also

[`haversine_distance_m`](https://mufflyt.github.io/cliff/reference/haversine_distance_m.md)
for meters,
[`haversine_distance_vectorized`](https://mufflyt.github.io/cliff/reference/haversine_distance_vectorized.md)
for vectors

Other spatial-distance:
[`calculate_haversine_distance()`](https://mufflyt.github.io/cliff/reference/calculate_haversine_distance.md),
[`haversine_distance_m()`](https://mufflyt.github.io/cliff/reference/haversine_distance_m.md),
[`haversine_distance_vectorized()`](https://mufflyt.github.io/cliff/reference/haversine_distance_vectorized.md)

## Examples

``` r
# geosphere is a suggested dependency, so the example guards on it: an
# unguarded call is an R CMD check ERROR in a library that lacks it.
if (requireNamespace("geosphere", quietly = TRUE)) {
  # Distance from Denver to Boulder (approx 40 km)
  print(haversine_distance(39.7392, -104.9903, 40.0150, -105.2705))

  # Distance from NYC to LA (approx 3936 km)
  print(haversine_distance(40.7128, -74.0060, 34.0522, -118.2437))
}
#> [1] 38.93062
#> [1] 3940.155
```
