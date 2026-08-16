# Adjudication: `data/classifier_validation_external.csv`

**Status:** **CLOSED** 2026-08-16 — inputs changed legitimately; reference standard now frozen and hash-verified
**Date:** 2026-08-16
**Queue:** `scripts/ci/artifact_drift_debt.txt` (1 of 10)

Neither the generator nor the committed artifact was modified during this
investigation.

---

## 1. Artifact and generator

| | |
|---|---|
| Artifact | `data/classifier_validation_external.csv` |
| Generator | `scripts/validate_departure_classifier_external.R` |
| Class | `upstream_repo` — reads the isochrones cohort and state-board registry |
| Manuscript exposure | **none.** No `.Rmd` cites these values; consumers are three test files |

## 2. Committed vs regenerated

| | n | TP | FN | FP | TN | sensitivity | ref-departed (TP+FN) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Committed (URPS) | 415 | 1 | 3 | 45 | 366 | 0.250 | **4** |
| Regenerated (URPS) | 499 | 3 | 13 | 44 | 439 | 0.188 | **16** |

GO and MIGS moved similarly (GO 390→519, MIGS 251→329).

## 3. Provenance

**Committed artifact:** written 2026-07-24 in `ac273bb`. `git diff` reports the
generator as a *new file* at that commit — the artifact was committed **before
its generator existed in cliff**, consistent with the isochrones extraction
carrying artifacts across without their code. The committed numbers were
therefore produced by the isochrones original, not by the version in this repo.

**Inputs, at the time of writing:**

| Input | Tracked? | State |
|---|---|---|
| `manuscript/tables/table1_physician_characteristics.csv` | yes, in isochrones | last commit 2026-06-21; working tree **matches git** |
| `data/state_licenses/state_board_lifecycle_registry.csv` | **no — gitignored** (`.gitignore:377`) | symlink → `gold/…`, rewritten **2026-08-09** |

## 4. Root cause

Two candidate causes were tested and one was eliminated.

**The generator did not change.** A semantic diff (comments and blank lines
stripped) of the isochrones original (`11343bbc`, 2026-07-18) against cliff's
ported copy shows four differences, none of them behavioural:

```
+ source(here::here("R", "wc_path.R"))
- COHORT <- "/Users/…/table1_physician_characteristics.csv"   → wc_path("cohort_csv")
- REG    <- "/Users/…/state_board_lifecycle_registry.csv"     → wc_path("state_registry")
- guess_max = 1e5                                             → READ_GUESS_MAX_ROWS   (== 1e5)
- write_csv(… here("cliff","data", …))                        → here("data", …)
```

Eligibility, the reference-label rule, the ambiguous-exclusion rule and the
confusion-matrix construction are character-for-character identical.

**The reference standard changed.** The registry is gitignored but snapshotted
under `data/state_licenses/snapshots/`. The snapshot current on 2026-07-24 is
`state_board_lifecycle_registry_2026-05-31_4a2c5e08.rds`; the live symlink now
resolves to a file written 2026-08-09.

Re-running the *unmodified* generator logic against the period-correct snapshot
reproduces the committed artifact **exactly**, for all three subspecialties:

```
2026-05-31 snapshot : URPS n=415 TP=1 FN=3  FP=45 TN=366 sens=0.250
                      GO   n=390 TP=3 FN=10 FP=38 TN=339 sens=0.231
                      MIGS n=251 TP=3 FN=6  FP=29 TN=213 sens=0.333
committed artifact  : URPS n=415 TP=1 FN=3  FP=45 TN=366 sens=0.250   ← identical
```

The registry grew from **36,070 rows / 35,536 NPIs** to **83,372 / 82,399** — a
2.3× expansion in board coverage.

## 5. Row-level account of the change

URPS movement: **+122 added, −38 dropped** (net +84).

Of the 122 added, **119 were absent from the old registry entirely** (new board
coverage) and 3 were previously `ambiguous` (inactive-only) and now carry a
definitive label. None entered through a rule change.

The sensitivity shift is a denominator effect, and it decomposes exactly:

| Source | Δ reference-departed |
|---|---:|
| Retained records whose board status flipped `active` → `departed` | **+10** |
| Newly covered records that are reference-departed | **+2** |
| Dropped records that were reference-departed | 0 |
| **Total** | **4 → 16** |

Of the 10 retained flips, the classifier called 8 active (new FN) and 2 departed
(new TP), which is precisely `TP 1→3` and `FN 3→13`.

So the change is driven **more by state boards updating existing physicians'
licence status (+10) than by new coverage (+2)** — a distinction that matters,
because the first is a genuine correction to the reference standard.

## 6. Authoritative side

