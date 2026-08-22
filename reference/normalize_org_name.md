# Normalize Organization Name for Matching

Strips punctuation, removes function words (the, of, at, etc.),
uppercases. Keeps generic medical terms — they are downweighted in token
scoring but not removed during normalization.

## Usage

``` r
normalize_org_name(name)
```

## Arguments

- name:

  Character scalar

## Value

Normalized uppercase string, or "" if NA/empty
