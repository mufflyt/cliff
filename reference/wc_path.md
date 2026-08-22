# Resolve an external input path from config/cliff_paths.yml

Look up a registered input key in \`config/cliff_paths.yml\`
(deep-merged with a gitignored \`config/cliff_paths.local.yml\` for
per-machine overrides) and return its resolved filesystem path.

## Usage

``` r
wc_path(key, must_exist = FALSE)
```

## Arguments

- key:

  Character scalar naming a registered entry in \`cliff_paths.yml\`
  (e.g. \`"signals_duckdb"\`). An unknown key is a fail-loud \`stop()\`.

- must_exist:

  Logical; when \`TRUE\`, \`stop()\` if the resolved path does not exist
  on disk. Defaults to \`FALSE\` (return the path unchecked).

## Value

A length-1 character filesystem path.

## Details

Resolution order per entry is: the named \`WORKFORCE\_\*\` environment
variable (if set and non-empty) \> the entry's \`path\` \> its
\`fallback\` (used only when \`path\` does not exist). The parsed config
is cached in the module-level \`.wc_paths_cfg\` on the first call. The
function is side-effect-free (no data loading), so upstream regeneration
scripts can source this module alone rather than the full engine just to
obtain a machine-independent path.

## See also

\[wc_duckdb_path()\] for the Medicare signals DuckDB shorthand;
\`config/cliff_paths.yml\` for the registered keys.

## Examples

``` r
if (FALSE) { # \dontrun{
wc_path("signals_duckdb")                     # env override > path > fallback
wc_path("signals_duckdb", must_exist = TRUE)  # stop() if the file is absent
} # }
```
