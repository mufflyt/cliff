# Validate Inference Results Quality

Comprehensive QA validation for inference output. Runs schema checks,
confidence bounds, phase-level breakdown, NPI uniqueness, distance
plausibility, and geographic consistency. Writes structured JSON audit
artifact to artifacts/audit/ on every call (pass or fail).

## Usage

``` r
validate_inference_qa(results, context = "training", write_artifact = TRUE)
```

## Arguments

- results:

  Data frame with inference columns (post-unnest)

- context:

  \[character\]: Label used in QA messages and artefact names, e.g.
  "fellowship". artifacts/audit/

- write_artifact:

  Logical; if TRUE (default), write JSON audit to

## Value

Invisible list with QA metrics; side-effect: warnings for issues, JSON
audit artifact written to `artifacts/audit/inference_qa_[context].json`
