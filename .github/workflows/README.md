# CI

Four workflows. `_core.yml` holds every shared job exactly once; `ci.yml` and
`nightly.yml` both call it, so the nightly run cannot drift from what
contributors see on a pull request.

```
ci.yml        push to main, PRs, manual   ->  _core.yml (deep: false)
nightly.yml   02:17 America/Denver        ->  _core.yml            (deep: true)
                                          ->  _reproducibility.yml (deep: true)
                                          ->  lockfile restore, upstream drift
                                          ->  nightly summary (aggregator)
contract-tests.yml  push, PRs             ->  minimal-dependency canary
```

`_core.yml` asks *is this a healthy R package*. `_reproducibility.yml` asks the
question that actually matters for cliff, which is also a projection engine, a
set of frozen artifacts and an SSOT system: *can a clean machine still reproduce
the evidence the manuscript rests on?*

## What runs where

| Job | ci | nightly | Guards against |
|---|:--:|:--:|---|
| `preflight` | ✓ | ✓ | pin drift, malformed `.Rbuildignore`, unescaped non-ASCII, stale `man/` |
| `check` | 3 configs | 5 configs | `R CMD check` regressions across R versions and platforms |
| `test` | ✓ | ✓ + coverage | the 100-file testthat suite |
| `smoke` | ✓ | ✓ | installed-package semantics — the `load_all()` blind spot |
| `render` | — | ✓ | a manuscript that parses but cannot render |
| `lockfile_restore` | — | ✓ | `renv.lock` no longer restoring from nothing |
| `upstream_drift` | — | ✓ | how far pins lag upstream (informational) |
| `report` | — | ✓ | a nightly failure nobody notices |

The check matrix always includes **R 4.4.2** (what `renv.lock` pins) and
**R 4.5.3** (what the acceptance gate validated), so neither can rot silently.
Nightly adds macOS and Windows. R-devel is deliberately absent: with no Posit
binaries for devel the whole tree builds from source, and it timed out in the
dependency install on all four nightly runs without once reaching `R CMD check`.
cliff is not on CRAN, so the `release` row gives the same warning one cycle
later at no cost.

## Why 02:17 is scheduled twice

GitHub cron is UTC and has no daylight-saving concept, so one entry drifts by an
hour twice a year. Two are registered — `17 8` and `17 9` UTC — and the `when`
job lets exactly one through by checking the Denver local hour. Scheduled runs
are often delayed under load, so the guard matches the local **hour**, not the
exact minute: a late run still fires, the wrong-offset run is still filtered.

## Debt registries, not permanent red

Three gates would be red from a standing start because the repository has real,
pre-existing drift. A permanently red job teaches people to ignore red, so each
records its current state in a committed registry and fails only when the set
**grows**:

| Registry | Currently | Meaning |
|---|--:|---|
| `scripts/ci/skip_baseline.json` | 13 reasons / 27 skips | approved test skips; a NEW reason fails |
| `scripts/ci/generator_debt.txt` | 7 | clean-checkout generators that no longer run |
| `scripts/ci/artifact_drift_debt.txt` | 10 | committed artifacts that do not reproduce from their own generator |
| `scripts/ci/data_hash_debt.txt` | 0 | in-scope inputs with no hash coverage |
| `scripts/ci/check_notes_baseline.txt` | 4 | accepted `R CMD check` NOTEs; a NEW one fails |

Every line in `artifact_drift_debt.txt` is an open scientific question, not a
formatting nit. `classifier_validation_external.csv`, for example, regenerates
with URPS n=499 against a committed 415. Shrink these by fixing the underlying
issue and deleting the line — never by adding a line to make CI pass.

## The completion sentinel

`scripts/ci/run_suite.R` writes `suite-completed.txt` only after `test_dir()`
returns, and a separate step asserts it exists. A `quit()`, segfault, OOM kill,
job timeout or reporter crash all leave it absent. Exit status alone cannot
distinguish "ran everything and passed" from "died before finishing", and the
suite pass count is deliberately **not** asserted — the suite may grow or shrink
on purpose. The invariants are: it finished, zero failures, and the skips are
the approved ones.

## Design notes

**No pak.** `pak` has failed repo-wide here (`there is no package called 'pak'`).
`use-public-rspm: true` points the default repo at Posit Package Manager, so
`install.packages()` pulls precompiled Linux binaries and `remotes` reads
`DESCRIPTION`. This is also why CI is minutes while a local restore is ~45
minutes: on Intel macOS a third of the lockfile compiles from source (duckdb
alone is 1802 `.cpp` files); on Ubuntu essentially all of it is prebuilt. See
`docs/APPENDIX_r_versions_and_build_time.md`.

**`error_on = "warning"`.** NOTEs are tolerated, WARNINGs are not. The package
carries two known NOTEs (NSE globals — issue #35; installed size — issue #36),
and failing on NOTE would make the gate meaningless rather than strict.

**Suggests are installed, but not required.** `_R_CHECK_FORCE_SUGGESTS_=false`
means one unavailable Suggest cannot fail the matrix, while the suite still runs
as fully as the runner allows.

**`CLIFF_ISOCHRONES_ROOT` is set empty on purpose.** 35 tests need the isochrones
monorepo and skip cleanly without it. Setting it explicitly makes a green run
mean "everything runnable ran", rather than depending on the variable happening
to be unset.

**The macOS acceptance gate is not run here.** `scripts/acceptance/run_gate.sh`
depends on `/Library/Frameworks`, `rig`, and Homebrew prefixes. `lockfile_restore`
tests the portable half — that `renv.lock` still restores into an empty library —
which is the part that actually rots.

## Running the checks locally

```sh
Rscript --no-init-file scripts/ci/check_pins.R            # pin agreement
Rscript --no-init-file scripts/ci/check_pins.R --upstream # + drift vs upstream
Rscript -e 'devtools::document()'                    # before pushing, if R/ changed
Rscript -e 'testthat::test_dir("tests/testthat")'    # ~85 s, 2960 assertions
SMOKELIB=<lib> Rscript scripts/smoke_installed_package.R
```

Both preflight guards also run inside the suite (`test-dependency-pins.R`), so a
push cannot pass locally and fail in CI on the same check.
