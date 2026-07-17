# Standing up 2026

Step-by-step runbook for bringing up this year's tier of the stack on a
target machine (an HPC node/login node — not a dev laptop; this was
written after a config-only dry run on a laptop that has neither the
target Lmod install nor is meant to run real builds). Read
`../../README.md` first for the architecture this is executing against;
this doc is the "do these things in this order" companion to it, scoped
to 2026 specifically — next year's `control/2027/INSTALL.md` may look
different if the process changes along with the Spack/meta versions.

Prerequisite check on the target machine before starting: `python3`,
a working C/C++/Fortran compiler toolchain, `git`, and **Lmod** (not
classic Environment Modules — run `module --version`; Lmod prints
something like `Modules based on Lua: Version 8.x`, classic Environment
Modules prints `Modules Release X.Y.Z`). If the target's `module` command
turns out to be classic Environment Modules, the meta-modules in this
stack (Lua, `prepend_path`-based) won't necessarily load correctly and
that needs resolving before step 8 below.

## 1. Move into this year's control directory

Every command below assumes you're sitting in `control/2026/` — that's
what keeps the rest of this runbook to short, relative paths instead of
repeating `control/2026/...` on every line:

```
cd control/2026
```

(paths in this doc are all relative to here unless written as an absolute
path, like the install root itself)

## 2. Clone Spack

Pins the version boundary for 2026 — check Spack's repo for whatever its
current latest release branch is rather than assuming a specific version:

```
git clone --depth 1 --branch <latest-release-branch> https://github.com/spack/spack.git spack
```

## 3. Pick an install root and bootstrap

Pick a path on scratch storage for this year's install root (e.g.
`/scratch/spack-install`), then render this year's config and generate
its init script:

```
./bootstrap.sh /scratch/spack-install
```

This writes:
- `rendered/instances/<tier>/spack-config/{config.yaml,upstreams.yaml,modules.yaml}`
- `rendered/bin/init.sh`
- `/scratch/spack-install/modules/meta/2026/<tier>.lua`

It also creates an empty `common/config/` directory — gitignored, so a
fresh clone never has it, but Spack needs it to exist before it can be
used as a `-C` config scope at all (step 5 writes `compilers.yaml` into
it).

Note where each lands: the Spack config and init script go into **control
space** (`rendered/`, i.e. `control/2026/rendered/`), not the install
root — so every command below references a path you already know, with
the actual `/scratch/spack-install` location baked into those files'
*contents* rather than something you type yourself. Only the meta-modules
stay install-root side, since that's what Lmod's `module use` needs to
point at directly (step 8).

Re-run `./bootstrap.sh` any time a template under `templates/` or
`meta/templates/` changes, or if you move to a different install root —
it's idempotent and only touches this year's rendered output, never
another year's. `bootstrap.sh` itself is git-tracked control-plane
tooling; everything under `rendered/` is not (it's gitignored) —
regenerated output, not something to hand-edit or commit.

## 4. Source the init script

```
source rendered/bin/init.sh
```

Do this in every shell you use for the remaining steps. It sets
`SPACK_DISABLE_LOCAL_CONFIG=1` and `SPACK_USER_CACHE_PATH` so nothing
Spack does touches `~/.spack` — this is the one manual step left; nothing
else in this runbook requires remembering an environment variable, or the
install root path, by hand.

## 5. Register compilers

Writes into 2026's shared scope instead of `~/.spack/compilers.yaml`:

```
spack/bin/spack -C common/config compiler find
```

Confirm it found something before moving on (`cat
common/config/compilers.yaml`) — an empty result usually means the
compiler prerequisite above isn't actually on `PATH`.

## 6. Concretize and install, one tier at a time, in dependency order

**Do not concretize all three tiers before installing any of them.**
Upstream reuse is decided *at concretize time*, and only by looking at
what's already **installed** upstream — a tier that's merely concretized
but not yet installed doesn't count. If `H1`/`annual` aren't installed
yet when `Q1` concretizes, `Q1`'s concretizer has nothing upstream to
reuse and resolves independently; since that result gets locked into
`Q1`'s `spack.lock`, a later `install` won't retroactively pick up
packages that became available upstream in the meantime. Concretizing
ahead of installing is still useful as a quick syntax/spec sanity check
(it's fast, no downloading/building) — just re-run `concretize` for a
downstream tier immediately before its `install`, once its upstream
actually has installed packages.

So: concretize then install `annual`, only then concretize then install
`H1`, only then concretize then install `Q1`:

```
spack/bin/spack -C common/config -C rendered/instances/<tier>/spack-config \
  -e instances/<tier>/environment concretize

spack/bin/spack -C common/config -C rendered/instances/<tier>/spack-config \
  -e instances/<tier>/environment install
```

`annual` (cmake, ghostscript, doxygen, universal-ctags) and `H1`
(git-lfs, openmpi) should both be quick. `Q1` is the one to budget real
time for: `intel-oneapi-compilers`, `intel-oneapi-mpi`, and
`intel-oneapi-mkl` are large downloads and slow builds — well over an
hour combined is plausible on a first run. If you just want to confirm
the mechanism works before committing to that wait, temporarily comment
those three plus `hdf5`/`netcdf-c`/`netcdf-fortran` out of
`instances/Q1/environment/spack.yaml`, confirm `pmix`/`ucx`/`hwloc`
install cleanly, then restore the full list and re-run — `Q1`'s
concretize step still catches a config/spec typo in seconds, before any
of that build time is spent, since it's the last thing to run in this
step, not the first.

## 7. Generate Lmod modulefiles

Safe to run regardless of whether Lmod itself is confirmed working yet —
it only writes text files:

```
spack/bin/spack -C common/config -C rendered/instances/<tier>/spack-config \
  -e instances/<tier>/environment module lmod refresh -y
```

Run this once per tier, same as install.

## 8. Wire up the meta-modules and try loading

One-time, on the target system's Lmod init (e.g. a profile.d script) —
this one's an absolute, install-root path regardless of where you're
`cd`'d to:

```
module use /scratch/spack-install/modules/meta
```

Then:

```
module avail        # should show 2026/annual, 2026/H1, 2026/Q1
module load 2026/Q1
module avail         # should now also list Q1/H1/annual's actual packages
```

## 9. Verify upstream reuse actually happened

Compare each tier's own install tree — `H1` shouldn't contain a second
copy of anything `annual` already built, and `Q1` shouldn't duplicate
anything from `H1`/`annual`:

```
spack/bin/spack -C common/config -C rendered/instances/<tier>/spack-config find
```

Cross-check against the install log from step 6 — reused specs are
reported as already installed rather than rebuilt.
