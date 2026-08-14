# Archived working notes

Superseded documents, kept for history. **Nothing here is current.** Each entry
below records what made it stale and where the live answer now lives.

They are archived rather than deleted because they are the record of how the
analysis got here, and because two of them document decisions whose *reasoning*
still matters even though the *conclusion* has changed.

Audited 2026-08-14 against the repository. The criterion for archiving was
evidence, not age: a document was archived only if it presents retired values as
current, or asks for a decision that has since been made. Documents that merely
predate recent work were left in place.

---

## `HANDOFF_WORKFORCE_CLIFF_2026-07-19.md`

**Why archived.** Its results table presents the retired vintage as current:

| Cohort | baseline | projected 2029 | ratio |
|---|---|---|---|
| URPS (both-pathway) | 1,295 | 1,505.4 | **5.61** |

All three are superseded. The adopted baseline is **1,306** and the URPS
completion-to-departure ratio is **5.38**. It also carries the GO ratio 7.35,
which predates 7.11, and 5.83, which never matched any committed artifact.

**Where the live answer is.** `data/workforce_projections_consolidated.csv`, written
by `scripts/rebuild_ssot_revised.R`. Retired values are pinned in the Hall of Shame
in `tests/testthat/test-ssot-no-stale-published-numbers.R` so they cannot return.

**Still useful for.** It names the generator for each artifact, which is what made
recovering the missing generators possible. That map now lives, generated, in
[`docs/PIPELINE.md`](../../docs/PIPELINE.md).

---

## `HANDOFF_cliff_manuscript_port.md`

**Why archived.** The port it requests is done. It opens "`mufflyt/cliff` has the
code/apps/data but is **missing the whole manuscript layer**" and lists four files
to add; all four are present:

- `manuscript/manuscript_WORKFORCE_CLIFF.Rmd`
- `manuscript/references_WORKFORCE_CLIFF.bib`
- `manuscript/supplement_WORKFORCE_CLIFF.Rmd`
- `manuscript/title_page_WORKFORCE_CLIFF.Rmd`

**Note.** Its guidance that `feature/7ss` is canonical and the green-journal copy
obsolete has itself been overtaken: the current manuscript IS the Green Journal
restructuring, condensed from 8,405 to 2,702 words and since made
urogynecology-only.

---

## `URPS_CONTAINMENT_AND_BASELINE_NOTES.md`

**Why archived.** Its central section is "The 1,295 vs 1,339 URPS baseline (needs
PI decision — do NOT silently unify)". That decision has been made, and neither
candidate won: the adopted baseline is **1,306** (ABOG 1,027 + ABU net-new 279),
defined by the isochrones v3.0.0 provider snapshot's `active_2023` gate. 1,295 is
retained only as the frozen legacy SGS projection cohort; 1,339 is the 2025
roster snapshot, a different measure entirely.

**Where the live answer is.** `mufflyaccess::urps_count()`, and the derivation in
`data/consort_cohort_flow.csv` written by `scripts/algorithm_supplement_data.R`.
`tests/testthat/test-no-unqualified-urps-baseline.R` fails on any unqualified use
of 1,295 / 1,332 / 1,339 in production code.

---

## Not archived

`SIMULATION_TO_CLIFF_INTEGRATION_PLAN.md` (root) is a live plan and stays there.
Its stale 1,295 rows were corrected in place on 2026-08-14 rather than archived,
because the rest of the document is current: lineage A is marked retired and
un-runnable, the side-by-side gives 1,306 as adopted, and the baseline
reconciliation is closed on the cliff side with `simulation`'s 1,169@2022 noted
as still open.

Chasing that one row found something else: lineage A
(`code/01_consolidate_workforce_data.R`) writes the SSOT, and was the only
non-canonical writer of it that was **not** locked. It is now locked behind
`WORKFORCE_ALLOW_NONCANONICAL_SSOT_WRITE=1`, matching
`scripts/rebuild_ssot_final.R` and `scripts/rebuild_ssot_dynamic_acgme.R`. It
cannot run today because its archived input is absent, but restoring that archive
would have let `code/00_RUN_ALL.R` silently rebuild the SSOT on the retired 1,295
basis.
