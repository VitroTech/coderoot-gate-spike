#!/usr/bin/env bash
# Static checks for selected release-workflow properties.
#
# These text-based checks are smoke tests, not a complete security audit.

set -euo pipefail
WF="$(cd "$(dirname "$0")/.." && pwd)/.github/workflows/release.yml"

# Comments explain why things are absent, so strip them before asserting absence.
BODY="$(sed 's/#.*//' "$WF")"
# Shell bodies only, for the injection check.
RUNS="$(awk '/run: \|/{f=1;next} /^      - /{f=0} f' "$WF")"

pass=0; fail=0
check() { # name, condition-result
  if [ "$2" = "0" ]; then printf '  OK    %s\n' "$1"; pass=$((pass+1));
  else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi
}
has()  { grep -qE -e "$1" <<<"$BODY"; }
lacks(){ ! grep -qE -e "$1" <<<"$BODY"; }

echo "workflow: ${WF#"$PWD"/}"
has 'workflow_dispatch:';                    check "dispatch-triggered"            $?
lacks 'pull_request_target';                 check "no pull_request_target"        $?
lacks 'secrets\.';                           check "no secrets referenced"         $?
lacks 'NPM_TOKEN|_authToken|NODE_AUTH_TOKEN';check "no npm credential"             $?
has 'id-token:[[:space:]]*write';            check "id-token: write"               $?
has 'contents:[[:space:]]*read';             check "contents: read only"           $?
has 'cache:[[:space:]]*""';                  check "actions cache off"             $?
has '--provenance';                          check "--provenance"                  $?
has 'shasum -a 256';                         check "tarball digest enforced"       $?
grep -qE '\$\{\{[[:space:]]*inputs\.' <<<"$RUNS" && r=1 || r=0
check "inputs reach shell via env only" "$r"

# Unpinned = any `uses:` whose ref is not a 40-char SHA.
if grep -oE 'uses:[[:space:]]*\S+' <<<"$BODY" | grep -vqE '@[0-9a-f]{40}$'; then r=1; else r=0; fi
check "all actions pinned to SHAs" "$r"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
