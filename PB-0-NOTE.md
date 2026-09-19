# PB-0 — publish-mechanism spike: the release runner as npm trusted publisher

Status: **steps 1-4 and 6-8 done and evidenced. Step 5 (the provenance statement) is blocked by
repository visibility, which is a finding in itself.** Reproducible from this repository.
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

**Done on 2026-09-19**, in `VitroTech/coderoot-gate-spike`:

| item | result |
|---|---|
| dispatch publishes with no stored token | **yes** — `@vitrotech/gate-spike@0.0.2`, run 35429286258 |
| credential references anywhere in the job log | **zero** |
| publish refused with no npm identity | yes |
| publish refused from a *different workflow in the same repo* | **yes** — the key result |
| the provenance statement as published | **blocked: private repository.** See §4 |

Evidence: [`evidence/dispatch-evidence.log`](evidence/dispatch-evidence.log).

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

After the gate published 0.0.2, the same command still answers `unregistered`:

```
$ coderoot verify --file gate-spike-0.0.2.tgz
! unregistered
  digest  sha256:9d7f6982beeb98ea8ff71a99b8c8a31b475977e3ad0b2f55c92fc7a35b731e2f
```

That is correct and worth stating plainly, because it is easy to expect otherwise. **Publishing
through the gate proves who published; it does not create an attestation.** Writing the
attestation is PB-2/PB-3, and until that exists the gate's own client cannot recognise the gate's
own output. PB-0 closes the publish half only.

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

### The package settings, as the registry reports them

Deliverable item: *the npm package settings as configured*. Rather than a screenshot of the npm
UI, here is the registry's own record, which is the same fact in a form anyone can re-read
([`evidence/package-settings.log`](evidence/package-settings.log)):

```
0.0.1:
  _npmUser.name              'pawelbudnik15'
  _npmUser.trustedPublisher  None

0.0.2:
  _npmUser.name              'GitHub Actions'
  _npmUser.email             'npm-oidc-no-reply@github.com'
  _npmUser.trustedPublisher  {'id': 'github', 'oidcConfigId': 'oidc:3ae54681-…'}
```

That pair is the whole spike in four lines. **0.0.1** was published by a person holding a token.
**0.0.2** was published by a workflow holding nothing, and npm records the trusted-publisher
binding against the version rather than taking our word for it.

Configured by Pawel (2026-09-17): trusted publishing bound to
`VitroTech/coderoot-gate-spike` running `.github/workflows/release.yml`, 2FA required, bypass
tokens disallowed.

---

## 4. Provenance — recommendation: **on, and the gate repo must be public**

Measured 2026-09-19, and this changes the recommendation from a preference into a constraint.

**npm refuses `--provenance` from a private repository.** The failure is late and specific: the
OIDC handshake succeeds, npm signs the statement and writes it to the Sigstore transparency log
(logIndex 2891565617), and only then the registry rejects the upload:

```
npm notice publish Signed provenance statement with source and build information from GitHub Actions
npm notice publish Provenance statement published to transparency log: https://search.sigstore.dev/?logIndex=2891565617
npm error code E422
npm error 422 Unprocessable Entity - Error verifying sigstore provenance bundle:
  Unsupported GitHub Actions source repository visibility: "private".
  Only public source repositories are supported when publishing with provenance.
```

Two things follow.

**Trusted publishing and provenance have different prerequisites.** The tokenless publish works
from a private repo; provenance does not. A gate can have one without the other, and the choice
is now explicit rather than accidental.

**If ADR-015 §3 requires provenance, it also requires the gate's release repository to be
public.** That is a real disclosure decision - the repo's workflow, its history and its structure
all become readable - and it should be made deliberately rather than discovered during a release.
The spike ran with `--provenance` off to prove the rest of the mechanism; the flag is an input on
the workflow, ready to exercise the moment visibility changes.

*The recommendation below is unchanged and is the item ADR-015 §3 actually needs.*

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

**5.6a A different repository cannot publish.** `Poulman/coderoot-gate-spike-rogue` requests an
OIDC token exactly as `release.yml` does and attempts the same publish. npm refused it
(run 35430111055). Trust is bound to the repository, so holding a GitHub identity is not enough.

**5.6 A second workflow in the same repository cannot publish.** This is the strongest result in
the spike and it was measured, not assumed. `rogue.yml` is identical to `release.yml` in every
way that matters - same repo, same ref, same `id-token: write`, same OIDC request - and differs
only in filename. npm refused it:

```
npm error code ENEEDAUTH
npm error need auth This command requires you to be logged in to https://registry.npmjs.org/
```

So npm's trust is bound to the repository *and the workflow path*, not to the repository alone.
An attacker who can add a workflow to a trusted repo still cannot publish; they would have to
modify `release.yml` itself, which `contents: read` and branch protection are there to prevent.
The rogue workflow is kept in the repo, with its exit inverted, so a future change that widens
the binding fails the run instead of passing silently.

**5.7 `setup-node`'s `registry-url` injects a credential.** Found on the first dispatch. Setting
it makes `setup-node` write an `.npmrc` with an auth line and export `NODE_AUTH_TOKEN` into every
later step - the exact stored credential this spike exists to remove. Trusted publishing needs
neither, so the input was removed. A spike that had kept it would have "proved" tokenless
publishing while carrying a token in the environment the whole time.

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
