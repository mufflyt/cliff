# Acceptance gate

Proves that cliff, at a frozen SHA, restores its lockfile, builds, installs,
tests and checks cleanly under a target R — in **genuinely fresh libraries**,
not the developer's.

```sh
scripts/acceptance/run_gate.sh                    # HEAD, R 4.5.3
CLIFF_GATE_R=4.4.2   scripts/acceptance/run_gate.sh
CLIFF_GATE_SHA=abc123 scripts/acceptance/run_gate.sh
CLIFF_GATE_WORK=~/scratch/gate scripts/acceptance/run_gate.sh
```

Exit codes: `90` R version changed mid-run · `91` gate Makevars vanished ·
`92` wrong SHA · `93` dirty tree · `94` restore failed · `95` no tarball ·
`96` work dir inside the repo.

## Why it exists

`devtools::load_all()` sees the whole repository. An installed package sees only
what was shipped and what the lockfile provides. Nearly every defect this gate
has caught lives in that gap, and none were visible to the 2,900-test suite:

- Two exported functions called five helpers that were never carried over from
  the isochrones extraction.
- Package code lived in `R/` that could only ever run from a source checkout.
- `haversine_distance`'s example called a **Suggests** package unconditionally,
  and `geosphere` was missing from `renv.lock`. A clean restore never installed
  it, so `R CMD check` failed with 1 ERROR. It passed for years on machines that
  happened to have geosphere installed.

## What the phases prove

| Phase | Proves |
|---|---|
| 1 | The SHA under test is exactly what is claimed, tree clean |
| 2 | The lockfile restores from nothing under the target R |
| 3–4 | The tarball builds and installs into a library that never saw the repo |
| 5 | Examples and tests pass against the *installed* package |
| 6 | cliff loads without `data.table`, `sf`, `tidycensus`, `tigris`, `geosphere`, and geosphere-dependent functions fail with their intended message |
| 7 | `R CMD check` counts |

## Two ways the environment breaks the gate

Both cost an hour before being understood. The script now guards both.

**Switching R with an installer.** The CRAN macOS `.pkg` does not coexist with
other versions: installing 4.4.2 repointed `Versions/Current` *and* deleted the
4.5.3 tree, mid-restore. Packages compiled against 4.5 headers then failed to
load into a 4.4 process (`Symbol not found: _ANY_ATTRIB`) — 46 cascading
failures that looked like package incompatibilities and were not.

> Switch R with `rig default <version>`. Never run an installer during a gate.
> `assert_r()` now runs between every phase, so a flip is a five-second
> diagnostic.

**Suppressing `~/.R/Makevars` wholesale.** That file mixes a contaminant
(Homebrew clang, `-march=native`) with a necessary fix (R's Makeconf points
Fortran at `/opt/gfortran`, which does not exist on this machine). Dropping both
broke RcppArmadillo. `Makevars.gate` keeps the fix, drops the contaminant, and
adds the gettext/libpng/libgit2/cairo paths CRAN's toolchain does not provide.
Note that `CPPFLAGS`/`LDFLAGS` must **also** be exported: Makevars covers
compilation, but `./configure` scripts read the environment.

Neither `~/.R/Makevars` nor the repository is modified by this script.

## Notes

- `duckdb` is 1802 `.cpp` files. Under renv's parallel installer it is killed by
  the per-worker timeout, so `restore.R` pre-builds it in the main process
  (~26 min at `-j4`; ~5 hours at `-j1`).
- The renv cache is left **enabled**. It was disabled once to prove the lockfile
  restores from nothing, which cost ~45 minutes of recompilation; set
  `RENV_CONFIG_CACHE_ENABLED=FALSE` to reproduce that experiment.
- This Mac is Intel x86_64, where CRAN's R 4.5 binary coverage is thin, so most
  of the lockfile compiles from source. A first run is hours; cached reruns are
  minutes.
