# coderoot-gate-spike

A minimal npm trusted-publishing experiment using GitHub Actions.

One workflow publishes `@vitrotech/gate-spike` to npm with **no stored token**. npm trusts this
repository running this workflow file, and the runner proves that with a short-lived OIDC token
requested at publish time. There is no `NPM_TOKEN` here, in the repo secrets, or in the workflow.

This is a throwaway test package, not a production publishing service. Publishing with
provenance requires a public source repository; the release workflow exposes a `provenance`
input for it.

## Layout

```
.github/workflows/release.yml   the publish workflow (npm trusts this exact path)
.github/workflows/rogue.yml     an untrusted-workflow publish attempt (expected to fail)
.github/workflows/env-publish.yml  per-environment publish checks for the two packages below
package/                        the throwaway package source
packages/a, packages/b          @vitrotech/gate-spike-a and -b, README-only test packages
scripts/dispatch.sh             start a publish from a tarball reference
scripts/check-workflow.sh       static checks on the release workflow
scripts/local-dry-run.sh        local packaging, digest, and registry rehearsal
evidence/                       captured output from the publish runs
```

## Run it

```bash
scripts/check-workflow.sh [workflow]             # 11 static workflow checks (default: release.yml)
scripts/local-dry-run.sh                         # uses npm and localhost:4873
scripts/dispatch.sh <tarball-url> [--dry-run]    # the real publish
```

The static checks are not a security audit. The local rehearsal does not verify npm OIDC
authorization or provenance. Dispatching the release workflow without `--dry-run` attempts
a real publish; the rogue workflow also attempts a real publish and expects it to be refused.

**The repo name and workflow path are load-bearing.** npm binds trust to
`VitroTech/coderoot-gate-spike` running `.github/workflows/release.yml`; renaming either breaks
the binding and the publish is refused.

## What npm records

```
0.0.1   _npmUser  pawelbudnik15      trustedPublisher: none
0.0.2   _npmUser  GitHub Actions     trustedPublisher: github
0.0.3   _npmUser  GitHub Actions     trustedPublisher: github   + provenance
```

0.0.1 was published by a person holding a token. 0.0.2 and 0.0.3 came from the workflow, which
holds none.

```bash
curl -s https://registry.npmjs.org/@vitrotech/gate-spike \
  | jq '.versions | to_entries[] | {version: .key, publisher: .value._npmUser.name}'
```

### Provenance

0.0.3 was published with `--provenance`. npm stores the signed SLSA statement against the
version, and it names the repository and workflow file that built the package
([`evidence/provenance-statement.log`](evidence/provenance-statement.log)):

```
subject   : pkg:npm/%40vitrotech/gate-spike@0.0.3
workflow  : repository  https://github.com/VitroTech/coderoot-gate-spike
            path        .github/workflows/release.yml
            ref         refs/heads/main
builder   : https://github.com/actions/runner/github-hosted
```

Sigstore transparency log index 2918465003.

```bash
curl -s https://registry.npmjs.org/@vitrotech/gate-spike \
  | jq '.versions["0.0.3"].dist.attestations'
```

npm refuses `--provenance` while the source repository is private, answering 422 after it has
already signed the statement and written it to the transparency log.

## Per-environment checks

`env-publish.yml` publishes one of two test packages from a chosen GitHub environment. Each
package trusts this workflow file in one environment only:

```
@vitrotech/gate-spike-a   environment cust-a   npm publish
@vitrotech/gate-spike-b   environment cust-b   npm stage publish only
```

Both environments allow deployments from `main` only and hold no secrets. A dispatch picks the
package, the environment (`none` runs the publish job with no environment), the version and the
mode. A run whose environment, branch or mode does not match the package's trust configuration is
expected to be refused by GitHub or by npm.

The `pack` job has no publish rights. The publish job verifies the tarball's digest and runs only
the pinned npm, with the registry, access and `--ignore-scripts` given on the command line.
