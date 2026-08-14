# cliff — working notes

## Searching for a "missing" generator

**Search isochrones' git HISTORY, not its working tree.** cliff was extracted from
the isochrones monorepo, and the extraction carried artifact OUTPUTS across without
the code that produces them. Many generators exist only in isochrones history: they
are not in `~/isochrones/scripts/` today, and `find`/`ls`/`grep` over the working
tree will report them as absent.

I concluded "this artifact has no generator" three times in one session and was
wrong all three times:

| Claim | Reality |
|---|---|
| `build_audit_table.R` — none | isochrones branch `fix/workforce-cliff-data-contract` |
| `feminization_sensitivity.R` — none | isochrones commit `0d8fa3662` |
| "0 of 22 artifacts recoverable" | **19 of 22** were recoverable |

The first two searched the working tree. The third also used an over-restrictive
history scan (only the first 25 commits touching each name, with a fragile inner
loop), which produced a confident, wholly false "NONE IN ISOCHRONES" for every
row — including two generators I had *already verified by hand* minutes earlier.

### The method that actually works

Materialise the latest version of every script that ever existed under
`scripts/`, then grep the corpus once per target:

```sh
cd ~/isochrones
git log --all --name-only --format="" -- 'scripts/*.R' 'scripts/**/*.R' \
  | grep -E '^scripts/.*\.R$' | sort -u > /tmp/allscripts.txt

mkdir -p /tmp/corpus
for p in $(cat /tmp/allscripts.txt); do
  c=$(git log --all --format=%H -1 -- "$p")
  [ -n "$c" ] && git show "$c:$p" > "/tmp/corpus/$(echo $p | tr '/' '_')"
done                                   # ~978 scripts

grep -lE "write[._]csv\([^)]*TARGET\.csv" /tmp/corpus/*
```

Grep for a **write** of the file (`write_csv(...)`/`write.csv(...)`), not a mention
— tests, handoff notes and READMEs mention artifacts constantly without producing
them, and `non_op_anchored` turned out to appear only in tests, never in any
generator.

Corroborating evidence lives in `~/isochrones/docs/HANDOFF_*.md`, which names
generators per artifact. If a handoff names a script, it exists; believe the
handoff over a failed search.

### Before declaring anything unrecoverable

Say "I did not find it with method X", not "it does not exist". A false "no
generator" is expensive here: it sends the user to look for something that is
already on disk, and it invites hand-editing an artifact that could have been
regenerated.

## Porting a recovered generator

Three changes, every time:

1. `here::here("cliff", "data", X)` → `here::here("data", X)` — this **is** cliff now.
2. Hardcoded `/Users/.../isochrones/...` inputs → resolve under
   `CLIFF_ISOCHRONES_ROOT` (and `CLIFF_URPS_SNAPSHOT` for the v3.0.0 parquet),
   failing loudly when absent. Never let a generator silently rebuild on whatever
   happens to be there.
3. Re-base the URPS cohort. Rebuilding it from the ABU rosters gives
   1,031 + 302 = **1,333**, not 1,306: it keeps the 4 providers the v3.0.0
   `active_2023` gate drops and excludes only 6 ABU NPIs for a missing
   certification year where the snapshot excludes 29 — exactly the
   `consort_cohort_flow` removals. Take active ages from
   `scripts/urps_scenario_cube/urps_cohort_ages_pathway_geo_v3.0.0.csv`, or the
   physician-level snapshot when you need NPIs or sex. Assert against
   `mufflyaccess::urps_count()` rather than the literal 1306, which the
   `no-unqualified-urps-baseline` guard will otherwise flag.

GO keeps the monorepo cohort — its 1,052 already matches the SSOT.

## Not everything must reconcile to the headline

`feminization_sensitivity.csv` is deliberately ABOG-pathway only (sex is
ascertainable only for the ABOG cohort; entrants are the 48 OB/GYN-sponsored
fellows, not 64), and the supplement says so. A guard demanding it match the
headline ratio was wrong. Read the surrounding prose before asserting an
artifact should reconcile.

## Verify by rendering

`rmarkdown::render()` catches what parsing and unit tests cannot. A helper named
`cf()` passed 2,853 unit tests while the supplement could not render at all,
because the supplement binds `cf` to a data.frame sixty lines below the setup
chunk. Rendering also surfaced two stale artifacts no test was checking.
`CLIFF_RENDER_TESTS=1` enables the render gate.

## Do not mutate tracked files with `git checkout --` to restore

A mutation-test script that reverted with `git checkout -- <file>` destroyed
uncommitted work in the same run. Copy the file aside and copy it back.
