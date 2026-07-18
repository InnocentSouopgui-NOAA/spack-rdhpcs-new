#!/usr/bin/env bash
# Renders this year's control-plane templates against a concrete OS
# distro and install root. Everything the installer needs to reference
# directly -- Spack config and the init script -- is rendered into
# control space, not the install root, so running/using this year's
# stack never requires knowing or typing the install root path: only
# bootstrap.sh itself does, as an argument.
#
# This script is git-tracked control-plane tooling, isolated per year
# (control/<year>/bootstrap.sh, not a shared control/bootstrap.sh) -- so
# its behavior (like spack/ and meta/) is free to change incompatibly
# from one year to the next. The year itself is inferred from its own
# location (one level up), not passed as an argument.
#
# Three things get rendered, with different output rules:
#
#   templates/...  ->  control/<year>/rendered/...
#     (Spack config: config.yaml, upstreams.yaml, modules.yaml. Lives in
#     control space -- generated, not hand-edited, and gitignored -- so
#     `spack -C control/<year>/rendered/instances/<tier>/spack-config`
#     is a path you already know, with the actual install root baked into
#     its *contents* rather than something you pass on the command line.)
#
#   (init script)  ->  control/<year>/rendered/bin/init.sh
#     (Same reasoning: `source control/<year>/rendered/bin/init.sh` sets
#     SPACK_DISABLE_LOCAL_CONFIG and SPACK_USER_CACHE_PATH -- namespaced
#     per year, so a different year's Spack version never shares a
#     bootstrap store with this one -- without you ever typing the
#     install root.)
#
#   meta/templates/<tier>.lua  ->  <install-root>/modules/meta/<year>/<tier>.lua
#     (Lmod meta-modules stay install-root side -- this is what Lmod's
#     `module use <install-root>/modules/meta` points at, a stable path
#     that doesn't move between years so `module load <year>/<tier>`
#     keeps resolving the way Lmod expects. This one's for end users
#     loading modules, not for the installer, so it isn't in scope for
#     "never type the install root" the way the two above are.)
#
# Three placeholders get substituted in every rendered file:
#   @@SPACK_INSTALL_ROOT@@  ->  the install root given as this script's
#                               2nd argument
#   @@SPACK_LMOD_ARCH@@     ->  linux-<distro>-x86_64, built from the
#                               distro given as this script's 1st
#                               argument. Spack's Lmod modules always land
#                               two-plus directories deeper than
#                               `roots.lmod`
#                               (<roots.lmod>/<arch>/Core/<pkg>/<ver>.lua>,
#                               or deeper still under a compiler/mpi
#                               hierarchy) -- our meta-modules need to
#                               know that <arch> segment to point
#                               MODULEPATH at the right place. Assumes
#                               platform=linux and target=x86_64; if a
#                               future year runs on a different
#                               platform/target, that assumption is the
#                               one line to change below (`lmod_arch=...`).
#   @@SPACK_CORE_COMPILER@@ ->  the compiler spec looked up for this
#                               distro in core-compilers.yaml (e.g.
#                               `gcc@11.5` for `rocky9`). Used by
#                               modules.yaml's `core_compilers` so that
#                               only builds made with this compiler are
#                               visible without loading a compiler module
#                               first -- see the README's "Modules"
#                               section. Fails loudly if the distro isn't
#                               listed there; add an entry rather than
#                               guessing.
#
# The distro argument is also expected to matter beyond these two fixes
# later: if different OSes end up needing different package/version
# choices in a given tier, that's the variable this plumbs through --
# nothing does that yet.
#
# Usage: control/<year>/bootstrap.sh <distro> <install-root-path>
#   e.g. control/2026/bootstrap.sh rocky9 /scratch/spack-install
#
# Idempotent: re-run after editing a template, adding a tier, or switching
# to a different distro/install root -- it just overwrites the previously
# rendered files for this year.
#
# This script reads control/<year>/ and writes under control/<year>/rendered/
# plus the given install root. It does not touch $HOME, /etc, or any other
# system path, and it does not invoke spack, clone anything, or install
# any software.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <distro> <install-root-path>" >&2
  echo "  e.g. $0 rocky9 /scratch/spack-install" >&2
  exit 1
fi

distro="$1"
install_root="$2"
year_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
year="$(basename "$year_dir")"
install_root_placeholder="@@SPACK_INSTALL_ROOT@@"
lmod_arch_placeholder="@@SPACK_LMOD_ARCH@@"
core_compiler_placeholder="@@SPACK_CORE_COMPILER@@"
lmod_arch="linux-${distro}-x86_64"
rendered_dir="$year_dir/rendered"

core_compilers_file="$year_dir/core-compilers.yaml"
if [ ! -f "$core_compilers_file" ]; then
  echo "no core-compilers.yaml at $core_compilers_file" >&2
  exit 1
fi
core_compiler="$(grep -E "^${distro}:" "$core_compilers_file" | sed -E 's/^[^:]+:[[:space:]]*//' | head -1 || true)"
if [ -z "$core_compiler" ]; then
  echo "no core compiler defined for distro '$distro' in $core_compilers_file" >&2
  echo "add a line like '$distro: gcc@11.5' there" >&2
  exit 1
fi

render() {
  # render <src> <dst>: substitute all placeholders, write result.
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  sed \
    -e "s|$install_root_placeholder|$install_root|g" \
    -e "s|$lmod_arch_placeholder|$lmod_arch|g" \
    -e "s|$core_compiler_placeholder|$core_compiler|g" \
    "$src" > "$dst"
}

mkdir -p "$install_root"

# common/config/ is where `spack compiler find` writes compilers.yaml
# (see INSTALL.md) -- it's gitignored (host-specific) so a fresh clone
# never has it, and spack needs the directory to already exist to use it
# as a -C config scope at all. Create it here so it's ready right after
# bootstrapping, before compilers are ever registered.
mkdir -p "$year_dir/common/config"

# Spack config: rendered into control space, not the install root.
if [ -d "$year_dir/templates" ]; then
  find "$year_dir/templates" -type f | while IFS= read -r tmpl; do
    rel="${tmpl#"$year_dir/templates/"}"
    render "$tmpl" "$rendered_dir/$rel"
    echo "rendered rendered/$rel"
  done
fi

# Meta-modules: flatten into <install-root>/modules/meta/<year>/<file>,
# regardless of how the meta/ tree itself is organized internally. This
# one stays install-root side -- see header comment for why.
if [ -d "$year_dir/meta/templates" ]; then
  find "$year_dir/meta/templates" -type f | while IFS= read -r tmpl; do
    name="$(basename "$tmpl")"
    dst="$install_root/modules/meta/$year/$name"
    render "$tmpl" "$dst"
    echo "rendered modules/meta/$year/$name"
  done
fi

# Init script: also rendered into control space -- source this before
# running spack or module commands against this year.
init_script="$rendered_dir/bin/init.sh"
mkdir -p "$(dirname "$init_script")"
cat > "$init_script" <<EOF
# Source this before running spack or module commands against the $year
# tier of this stack. Do not execute it directly -- it only takes effect
# in the shell that sources it:
#   source $init_script
export SPACK_DISABLE_LOCAL_CONFIG=1
export SPACK_USER_CACHE_PATH="$install_root/$year/user-cache"
EOF
echo "wrote rendered/bin/init.sh"
