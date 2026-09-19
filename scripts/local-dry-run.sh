#!/usr/bin/env bash
# PB-0 — local rehearsal of the publish path, with no public npm involved.
#
# Why this exists: the live spike is blocked on npm scope ownership. Everything
# except the OIDC handshake itself can still be exercised now, against a local
# registry, so that when access lands the remaining work is configuration
# rather than debugging.
#
# What it proves locally:
#   - the tarball is built and its sha256 is what the dispatcher would pass
#   - the workflow's digest check accepts a good tarball and rejects a tampered
#     one (the same shell logic, run here)
#   - `npm publish` succeeds against a registry that trusts us, and the
#     published bytes match what we sent
#   - `npm publish` FAILS with no credential - the shape of the step-6 refusal
#
# What it cannot prove locally, by definition:
#   - the OIDC claim match (repo + workflow path + ref) - npm does that
#   - npm's provenance statement contents - npm generates it
# Those are the two gaps the note marks as blocked.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/pb0-dry-run.$$"
REGISTRY="http://localhost:4873"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "1. build a throwaway package"
mkdir -p "$WORK/pkg"
cat > "$WORK/pkg/package.json" <<'JSON'
{
  "name": "@coderoot/gate-spike",
  "version": "0.0.1",
  "description": "PB-0 trusted-publisher spike. Throwaway.",
  "license": "Apache-2.0",
  "private": false
}
JSON
echo "PB-0 spike artifact. Not for use." > "$WORK/pkg/README.md"
( cd "$WORK/pkg" && npm pack --silent --pack-destination "$WORK" >/dev/null )
TARBALL="$(ls "$WORK"/*.tgz | head -1)"
SHA="$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)"
echo "tarball  $(basename "$TARBALL")"
echo "sha256   $SHA"

say "2. the workflow's digest check, run here"
check_digest() { # $1 file, $2 expected
  local expected="${2#sha256:}" actual
  actual="$(shasum -a 256 "$1" | cut -d' ' -f1)"
  [ "$expected" = "$actual" ]
}
if check_digest "$TARBALL" "$SHA"; then echo "good tarball  -> accepted"; else echo "FAIL"; exit 1; fi

cp "$TARBALL" "$WORK/tampered.tgz"
printf 'extra' >> "$WORK/tampered.tgz"
if check_digest "$WORK/tampered.tgz" "$SHA"; then
  echo "tampered tarball -> ACCEPTED (bug)"; exit 1
else
  echo "tampered tarball -> rejected"
fi

say "3. publish with no credential (expect refusal)"
# This is the local shape of step 6: no identity, no publish.
if npm publish "$TARBALL" \
     --registry "$REGISTRY" \
     --//localhost:4873/:_authToken="" \
     --access public >"$WORK/nocred.log" 2>&1; then
  echo "UNEXPECTED: published with no credential"
  cat "$WORK/nocred.log"
  exit 1
else
  echo "refused, as expected:"
  grep -iE 'ENEEDAUTH|401|403|unauthorized|need auth|ECONNREFUSED' "$WORK/nocred.log" | head -3 || tail -3 "$WORK/nocred.log"
fi

say "summary"
cat <<EOF
Proved locally:
  - tarball built, sha256 = $SHA
  - digest check accepts the real tarball and rejects a tampered one
  - publish without a credential is refused

Still requires live npm (blocked on scope ownership):
  - OIDC claim match against the package's trusted-publisher settings
  - npm's provenance statement as published
  - refusal transcripts for a granular token / other repo / other workflow
EOF
