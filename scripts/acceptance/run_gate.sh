#!/bin/bash
# Acceptance gate: prove that this repository, at a frozen SHA, restores its
# lockfile, builds, installs, tests and checks cleanly under a target R.
#
# Usage:
#   scripts/acceptance/run_gate.sh                  # HEAD, R 4.5.3
#   CLIFF_GATE_R=4.4.2 scripts/acceptance/run_gate.sh
#   CLIFF_GATE_SHA=abc1234 scripts/acceptance/run_gate.sh
#
# Work directory (libraries, tarball, check output) defaults to a temp dir and
# is NEVER inside the repo: the gate builds a tarball from the working tree, so
# anything it writes there would end up inside the artefact under test.
#   CLIFF_GATE_WORK=/path/to/scratch scripts/acceptance/run_gate.sh
#
# ---------------------------------------------------------------------------
# Why this script is shaped the way it is (2026-08-15):
#
# Three runs were needed to get a clean result, and two were destroyed by the
# environment rather than by the package:
#
#   1. R 4.4.2 was reinstalled via Installer.app 12 minutes into a 43-minute
#      restore. The CRAN .pkg does not coexist with other versions: it repointed
#      Versions/Current AND deleted the 4.5.3 tree. Packages compiled against
#      4.5 headers then failed to load into a 4.4 process
#      ("Symbol not found: _ANY_ATTRIB"), producing 46 cascading failures that
#      looked like package incompatibilities and were not.
#      => assert_r() now runs between EVERY phase. A version flip is a
#         five-second diagnostic instead of an hour-long mystery.
#      => switch R with `rig default`, never by running an installer.
#
#   2. ~/.R/Makevars was suppressed wholesale to keep machine-specific compiler
#      settings out of the run. Too blunt: that file holds a contaminant
#      (Homebrew clang, -march=native) AND a necessary fix (R's Makeconf points
#      Fortran at /opt/gfortran, which does not exist here). Dropping both broke
#      RcppArmadillo.
#      => Makevars.gate keeps the fix, drops the contaminant, and adds the
#         gettext/libpng/libgit2/cairo paths CRAN's toolchain does not provide.
#
# Neither ~/.R/Makevars nor the repo is modified by this script.
# ---------------------------------------------------------------------------

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
WANT="${CLIFF_GATE_R:-4.5.3}"
SHA="${CLIFF_GATE_SHA:-$(git -C "$REPO" rev-parse HEAD)}"
GATE="${CLIFF_GATE_WORK:-${TMPDIR:-/tmp}/cliff-gate-$$}"

