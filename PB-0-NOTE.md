# PB-0 — publish-mechanism spike: the release runner as npm trusted publisher

Status: **partial — four items await the GitHub repo.** The npm side is resolved. Everything that does not require
publishing to the public registry is done and is reproducible from this directory.
Written 2026-09-15 for Pablo's review. Intended to settle the wording of the ADR-015 §3
amendment.

No keys, no Vault, nothing on `secure.coderoot.app`.

---

## 0. What is done, and what remains

**The npm side is settled** (Pawel, 2026-09-17):

| item | state |
|---|---|
| scope | `@vitrotech` — confirmed with David; no second org needed |
| placeholder publish | `@vitrotech/gate-spike` 0.0.1 published, with a token |
| trusted publishing | configured against `coderoot-gate-spike` / `release.yml` |
| hardening | 2FA required, bypass tokens disallowed |

The granular token used for the placeholder was Pawel's and is his to delete; this note records
that it was used once, for step 2 only, and that every later publish goes through the workflow.

**Remaining, and all waiting on the same thing — the GitHub repo:**

| item | needs |
|---|---|
| the provenance statement as published | one `--provenance` dispatch |
| the "direct publish fails" transcripts | the repo, to attempt from a second identity |
| confirmation that dispatch publishes with no stored token | the repo |
| the package settings as configured | a screenshot/export once the repo is bound |

`coderoot-gate-spike` under VitroTech, write access, Actions enabled. Requested from David and
Pablo 2026-09-18. **The repo name is load-bearing**: npm binds trust to the repo *and* the
workflow path, so `coderoot-gate-spike` + `release.yml` cannot be renamed without reconfiguring.

### Baseline, captured before the gate exists

The placeholder was published with a token rather than through the gate, so the gate's own client
does not recognise it. That is the "before" half of the spike
([`evidence/baseline-pre-gate.log`](evidence/baseline-pre-gate.log)):

```
$ coderoot verify --file gate-spike-0.0.1.tgz
! unregistered
  digest  sha256:e14d3280f8175331c26ad5f3421d14b227aaae5c7b316842a56ee311f1e5baf5
  bytes   901
  reason  No attested record exists for these bytes.
```

After the trusted-publisher dispatch republishes it with provenance, the same command is the
"after" half. That pairing is the most legible demonstration in this note.

### One thing to confirm on the first dispatch

Pawel set **2FA required** on the package. Trusted publishing is designed to satisfy that without
a token, which is why the setting is correct — but this workflow has not been run against a
2FA-required package, and automated publishing can interact with that setting in ways worth
finding on a dispatch rather than during a demo. First thing to check when the repo lands.

---

## 1. The mechanism, in one paragraph

Trusted publishing replaces a stored npm token with a short-lived OIDC token the runner requests
at publish time. npm is configured to trust *a specific repository running a specific workflow
file on a specific ref*; at publish, npm checks the token's claims against that configuration.
The credential never exists at rest, so there is no `NPM_TOKEN` to leak from repo secrets, no
token to rotate, and no value an attacker can exfiltrate and reuse later from somewhere else.

What it does **not** do is remove the runner as a target. The token exists in runner memory for
the duration of the job, and anything that executes inside that job can ask for it. That is the
whole of §5.

---

## 2. The workflow

[`.github/workflows/release.yml`](.github/workflows/release.yml) — publishes a tarball passed at
dispatch. Three things to note:

- **`permissions:` is two lines.** `contents: read` and `id-token: write`. The second is the only
  permission trusted publishing needs; the job cannot write to the repo.
- **The tarball is verified before publishing.** The dispatcher passes a sha256, and the job
  refuses to publish if the fetched bytes disagree. Without this the workflow would publish
  whatever a URL happened to serve at that moment.
- **No `environment:`, no reusable workflow.** npm binds trust to this repo and this file path;
  indirection widens what is trusted for no gain here.

The hardening claims in §5 are asserted mechanically by
[`scripts/check-workflow.sh`](scripts/check-workflow.sh), so this note cannot quietly drift from
the file it describes:

```
$ scripts/check-workflow.sh
  OK    dispatch-triggered
  OK    no pull_request_target (§5.1)
  OK    no secrets referenced
  OK    no npm credential (§1)
  OK    id-token: write
  OK    contents: read only
  OK    actions cache off (§5.3)
  OK    --provenance (§4)
  OK    tarball digest enforced
  OK    inputs reach shell via env only (§5.4)
  OK    all actions pinned to SHAs (§5.2)

11 passed, 0 failed
```

Both pinned SHAs were checked against the upstream repositories and match the tags named in the
comments (`actions/checkout@v4.2.2`, `actions/setup-node@v4.1.0`).

## 3. The dispatch call

[`scripts/dispatch.sh`](scripts/dispatch.sh):

```bash
scripts/dispatch.sh https://example.com/gate-spike-0.0.1.tgz
scripts/dispatch.sh https://example.com/gate-spike-0.0.1.tgz --dry-run
```

It computes the tarball's sha256 locally when not given one, so the digest the workflow enforces
is one the caller actually observed rather than one the server asserted. **The only credential it
uses is the caller's GitHub auth**, which permits starting a workflow run and confers no publish
rights of its own — that is the point of the exercise.

### Rehearsed locally

Because the live publish is blocked, [`scripts/local-dry-run.sh`](scripts/local-dry-run.sh)
exercises everything except the OIDC handshake against a local registry
([`evidence/local-dry-run.log`](evidence/local-dry-run.log)):

