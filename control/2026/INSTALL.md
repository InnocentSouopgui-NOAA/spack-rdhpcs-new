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
`/scratch/spack-install`), determine this node's OS distro (run
`spack/bin/spack arch` — it prints something like `linux-rocky9-x86_64`;
the middle segment, e.g. `rocky9`, is the distro to pass below), then
render this year's config and generate its init script:

```
./bootstrap.sh rocky9 /scratch/spack-install
```

The distro matters for two things. First, Spack's Lmod modules always
land two-plus directories deeper than `roots.lmod` —
`<roots.lmod>/linux-<distro>-x86_64/Core/<pkg>/<version>.lua` (or deeper
still under the compiler/mpi hierarchy, see step 8) — and the
meta-modules need to know that path to point MODULEPATH at the right
place. (Assumes `linux`/`x86_64`; see the comment at the top of
`bootstrap.sh` if a future year runs on a different platform/target.)

Second, `bootstrap.sh` looks the distro up in `core-compilers.yaml`
(sitting alongside it, git-tracked) to fill in `modules.yaml`'s
`core_compilers` — the compiler whose builds are visible without loading
a compiler module first (see step 8). It fails loudly if the distro
isn't listed there; add a line like `rocky9: gcc@11.5` rather than
guessing.

`distro` is also the variable to build on later if different OSes ever
need different package/version choices in a tier — nothing does that
yet.

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
# annual
spack/bin/spack -C common/config -C rendered/instances/annual/spack-config \
  -e instances/annual/environment concretize

spack/bin/spack -C common/config -C rendered/instances/annual/spack-config \
  -e instances/annual/environment install
```

```
# H1 (only after annual has finished installing)
spack/bin/spack -C common/config -C rendered/instances/H1/spack-config \
  -e instances/H1/environment concretize

spack/bin/spack -C common/config -C rendered/instances/H1/spack-config \
  -e instances/H1/environment install
```

```
# Q1 (only after H1 has finished installing)
spack/bin/spack -C common/config -C rendered/instances/Q1/spack-config \
  -e instances/Q1/environment concretize

spack/bin/spack -C common/config -C rendered/instances/Q1/spack-config \
  -e instances/Q1/environment install
```

The slowest packages in each tier are currently **commented out** in the
tracked `environment/spack.yaml` files, for a fast first pass through all
three tiers: `ghostscript` (annual), `openmpi` (H1), and
`intel-oneapi-compilers`/`intel-oneapi-mpi`/`intel-oneapi-mkl`/`hdf5`/
`netcdf-c`/`netcdf-fortran` (Q1, leaving just `pmix`/`ucx`/`hwloc`
active). Once you've confirmed the mechanism works end to end with those
commented out, uncomment them (in `instances/<tier>/environment/spack.yaml`)
and re-run concretize + install for whichever tier(s) you changed. Budget
real time for that full `Q1` build — `intel-oneapi-compilers`,
`intel-oneapi-mpi`, and `intel-oneapi-mkl` are large downloads and slow
builds, well over an hour combined is plausible on a first run.

## 7. Generate Lmod modulefiles

Each tier's `modules.yaml` sets `exclude_implicits: true`, so only specs
listed explicitly in that tier's `environment/spack.yaml` get a
modulefile — not every transitive build/link dependency that happened to
get installed along with them. `--delete-tree` clears out that tier's
module root before regenerating, so if you'd already run `module lmod
refresh` before this setting was in place, any leftover modules for
implicit dependencies get removed too, not just skipped going forward.

Run once per tier, after that tier has finished installing:

```
# annual
spack/bin/spack -C common/config -C rendered/instances/annual/spack-config \
  -e instances/annual/environment module lmod refresh --delete-tree -y
```

```
# H1
spack/bin/spack -C common/config -C rendered/instances/H1/spack-config \
  -e instances/H1/environment module lmod refresh --delete-tree -y
```

```
# Q1
spack/bin/spack -C common/config -C rendered/instances/Q1/spack-config \
  -e instances/Q1/environment module lmod refresh --delete-tree -y
```

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

That last `module avail` will only show packages built with the
`core_compilers` compiler from `core-compilers.yaml` (e.g. the default
system GCC) — that's the point of the hierarchy config in `modules.yaml`.
Anything built with a different compiler (Intel OneAPI, a newer GCC
installed via Spack) or that depends on MPI won't show up until you load
*that* compiler's or MPI's own module first — e.g.
`module load gcc/13.2.0` reveals what was built with it,
`module load openmpi/4.1.6` (or `intel-oneapi-mpi/...`) reveals
MPI-linked packages on top of that.

## 9. Verify upstream reuse actually happened

Compare each tier's own install tree — `H1` shouldn't contain a second
copy of anything `annual` already built, and `Q1` shouldn't duplicate
anything from `H1`/`annual`:

```
spack/bin/spack -C common/config -C rendered/instances/<tier>/spack-config find
```

Cross-check against the install log from step 6 — reused specs are
reported as already installed rather than rebuilt.
