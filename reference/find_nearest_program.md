# Find Nearest OB/GYN Program to a Location (Hierarchical Matching)

Shared implementation used by both residency and fellowship inference.
Uses a strict priority chain: 1. Organization/hospital name match
(strict: 2+ meaningful tokens or exact) 2. Street address match (street
number + street name tokens) 3. ZIP proximity (same ZIP code, within 20
km) 4. Distance-only nearest program (haversine) 5. Program size
tiebreaker (when top programs within 5 km of each other)

## Usage

``` r
find_nearest_program(
  physician_lat,
  physician_lon,
  programs,
  max_distance_km = 160,
  physician_org = NA_character_,
  physician_address = NA_character_,
  physician_zip = NA_character_
)
```

## Arguments

- physician_lat:

  Numeric latitude of physician location

- physician_lon:

  Numeric longitude of physician location

- programs:

  Data frame of programs (from load_freida_programs)

- max_distance_km:

  Maximum distance in km to consider (default 160 km ~ 100 miles)

- physician_org:

  Character: physician's org name from NPPES (optional)

- physician_address:

  Character: physician's street address from NPPES (optional)

- physician_zip:

  Character: physician's 5-digit ZIP code from NPPES (optional)

## Value

Data frame with nearest program info, confidence, and training
environment
