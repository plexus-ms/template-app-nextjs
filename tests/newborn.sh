#!/bin/sh
# A newborn app passes its repo's own check: the Turborepo template is rendered as copier would
# render it for a new app repo, birth tasks included, this template is rendered into it as
# apps/<name>, once per profile, and the generated repo's own `mise run check` is run there
# (lint, then each project's check script). The app template renders the smallest app Next
# accepts, a layout, a page and the /healthz route, so what is checked is mostly its config:
# package.json, tsconfig.json, next.config.ts and the rest as biome, next typegen and tsc read
# them. This template's working tree is what is rendered, uncommitted changes included.
#
# The Turborepo template is the one that ships with this one at the same Plexus version: every
# versioned repo is tagged at once when a version is cut, so during development that is the
# forge's main, and its newest tag is a version behind. TURBO_TEMPLATE names another source, a
# sibling checkout or the one being cut; a local checkout is rendered as it stands (TURBO_REF
# defaults to HEAD there, to main on the forge).
#
#   tests/newborn.sh                                         # the forge's main around this tree
#   TURBO_TEMPLATE=../template-repo-turbo tests/newborn.sh   # a sibling checkout as it stands
#   TURBO_REF=0.122.1 tests/newborn.sh                       # a released version around it
#   KEEP=1 tests/newborn.sh                                  # leave the rendered repo in place
set -eu

# git runs a hook with GIT_DIR (and GIT_WORK_TREE) pointing at the pushing repository. Left set,
# the newborn's `git init` and copier's clones act on that repository instead of the scratch
# directory: from a linked worktree `git init` marks the shared repository bare.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)

here=$(cd "$(dirname "$0")/.." && pwd)
if [ -n "${TURBO_TEMPLATE:-}" ]; then
  turbo=$TURBO_TEMPLATE
  ref=${TURBO_REF:-HEAD}
else
  turbo=gh:plexus-ms/template-repo-turbo
  ref=${TURBO_REF:-main}
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/newborn.XXXXXX")
repo=$tmp/acme
if [ -n "${KEEP:-}" ]; then trap 'echo "kept: $repo"' EXIT; else trap 'rm -rf "$tmp"' EXIT; fi

echo "→ repo: render $turbo at $ref"
copier copy --quiet --defaults --trust --vcs-ref "$ref" -d tenant=acme "$turbo" "$repo"

for profile in stateless-app stateful-app; do
  echo "→ apps/$profile: render"
  copier copy --quiet --defaults --trust --vcs-ref HEAD \
    -d tenant=acme -d name="@acme/$profile" -d profile="$profile" "$here" "$repo/apps/$profile"
done

# The lockfile was written at the repo's birth, before the apps existed. An author who adds an app
# installs, which updates it; under CI=true the check's install is frozen and refuses a stale one.
echo "→ repo: lockfile"
(cd "$repo" && pnpm install --lockfile-only)

echo "→ repo: check"
(cd "$repo" && mise run check)

# plx doctor: the newborn's `plx doctor` goes here, once the released plx has the new doctor.

echo "✓ newborn"
