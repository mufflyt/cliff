# Resolve FREIDA data directory

Checks three locations in priority order: 1. FREIDA_DATA_DIR environment
variable 2. freida_data_dir key in config/paths.yml 3. data/freida/
(project-local copy)

## Usage

``` r
resolve_freida_dir()
```

## Value

Character path to directory containing FREIDA CSVs
