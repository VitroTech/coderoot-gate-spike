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
packages/a, packages/b, packages/c  @vitrotech/gate-spike-a, -b and -c, README-only test packages
scripts/dispatch.sh             start a publish from a tarball reference
scripts/check-workflow.sh       static checks on both publishing workflows
scripts/local-dry-run.sh        local packaging, digest, and registry rehearsal
evidence/                       captured output from the publish runs
```

## Run it

```bash
scripts/check-workflow.sh [workflow]             # checks release.yml and env-publish.yml by default
python3 scripts/test-check-workflow.py           # offline regression checks for the checker
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
@vitrotech/gate-spike-c   environment cust-a   npm publish, restricted access
```

Both environments allow deployments from `main` only. Neither holds a secret. A dispatch picks the
package, the environment (`none` runs the publish job with no environment), the version, the npm
access and the mode. Mode `claims` publishes nothing: the job decodes the OIDC token it is issued
and prints its claims. A run whose environment, branch or mode does not match the package's trust configuration is
expected to be refused by GitHub or by npm.

The `pack` job has no publish rights. The publish job verifies the tarball's digest and runs only
the pinned npm, with the registry, access and `--ignore-scripts` given on the command line.

### Submitting to CodeRoot

With `submit`, the release goes to CodeRoot for a person's approval once it reaches npm: flow
`published` after `npm publish`, flow `staged` after `npm stage publish`. A staged submission needs
`provenance-source: file`, because the gate checks the exact bundle npm attaches.

The `submit` job runs in a third environment, `coderoot-submit`, which allows `main` only and holds
no secrets. It runs the public [CodeRoot Action](https://github.com/coderoot-eth/action), pinned to
the commit of `v1.1.1`. npm trusts this workflow only in `cust-a` and `cust-b`, so the identity
token `submit` holds is refused by npm and the job cannot publish. It signs in to CodeRoot with that
token; no CodeRoot or npm token is stored anywhere.

The environment name must stay `coderoot-submit`; putting this job in `cust-a` or `cust-b`
would give its identity token npm publishing authority. Configure this environment with a
deployment branch rule of type `branch`, name `main`.
The local checker verifies the workflow references, not the live GitHub environment settings.

### Limits of the submission sample

Job outputs are not a private transport. GitHub prints the `TB64` environment value in the
restore steps, so the tarball can be reconstructed from public workflow logs even before a
staged release is approved. Use these README-only throwaway packages; the workflow uploads no
artifacts of its own, but that does not make the release bytes confidential.

If publication succeeds and submission fails, `Re-run failed jobs` retains the original
provenance while issuing the submit job a token with a later `run_attempt`. The gate accepts
signed provenance from an equal or earlier attempt of the same run, with the same repository,
workflow and source commit/ref. It still checks that the certificate and signed statement
identify the exact producer invocation. This backend recovery support was deployed on
October 18, 2026.

The Action uploads the tarball and staged bundle afresh on each attempt: old upload IDs
cannot cross attempts. An already accepted submission remains subject to the gate's duplicate
checks. Re-run only the failed submit job; re-running all jobs tries to publish the same
version again. A claims-only run does not validate submission or this recovery behavior;
live acceptance still needs both flows exercised against the gate.
