#!/bin/sh
# A newborn app passes its repo's own check: this working tree, uncommitted changes included, is
# rendered once per profile into a newborn of the Turborepo template, whose `mise run check` runs.
# That template is the forge's main, which ships with this one, or TURBO_TEMPLATE as it stands.
#
#   tests/newborn.sh                                         # the forge's main around this tree
#   TURBO_TEMPLATE=../template-repo-turbo tests/newborn.sh   # a sibling checkout as it stands
#   TURBO_REF=0.122.1 tests/newborn.sh                       # a released version around it
#   KEEP=1 tests/newborn.sh                                  # leave the rendered repo in place
set -eu

# Left set by a hook, GIT_DIR and GIT_WORK_TREE would point the newborn's `git init` and copier's
# clones at the pushing repository: from a linked worktree, `git init` marks it bare.
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

# The lockfile predates the apps, and under CI=true the check's frozen install refuses it.
echo "→ repo: lockfile"
(cd "$repo" && pnpm install --lockfile-only)

echo "→ repo: check"
(cd "$repo" && mise run check)

echo "✓ newborn"
