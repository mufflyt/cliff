# Vectorized Haversine Distance Calculation

Calculates distances between pairs of coordinates (vectorized). Uses
geosphere::distHaversine which handles vectors efficiently.

## Usage

``` r
haversine_distance_vectorized(lat1, lon1, lat2, lon2, units = "km")
```

## Arguments

- lat1:

  \`numeric vector\`: - latitudes of first points

- lon1:

  \`numeric vector\`: - longitudes of first points

- lat2:

  \`numeric vector\`: - latitudes of second points

- lon2:

  \`numeric vector\`: - longitudes of second points

- units:

  \`character\`: - "km" (default) or "m" for kilometers or meters

## Value

Numeric vector - distances in specified units

## See also

[`haversine_distance`](https://mufflyt.github.io/cliff/reference/haversine_distance.md)
for single-point calculations

Other spatial-distance:
[`calculate_haversine_distance()`](https://mufflyt.github.io/cliff/reference/calculate_haversine_distance.md),
[`haversine_distance()`](https://mufflyt.github.io/cliff/reference/haversine_distance.md),
[`haversine_distance_m()`](https://mufflyt.github.io/cliff/reference/haversine_distance_m.md)

## Examples

``` r
if (requireNamespace("geosphere", quietly = TRUE)) {
  # Calculate multiple distances at once
  lats1 <- c(39.7392, 40.7128)
  lons1 <- c(-104.9903, -74.0060)
  lats2 <- c(40.0150, 34.0522)
  lons2 <- c(-105.2705, -118.2437)
  print(haversine_distance_vectorized(lats1, lons1, lats2, lons2))
}
#> [1]   38.93062 3940.15520
```
