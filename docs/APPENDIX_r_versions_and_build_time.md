# Appendix: R versions, rig, and what a library rebuild actually costs

Companion to `scripts/acceptance/README.md`. This records what the R 4.5.3
acceptance gate for issue #37 cost in wall-clock time, why two of the three
attempts were destroyed by the environment rather than by the package, and the
operational rules that follow from it.

Every number here is measured from the run logs, not estimated, except where
explicitly labelled an extrapolation.

---

## 1. The machine

```
Intel(R) Core(TM) i5-1038NG7 CPU @ 2.00GHz
4 physical cores / 8 logical
x86_64-apple-darwin20, macOS Sequoia 15.7.3
```

This is the single most important fact in this document, and it is easy to
miss. CRAN's macOS binary coverage for R 4.5 on **x86_64 is thin** — the
platform is being wound down in favour of arm64. On an Apple Silicon machine
most of this lockfile would arrive as prebuilt binaries in a few minutes. Here,
a third of it compiles from source on four 2.0 GHz cores.

Nothing about cliff is slow. The combination of *this architecture*, *this R
version*, and *pinned versions that no longer match current CRAN binaries* is
slow.

---

## 2. Three attempts

| # | Started | Ended | Outcome |
|---|---|---|---|
| 1 | 01:49:09 | ~02:32 | Destroyed at 02:01 by an R 4.4.2 installer run |
| 2 | ~07:52 | ~08:51 | 6 package failures + duckdb worker timeout |
| 3 | 08:53:48 | 09:37:41 | **Complete — 43 min 53 s** |

Run 2's log was overwritten by run 3; its timings are as recorded during the
session rather than re-read from disk. Runs 1 and 3 are exact.

### Run 1 — the R interpreter was replaced mid-restore

Forty-three minutes in, the restore collapsed with 46 package failures whose
signature was:

```
Symbol not found: _ANY_ATTRIB   (referenced from rlang.so)
Symbol not found: _R_getVar     (referenced from Rcpp.so)
  Expected in: .../Versions/4.4-x86_64/Resources/lib/libR.dylib
```

`R_getVar` and `ANY_ATTRIB` are **R 4.5 additions**. Packages had been compiled
against 4.5 headers and were being loaded into a 4.4 process. The R
installation had changed underneath a running restore.

`renv::restore()` installs *packages*, not R, and the logs confirm it: zero
occurrences of `installer`, `rig`, `pkgutil`, `sudo`, `ln -s`, or
`Versions/Current` across 134 KB of output. The only `4.4` strings are dyld's
`Expected in:` lines — the symptom.

The cause was external, and macOS records it. `/Library/Receipts/InstallHistory.plist`
distinguishes the CLI `installer` tool from `Installer.app` by `processName`,
consistently across this machine's entire six-year R history:

```
2026-08-15 07:35:31Z | R 4.5.3 | processName='installer'   <- CLI
2026-08-15 08:01:32Z | R 4.4.2 | processName='Installer'   <- GUI, mid-restore
```

Both wrote the same payload, `org.R-project.x86_64.R.fw.pkg`.

### The finding that matters

**The CRAN macOS `.pkg` does not coexist with other R versions.** Installing
4.4.2 did two things: it repointed `Versions/Current`, *and* it removed the
4.5.3 tree. Afterwards:

```
/Library/Frameworks/R.framework/Versions/4.5-x86_64/
└── Resources/fontconfig/cache/        # 20 entries, all stale font caches
                                       # no bin/R, no libR.dylib
```

`rig list` no longer showed 4.5 at all. It was not deactivated; it was deleted.
The framework layout *looks* like it supports side-by-side versions — and it
does — but the installer does not honour that. Reinstalling any version is
destructive to the others.

---

## 3. Use rig, never an installer

```sh
rig add 4.5.3                # install alongside, non-destructively
rig default 4.5-x86_64       # switch
rig list                     # what is actually present
```

`rig add` registers the version so switching afterwards is a symlink change
rather than a package installation. That is the whole point: **the failure mode
above is only reachable by running an installer.** Once both versions are under
rig, switching cannot delete anything.

