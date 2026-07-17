#!/usr/bin/env bash
# Renders this year's control-plane templates against a concrete install
# root. Everything the installer needs to reference directly -- Spack
# config and the init script -- is rendered into control space, not the
# install root, so running/using this year's stack never requires
# knowing or typing the install root path: only bootstrap.sh itself does,
# as its one argument.
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
# In all cases the placeholder @@SPACK_INSTALL_ROOT@@ is replaced with
# the literal install root given as this script's argument.
#
# Usage: control/<year>/bootstrap.sh <install-root-path>
#
# Idempotent: re-run after editing a template, adding a tier, or switching
# to a different install root (e.g. a new scratch disk) -- it just
# overwrites the previously rendered files for this year.
#
# This script reads control/<year>/ and writes under control/<year>/rendered/
# plus the given install root. It does not touch $HOME, /etc, or any other
# system path, and it does not invoke spack, clone anything, or install
# any software.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <install-root-path>" >&2
  exit 1
fi

install_root="$1"
year_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
year="$(basename "$year_dir")"
placeholder="@@SPACK_INSTALL_ROOT@@"
rendered_dir="$year_dir/rendered"

mkdir -p "$install_root"

# Spack config: rendered into control space, not the install root.
if [ -d "$year_dir/templates" ]; then
  find "$year_dir/templates" -type f | while IFS= read -r tmpl; do
    rel="${tmpl#"$year_dir/templates/"}"
    dst="$rendered_dir/$rel"
    mkdir -p "$(dirname "$dst")"
    sed "s|$placeholder|$install_root|g" "$tmpl" > "$dst"
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
    mkdir -p "$(dirname "$dst")"
    sed "s|$placeholder|$install_root|g" "$tmpl" > "$dst"
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