```
== 2. the workflow's digest check, run here
good tarball  -> accepted
tampered tarball -> rejected

== 3. publish with no credential (expect refusal)
refused, as expected:
npm error code ENEEDAUTH
npm error need auth This command requires you to be logged in to http://localhost:4873/
```

That last block is the *shape* of the step-6 refusal, not the real transcript: it proves an
unauthenticated publish is refused, but not that a **wrongly-authenticated** one is — which is
the interesting case and needs the live package.

---

## 4. Provenance — recommendation: **on**

*The statement as published is blocked; the recommendation is not, and is the item ADR-015 §3
actually needs.*

`npm publish --provenance` makes npm generate a signed SLSA attestation recording which
repository, workflow and commit produced the artifact, logged in a public transparency log.

**Recommend `--provenance` on for gated publishes**, with one caveat that must be written down
rather than discovered later.

**Why on.** It is the only artifact that survives the build. A trusted-publisher configuration
proves who *may* publish; provenance proves what *did* publish, after the fact, to someone who
was not watching at the time. For a gate whose entire value proposition is "these are the bytes
the maintainer published", declining the attestation that says so would be odd. It costs nothing
per publish and requires no key custody on our side.

**The caveat, and it is the important part of this note.** The provenance statement will name
**CodeRoot's repository as the build source** — not the customer's. That is accurate: CodeRoot's
runner did build and publish it. But a consumer reading the provenance of a package they got
through the gate sees a CodeRoot repo they have never heard of, not the upstream project they
think they are installing.

This is a real semantic change and ADR-015 §3 should say so explicitly: **gated publishing moves
the attested build source from the maintainer to CodeRoot.** Left unsaid, it will be read as
provenance laundering — an attestation that looks like upstream provenance but attests to a
republisher. Said plainly, it is simply what a gate is.

Worth deciding alongside: whether the gate also records the *upstream* source in the package
metadata, so a consumer can follow the chain rather than dead-ending at CodeRoot.

---

## 5. Threat pass — the Mini Shai-Hulud class

The May 2026 class does not attack the stored token, because there isn't one. It attacks the
*job that holds a publishable identity*. Getting arbitrary code into that job is equivalent to
holding the credential, for as long as the job runs.

### What this workflow defends against

**5.1 `pull_request_target`.** The primary entry point. It runs with repository write scope
against code from an untrusted fork, which is how attacker-authored code lands in a privileged
job. This workflow is `workflow_dispatch` only — a fork cannot trigger it, and there is no code
path from an incoming PR to a job holding the OIDC token.

**5.2 Mutable action tags.** `actions/checkout@v4` is a moving pointer; whoever controls that
repository can repoint it at new code that then runs inside a job that can publish. Both actions
are pinned to 40-character commit SHAs, verified upstream.

**5.3 Poisoned Actions cache.** A cache entry is attacker-writable from a lower-privileged
workflow in the same repo and is restored into the privileged job. `cache: ""` disables it. This
costs roughly twenty seconds per run, which for a publish job is not a real cost.

**5.4 Script injection via dispatch inputs.** Inputs are passed through `env:` and referenced as
shell variables, never interpolated into the script body, so a crafted input cannot terminate
the string and execute. The tarball URL is also constrained to `https://`.

**5.5 Blast radius.** `contents: read` means a compromised job cannot write to the repository,
so it cannot persist by modifying the workflow it is running in.

### What it does **not** defend against

Stated plainly, because this is the half that matters for the ADR:

**The OIDC token is readable from runner memory by anything running in the job.** Every defence
above is about keeping foreign code out of the job. None of them help once it is in. Specifically:

- **A malicious dependency in the published package's own build.** This workflow publishes a
  prebuilt tarball and runs no project build, which narrows it considerably — but anything that
  did run `npm install` before packing would execute arbitrary lifecycle scripts next to the
  token.
- **A compromise of `actions/checkout` or `actions/setup-node` at the pinned SHA.** Pinning
  defends against the tag moving, not against the pinned commit being malicious to begin with.
- **A malicious `npm` release.** The job installs `npm@^11.5.1` from the registry at runtime — a
  range, not a pin, and it is the very tool that handles the token.
- **Anyone who can push to `main` in the spike repo.** They can edit the workflow and publish.
  Branch protection is a governance control, not a technical one, and it is outside this spike.
- **GitHub itself**, as the OIDC issuer.

### What would close the remaining gaps

In rough order of value for effort:

1. **Pin `npm` to an exact version** rather than a range. One line; removes a runtime fetch of
   the tool that holds the credential.
2. **Never build in the publishing job.** Keep the split this workflow already has — build
   elsewhere, publish a verified tarball. Worth writing into the ADR as a rule, not just a habit.
3. **Branch protection plus required review** on the spike repo, so publishing requires two
   people.
4. **Ephemeral, single-use runners.** GitHub-hosted runners are already fresh per job; this
   matters if the gate ever moves to self-hosted, where it becomes essential.
5. **A second factor on publish** — a manual approval environment — if the ADR decides that
   automated publishing is too much authority for one dispatch.

Items 1 and 2 are cheap and should be in the ADR wording. Items 3–5 are policy decisions for
Pablo rather than spike findings.

---

## 6. Reproducing this

```bash
scripts/check-workflow.sh    # assert the §5 hardening claims
scripts/local-dry-run.sh     # rehearse the publish path locally
```

Neither needs npm credentials or network access to the public registry.

When the scope question is answered, the blocked items are configuration rather than
development: publish the placeholder, register the trusted publisher, delete the granular token
immediately and say so here, then dispatch and capture the three refusal transcripts.