```
* name        version    aliases
  3.6         (R 3.6.3)
  4.2         (R 4.2.1)
  4.4-x86_64  (R 4.4.2)
* 4.5-x86_64  (R 4.5.3)
```

Two consequences worth internalising:

- **`rig list` is the source of truth for "is it installed".** A version
  directory can exist under `Versions/` and be an empty shell. rig filters
  those; `ls` does not.
- **Switching the default is global.** `rig default` changes R for every
  project on the machine, so a gate that needs 4.5.3 borrows the default from
  isochrones and mufflyaccess for its duration.

### The guard this produced

`assert_r()` in `run_gate.sh` now runs between **every** phase, printing the
running version and `readlink Versions/Current`, and aborting with exit 90 on
mismatch. Run 1 took 43 minutes to discover a flip that had happened at minute
12. The same flip is now a five-second diagnostic:

```
----- CHECKPOINT [after restore] -----
  R version 4.4.2 (2024-10-31) -- "Pile of Leaves"
  Versions/Current -> 4.4-x86_64
*** ABORT: R is no longer 4.5.3 at phase "after restore".
```

This is cheap and it is the highest-value line in the harness. Long runs must
verify their own preconditions continuously, not once at startup.

---

## 4. What the rebuild actually cost

Run 3, complete gate, cache disabled, `MAKEFLAGS=-j4`:

```
total wall clock                     43 min 53 s
  duckdb (pre-built, serial)         25 min 54 s     59% of the entire gate
  everything else                    ~18 min

packages restored                    209
  installed as binary                141
  compiled from source                66
sum of source-build time             80 min  (4 801 s)
```

Note the last two lines together: **80 minutes of compilation finished in 44
minutes of wall clock**, because renv installs in parallel. The parallelism is
real and it is doing heavy lifting.

### The long tail is very long

```
duckdb              1 560 s   ████████████████████████████████████████
stringi               660 s   █████████████████
Matrix                438 s   ███████████
sf                    198 s   █████
lme4                  126 s   ███
websocket             120 s   ███
httpuv                108 s   ██
RcppArmadillo          84 s   ██
eulerr                 84 s   ██
ragg                   78 s   ██
```

One package is 33% of all compilation. duckdb vendors the entire database
engine: **1 802 `.cpp` files**, and it is a hard `Imports:` dependency of cliff
(`R/infer_fellowship_training.R`, `R/freida_program_loader.R`), so it cannot be
scoped out of the gate.

### duckdb defeated renv twice before it was handled

Under renv's parallel installer, duckdb is killed by the per-worker timeout:

```
# duckdb ---------------------------------
worker process timed out
```

It failed this way in runs 1 and 2. In run 2 it was measured at ~5.9 objects
per minute single-threaded, having built roughly 340 of 1 802 objects in 58
minutes before being killed. Extrapolating gives **~5 hours**, and that figure
should be treated as rough — the rate varied between 5.9 and 14 objects/min as
translation-unit sizes changed.

The fix, in `restore.R`, is two lines of strategy rather than tuning:

1. **Pre-build duckdb in the main process**, before `renv::restore()`. No
   worker, no worker timeout. `restore()` then sees the pinned version
   satisfied and skips it.
2. **`MAKEFLAGS=-j4`.** Measured result: **25.9 minutes**, versus the ~5-hour
   single-threaded extrapolation.

---

## 5. Why the first clean run was slower than it needed to be

The renv cache was deliberately **disabled** for run 3:

```sh
RENV_CONFIG_CACHE_ENABLED=FALSE
RENV_CONFIG_INSTALL_SHORTCUTS=FALSE
```

This was correct for the question being asked. The acceptance question is *"does
this exact lockfile restore cleanly under R 4.5.3 from nothing?"* — and a cache
hit or a package borrowed from a user library answers a weaker question. With
both disabled, every one of the 66 source builds was genuinely performed.

It cost roughly 45 minutes, once. That was worth paying once and is not worth
paying again: no build for R 4.5.3 existed before run 3, so nothing could have
been reused anyway.

