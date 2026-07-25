# HANDOFF → the window building `mufflyt/cliff`

## TL;DR
`mufflyt/cliff` has the code/apps/data but is **missing the whole manuscript layer**.
Add those files from **`origin/feature/seven-subspecialty-expansion` @ `655d279e9`** (fetchable
— it's pushed), then apply the tiny **citation port** below (my commit `4c89d4be5` is
LOCAL-ONLY on the other machine, so apply it as text, not as a git commit).

`feature/7ss` @ 655d279e9 is the **canonical** (reviewer major-revision) workforce paper —
partial-pooling hazard, URPS both-pathway, MIGS exploratory. The green-journal
"Surgical Workforce Cliff" copy is the obsolete pre-revision fork; do not use it.

## Step 1 — add the missing manuscript layer (from origin/feature/7ss @ 655d279e9)
Files absent from mufflyt/cliff's 199-file snapshot:
- manuscript/manuscript_WORKFORCE_CLIFF.Rmd
- manuscript/references_WORKFORCE_CLIFF.bib
- manuscript/supplement_WORKFORCE_CLIFF.Rmd
- manuscript/title_page_WORKFORCE_CLIFF.Rmd
- manuscript/RESPONSE_TO_REVIEWERS_WORKFORCE_CLIFF.md
- cliff/URPS_SUPPLY_DEMAND_METHODS_REFERENCES.md
- cliff/URPS_WORKFORCE_LITERATURE_SYNTHESIS_2026-07-23.md
- cliff/shiny_urps_adequacy/tests/e2e_browser.R   (browser E2E; 9/9 passing)

`workforce_statistics.R` / `workforce_data_contract.R` / `workforce_figures.R` /
`workforce_cliff_engine.R` / the SSOT `cliff/data/workforce_projections_consolidated.csv`
appear already present — verify they match the 655d279e9 versions.

## Step 2 — apply the citation port (my local-only commit 4c89d4be5, +45/-1)

### 2a. Append these 5 entries to references_WORKFORCE_CLIFF.bib (append-only, order-free)
Note: `leejt2024` key is deliberate — `lee2024` already exists as an unrelated paper.
DOIs intentionally omitted (verified journal/year/vol/pages only; fill before submission).

```bibtex
% --- Prior surgical-workforce models (ported 2026-07-24; DOIs to fill) ---
@article{etzioni2003,
  author  = {Etzioni, D. A. and Liu, J. H. and Maggard, M. A. and others},
  title   = {The aging population and its impact on the surgery workforce},
  journal = {Annals of Surgery}, year = {2003}, volume = {238}, pages = {170--177}
}
@article{fraher2013,
  author  = {Fraher, E. P. and Knapton, A. and Sheldon, G. F. and Meyer, A. and Ricketts, T. C.},
  title   = {Projecting surgeon supply using a dynamic model},
  journal = {Annals of Surgery}, year = {2013}, volume = {257}, pages = {867--872}
}
@article{edwards2014,
  author  = {Edwards, J. P. and Datta, I. and Hunt, J. D. and others},
  title   = {A novel approach for the accurate prediction of thoracic surgery workforce requirements in {Canada}},
  journal = {Journal of Thoracic and Cardiovascular Surgery}, year = {2014}, volume = {148}, pages = {7--12}
}
@article{leejt2024,
  author  = {Lee, J. T. and Crettenden, I. and Tran, M. and others},
  title   = {Methods for health workforce projection model: systematic review and recommended good practice reporting guideline},
  journal = {Human Resources for Health}, year = {2024}, volume = {22}, pages = {25}
}
@article{ellison2018,
  author  = {Ellison, E. C. and Pawlik, T. M. and Way, D. P. and others},
  title   = {Ten-year reassessment of the shortage of general surgeons: increases in graduation numbers of general surgery residents are insufficient to meet the future demand for general surgeons},
  journal = {Surgery}, year = {2018}, volume = {164}, pages = {726--732}
}
```

### 2b. Insert ONE sentence in manuscript_WORKFORCE_CLIFF.Rmd, Introduction ¶2
Between `...without quantifying the uncertainty in the timing of individual exits.` and
`Federal supply-demand modeling, moreover, cannot separate...`, insert:

> Prior surgical workforce models nonetheless offer complementary methods that inform our
> design: demand-side models apply age-specific procedure-use rates to population
> projections,[@etzioni2003; @edwards2014] dynamic stock-and-flow supply models age cohorts
> forward annually and can express capacity as full-time equivalents rather than
> headcount,[@fraher2013] and good-practice reporting standards emphasize explicit
> assumptions and quantified uncertainty.[@leejt2024] Contemporary surgical projections that
> combine board certifications, residency completions, and retirement have likewise found
> that training expansion alone is insufficient to offset losses,[@ellison2018] a pattern
> our subspecialty-specific, uncertainty-quantified model tests directly against graduate output.

## Step 3 — verify
- Every `[@key]` resolves to a bib entry; no dangling references (I verified: 52 cited, 60 defined, 0 dangling on isochrones).
- Render the manuscript in the standalone repo; confirm the 5 new refs appear and it knits.

## Provenance of the port (for the record)
Salvaged from the pre-revision green-journal manuscript body (refs 9/10/11/12/14),
which had this literature but is otherwise obsolete. Reference details are from the
verified reference list. My source commit `4c89d4be5` never left the other machine.
