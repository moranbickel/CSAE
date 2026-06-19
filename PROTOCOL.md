# CSAE Protocol — Continuous Session-Attested Evidence

This is the formal specification of the protocol described informally in [`README.md`](./README.md). The README is the *why*; this is the *how*, with enough specificity that a reader can implement it without ambiguity.

The protocol has three concepts (intent registration, bundle authoring, audit mirror), one mechanical-enforcement layer (the validator), an explicit threat model, and a recovery discipline for when the chain breaks.

This document specifies invariants and workflow shape. It does not specify cryptographic substrate — point at [in-toto](https://in-toto.io), [Sigstore](https://www.sigstore.dev), or [SLSA](https://slsa.dev) for that layer. The methodology is what's distinctive; the primitives are standard.

---

## Vocabulary

| Term | Meaning |
|---|---|
| **Canonical** | The main branch that downstream consumers read. Typically `origin/main`. |
| **Audit mirror** | A separate repository (private or public) holding the attestation chain. Append-only at the branch level. Distinct keys from the primary repo. |
| **Scope claim** | An operator-authored declaration of *what work was authorized*, registered before the work begins. Lives in a registration commit on the worker branch. |
| **Intent registration** | The act of producing a scope claim before substantive work. Eager-registration discipline: registration precedes work, not follows it. |
| **Verdict** | An artifact produced by a reviewer (human, RJ, or other) recording that work passed review at a defined floor. Lives in a verdicts directory with its own signing/attestation. |
| **Bundle** | A markdown file or signed manifest that links a commit range to its scope claim and verdict references, with a self-attestation commit inside the range. |
| **Coverage** | A commit is *covered* if it falls within a bundle's claimed commit range *and* the bundle's chain integrity is intact. |
| **Self-attestation commit** | A commit within the bundle's covered range whose message embeds the bundle's content hash, predecessor bundle reference, and verdict references. |
| **Chain** | The linked sequence of bundles, each referencing its predecessor. Bottoms out at the first bundle (predecessor reference null). |
| **Validator** | A pre-push hook or required status check on canonical main that rejects pushes whose commits aren't covered. |
| **Floor** | The minimum acceptable verdict standard (defined per project — typically a numeric score plus a defect-class threshold). |
| **Bypass** | A logged exception that allows a push without bundle coverage. Bypasses are themselves audit-chain entries. |
| **Closure** | The act of recording that a work-item (a tracked task, backlog row, or milestone) is *verified-and-done*, citing the commit(s) that close it. A closure note is authored after the work lands on canonical main and cites the canonical commit, not a pre-merge working-branch SHA. |
| **Closure SHA** | A commit cited in a closure note as the verification for a closed work-item. Its integrity property: it MUST be an ancestor of the canonical branch (see Closure-SHA canonical binding). |
| **Mirror worktree** | A dedicated, ref-isolated working tree used only to publish to the audit mirror. Checked out in a detached-HEAD state at the canonical branch tip; its pushes never advance the working repository's branch refs. |

---

## The three concepts — formal definitions

### Intent registration

**Trigger:** Before any substantive commit on a worker branch.

**Preconditions:**
- An operator is initiating a session of work
- A workstream identifier is chosen (unique within the project's workstream namespace)
- A one-sentence intent statement is composable

**Procedure:**
1. Operator runs an intent-registration step (script, command, or manual commit) that produces a registration commit on the worker branch.
2. The registration commit's message embeds: the workstream identifier, the intent statement, a timestamp, and any session-level metadata (operator identifier, tooling version, etc.).
3. The registration commit's hash becomes the scope claim's identifier for downstream bundle references.

**Postconditions:**
- A registration commit exists on the worker branch
- The commit precedes any substantive work for the named workstream

**Invariants:**
- Registration is eager: a registration commit produced *after* substantive work is description, not authorization. Late registration breaks the temporal property the scope claim depends on.
- One workstream per registration. Bundling multiple workstreams into one scope claim produces bundles that are too large to verify meaningfully.

**Failure mode:** if a session aborts before bundle authoring, the registration commit is *stranded* (see Recovery).

---

### Bundle authoring

**Trigger:** A logical workstream completes (session end, milestone, coherent commit range ready to land).

**Preconditions:**
- A scope claim exists (from a prior intent registration commit `C_scope`)
- A commit range `[C_scope..C_work_end]` contains the substantive work for the workstream
- At least one reviewer verdict at floor exists covering the commit range
- The audit mirror is reachable (writable by the bundle author's key)

**Procedure:**
1. Identify the commit range `[C_scope..C_work_end]` for this workstream.
2. Identify the verdict reference(s) — each verdict's content hash plus its location in the verdicts directory.
3. Identify the predecessor bundle in the chain (the most recent bundle in the audit mirror for this project, or null for the chain's first bundle).
4. Produce a bundle file with the required fields (see Bundle Field Requirements below).
5. Produce a self-attestation commit `C_attest` on the worker branch. `C_attest`'s message embeds: the bundle file's content hash, the predecessor bundle reference, the verdict reference(s), and the scope-claim hash from `C_scope`.
6. The bundle's covered range becomes `[C_scope..C_attest]` — inclusive of registration, work, and self-attestation.
7. Push the bundle file to the audit mirror as a new commit there.
8. Push `[C_scope..C_attest]` to canonical main (typically via a convergence ceremony like [PWC](https://github.com/moranbickel/peer-worker-convergence) β.2).

**Postconditions:**
- A bundle exists in the audit mirror with predecessor → this → (future-successor) chain integrity
- A self-attestation commit exists on canonical main within the bundle's claimed range
- The canonical-main commit range is *covered* per the validator's definition

**Invariants:**
- The self-attestation commit is *inside* the covered range, not outside (see Self-Attestation Mechanics below)
- The bundle is published to the audit mirror *before* canonical main accepts the commit range (the validator depends on the bundle existing in the mirror)
- The bundle's predecessor reference points to a real, well-formed bundle in the audit mirror (or is null for the chain's first bundle)

---

### Audit mirror

**Trigger:** Bundle publication.

**Preconditions:**
- The audit mirror is a separate repository (distinct from the primary repo)
- The audit mirror's keys are distinct from the primary repo's keys
- Append-only branch protection is configured

**Procedure:**
1. Bundle author writes the bundle file to a new commit on the audit mirror's primary branch.
2. The commit is signed (with the audit-mirror author key) and pushed to origin.
3. The audit mirror's branch protection accepts the push if and only if it's a fast-forward.

**Postconditions:**
- The bundle is part of the audit mirror's append-only history
- The bundle is readable to audit consumers (compliance, due-diligence, attribution-resolution)

**Invariants:**
- No history rewriting on the audit mirror (no `--force` push, no branch deletion, no bundle modification once committed)
- Bundles are additive only; corrections take the form of new bundles that reference and explain (see Recovery)
- The audit mirror's read-side is stable; consumers can rely on bundle URLs/hashes being permanent

### Detached-mirror publishing

The audit-mirror push SHOULD be issued from a **dedicated mirror worktree** that is decoupled from the working clone, rather than from whatever branch the working clone happens to have checked out. This hardens the key/write separation the audit mirror depends on and removes a coupling that otherwise blocks the audit push behind the working repo's branch state.

**The problem it solves.** When the audit-mirror publish runs from the working clone, it inherits that clone's state: if the working clone is dirty, behind, or mid-ceremony on a feature branch, the publish stalls or has to be deferred. The audit trail — which is supposed to be the most durable, least-coupled artifact in the system — ends up gated on the most volatile one. Teams that defer the publish "until the working tree is clean" accumulate an audit-publish backlog, which is exactly the coverage-gap class the protocol exists to prevent.

**The mechanism.** Provision a separate worktree (sharing the primary repo's object store, so it costs no extra clone) checked out in a **detached-HEAD** state at the canonical branch tip. Publish from there:

1. The mirror worktree is reset clean and re-detached at the canonical tip before each publish (it carries no carried-over local state).
2. The bundle commit lands on the *detached HEAD*.
3. The push targets the canonical branch explicitly (`HEAD:main`), advancing the audit mirror's branch — **never** the working clone's local branch ref.

**Why detached, specifically.** Worktrees of one repository share branch refs. If the mirror worktree were checked out *on* the canonical branch and advanced it, it would move the canonical ref out from under the working clone that also has it checked out, corrupting that clone's view. A detached HEAD touches no branch ref: the working clone is untouched, and the audit publish can run at any time regardless of the working clone's state. The mirror worktree shares the object store (lightweight; no multi-gigabyte second clone) but isolates the ref.

**Invariants (detached-mirror specific):**
- The mirror worktree's HEAD is detached for the duration of the publish — a publish issued from a worktree that is *attached* to the canonical branch is refused, because it would advance the shared branch ref.
- The mirror push advances only the audit mirror's canonical branch; it never reattaches or advances the working clone's local branch ref.
- The mirror worktree is reset-clean and re-detached at the canonical tip before each publish; it is a transient publishing host, not a place to do work.

The legacy flow — publishing from a sibling clone of the working repo with the canonical branch checked out — remains valid for single-clone setups where no working clone shares the branch ref. The detached-mirror approach is the recommended default once more than one worktree shares the repository.

---

## Bundle field requirements

A bundle MUST contain:

| Field | Purpose |
|---|---|
| Bundle identifier | Unique within the audit mirror. Can be a content hash. |
| Scope claim reference | Hash of the registration commit `C_scope` |
| Workstream identifier | The identifier from the scope claim, for cross-bundle search |
| Commit range | `[C_scope..C_attest]` — inclusive of registration and self-attestation |
| Verdict reference(s) | One or more verdict identifiers (content hashes + paths) |
| Self-attestation commit reference | The hash of `C_attest` |
| Predecessor bundle reference | The previous bundle in the chain, or `null` for the chain's first bundle |
| Bundle author identifier | Typically the operator's signing key fingerprint |
| Timestamp | When the bundle was authored |

A bundle MAY contain:

- Free-form description (one paragraph max — the bundle is metadata, not narrative)
- Bypass acknowledgments if some commits in the range were not reviewed at floor (each acknowledgment names the commit, the reason, and the operator's explicit authorization)
- Annotation about exceptional circumstances (e.g., "retroactive attestation; chain-repair predecessor")

A bundle MUST NOT contain:

- Reviewer credentials directly (verdict references stand in)
- Operator credentials directly (the bundle is signed by the author; credentials aren't embedded)
- Substantive content of the work (no diffs, no source code — the bundle references the commit range, doesn't carry it)
- References to bundles in other projects' audit chains (chains don't cross-link between projects; each project's chain is self-contained)

---

## Validator semantics

The validator runs on push to canonical main (as a pre-push hook, a CI required status check, or both).

**Inputs:**
- The commit range being pushed (typically `origin/main..HEAD`)
- Read access to the audit mirror

**Procedure:**
1. For each commit `C` in the push range:
   - Find the bundle in the audit mirror whose covered range contains `C`.
   - If no such bundle exists: **REJECT** with diagnostic naming `C`.
   - If a bundle exists, verify the bundle's chain integrity:
     - Verdict references resolve to verdicts at floor in the verdicts directory.
     - Predecessor bundle reference resolves to a real, well-formed bundle (recurse).
     - Self-attestation commit exists within the bundle's claimed range.
     - Scope-claim hash matches the actual content of the registration commit.
   - If chain integrity is broken at any step: **REJECT** with diagnostic naming the broken link.
2. If all commits pass coverage and chain-integrity checks: **ACCEPT**.

**Output:** push succeeds (validator accepts) or push fails (validator rejects with diagnostic).

**Performance:** chain-integrity verification is O(N) in the number of bundles in the chain. For projects with long chains, cache verified-chain state at the audit-mirror level (the verifier doesn't need to re-walk the full chain on every push; it walks back to the last verified state).

**Bypass:** an environment-variable-mediated bypass (intentionally awkward; not a CLI flag) allows pushes without bundle coverage. Bypass invocations produce a bypass-record commit on the audit mirror that names the bypassed commits, the operator, the rationale, and the timestamp. The bypass-record is itself an audit-chain entry.

---

## Self-attestation mechanics

The self-attestation commit `C_attest` lives *inside* the bundle's covered range `[C_scope..C_attest]`, not outside. This section formalizes the property and explains why it's non-circular.

**Mechanics:**

1. The bundle B claims to cover the range `[C_scope..C_attest]`.
2. `C_attest`'s message embeds:
   - The content hash of bundle file B
   - A reference to the predecessor bundle (the last bundle in the chain before B)
   - References to verdict(s) at floor that cleared the work in `[C_scope..C_attest-1]`
   - The scope-claim hash from `C_scope` (which is in the range)
3. Verification of B walks the chain:
   - Resolve `C_attest`'s predecessor reference to a real bundle in the audit mirror.
   - Verify the predecessor bundle's own chain integrity (recursive).
   - Resolve `C_attest`'s verdict references to real verdicts in the verdicts directory.
   - Confirm the scope-claim hash in `C_attest` matches the content of `C_scope`.
   - Confirm `C_attest` is the actual commit it claims to be in the canonical-main range.

**Why this is non-circular:**

The skeptical reading is: *"The bundle attests itself. That's circular. The attestation has no force."*

The mechanics show otherwise. The attestation references two artifacts that exist *outside* B's covered range:

- The **predecessor bundle**, which was authored before B and is already in the audit mirror, independently signed and chained to its own predecessor.
- The **verdict(s)**, which were authored before `C_attest` by a reviewer with their own signing key, and which exist in the verdicts directory with their own integrity.

What `C_attest` claims is *correspondence*, not authority:
- *"These commits map to that scope claim."*
- *"These commits were reviewed under that verdict."*
- *"This bundle file (whose hash I embed) accurately describes the above."*

The chain extends one link forward by referencing one link backward. The chain's authority bottoms out at the first scope claim, which is an operator-authored decision and is therefore an irreducible primitive of authority for that project.

**What "non-circular" does and does not mean.** This is a precise, bounded claim: no link depends on *itself* or on a *successor* to be validated — every link is verifiable by walking back to predecessors that existed before it. It is **not** a claim of independent, zero-trust authority. The chain's ground truth bottoms out at the first operator-authored scope claim, and to a third party who does not trust the operator, that claim has no independent force — it asserts *"I scoped this honestly,"* which the chain can record but cannot prove. What CSAE gives a third-party auditor is **internal consistency and tamper-evidence** (these commits map to that scope claim under that verdict, and nothing in the chain has been altered since), not **external verification of the scope claim's truth**. Where independent force is required — compliance, due diligence, litigation discovery — anchor the chain head to an authority the auditor already trusts: an [RFC-3161](https://www.rfc-editor.org/rfc/rfc3161) timestamp, a [Sigstore/Rekor](https://www.sigstore.dev) transparency-log entry, or a signature from an independently-held key. That converts "trust the operator" into "trust a third party the auditor already accepts," which is the substrate CSAE deliberately leaves to your implementation (Path A).

**The self-include property** (that `C_attest` is in `[C_scope..C_attest]`, not outside) does load-bearing work:

- It binds the bundle file and the self-attestation commit together. Tampering with the bundle file would invalidate `C_attest`'s embedded content-hash claim; tampering with `C_attest` would put it outside the bundle's covered range.
- It makes the chain tamper-evident in the small: any modification to a bundle invalidates the bundle's self-attestation locally, which fails the validator on the next push.
- It removes the need for an external attestation authority. The chain is continuously self-referential; the audit mirror's append-only invariant is the only external constraint.

---

## Closure-SHA canonical binding

A bundle attests *that a commit range was reviewed under a verdict*. A **closure** is the adjacent act of recording *that a tracked work-item is verified-and-done, by citing the commit that closed it*. The two are different artifacts — a bundle lives in the audit mirror; a closure note lives wherever the project tracks work (a backlog row, an issue, a milestone record) — but they share a failure mode, and closure adds one integrity property the chain must hold.

**The integrity property.** When a closure note cites a commit as the verification for a closed work-item, the cited commit MUST be an ancestor of the canonical branch, and the closure note MUST be authored *after* the work has landed on canonical main. The note cites the **canonical** commit, never a pre-merge working-branch SHA.

**Why this matters — the SHA-evaporation failure.** Convergence ceremonies that reach canonical main via cherry-pick or rebase (rather than a fast-forward of the exact working-branch commits) produce *content-identical-but-different* SHAs on the canonical branch. The working-branch commit `W` and its canonical twin `C` have the same diff, author, and message — but different hashes. If a closure note is authored *before* the merge and cites `W`, that SHA evaporates the moment the working branch is cleaned up: `W` is no longer an ancestor of anything, and a future audit asking "is the commit that closed this work-item real and on canonical main?" finds a SHA that exists nowhere. The work was real; the citation is dead.

The fix is sequencing, not new machinery:

1. **Land first, cite second.** The work converges onto canonical main (through whatever ceremony the project uses). Only then is the closure note authored.
2. **Cite the canonical twin.** The closure note cites `C` (the ancestor of canonical main), not `W` (the working-branch commit that produced it).
3. **Verify the ancestry at write time.** Before recording a closure SHA, confirm it is an ancestor of the canonical branch. A SHA that fails the ancestry check is either a pre-merge working-branch SHA (cite its canonical twin instead) or a transcription error (correct it).

**Binding closure to the chain by construction.** A bundle's covered commit range, once the bundle's canonical push has landed, *is* a set of canonical commits by construction — every commit in `[C_scope..C_attest]` is an ancestor of canonical main at that point. A closure note that derives its cited SHA from the just-landed bundle's covered range therefore satisfies the canonical-binding property automatically: the closure SHA is canonical because it came from the post-landing range, and it is bound to a named verdict because the bundle that contains it references one. Authoring closures *from the bundle's post-landing range* makes the ancestry property hold by construction rather than by after-the-fact audit.

**Invariants:**
- A closure SHA is an ancestor of the canonical branch (verifiable: the ancestry check passes for every cited closure SHA).
- A closure note is authored after the work lands on canonical main, not before. A pre-merge closure annotation uses a *pending* marker ("verified locally; canonical SHA to be cited after convergence") and cites no SHA until the canonical commit exists.
- A closure SHA traces to a named verdict (directly, or via the bundle whose covered range contains it). A closure citing a commit that no bundle covers is a coverage-gap signal, not a valid closure.

**Relationship to retroactive attestation.** A pre-merge SHA discovered in an already-written closure note is a content-twin remediation, not a chain break: edit the note in place to cite the canonical twin (matching author + date + diff). This is cheaper than the coverage-gap recovery and should be applied whenever an audit surfaces a non-canonical closure SHA.

---

## Closure orchestration and the no-vacuous-attestation floor

The deterministic tail of a convergence-plus-attestation cycle — conform the review receipts, author the bundle, publish to the audit mirror, record the closures — is mechanizable. A **closure orchestrator** chains those steps into one fail-closed sequence and stops at the irreducibly-human boundaries. Its load-bearing contribution is a single gate: it refuses to produce a *vacuous attestation*.

### What a vacuous attestation is

A vacuous attestation is one whose form is valid but whose substance is empty:

- A bundle authored over an **empty commit range** — nothing was actually attested.
- A bundle authored with **no verdict reference**, or a placeholder verdict that names no real reviewer artifact — nothing was actually reviewed.
- A closure recorded against an **aggregate verdict that does not meet floor** but is presented as if it passed — the attestation claims a standard it didn't meet.

Each of these produces a chain entry that *looks* like a clean attestation and carries no information. At audit time, a vacuous attestation is worse than a missing one: the missing one prompts the question, the vacuous one silently answers it wrong.

### The floor gate

The orchestrator enforces, before it will author anything:

1. **Non-empty range.** The commit range being attested is real and non-empty. An empty range is a fail-closed halt.
2. **Named verdict, not placeholder.** At least one verdict reference resolves to a real review artifact (not a placeholder, not an empty path). No verdict references → fail-closed halt: *refusing to attest an empty closure.*
3. **Aggregate meets floor.** When multiple review rounds or review lanes feed one closure, the orchestrator aggregates the *terminal* verdict of each lane (the last round in each review chain) and checks the aggregate against the floor. A below-floor aggregate is recorded *truthfully* (the closure note declares the sub-floor status) — it is never silently presented as a pass. An aggregate that carries unresolved Critical/Important defects is a fail-closed halt: the closure does not proceed until the defects clear or the operator explicitly accepts a documented exception.

The floor gate keys off lane *terminals*, not every receipt: a clean terminal round passes even when an earlier round in the same lane failed (the failure is in the chain and visible; the lane ended at floor).

### Receipt conformance

Reviewers often author verdicts in a reviewer-native shape (a score, a round marker, a free-form verdict line) that omits fields the bundle schema requires. The orchestrator **conforms** each receipt to the bundle schema before authoring, deriving the missing bundle fields *truthfully* from what the receipt already states:

- The pass/fail assertion is **derived** from the score and defect counts against the floor — never copied from the reviewer's own hand-assertion. (A reviewer who writes "pass" on a sub-floor score does not get a passing bundle; the derived assertion overrides the claim.)
- The score and defect counts are **read** from the receipt's own fields, with a fallback to the receipt's verdict line.
- Conformance is **surgical**: it inserts the missing fields without rewriting the receipt's untouched content. It never round-trips the receipt through a serializer that would strip comments or reflow the file.
- Conformance **fails closed** on anything it cannot determine without fabricating judgment — a missing verdict identity, an unparseable score, a duplicate key whose authoritative value is ambiguous. It conforms a below-floor round *truthfully* (asserting non-pass); it does not gate it away.

### SHA canonicalization at closure time

When the convergence ceremony rebased or cherry-picked the work, the receipts were authored against pre-merge working-branch SHAs that have since evaporated (see Closure-SHA canonical binding). The orchestrator **canonicalizes** each receipt's cited range to the post-merge canonical range before authoring the bundle — so the SHAs the bundle attests, and the SHAs any derived closure cites, are the canonical ones. Without this step, a SHA-consistency check would correctly flag the stale working-branch SHAs as fabrication candidates; the canonicalization is what makes the check pass *honestly* rather than by disabling it.

### Human boundaries (preview-only)

The orchestrator automates the deterministic tail and **stops** at the steps that require human judgment, emitting a preview rather than executing them:

- The **commit-selection** that precedes the orchestrator (which commits belong to this workstream) is the operator's precondition, not the orchestrator's job.
- The **work-item state flip** (marking a tracked item done) previews the closure line but does not flip the state — a human verifies the closure premise and flips it.
- The **narrative wrapper** (the human-readable session summary) previews a stub for the operator to fill.

**Safety invariants:**
- Dry-run is the default and is side-effect-free. Execution is opt-in.
- Fail-closed: a non-zero step halts the chain; downstream steps do not run; the failing step is recorded.
- The state flip and narrative wrapper are never executed — only previewed.

---

## Composition with Russian Judge verdicts and Peer-Worker Convergence bundles

### Verdict references

The verdict reference field in a CSAE bundle is the artifact identifier of one or more reviewer verdicts. The reviewer (human or [Russian Judge](https://github.com/moranbickel/russian-judge)) produces a verdict artifact — typically a markdown file with structured fields (score, defect classification, pass status) — signed by the reviewer's key and stored in a verdicts directory in the primary repo (or in the audit mirror, depending on the project's choice).

The bundle references the verdict by content hash + path. The bundle does not embed the verdict's content (per Bundle Field Requirements: MUST NOT contain reviewer credentials or substantive content).

Verification at the validator: the validator follows the verdict reference, opens the verdict artifact, checks that the verdict is at floor (e.g., score ≥ 9.0 AND 0 Critical/Important defects, per RJ's standard floor). If the verdict isn't at floor, the bundle is invalid and the push is rejected.

### β.2 ceremony integration

In a peer-worker setup where canonical main is reached via [PWC](https://github.com/moranbickel/peer-worker-convergence)'s β.2 ceremony (precision-target side-branch), CSAE bundle authoring runs as a step within the ceremony:

1. **PWC steps 1-3** identify the commit range and create the side-branch from `origin/main`.
2. **CSAE step**: author the bundle for the side-branch's commit range. The bundle's commit range is `[C_scope..C_attest]` where `C_scope` is the worker's intent-registration commit, `C_attest` is the self-attestation commit appended to the side-branch.
3. **PWC step 4**: push the side-branch (now including the self-attestation commit).
4. **CSAE step**: push the bundle file to the audit mirror.
5. **PWC step 5**: merge the side-branch into canonical main. The validator fires; if the bundle is in the audit mirror and chain-integrity holds, the merge lands.
6. **PWC step 6**: verification — both PWC's ancestry check and CSAE's coverage check pass.

The two ceremonies interleave cleanly because they address different dimensions: PWC handles topology (which commits go where, with what attribution), CSAE handles attestation (what each commit traces back to). The interleaved ceremony is one operator action sequence; in practice it can be scripted as a single command.

### Independent use

You can run CSAE without RJ (informal review feeds verdict references; the verdict is whatever artifact the reviewer signs) or without PWC (single-worker setup; CSAE bundles attach to the worker's direct push). The bundle-authoring discipline is the load-bearing part; the surrounding ceremony shape is project-dependent.

---

## Anti-patterns

Eight anti-patterns. Each names what people try, why it fails, what to do instead.

### 1. "I'll register intent at session end after I know what shipped."

**What people try:** delay registration until the work is done, then write the scope claim to match.

**Why it fails:** late registration is description, not authorization. The temporal property — that the scope claim *preceded* the work — is what makes the claim load-bearing. A scope claim authored after the work has no constraining force; it's a summary.

**What to do instead:** register at session start, before the first substantive commit. If scope drifts mid-session, register an additional scope claim for the expanded workstream; don't retrofit the original.

### 2. "I'll bypass the validator for this small fix; I'll attest it next time."

**What people try:** skip CSAE for an "exceptional" commit, intending to clean it up later.

**Why it fails:** "I'll clean it up next time" is exactly how chains develop coverage gaps. Each ungentle gap requires retroactive attestation, which is honest but lower-confidence. A chain with many gaps is a chain with many "we'll get to it" annotations — and at audit time, those annotations are the first thing that erodes trust.

**What to do instead:** bypass with a documented bypass-record (logged at the audit mirror), or take the 30 seconds to register intent + author a bundle for the small fix. The discipline costs less than the audit-trail-debt accumulates.

### 3. "I'll use the same scope claim for multiple sessions."

**What people try:** register a broad scope claim once ("ws-refactor"), then run multiple sessions under it, authoring one massive bundle at the end.

**Why it fails:** large bundles are unverifiable in practice. A reviewer asked "did this fifty-commit bundle's review verdict actually cover all fifty commits?" can't easily answer. The bundle's scope claim becomes too coarse to constrain anything.

**What to do instead:** one scope claim per session, one bundle per scope claim. The chain has more links; each link is verifiable in isolation.

### 4. "I'll skip CSAE on docs-only changes."

**What people try:** decide that docs commits are "low-stakes" and not worth the attestation overhead.

**Why it fails:** docs changes can be exactly the audit question someone asks later. *"Who authorized renaming the customer-facing term?"* The docs change looked harmless; the dispute it caused was real.

**What to do instead:** CSAE applies to all commits landing on canonical main, regardless of perceived stakes. The overhead is minimal once the discipline is internalized.

### 5. "I'll author the bundle on the worker tree and rely on the convergence ceremony to land it."

**What people try:** treat the bundle as a worker-tree artifact, rely on the merge to push everything together.

**Why it fails:** the validator on canonical main checks the audit mirror, not the worker tree. If the bundle hasn't been pushed to the audit mirror before the canonical push, the validator rejects. The bundle has to land in the mirror first, then the canonical push references it.

**What to do instead:** sequence is *bundle to audit mirror → wait for confirmation → canonical push*. The order is non-negotiable; the validator depends on it.

### 6. "I'll include the verdict file content directly in the bundle."

**What people try:** embed the full verdict in the bundle rather than referencing it.

**Why it fails:** embedding creates the appearance of self-evidence (the bundle "contains" the verdict) but undermines the separation between work-attestation (bundle) and review-attestation (verdict). The verdict has its own signing key, its own integrity, its own attestation chain. Embedding collapses two layers into one and breaks the property that the validator can check the verdict's freshness and integrity independently.

**What to do instead:** the bundle references the verdict by content hash + path. The validator resolves the reference at check time. The verdict and the bundle stay separately auditable.

### 7. "I'll write the closure note now and cite the commit I just made on my working branch."

**What people try:** record a work-item as closed, citing the working-branch commit, before the work has converged onto canonical main.

**Why it fails:** if the convergence ceremony cherry-picks or rebases, the working-branch SHA becomes a content-identical-but-different canonical twin and the cited SHA evaporates when the working branch is cleaned up. A future audit asking "is the commit that closed this real and on canonical main?" finds a SHA that exists nowhere. The work was real; the citation is dead.

**What to do instead:** land first, cite second. Author the closure note *after* the work reaches canonical main, and cite the canonical commit (the ancestor of canonical main), not the working-branch commit. Verify the ancestry before recording the SHA. If you must annotate a closure before convergence, use a *pending* marker and cite no SHA until the canonical commit exists. (See Closure-SHA canonical binding.)

### 8. "I'll author the bundle even though the range is empty / the verdict is a placeholder; the chain entry is what matters."

**What people try:** produce a chain entry to keep the cadence going, over an empty commit range or with a placeholder verdict reference, intending to "fill it in later."

**Why it fails:** a vacuous attestation is worse than a missing one. The missing entry prompts the audit question; the vacuous entry silently answers it wrong — it looks like a clean attestation and carries no information. A chain that accumulates vacuous entries is a chain whose pass entries can't be trusted on their face.

**What to do instead:** the floor gate refuses to author over an empty range, with no real verdict, or with an aggregate that doesn't meet floor. If there is genuinely nothing to attest, author nothing. If the work is real but below floor, attest it *truthfully* — the closure note declares the sub-floor status rather than presenting it as a pass. (See Closure orchestration and the no-vacuous-attestation floor.)

---

## Recovery

The discipline across every recovery scenario is one principle: **don't compound the failure.** A break in the chain creates a divergent state; the fix is to converge back through the protocol, not to bypass it.

### Recovery from stranded intent

**Symptom:** a registration commit exists on a worker branch (or canonical main), but no bundle ever covered it. The session ended without bundle authoring — work was abandoned, scope changed, machine crashed.

**Procedure:**

1. **Determine the disposition.** Was the work abandoned (no commits beyond the registration), partially completed, or completed but unbundled?
2. **For abandoned scope:** author a "no-op bundle" that closes the workstream as abandoned. The bundle's covered range is `[C_scope..C_attest]` where `C_attest` is the no-op self-attestation. The bundle's verdict reference can point at a self-authored "abandonment record" (signed by the operator) rather than a reviewer verdict. The chain remains intact; the workstream is honestly recorded as abandoned.
3. **For partially completed work:** author a bundle covering the work that was done, with a reviewer verdict on the partial scope. The bundle's annotation field records that the original scope was broader; the actual covered range is what was completed.
4. **For completed but unbundled work:** retroactive attestation (see next subsection).

The thing to avoid is *silently* leaving stranded intent. Stranded registration creates the appearance of unfinished authorized work and erodes chain trust.

### Recovery from a coverage gap

**Symptom:** commits exist on canonical main without matching bundle attestation. Either the validator was bypassed (with logged bypass, hopefully) or it was misconfigured.

**Procedure:**

1. **Identify the gap.** Determine which commits on canonical main aren't covered by any bundle in the audit mirror.
2. **Determine the reason.** Was there a logged bypass? If so, the bypass-record itself is the audit-chain entry; the gap may not need additional remediation beyond confirming the bypass-record is well-formed. If no logged bypass exists, the gap is unauthorized.
3. **Retroactive attestation.** Author a bundle covering the gap. The bundle's annotation field explicitly notes the retroactive status: *"This bundle was authored after the commits it covers, in response to discovering an unattested gap."* If post-hoc review can be conducted, reference the post-hoc verdict; if not, note explicitly that no review preceded the commits.
4. **Honesty over appearance.** Retroactive attestation has lower audit confidence than eager attestation. The annotation makes this visible. Pretending the chain was never broken is worse than acknowledging the break.

### Recovery from a compromised key or tampered audit mirror

**Outside CSAE's direct scope** — this is a primitive-layer concern. Apply standard key-rotation discipline (see Sigstore, in-toto). If the audit mirror itself is suspected tampered, the recovery requires forensic reconstruction from independent copies (audit mirrors should be replicated for exactly this reason).

The CSAE-specific response: after key rotation or mirror reconstruction, author a "chain repair" bundle that explicitly marks the transition. Downstream bundles reference the repair bundle as their new predecessor; the pre-compromise chain remains visible in history but is marked as "pre-key-rotation."

### Recovery from a cascading break

**Symptom:** a break early in the chain that everything after the break references. Discovered when an audit walks back and hits a broken link.

**Procedure:**

1. **Identify the break.** Walk the chain backward from a recent bundle until a link fails. Note the failing bundle.
2. **Determine the scope of the break.** What's the earliest bundle that depends on the broken link? Everything after that is affected.
3. **Chain repair.** Author a chain-repair bundle that names the break explicitly: which bundle is broken, what the break is (missing verdict reference, malformed predecessor, etc.), and what's recoverable. The repair bundle becomes the predecessor for the recoverable subchain going forward.
4. **The break stays visible.** Don't paper over the break by removing the broken bundle from the mirror; the append-only invariant forbids that. The break remains as a historical record; the repair bundle acknowledges it; downstream chains reference the repair.

---

## Threat model

CSAE's threat model is *honest teams operating in good faith who need verifiable records for later questions*. The protocol provides:

- **Audit reconstruction:** given a commit on canonical main, the chain answers *who authorized what, under whose review, when*.
- **Tamper evidence:** modifications to a bundle invalidate the bundle's self-attestation locally; modifications to the audit mirror require violating its append-only invariant, which leaves forensic traces.
- **Attribution clarity:** AI-assisted commits, bundled commits, and operator-authored commits are distinguishable by chain-walk.

CSAE does **not** provide:

- **Defense against adversarial signing.** A determined adversary with key access can forge a bundle. CSAE assumes the underlying signing primitives (PGP, Sigstore, etc.) are sound; if they're compromised, CSAE's chain is compromised at the same point.
- **Defense against reviewer collusion.** If the reviewer and the operator collude to author a verdict that passes a bundle through despite substantive issues, CSAE's chain shows a clean verdict — because there is a clean verdict. The chain captures *what was attested*, not *whether the attestation was substantively correct*.
- **Defense against compromised audit mirror.** If the audit mirror itself is tampered (write keys compromised, branch protection bypassed), forensic reconstruction requires independent replicas. Mirror replication is standard practice for this reason.
- **Forward secrecy.** A compromise of current keys retroactively undermines the integrity of past bundles signed with those keys. Standard key-rotation discipline applies; CSAE does not provide stronger guarantees than the underlying primitives.

The protocol is a methodology layer above well-audited cryptographic primitives. It assumes the primitives are sound and provides structure on top. Use [Sigstore](https://www.sigstore.dev) / [in-toto](https://in-toto.io) for the primitives; CSAE for the workflow shape.

---

## Verification

Quick incantations to confirm the chain is intact:

| Check | Approximate command shape | Expected |
|---|---|---|
| A specific commit is covered | `csae-verify --commit <SHA>` | bundle ID returned; chain walks back to first scope claim |
| A bundle is well-formed | `csae-verify --bundle <bundle-id>` | predecessor resolves; verdict references resolve; self-attestation present in claimed range |
| The full chain is intact | `csae-verify --full` | every bundle's predecessor resolves; no broken links from chain head to chain tail |
| The audit mirror's append-only invariant holds | `git log --diff-filter=DM origin/main -- bundles/` | empty (no deletions, no modifications) |

The exact tooling depends on your implementation substrate. The verification logic is what matters: walk the chain, resolve references, verify integrity at each link.

Run a full chain verification at least monthly, and immediately after any suspected break.

---

## Glossary

- **Audit mirror** — separate repository holding the append-only attestation chain
- **Bundle** — the markdown/manifest artifact linking a commit range to its scope and review
- **Chain** — linked sequence of bundles, predecessor-referenced
- **Coverage** — property of a commit being within a well-formed bundle's claimed range
- **Floor** — minimum acceptable verdict standard (project-defined)
- **Intent registration** — pre-work scope-claim authoring (eager-registration discipline)
- **Predecessor bundle** — the previous bundle in the chain; provides the recursive integrity property
- **Scope claim** — operator-authored declaration of what work was authorized
- **Self-attestation commit** — the commit within a bundle's range whose message embeds the bundle's integrity references
- **Validator** — pre-push hook or CI check rejecting pushes without coverage
- **Verdict** — reviewer artifact recording that work passed review at floor
- **Verdict reference** — content-hash + path identifier of a verdict; bundle field

---

For the informal motivation and the failure-it-solves story, see [`README.md`](./README.md). For a complete walkthrough including a coverage-gap recovery, see [`examples/attestation-walkthrough.md`](./examples/attestation-walkthrough.md).

— Moran Bickel
