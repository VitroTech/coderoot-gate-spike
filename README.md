# coderoot-gate-spike

A minimal npm trusted-publishing experiment using GitHub Actions.

One workflow publishes `@vitrotech/gate-spike` to npm with **no stored token**. npm trusts this
repository running this workflow file, and the runner proves that with a short-lived OIDC token
requested at publish time. There is no `NPM_TOKEN` here, in the repo secrets, or in the workflow.

This is a throwaway test package, not a production publishing service. Publishing with
provenance requires a public source repository; the release workflow exposes a `provenance`
input for that test.

## Layout

```
.github/workflows/release.yml   the publish workflow (npm trusts this exact path)
.github/workflows/rogue.yml     an untrusted-workflow publish attempt (expected to fail)
package/                        the throwaway package source
scripts/dispatch.sh             start a publish from a tarball reference
scripts/check-workflow.sh       static checks on the release workflow
scripts/local-dry-run.sh        local packaging, digest, and registry rehearsal
```

## Run it

```bash
scripts/check-workflow.sh                        # 11 static workflow checks
scripts/local-dry-run.sh                         # uses npm and localhost:4873
scripts/dispatch.sh <tarball-url> [--dry-run]    # the real publish
```

The static checks are not a security audit. The local rehearsal does not verify npm OIDC
authorization or provenance. Dispatching the release workflow without `--dry-run` attempts
a real publish; the rogue workflow also attempts a real publish and expects it to be refused.

**The repo name and workflow path are load-bearing.** npm binds trust to
`VitroTech/coderoot-gate-spike` running `.github/workflows/release.yml`; renaming either breaks
the binding and the publish is refused.
