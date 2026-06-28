# Attestation Walkthrough

A complete end-to-end CSAE session, plus a coverage-gap recovery from a prior unlogged bypass.

The scenario: a small team (one operator + AI assistant) is refactoring an authentication module on a project where CSAE is in production. The operator wants the work auditable. Three days later, an old coverage gap from a previous session's bypass surfaces and needs retroactive attestation.

This walkthrough shows the full eager-attestation cycle (intent → work → review → bundle → audit-mirror publish → canonical push → audit-query) followed by a retroactive-attestation recovery.

---

## Scenario setup

- Operator: alice
- Workstream: `ws-auth-refactor`
- Intent: extract OAuth flow from monolithic auth module into a separate service-boundary
- Reviewer: bob (using Russian-Judge-style structured verdicts)
- Audit mirror: separate repo `org/csae-audit-mirror`, append-only, distinct keys from the primary repo

The codebase already runs CSAE in production: pre-push validator on canonical main, audit mirror in place, intent-registration discipline established.

Tool names in this walkthrough (`csae-register-intent`, `csae-author-bundle`, `csae-publish-bundle`, `csae-verify`) are illustrative. Every team implementing CSAE will have similarly-shaped tooling with different specific names.

---

## Morning — intent registration

alice opens the worker tree and runs intent registration *before* any substantive work:

```bash
$ csae-register-intent --workstream ws-auth-refactor \
  --intent "extract OAuth flow from monolithic auth module into separate service-boundary; touches oauth/, tests/oauth/, and the consumer at api/middleware/auth.py"
[csae-reg] commit_A0 = a1b2c3d (workstream: ws-auth-refactor)
```

The registration produces commit `a1b2c3d` on alice's worker branch. The commit message embeds the workstream ID, intent statement, operator identifier, and timestamp. This is the scope claim: the *what was authorized* boundary that precedes the work.

`git log --oneline` shows just one commit so far:
```
a1b2c3d [csae-reg] ws-auth-refactor: extract OAuth flow from monolithic auth
```

---

## Work — six commits over the morning

alice and the AI assistant produce six work commits:

```
e4f5g6h - oauth: extract token-exchange to new module
i7j8k9l - oauth: extract refresh-flow to new module
m0n1o2p - tests/oauth: cover token-exchange edge cases
q3r4s5t - tests/oauth: cover refresh-flow edge cases
u6v7w8x - api/middleware/auth: route to new oauth module
y9z0a1b - docs: update OAuth section of API reference
```

The work spans the auth-refactor scope. None of these commits are on canonical main yet; they live on alice's worker branch.

---

## Afternoon — review

alice dispatches a Russian-Judge review (Code RJ) on the commit range `a1b2c3d..y9z0a1b`. The reviewer returns a verdict file at `verdicts/oauth-refactor-2026-05-20T140000Z.md`:

```
verdict_id: c3d4e5f-6789-abcd-ef01-234567890abc
score: 9.4/10
critical: 0
important: 0
minor: 1 (m-1: variable name 'tmp' in oauth/refresh.py:47)
pass: yes (≥9.0 + 0 C/I)
covered_range: a1b2c3d..y9z0a1b
```

The verdict file is signed by bob's reviewer key. alice acknowledges m-1 (rename `tmp` → `next_token`) and adds one fix-up commit:

```
c2d3e4f - oauth/refresh: rename tmp → next_token (addresses m-1)
```

The current worker-branch tip is `c2d3e4f`. The covered range is now `a1b2c3d..c2d3e4f`.

---

## Bundle authoring

```bash
$ csae-author-bundle --workstream ws-auth-refactor \
  --range a1b2c3d..c2d3e4f \
  --verdict verdicts/oauth-refactor-2026-05-20T140000Z.md
[csae-bundle] reading scope claim from a1b2c3d... OK
[csae-bundle] reading verdict c3d4e5f-6789... OK (score 9.4, pass)
[csae-bundle] reading predecessor bundle... OK (audit mirror tip: bundle_X9)
[csae-bundle] authoring bundle file: bundles/ws-auth-refactor-2026-05-20T143500Z.md
[csae-bundle] producing self-attestation commit: 7e8f9a0
```