**Both sides are internally correct.** The committed artifact is exactly what the
generator produces from the inputs available when it was written; the
regenerated artifact is exactly what the same generator produces from today's
reference standard. There is no defect in either.

This is outcome category **"inputs changed legitimately"** — the artifact/input
relationship must be versioned rather than silently replaced.

## 7. Scientific consequence

The headline caution is **not** which number is right. It is that **both rest on
a denominator of 4 and 16 reference-departed URPS physicians.** A sensitivity of
0.250 is `1/4`; 0.188 is `3/16`. Neither supports a precise claim, and the
apparent "drop in sensitivity" is well inside what a handful of licence-status
updates can move.

The newer basis is better powered (2.3× coverage, 16 vs 4 departed) and
incorporates board corrections, so it is the better estimate — but it is still
an underpowered one, and reporting it without its interval would overstate what
this validation can support.

No manuscript text depends on these values, so nothing published is affected.

## 8. Action

**Not taken here** (this is an adjudication record, not a fix):

1. **Do not silently regenerate.** Replacing the artifact would erase the fact
   that it was correct for a different reference vintage.
2. **Version the input relationship.** The generator should record which registry
   snapshot it consumed — id and date — in the artifact itself or alongside it,
   so "which reference standard produced this?" is answerable from the file.
3. **Then refresh deliberately**, on the 2026-08-09 basis, in a commit that says
   the reference standard was expanded and cites this record.
4. **Report an interval.** With 4–16 events, a point sensitivity is misleading on
   its own.

The deeper process finding is that **the gold standard is gitignored.** A
reference standard that can be rewritten with no commit, no hash and no record
is why this artifact became unreproducible without anyone doing anything wrong.
The snapshots exist and are dated, which is what made this adjudication
possible — pinning the snapshot id is a small change that would make it
unnecessary next time.

## 9. Regression test (proposed, not added)

Once the input relationship is versioned, the check is not "does the artifact
reproduce" — it cannot, against a moving reference — but:

> the artifact records a registry snapshot id, that snapshot exists under
> `snapshots/`, and regenerating against **that** snapshot reproduces the
> committed metrics exactly.

That is a reproducibility guarantee that survives the reference standard being
refreshed, which the current byte-comparison does not.


---

## 10. Resolution (2026-08-16)

The scientific result was **not** changed. `0.250` stands as published.

**The reference standard is frozen and verified.** `config/cliff_paths.yml` gained
`state_registry_frozen`, pinning the dated snapshot that reproduces the committed
artifact, and `state_registry_updated` for the refreshed basis. The generator
resolves the frozen key, records the snapshot id and its sha256, and **refuses to
run if the bytes differ**:

```
reference standard: state_board_lifecycle_registry_2026-05-31_4a2c5e08
  sha256 f95b29fdcd51a0ff7fce9f6652156a7dddaec3159caafaa7f98fb9184f4785d6 (verified)
```

Running it now reproduces `data/classifier_validation_external.csv`
**byte-identically**. The artifact went from unreproducible to reproducible with
no change to any published number.

**The refreshed basis is a separate, labelled analysis.**
`scripts/validate_departure_classifier_external_updated_reference.R` reports both
bases side by side in
`data/classifier_validation_external_updated_reference.csv`, each row stamped
with its snapshot id and sha256, and each sensitivity carrying a Wilson interval:

| basis | subspec | sensitivity | 95% CI |
|---|---|---:|---|
| frozen 2026-05-31 | URPS | 1/4 = 0.250 | 0.046 – 0.699 |
| updated 2026-08-09 | URPS | 3/16 = 0.188 | 0.066 – 0.430 |
| frozen 2026-05-31 | ALL | 7/26 = 0.269 | 0.137 – 0.461 |
| updated 2026-08-09 | ALL | 11/53 = 0.208 | 0.120 – 0.335 |

**Each interval contains the other's point estimate.** There is no evidence the
classifier's performance changed; the movement is reference-standard correction,
and 10 of the 12 additional reference-departed URPS physicians came from boards
updating existing records rather than from expanded coverage.

**Guard added.** `tests/testthat/test-external-validation-reference-frozen.R`
requires an external-validation generator to pin a hashed snapshot, verify it at
run time, and never resolve the mutable `state_registry` key; it also checks the
frozen snapshot still matches its hash, that the updated analysis carries both
bases with intervals, and that the published `n=415 / 0.250` is unchanged.
Mutation-tested: reverting the generator to the mutable key fails it.

**Remaining exposure.** The upstream registry is still gitignored, so *future*
snapshots are still unversioned upstream. What has changed is that cliff no
longer depends on whichever one happens to be current: it names the one it used.
