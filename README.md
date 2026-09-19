# coderoot-gate-spike

PB-0: the release runner as npm trusted publisher.

One workflow publishes `@vitrotech/gate-spike` to npm with **no stored token**. npm trusts this
repository running this workflow file, and the runner proves that with a short-lived OIDC token
requested at publish time. There is no `NPM_TOKEN` here, in the repo secrets, or in the workflow.

Read [`PB-0-NOTE.md`](PB-0-NOTE.md) for the findings, the threat pass, and the provenance
recommendation.

## Layout

```
.github/workflows/release.yml   the publish workflow (npm trusts this exact path)
package/                        the throwaway package source
scripts/dispatch.sh             start a publish from a tarball reference
scripts/check-workflow.sh       assert the note's hardening claims
scripts/local-dry-run.sh        rehearse the publish path with no npm involved
evidence/                       captured output
```

## Run it

```bash
scripts/check-workflow.sh                        # 11 hardening assertions
scripts/local-dry-run.sh                         # local rehearsal, no network
scripts/dispatch.sh <tarball-url> [--dry-run]    # the real publish
```

**The repo name and workflow path are load-bearing.** npm binds trust to
`VitroTech/coderoot-gate-spike` running `.github/workflows/release.yml`; renaming either breaks
the binding and the publish is refused.
