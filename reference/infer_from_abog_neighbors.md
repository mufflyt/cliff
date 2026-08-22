# Infer residency from ABOG sequential ID neighbor majority vote

ABOG assigns IDs sequentially by program registration, creating clusters
of co-residents with nearby IDs. For physicians without GT resolution,
this function looks at their ABOG ID neighbors (within +/-5) and assigns
the majority residency program.

## Usage

``` r
infer_from_abog_neighbors(
  npis,
  db_path,
  crosswalk,
  programs,
  window = 5L,
  min_neighbors = 2L,
  confidence = 0.7
)
```

## Arguments

- npis:

  \[character\]: NPIs to infer training for.

- db_path:

  \[character\]: Path to the temporal NPPES DuckDB used for neighbour
  lookup. 0.70)

- crosswalk:

  Data frame from load_training_crosswalk("residency")

- programs:

  Data frame from load_freida_programs("residency")

- window:

  Integer: ABOG ID neighbor window size (default 5)

- min_neighbors:

  Integer: minimum neighbors with known residency (default 2)

- confidence:

  Numeric: base confidence score for voted results (default

## Value

Data frame with columns matching inference_output_columns() plus
abog_vote\_\* audit trail columns, or NULL if no ABOG data available.
Output NPIs are guaranteed unique and a subset of input NPIs.

## Details

Validated agreement: ~24

\## Audit trail columns in output - \`abog_vote_name\`: Raw residency
name from goba (what neighbors said) - \`abog_vote_count\`: How many
neighbors voted for the winning program - \`abog_vote_total\`: Total
neighbors with known residency in window - \`abog_vote_share\`:
vote_count / vote_total (0-1) - \`abog_vote_runner_up\`: Second-place
program name (for contested votes) - \`abog_vote_runner_up_count\`: How
many voted for runner-up - \`abog_id\`: The physician's ABOG sequential
ID - \`abog_neighbor_npi_list\`: Pipe-delimited NPIs of voting neighbors

\## Confidence calibration Base confidence is scaled by vote share: -
vote_share \>= 0.75: confidence \* 1.00 (strong consensus) - vote_share
\>= 0.50: confidence \* 0.90 - vote_share \>= 0.33: confidence \* 0.80 -
vote_share \< 0.33: confidence \* 0.70 (weak plurality)