`run_gate.sh` therefore ships with the cache **enabled** by default. Set
`RENV_CONFIG_CACHE_ENABLED=FALSE` to reproduce the from-scratch experiment.

---

## 6. Toolchain: override surgically, never wholesale

Run 2 failed on 6 packages, all missing system headers:

| Package | Failure |
|---|---|
| Matrix, nlme, gdtools | `libintl.h` / `ld: library 'intl' not found` |
| svglite | `png.h` |
| gert | `git2.h` |
| RcppArmadillo | `/opt/gfortran/...` not found |

The first three groups are real gaps: CRAN's static toolchain at
`/opt/R/x86_64` ships no gettext, and R's Makeconf does not look in Homebrew.

**RcppArmadillo was self-inflicted.** The gate had suppressed `~/.R/Makevars`
entirely, on the reasonable principle that machine-specific compiler settings
must not influence an acceptance run. But that file mixes two different things:

```make
CC  = /usr/local/opt/llvm/bin/clang       # contaminant
CXX17FLAGS = -O3 -march=native            # contaminant

# Fortran — Homebrew GCC (overrides broken /opt/gfortran paths in R Makeconf)
FC    = /usr/local/bin/gfortran           # NECESSARY
FLIBS = -L/usr/local/lib/gcc/current ...  # NECESSARY
```

That comment is accurate: `/opt/gfortran` does not exist on this machine and
`/usr/local/lib/gcc/current` does. Blanket suppression removed a genuine
correction along with the contaminant, and broke a package that had built fine
the run before.

`Makevars.gate` keeps the fix, drops the contaminant, and adds the missing
library paths. One further subtlety:

```sh
export CPPFLAGS="-I/usr/local/opt/gettext/include ..."
export LDFLAGS="-L/usr/local/opt/gettext/lib ..."
```

**Makevars governs compilation; `./configure` scripts read the *environment*.**
This shell exports `CPPFLAGS=-I/usr/local/opt/llvm/include`, which would
otherwise leak past Makevars into every configure step. Both layers need
setting.

Result: run 3 restored **209 packages with zero failures**.

---

## 7. Operational rules

1. **Switch R with `rig default`. Never run an installer to change versions** —
   the CRAN `.pkg` deletes the version you are not installing.
2. **Do not touch the toolchain while a gate is running.** Runs 1 and 2 were
   both damaged by concurrent environment changes: an installer, then a `brew`
   upgrade of gdal/pkgconf mid-restore.
3. **Assert preconditions between phases, not once.** A precondition that can
   change during the run must be re-checked during the run.
4. **Override machine config surgically.** Read what you are suppressing; it
   may contain a fix as well as a contaminant.
5. **Budget realistically on x86_64**: ~45 minutes cold for this lockfile,
   minutes warm. duckdb alone is ~26 minutes at `-j4` and must be pre-built
   outside renv's worker.
6. **Preserve failures before changing anything.** All three runs were
   diagnosable afterwards because logs were kept and nothing was fixed forward
   mid-gate.

---

## 8. Result

```
R version 4.5.3 (2026-03-11) -- "Reassured Reassurer"
Platform: x86_64-apple-darwin20 · macOS Sequoia 15.7.3

restore                209 packages, 0 failures
tarball                cliff_0.1.0.tar.gz, 2.8 MB
installed tests        FAIL 0 · WARN 0 · SKIP 129 · PASS 94
smoke test             pass 11 · fail 0
R CMD check            1 ERROR · 0 WARNINGS · 1 NOTE   (SHA f7725b2)
                       0 ERRORs after the geosphere fix (0770abd)
```

**GenSA 1.1.15 — the reason issue #27 stayed open — installs as a plain binary
under R 4.5.3** (`262 kB in 0.22s`, no compilation), reproduced in both clean
runs. The premise that its pin cannot build on R ≥ 4.5 does not hold on 4.5.3.

The single ERROR was a genuine cliff defect that three years of green test runs
had never surfaced: `geosphere` was a `Suggests` dependency absent from
`renv.lock`, and three exported functions called it unconditionally in their
examples. It was invisible until a library was built from nothing — which is
the entire argument for this gate existing.
