#!/bin/sh
# A newborn app passes its repo's own check: this working tree, uncommitted changes included, is
# rendered once per profile into a newborn of the Turborepo template, taking the tenant from the repo's
# answers, and the repo's `mise run check` runs. An app rendered where no repo's answers give a tenant is refused.
# Each app's compose file refuses an unset loopback port and publishes a set one (PLX-App/LoopbackPort), which needs docker compose.
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
    -d name="@acme/$profile" -d profile="$profile" "$here" "$repo/apps/$profile"
done

echo "→ apps/orphan: render with no repo around it"
if out=$(copier copy --quiet --defaults --trust --vcs-ref HEAD -d name=@acme/orphan "$here" "$tmp/orphan/apps/orphan" 2>&1); then
  echo "✗ apps/orphan: rendered without a tenant" >&2
  exit 1
fi
case $out in
  *"no tenant in "*"/orphan/.copier-answers.yml"*) ;;
  *) printf '%s\n✗ apps/orphan: refused without naming the answers file\n' "$out" >&2; exit 1 ;;
esac

# Without PLEXUS_LOOPBACK_PORT compose would publish on a random loopback port, where a deploy turns healthy and the proxy finds nothing.
for profile in stateless-app stateful-app; do
  echo "→ apps/$profile: compose refuses an unset loopback port"
  dir=$repo/apps/$profile/docker
  if out=$(cd "$dir" && env -u PLEXUS_LOOPBACK_PORT PLEXUS_DEPLOYMENT_IMAGE=newborn docker compose config 2>&1); then
    printf '%s\n✗ apps/%s: compose took the file without PLEXUS_LOOPBACK_PORT\n' "$out" "$profile" >&2
    exit 1
  fi
  case $out in
    *"required variable PLEXUS_LOOPBACK_PORT"*) ;;
    *) printf '%s\n✗ apps/%s: compose failed without naming PLEXUS_LOOPBACK_PORT\n' "$out" "$profile" >&2; exit 1 ;;
  esac
  (cd "$dir" && PLEXUS_LOOPBACK_PORT=3011 PLEXUS_DEPLOYMENT_IMAGE=newborn docker compose config --quiet)
done

# The lockfile predates the apps, and under CI=true the check's frozen install refuses it.
echo "→ repo: lockfile"
(cd "$repo" && pnpm install --lockfile-only)

echo "→ repo: check"
(cd "$repo" && mise run check)

echo "✓ newborn"
