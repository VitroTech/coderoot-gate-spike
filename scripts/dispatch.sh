#!/usr/bin/env bash
# Dispatch the release workflow with a tarball reference.
#
# This is the "from a script" half of the spike. Note what is NOT here: no npm
# token, no registry credential, no secret of any kind. The only credential is
# the caller's GitHub auth, which is what lets them start a workflow run - it
# confers no publish rights by itself.
#
# usage:
#   scripts/dispatch.sh <tarball-url> [sha256]
#   scripts/dispatch.sh <tarball-url> --dry-run
#
# If the sha256 is omitted it is computed locally from the URL, so the digest
# the workflow enforces is one the caller actually observed.

set -euo pipefail

REPO="${GATE_SPIKE_REPO:-VitroTech/coderoot-gate-spike}"
WORKFLOW="release.yml"
REF="${GATE_SPIKE_REF:-main}"

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \?//'
  exit "${1:-1}"
}

[ $# -ge 1 ] || usage
case "${1:-}" in -h|--help) usage 0 ;; esac

TARBALL_URL="$1"
shift

DRY_RUN=false
SHA256=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) SHA256="$arg" ;;
  esac
done

case "$TARBALL_URL" in
  https://*) ;;
  *) echo "error: tarball url must be https" >&2; exit 2 ;;
esac

if [ -z "$SHA256" ]; then
  echo "computing sha256 of $TARBALL_URL ..." >&2
  SHA256="$(curl -fsSL --proto '=https' --tlsv1.2 "$TARBALL_URL" | shasum -a 256 | cut -d' ' -f1)"
fi
SHA256="${SHA256#sha256:}"

echo "repo      $REPO" >&2
echo "workflow  $WORKFLOW (ref $REF)" >&2
echo "tarball   $TARBALL_URL" >&2
echo "sha256    $SHA256" >&2
echo "dry-run   $DRY_RUN" >&2
echo >&2

gh workflow run "$WORKFLOW" \
  --repo "$REPO" \
  --ref "$REF" \
  --field "tarball_url=$TARBALL_URL" \
  --field "tarball_sha256=$SHA256" \
  --field "dry_run=$DRY_RUN"

echo >&2
echo "dispatched. following the run:" >&2
sleep 4
RUN_ID="$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$RUN_ID" --repo "$REPO" --exit-status
