#!/usr/bin/env bash
# Static checks for selected release-workflow properties.
#
# These text-based checks are smoke tests, not a complete security audit.

set -euo pipefail
if [ "$#" -eq 0 ]; then
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  result=0
  for workflow in release.yml env-publish.yml; do
    bash "$0" "$ROOT/.github/workflows/$workflow" || result=1
  done
  exit "$result"
fi
WF="$1"

# Comments explain why things are absent, so strip them before asserting absence.
BODY="$(sed 's/#.*//' "$WF")"
# Shell bodies only, for the injection check.
RUNS="$(awk 'f{ match($0,/^ */); if ($0 ~ /^[[:space:]]*$/ || RLENGTH>ind) {print; next}; f=0 } /run: \|/{ match($0,/^ */); ind=RLENGTH; f=1 }' "$WF")"

pass=0; fail=0
check() { # name, command and arguments; report every failure even with set -e.
  local name="$1"
  shift
  if "$@"; then printf '  OK    %s\n' "$name"; pass=$((pass+1));
  else printf '  FAIL  %s\n' "$name"; fail=$((fail+1)); fi
}
has()  { grep -qE -e "$1" <<<"${2-$BODY}"; }
lacks(){ ! has "$@"; }

# Job blocks have two-space indentation in these workflows. This is deliberately
# a check of the checked-in layout, not a general YAML parser.
SUBMIT="$(awk '/^  [A-Za-z0-9_-]+:/{s=($0 ~ /^  submit:/)} s' <<<"$BODY")"
OUTSIDE_SUBMIT="$(awk '/^  [A-Za-z0-9_-]+:/{s=($0 ~ /^  submit:/)} !s' <<<"$BODY")"
SECRET_REFERENCE='(^|[^[:alnum:]_])secrets([^[:alnum:]_]|$)'
approved_key_only() {
  local references
  references="$(grep -E "$SECRET_REFERENCE" <<<"$SUBMIT" | sed -E 's/^[[:space:]]+//' || true)"
  [ "$references" = 'ssh-key: ${{ secrets.CODEROOT_ACTION_KEY }}' ]
}
pinned_uses() {
  local ref
  while read -r ref; do
    if [ -n "$SUBMIT" ] && [ "$ref" = './coderoot-action' ]; then continue; fi
    [[ "$ref" =~ @[0-9a-f]{40}$ ]] || return 1
  done < <(grep -oE 'uses:[[:space:]]*[^[:space:]]+' <<<"$BODY" | awk '{print $2}')
}

echo "workflow: ${WF#"$PWD"/}"
check "dispatch-triggered" has 'workflow_dispatch:'
check "no pull_request_target" lacks 'pull_request_target'
if [ -n "$SUBMIT" ]; then
  check "submit uses coderoot-submit" has '^    environment: coderoot-submit[[:space:]]*$' "$SUBMIT"
  check "submit has identity-token permission" has '^      id-token: write[[:space:]]*$' "$SUBMIT"
  check "only the Action checkout references a secret" approved_key_only
  check "no secrets outside submit" lacks "$SECRET_REFERENCE" "$OUTSIDE_SUBMIT"
  check "private Action repository is explicit" has '^          repository: VitroTech/coderoot-action[[:space:]]*$' "$SUBMIT"
  check "checkout credentials are not persisted" has '^          persist-credentials: false[[:space:]]*$' "$SUBMIT"
  check "no local actions outside submit" lacks 'uses:[[:space:]]*\./' "$OUTSIDE_SUBMIT"
  check "no workflow artifact transfer" lacks 'uses:.*actions/(upload|download)-artifact@'
else
  check "no secrets referenced" lacks "$SECRET_REFERENCE"
fi
check "no npm credential" lacks 'NPM_TOKEN|_authToken|NODE_AUTH_TOKEN'
check "id-token: write" has 'id-token:[[:space:]]*write'
check "contents: read only" has 'contents:[[:space:]]*read'
check "actions cache off" has 'cache:[[:space:]]*""'
check "--provenance" has '--provenance'
check "tarball digest enforced" has 'shasum -a 256'
check "inputs reach shell via env only" lacks '\$\{\{[[:space:]]*inputs\.' "$RUNS"
check "uses references pinned or approved local Action" pinned_uses

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