case "$GATE" in
  "$REPO"|"$REPO"/*)
    echo "*** ABORT: work dir must not be inside the repo ($GATE)."
    echo "*** The gate builds a tarball from the working tree."
    exit 96 ;;
esac
mkdir -p "$GATE"
export GATE REPO WANT                         # restore.R reads these
export CLIFF_GATE_R="$WANT"

# Targeted compiler override; see the header. ~/.R/Makevars is left alone.
export R_MAKEVARS_USER="$SCRIPT_DIR/Makevars.gate"
export MAKEFLAGS="${MAKEFLAGS:--j4}"           # duckdb is 1802 .cpp files

# Makevars covers compilation, but ./configure scripts read these from the
# ENVIRONMENT, so an exported Homebrew-LLVM CPPFLAGS would leak past Makevars.
export CPPFLAGS="-I/usr/local/opt/gettext/include -I/usr/local/opt/libpng/include -I/usr/local/opt/libgit2/include -I/usr/local/opt/cairo/include -I/opt/R/x86_64/include"
export LDFLAGS="-L/usr/local/opt/gettext/lib -L/usr/local/opt/libpng/lib -L/usr/local/opt/libgit2/lib -L/usr/local/opt/cairo/lib -L/opt/R/x86_64/lib"

# The cache is left ENABLED. It was disabled for the first clean run to prove
# the lockfile restores from nothing; that cost ~45 minutes of recompilation.
# Now that a build exists for this R, reuse makes reruns minutes. Set
# RENV_CONFIG_CACHE_ENABLED=FALSE to reproduce the from-scratch experiment.
export RENV_CONFIG_CACHE_ENABLED="${RENV_CONFIG_CACHE_ENABLED:-TRUE}"
export RENV_CONFIG_INSTALL_SHORTCUTS="${RENV_CONFIG_INSTALL_SHORTCUTS:-FALSE}"
export RENV_CONFIG_AUTOLOADER_ENABLED=FALSE

DEPLIB="$GATE/deplib"; PKGLIB="$GATE/pkglib"; SMOKELIB="$GATE/smokelib"

assert_r() {
  local phase="$1" ver cur
  ver=$(R --version 2>/dev/null | head -1)
  cur=$(readlink /Library/Frameworks/R.framework/Versions/Current 2>/dev/null)
  printf '\n----- CHECKPOINT [%s] -----\n  %s\n  Versions/Current -> %s\n' \
         "$phase" "$ver" "$cur"
  if ! printf '%s' "$ver" | grep -q "$WANT"; then
    printf '\n*** ABORT: R is no longer %s at phase "%s".\n' "$WANT" "$phase"
    printf '*** Something outside this script changed the active R.\n'
    printf '*** Use `rig default`, not an installer. Not fixing forward.\n'
    date; exit 90
  fi
  if [ ! -e "$R_MAKEVARS_USER" ]; then
    printf '\n*** ABORT: %s vanished; gate Makevars no longer in effect.\n' "$R_MAKEVARS_USER"
    exit 91
  fi
}

banner() { printf '\n\n============================================================\n== %s\n============================================================\n' "$1"; }

date
banner "PHASE 0  environment"
echo "repo                 = $REPO"
echo "work dir             = $GATE"
echo "target R             = $WANT"
echo "R_MAKEVARS_USER      = $R_MAKEVARS_USER   (exists: $([ -e "$R_MAKEVARS_USER" ] && echo YES || echo NO-BAD))"
echo "MAKEFLAGS            = $MAKEFLAGS"
echo "RENV_CONFIG_CACHE_ENABLED     = $RENV_CONFIG_CACHE_ENABLED"
echo "RENV_CONFIG_INSTALL_SHORTCUTS = $RENV_CONFIG_INSTALL_SHORTCUTS"
echo "command -v R         = $(command -v R)"
echo "R RHOME              = $(R RHOME)"
echo "--- gate Makevars (~/.R/Makevars is NOT modified) ---"
grep -vE '^\s*#|^\s*$' "$R_MAKEVARS_USER" | sed 's/^/    /'
echo "--- ~/.R/Makevars md5, unchanged by this script: $(md5 -q ~/.R/Makevars 2>/dev/null || echo none) ---"
command -v rig >/dev/null && rig list 2>/dev/null | grep -v RIG
assert_r "start"

banner "PHASE 1  frozen SHA and clean tree"
cd "$REPO" || exit 1
HEAD_NOW=$(git rev-parse HEAD)
echo "HEAD:     $HEAD_NOW"
echo "expected: $SHA"
[ "$HEAD_NOW" = "$SHA" ] || { echo "*** ABORT: HEAD is not the frozen SHA."; exit 92; }
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
echo "uncommitted files: $DIRTY"
[ "$DIRTY" = "0" ] || { echo "*** ABORT: working tree is dirty."; git status --porcelain; exit 93; }
echo "MATCH, clean"

banner "PHASE 2  fresh dependency library + restore"
rm -rf "$DEPLIB"; mkdir -p "$DEPLIB"
echo "deplib entries before: $(ls -A "$DEPLIB" | wc -l | tr -d ' ')"
R_LIBS_SITE="" R_LIBS_USER="$DEPLIB" Rscript --vanilla "$SCRIPT_DIR/restore.R" 2>&1
RESTORE_RC=$?
echo "restore exit: $RESTORE_RC"
assert_r "after restore"
[ $RESTORE_RC -eq 0 ] || { echo "*** ABORT: restore failed (rc=$RESTORE_RC). Preserved, not fixed."; exit 94; }

banner "PHASE 3  build the tarball"
cd "$REPO" || exit 1
R_LIBS_USER="$DEPLIB" R CMD build --no-build-vignettes . 2>&1 | tail -20
TARBALL=$(ls -t "$REPO"/cliff_*.tar.gz 2>/dev/null | head -1)
[ -n "$TARBALL" ] || { echo "*** ABORT: no tarball produced."; exit 95; }
mv "$TARBALL" "$GATE/" && TARBALL="$GATE/$(basename "$TARBALL")"
echo "tarball: $TARBALL  ($(du -h "$TARBALL" | cut -f1))  [moved out of the repo]"
assert_r "after build"

banner "PHASE 4  install the tarball into a SECOND fresh library"
rm -rf "$PKGLIB"; mkdir -p "$PKGLIB"
R_LIBS_USER="$DEPLIB" R CMD INSTALL --library="$PKGLIB" "$TARBALL" 2>&1 | tail -25
echo "install exit: $?"
assert_r "after install"

banner "PHASE 5  examples + installed-package tests"
R_LIBS_USER="$DEPLIB" Rscript --vanilla -e "
  .libPaths(c('$PKGLIB', '$DEPLIB'))
  cat('--- examples ---\n')
  r <- try(tools::testInstalledPackage('cliff', types='examples', lib.loc='$PKGLIB', outDir=tempdir()))
  cat('examples result:', if (inherits(r,'try-error')) 'ERROR' else r, '\n')
  cat('--- tests ---\n')
  r2 <- try(tools::testInstalledPackage('cliff', types='tests', lib.loc='$PKGLIB', outDir=tempdir()))
  cat('tests result:', if (inherits(r2,'try-error')) 'ERROR' else r2, '\n')
" 2>&1 | tail -40
assert_r "after examples/tests"

banner "PHASE 6  constrained SMOKELIB smoke test"
# These five must be ABSENT: the smoke test proves cliff loads and its core
# helpers work without them, and that geosphere-dependent functions fail with
# their intended message rather than "could not find function".
rm -rf "$SMOKELIB"; mkdir -p "$SMOKELIB"
for d in "$DEPLIB"/*/ "$PKGLIB"/*/; do
  b=$(basename "$d")
  case "$b" in data.table|sf|tidycensus|tigris|geosphere) continue ;; esac
  ln -s "${d%/}" "$SMOKELIB/$b" 2>/dev/null
done
echo "SMOKELIB entries: $(ls -A "$SMOKELIB" | wc -l | tr -d ' ')"
for p in data.table sf tidycensus tigris geosphere; do
  printf '  %-12s present in SMOKELIB: %s\n' "$p" "$([ -e "$SMOKELIB/$p" ] && echo YES-BAD || echo no)"
done
SMOKELIB="$SMOKELIB" Rscript --vanilla "$REPO/scripts/smoke_installed_package.R" 2>&1 | tail -40
echo "smoke exit: $?"
assert_r "after smoke"

banner "PHASE 7  R CMD check"
cd "$GATE" || exit 1
rm -rf "$GATE/chklib"; mkdir -p "$GATE/chklib"
R_LIBS_USER="$DEPLIB" _R_CHECK_FORCE_SUGGESTS_=false \
  R CMD check --no-manual --library="$GATE/chklib" "$TARBALL" 2>&1 | tail -60
assert_r "after check"

banner "PHASE 8  final environment report"
R_LIBS_USER="$DEPLIB" Rscript --vanilla -e "
  .libPaths(c('$PKGLIB','$DEPLIB'))
  cat(R.version.string, '\n\n'); print(sessionInfo())
" 2>&1
echo; echo "SHA tested: $SHA"
date
banner "GATE COMPLETE"