The bundle file (in alice's worker tree, ready to push to the audit mirror) contains the 9 MUST fields. The self-attestation commit `7e8f9a0` lands on the worker branch with a message embedding:

- The bundle file's content hash
- Predecessor bundle reference (`bundle_X9`)
- Verdict reference (`verdict c3d4e5f`)
- Scope-claim hash from `a1b2c3d`

The covered range is now `a1b2c3d..7e8f9a0`: registration + work + fix-up + self-attestation, with the self-attestation commit *inside* the range it attests (the load-bearing self-include property).

---

## Audit-mirror publish — before canonical push

The sequence is non-negotiable. The validator on canonical main reads from the audit mirror, not from alice's worker tree. The bundle has to land in the mirror first.

```bash
$ csae-publish-bundle --bundle bundles/ws-auth-refactor-2026-05-20T143500Z.md
[csae-publish] target: org/csae-audit-mirror
[csae-publish] predecessor: bundle_X9 (resolved)
[csae-publish] pushing to audit mirror...
[csae-publish] OK (audit mirror tip: bundle_X10)
```

Chain continuity intact.

---

## Canonical push

```bash
$ git push origin main
[csae-validator] commit a1b2c3d: covered by bundle_X10 ✓
[csae-validator] commit e4f5g6h: covered by bundle_X10 ✓
[csae-validator] commit i7j8k9l: covered by bundle_X10 ✓
[csae-validator] commit m0n1o2p: covered by bundle_X10 ✓
[csae-validator] commit q3r4s5t: covered by bundle_X10 ✓
[csae-validator] commit u6v7w8x: covered by bundle_X10 ✓
[csae-validator] commit y9z0a1b: covered by bundle_X10 ✓
[csae-validator] commit c2d3e4f: covered by bundle_X10 ✓
[csae-validator] commit 7e8f9a0: covered by bundle_X10 ✓ (self-attestation)
[csae-validator] ACCEPT: 9 commits, all covered, chain integrity intact
To origin:refs/heads/main
   d3f7e2c..7e8f9a0  main -> main
```

The canonical push lands. Audit chain extended by one bundle.

---

## Recording the closure — after the merge, citing the canonical SHA

The `ws-auth-refactor` work was tracking a backlog item: *"extract OAuth flow to service-boundary."* alice now marks it closed. The discipline: she records the closure **after** the canonical push, and cites the **canonical** commit, not the working-branch commit she made earlier.

This matters because the convergence ceremony cherry-picked her work onto a side-branch from canonical main. The working-branch commit `7e8f9a0` and its canonical twin have the same diff, author, and message, but different hashes. The canonical twin is what's actually an ancestor of canonical main; `7e8f9a0` will evaporate when alice cleans up her working branch.

So before recording the closure SHA, alice verifies the ancestry:

```bash
# The canonical twin of the self-attestation commit, now on canonical main:
$ git rev-parse origin/main
9f0a1b2  # the canonical twin (post-cherry-pick), not 7e8f9a0

$ git merge-base --is-ancestor 9f0a1b2 origin/main && echo "ancestor ✓"
ancestor ✓
```

She records the closure note citing `9f0a1b2`, the canonical commit, bound to the verdict the bundle already references:

```
ws-auth-refactor: CLOSED — extract OAuth flow to service-boundary.
verified by canonical commit 9f0a1b2 (ancestor of canonical main),
under verdict c3d4e5f (score 9.4, pass at floor), bundle bundle_X10.
```

Had alice authored this note *before* the merge (citing `7e8f9a0`), the citation would have died with her working branch, and a future audit would find a closure SHA that exists nowhere. Land first, cite second.

---

## Three days later — coverage gap surfaces

alice is reviewing a different workstream and walks the chain backward to verify a recent bundle's predecessor. The walk hits a coverage gap at commit `4f5e6d7` (from 2026-05-12, a prior session).

```bash
$ csae-verify --commit 4f5e6d7
[csae-verify] walking chain for commit 4f5e6d7...
[csae-verify] ERROR: commit 4f5e6d7 is on origin/main but not covered by any bundle in audit mirror
[csae-verify] nearest predecessor bundle covers a3b4c5d..b8c9d0e (does not include 4f5e6d7)
[csae-verify] nearest successor bundle covers f9e8d7c..ab23c45 (begins after 4f5e6d7)
```

The validator should have caught this when `4f5e6d7` was pushed. alice checks the bypass-record log on the audit mirror:

```bash
$ csae-audit-log --filter bypass --range 2026-05-10..2026-05-15
[csae-audit-log] no bypass-records in range
```

No logged bypass. This is an *unlogged* gap: either the validator was misconfigured at the time, or the pre-push hook was disabled locally before the push. The chain has a hole.

---

## Retroactive attestation

alice files the gap as a coverage-gap recovery per [`PROTOCOL.md`](../PROTOCOL.md) §"Recovery from a coverage gap":

**1. Identify the gap.** `4f5e6d7` and two adjacent commits (`5g6h7i8`, `6j7k8l9`), three commits total in the uncovered range.

**2. Determine the reason.** Unlogged. Worth noting in the recovery bundle's annotation field.

**3. Conduct post-hoc review.** alice dispatches a Code RJ on the gap range. The reviewer returns a verdict at score 8.7, below the standard floor of 9.0. The verdict is recorded *with this lower score*; the recovery bundle's annotation will explicitly declare that the post-hoc verdict didn't meet floor.

**4. Author retroactive bundle:**

```bash
$ csae-author-bundle --retroactive \
  --range 4f5e6d7..6j7k8l9 \
  --verdict verdicts/retroactive-oauth-gap-2026-05-23T091500Z.md \
  --annotation "Retroactive attestation. Original push 2026-05-12 had no logged bypass record. Post-hoc review scored 8.7 (below floor 9.0). Chain integrity preserved at lower confidence level; consumers should weight audit value accordingly."
[csae-bundle] producing self-attestation commit: 8h9i0j1
[csae-bundle] WARN: retroactive mode; annotation declares post-hoc + sub-floor status
```

The self-attestation commit `8h9i0j1` lands on a recovery branch alice creates for the chain-repair, separate from her current work:

```bash
$ git push origin recovery/coverage-gap-2026-05-12
[csae-validator] retroactive-mode push: skipping standard coverage check
[csae-validator] ACCEPT (retroactive recovery branch)
```

**5. Publish the recovery bundle to the audit mirror:**

```bash
$ csae-publish-bundle --bundle bundles/retroactive-oauth-gap-2026-05-23T091500Z.md
[csae-publish] target: org/csae-audit-mirror
[csae-publish] OK (audit mirror tip: bundle_X12)
```

The chain now has the gap filled, but the bundle declares its retroactive + below-floor status explicitly. Future audits walking through this section see honest annotation: *"This was attested retroactively. The original push was unlogged. Post-hoc verdict was below floor."*

Audit confidence at this section: lower than eager-attestation sections, honestly so.

---

## Final state — audit chain

```
bundle_X9  (prior workstream, eager attestation)
  ↓
bundle_X10 (ws-auth-refactor, eager, verdict 9.4)
  ↓
bundle_X11 (next workstream, eager attestation)
  ↓
bundle_X12 (RETROACTIVE — coverage gap repair, verdict 8.7 below floor, annotation declares post-hoc status)
```

A future audit walking the chain sees the gap was filled with explicit honesty about lower-confidence status. The chain stays intact; the honesty preserves trust.

---

## What was non-obvious

Four moves in this walkthrough are worth calling out because they're easy to get wrong:

**1. Eager-registration preceded any substantive work.** If alice had registered intent after the work was done, the scope claim would be description, not authorization. The temporal property is what makes the chain load-bearing.

**2. Bundle pushed to audit mirror *before* canonical push.** The validator reads from the audit mirror, not from alice's worker tree. Reverse the order and the canonical push fails. The sequence is non-negotiable.

**3. The closure note cited the *canonical* SHA, authored *after* the merge.** The convergence ceremony cherry-picked the work, so the working-branch SHA became a content-twin that evaporates. Citing it before the merge would have left a dead closure SHA. Land first, cite second; verify the ancestry before recording.

**4. Retroactive attestation was honest about being retroactive.** The annotation field declares post-hoc status + sub-floor verdict. Pretending the chain was never broken would be worse than acknowledging the break. Audit value preserved at lower confidence rather than fake confidence.

The whole eager-attestation cycle (intent → work → review → bundle → mirror push → canonical push) took about 5 minutes of operator action on top of the actual work. The retroactive repair took about 20 minutes including the post-hoc review. The chain is now whole.

---

← Back to [`README.md`](../README.md) · [`PROTOCOL.md`](../PROTOCOL.md)

— Moran Bickel
