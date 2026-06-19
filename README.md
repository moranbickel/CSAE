# CSAE — Continuous Session-Attested Evidence

**A protocol for attesting AI-generated commits to an audit chain that survives the next question.** Names the trust gap that opens when AI-assisted commits land on canonical main without verifiable provenance, and gives you the chain — intent registration, bundle authoring, audit mirror — that closes the gap before someone has to ask.

If you've ever looked at a months-old commit, seen "AI assistant" in the author field, and realized you couldn't reconstruct *who approved it, against what scope, under which reviewer's verdict* — this is the protocol.

I built it while developing [ORCA](#about-orca), an AI legal reasoning system for Israeli civil litigation. It's part of a series of methodology pieces I'm publishing from that work, alongside [Russian Judge](https://github.com/moranbickel/russian-judge), [Three-Body Protocol](https://github.com/moranbickel/three-body-protocol), and [Peer-Worker Convergence](https://github.com/moranbickel/peer-worker-convergence).

---

## The failure it solves

Three months into a project, someone asked who had approved a particular schema migration.

The commit message said the AI assistant authored it. There was no PR — the team had been bundling commits in a workflow that bypassed code review by design. The reviewer's verdict was in a Slack thread that had aged out of the search window. `git log` knew nothing useful.

The change was correct. The audit trail was empty.

What surfaced when the team looked back: every commit since they'd started using AI-assisted work had the same gap. Hundreds of commits with no verifiable record of who reviewed what, under whose authorization, against which scope claim. The work was probably fine. There was no way to prove it.

That's the failure mode CSAE fixes — before someone has to ask the question.

The gap isn't about *whether* the work was good. It's about whether the record exists to demonstrate that it was. Once AI assistants are doing meaningful authoring, the meaningful authorial decision is the operator's — *what scope, what review, what authorization* — and `git log` is not the medium that captures it. CSAE is the medium that does.

---

## What CSAE is not

CSAE is **not** full supply-chain attestation. [SLSA](https://slsa.dev) addresses build systems, dependency chains, and artifact provenance from source to deployment. CSAE is narrower: it addresses the commit-landing-on-main boundary, not the broader build-and-distribute chain. If you need both, run both.

It's **not** a substitute for code review. A signed bundle that points at a reviewer's verdict doesn't replace the verdict — it carries the verdict into a durable chain. The review still has to happen. [Russian Judge](https://github.com/moranbickel/russian-judge) is one shape of structured review that composes cleanly with CSAE; informal PR comments are another. The bundle attests *that* review happened and *what it concluded*; it does not attest *that the review was good.*

It's **not** commit-signing alone. `git commit -S` verifies that the commit's claimed author actually held the signing key at the time of the commit. That's a primitive. CSAE chains primitives like this into a higher-level structure: scope claim + commit range + verdict reference + self-attestation, all linked to predecessors and successors. The chain is the contribution; the primitives are inputs.

It's **not** anti-fraud at the cryptographic level. A determined adversary with key access can forge a bundle. CSAE's threat model is *honest teams operating in good faith who need verifiable records for later questions* — audit, attribution dispute, compliance review, due diligence. If your threat model includes adversarial signing, CSAE provides defense in depth but isn't the final layer.

And it's **not** a complete attestation solution by itself. It's one layer in a stack that, in my own practice, also includes adversarial review ([Russian Judge](https://github.com/moranbickel/russian-judge)) and topology convergence ([Peer-Worker Convergence](https://github.com/moranbickel/peer-worker-convergence)). Each layer answers a different question; the stack as a whole answers more than the layers individually.

---

## CSAE vs alternatives

| Dimension | Ad-hoc audit (`git log` + memory) | `git commit -S` (signed commits) | [SLSA](https://slsa.dev) | [Sigstore](https://www.sigstore.dev) / [in-toto](https://in-toto.io) | GitHub-native CI/CD | CSAE |
|---|---|---|---|---|---|---|
| Scope | Per-commit, informal | Per-commit, cryptographic | Build pipeline → artifact | Build artifact → consumer | Source → merge gate → artifact | Commit-range → canonical main |
| What's attested | Whatever `git log` recorded | Authorship (key held the commit) | Build provenance | Artifact provenance + transparency log | Workflow identity + artifact signature + "checks passed" | Scope claim + review verdict + self-attestation |
| Trust root | Memory, Slack search, PRs | The key trust hierarchy | Build platform attestation | Sigstore transparency log + Fulcio | GitHub OIDC issuer + Fulcio/Rekor + branch-protection config | Predecessor bundle + reviewer verdict + operator scope claim |
| Recovery from "who approved this?" | Often impossible | Author yes; reviewer no | N/A — different question | Artifact-level; commit-level limited | Review occurred (branch protection); scope/authorization not recorded | The bundle carries the answer |
| Operational burden | Zero (until you need it) | Low (one config flag) | Medium-high (build infra changes) | Medium (signing + verification) | Low-medium (platform-provided) | Medium-high (eager intent registration + bundle authoring + separate audit mirror + pre-push hook) |
| Best for | Solo dev, low-stakes work | Teams that just want authorship | Regulated build pipelines | Open-source artifact distribution | Teams already all-in on GitHub Actions | AI-assisted teams needing commit-level provenance |

*"GitHub-native CI/CD" is the integrated stack a DevSecOps reader reaches for first: protected branches + required status checks (review happened) + keyless [Cosign](https://docs.sigstore.dev/cosign/signing/overview/) signing under the [Actions OIDC](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect) identity (artifact tied to the workflow). See [Related work](#related-work) for where it stops and CSAE begins.*

CSAE doesn't replace the others; it fills the gap at the commit-landing layer that the others either don't address or address at the wrong granularity. If your project also distributes artifacts, you probably want both CSAE (commits → main) and SLSA-or-equivalent (main → release).

---

## Composition with [Russian Judge](https://github.com/moranbickel/russian-judge) and [Peer-Worker Convergence](https://github.com/moranbickel/peer-worker-convergence)

The three pieces form an attestation triangle. Each addresses a different question; together they make AI-assisted work auditable end to end.

- **Russian Judge** answers *was the work reviewed, and to what bar?* Its verdicts are structured: score, defect classification, pass floor. A verdict is an artifact you can point at.
- **Peer-Worker Convergence** answers *how did the work land on canonical main without scope blur?* Its β.2 ceremony bundles a worker's commits into a precision-target side-branch that's exact in attribution.
- **CSAE** answers *can anyone verify, months later, that the right work landed under the right review under the right authorization?* It chains the RJ verdict and the PWC bundle into a durable record.

The composition in practice: a peer-worker session ends, β.2 runs, the side-branch carries exactly that session's commits, and the CSAE bundle authored as part of β.2 references the RJ verdict that cleared the work plus the operator's scope claim from session start. Three layers, one ceremony.

You can run CSAE without the other two — informal review feeds bundle authoring, single-worker setups skip the convergence layer — and you still get most of the audit-trail benefit. But the trio compounds: with all three running, the question *"who approved this, against what, under whose authorization?"* is answerable in seconds rather than archeology.

---

## The protocol, at a glance

Three concepts. One mechanical-enforcement layer. One audit-trail repo.

**1. Intent registration.** Before substantive work, the operator registers a scope claim: a workstream identifier and a one-sentence intent statement. This produces a small registration commit on the worker branch that marks "what the operator authorized, before any work happened." The eager-registration discipline matters — registration at session-end (after the work is done) loses the temporal property of "this scope claim preceded the work." Registration that comes *after* the work is just a description of the work; registration that comes *before* is an authorization.

**2. Bundle authoring.** When a logical workstream completes — typically at session end, or when a coherent commit range is ready to land — the operator authors a bundle. The bundle carries:

- The scope claim from the intent registration (the *what was authorized*)
- The commit range the bundle covers (the *what shipped*)
- References to the reviewer verdict(s) at floor (the *what passed review*)
- A self-attestation commit within the bundle's own commit range (see below)

The bundle is a markdown file or signed manifest with these fields; the exact format is operator's choice. The content matters more than the encoding.

**3. Self-include attestation.** The bundle's attestation commit lives *inside* the commit range the bundle attests. This sounds circular and isn't — it's what makes the chain continuously self-referential rather than depending on an external authority.

The non-circularity works like this: the attestation references (a) the *prior* reviewer verdict, which already exists and is signed, and (b) the scope claim from registration, which *preceded* the work. The self-include commit doesn't claim authority over the work it's attesting — it claims correspondence: *these commits map to that scope claim, were reviewed under that verdict, and I (the bundle author) certify that the correspondence is honest.* The audit chain extends one link forward by referencing one link backward. No external authority is required because the chain's authority comes from the predecessors it links to.

Outside reviewers tend to read this move as either elegant or suspicious on first encounter. The elegance is that the chain is self-supporting: any link can be verified by walking back to the predecessor verdict and the predecessor scope claim, neither of which depended on the current bundle's existence. The suspicion is "but who attests the attestation?" — and the answer is *the previous link did, recursively*. The chain bottoms out at the first scope claim, which is an operator-authored decision.

Be precise about what that buys you. "Non-circular" means no link needs itself or a successor to be validated — not that the chain is independently authoritative. To a third party who doesn't trust the operator, the first scope claim is still just *"I scoped this honestly."* CSAE gives that auditor **internal consistency and tamper-evidence**, not **proof the scope claim is true**. Where you need the latter (compliance, due diligence, litigation), anchor the chain head to an authority they already trust — an RFC-3161 timestamp or a Sigstore/Rekor transparency-log entry. See [`PROTOCOL.md`](./PROTOCOL.md) §Self-attestation mechanics.

**4. Audit mirror.** Bundles publish to a separate tamper-evident repository — the audit-trail mirror — where they're append-only and cryptographically linkable to each other. The mirror serves two purposes: it survives a compromise of the primary repo (an attacker would have to compromise both repos to forge the chain), and it provides a stable read-side for downstream audit, due-diligence, or attribution-resolution work.

**Mechanical enforcement: the validator.** A pre-push hook on the canonical main (or equivalent CI-level required check) verifies that every commit being pushed is covered by an attested bundle that's already in the audit mirror. Pushes that fail coverage are rejected. The operator's bypass (for legitimate exceptional cases — release tags, manual recovery, ceremonial commits) is intentionally awkward and produces a logged bypass record that becomes itself an audit-chain entry.

**Three integrity properties on top of the core loop** (formal treatment in [`PROTOCOL.md`](./PROTOCOL.md)):

- **Detached-mirror publishing.** The audit-mirror push runs from a dedicated, ref-isolated worktree in a detached-HEAD state at the canonical tip — decoupled from the working clone, so the audit trail never stalls behind a dirty or mid-ceremony working tree. (§"Audit mirror" → "Detached-mirror publishing".)
- **Closure-SHA canonical binding.** When a work-item is recorded as closed "verified by commit X," the cited SHA must be an ancestor of the canonical branch, and the closure note is authored *after* the merge — so it cites the canonical commit, not a pre-merge working-branch SHA that evaporates via cherry-pick or rebase. (§"Closure-SHA canonical binding".)
- **No-vacuous-attestation floor.** A closure orchestrator conforms the review receipts to the bundle schema and refuses to attest an empty range, a placeholder verdict, or an aggregate that doesn't meet floor — an attestation must cover real work bound to a named verdict. (§"Closure orchestration and the no-vacuous-attestation floor".)

---

## A worked example

Imagine a session refactoring a database schema. The operator wants the work auditable.

**Session start — intent registration:**

The operator runs an intent-registration command that takes a workstream ID and a one-sentence intent. The command produces a small registration commit on the worker branch — call it `commit_A0` — whose message embeds the workstream metadata. This commit precedes any substantive work and is part of the audit chain's "before" boundary.

**Work happens.** The operator and an AI assistant produce commits `commit_A1` through `commit_A5`. These touch the schema, the consuming code, and the tests.

**Session end — review.** The operator dispatches a Russian Judge review (or equivalent structured review) on the commit range. The reviewer returns a verdict file — call it `verdict_v0` — with score, defect classification, and pass/fail status. The verdict lives in a verdicts directory and is signed by the reviewer.

**Bundle authoring.** The operator runs a bundle-authoring step that reads:
- The intent registration from `commit_A0` (the scope claim)
- The commit range `commit_A0..commit_A5` (the work shipped)
- The verdict reference `verdict_v0` (the work passed review)

The step produces a bundle markdown file and a self-attestation commit `commit_A6` that lands on the worker branch. The bundle file lives in the audit-mirror tree; the self-attestation commit's message references the bundle file's content hash, the verdict reference, and the scope claim from `commit_A0`.

The bundle's covered range is now `commit_A0..commit_A6` — the registration commit, the work commits, and the self-attestation commit itself. That last inclusion is what makes the attestation self-referential and tamper-evident in the small.

**Audit-mirror publish.** The operator pushes the bundle file to the audit-mirror repository. The audit mirror's history grows by one bundle entry. Each new bundle's metadata references the previous bundle in the chain.

**Canonical push.** The operator pushes `commit_A0..commit_A6` to canonical main (typically via [PWC](https://github.com/moranbickel/peer-worker-convergence)'s β.2 ceremony). The pre-push validator checks that every commit being pushed is covered by an attested bundle in the audit mirror. The push lands.

**Three months later.** Someone asks who approved the schema change. The audit chain walks:
- `commit_A3` (the actual schema change) → covered by bundle `B_A`
- Bundle `B_A` → references verdict `verdict_v0` and scope claim `ws-schema-cleanup`
- `verdict_v0` → signed by the reviewer, with score, defect list, pass status
- Scope claim → operator-authored registration in `commit_A0`

The answer comes back in seconds rather than archeology.

---

## Where teams actually break the chain

Three failure modes seen in practice often enough to surface as field-manual entries. Abstract anti-patterns live in [`PROTOCOL.md`](./PROTOCOL.md); these are the operational signals.

**Forgot intent registration.** *Signal:* work commits on canonical main with no preceding registration commit; `git log --grep="<workstream-id>"` returns work but no scope claim. *Why broke:* eager-registration discipline skipped; no `C_scope` exists for any bundle to reference. *Recover:* [Stranded intent](./PROTOCOL.md#recovery-from-stranded-intent) — retroactive bundle, honest about the gap.

**Landed uncovered commits on main.** *Signal:* commits on `origin/main` whose hashes don't match any bundle in the audit mirror; usually discovered when a future chain-walk hits an unattested predecessor. *Why broke:* validator was bypassed (logged or unlogged) or a force-push routed around coverage. *Recover:* [Coverage gap](./PROTOCOL.md#recovery-from-a-coverage-gap) — retroactive bundle with annotation declaring post-hoc status.

**Bundle published after canonical push, not before.** *Signal:* canonical push fails with the validator's "not covered" diagnostic; bundle file exists in worker tree but isn't yet in audit mirror. *Why broke:* sequence violation — the validator reads from the audit mirror, not from the local worker tree. *Recover:* push the bundle to the audit mirror first, confirm the push succeeded, then re-attempt the canonical push. No data loss; just sequence correction.

---

## Recovery

CSAE has four failure modes worth naming as classes. The discipline across all of them is the same as in [PWC](https://github.com/moranbickel/peer-worker-convergence): **don't compound the failure.** A break in the chain creates a divergent state; the fix is to converge back through the protocol, not to bypass it.

**Stranded intent.** The operator registered a scope claim but the session ended without bundle authoring (work abandoned, machine crashed, scope changed mid-flight). The registration commit exists on the worker branch but no bundle ever covered it. **Recovery:** either author a "no-op bundle" closing the workstream as abandoned (auditable abandonment is fine), or include the registration commit in the next bundle whose scope honestly covers it. The thing to avoid is *silently* leaving stranded intent — that creates the appearance of unfinished authorized work.

**Coverage gap.** Commits exist on canonical main without matching bundle attestation. Either someone bypassed the validator (logged bypass, hopefully) or the validator was misconfigured. **Recovery:** retroactive attestation — author a bundle that covers the gap commits, reference the post-hoc review (if one exists) or note explicitly that no review preceded the commits. Retroactive attestation is honest about being retroactive; it doesn't pretend the chain was never broken. The audit value is preserved at a lower confidence level.

**Compromised key or audit-mirror tampering.** Outside CSAE's scope per the threat-model note above. Standard key-rotation discipline (see Sigstore, in-toto) and standard tamper-evident-log discipline apply. CSAE depends on the underlying primitives being sound; if they're compromised, CSAE's chain is compromised at the same point the primitives are.

**Cascading break.** A break early in the chain that everything after the break references. This is the most expensive recovery. **Procedure:** mark the break explicitly with a "chain repair" bundle that names the break, declares what's recoverable downstream of it, and starts a new sub-chain from the repair bundle forward. Downstream bundles reference the repair bundle as their predecessor. The break stays visible in history; the chain continues forward with the break acknowledged rather than papered over.

---

## When to use it — and when not to

**Use it when:**
- Your team produces AI-assisted commits on a canonical main that may later need provenance reconstruction
- Retention of the main branch extends past the working memory or chat-search reach of the operators
- The cost of *"we can't reconstruct who approved this"* is higher than the ceremony cost
- Multiple operators or AI assistants share commit authority against the same canonical main

**Don't use it when:**
- You're doing casual solo work or hobby branches — no operator-attention sharing, no retention need
- Your team already runs disciplined PR review with decent retention — PRs and indexed search serve the same function
- Short-lived feature branches where the audit need ends at merge
- Experimental or scratch work where the ceremony cost outweighs the audit value

The gate isn't *"do you use AI?"* It's *"will someone need to reconstruct, months later, who authorized what under whose review?"* If yes, CSAE earns its weight. If no, the ceremony cost isn't worth it.

---

## Adopt the mechanics in 30 minutes; internalize the discipline over a week

1. **Decide the scope.** Which commits need attestation? Typically: all AI-assisted commits, plus anything landing on canonical main. If you're starting on an existing project, declare a cutover date and accept that pre-cutover commits don't have CSAE attestation — that's the honest starting state.
2. **Set up the audit-mirror repository.** A separate Git repo (private or public depending on your audit needs) that holds the bundle files. It should be tamper-evident — typically append-only via branch protection, or signed by a key separate from the primary repo's keys.
3. **Adopt the intent-registration discipline.** Run intent registration at session start, before the first non-trivial commit. The eager-registration property is what makes the scope claim load-bearing.
4. **Adopt the bundle format.** Decide what fields your bundles carry. Minimum viable: scope claim, commit range, verdict reference, self-attestation. Standardize the format so any future operator can read a bundle without context.
5. **Install the pre-push validator.** A Git hook or CI required check on canonical main that verifies every push's commits are covered by a bundle already in the audit mirror.

The setup is 30 minutes. The discipline takes a week to internalize. The first time you forget to register intent and have to do a retroactive bundle, you'll feel the chain-integrity tax. The third time you reach for a release-tag bypass and *don't* take it, the discipline will feel automatic.

For the formal protocol — invariants, bundle field requirements, validator semantics, audit-mirror discipline, recovery procedures — see [`PROTOCOL.md`](./PROTOCOL.md). For a complete walkthrough including a coverage-gap recovery, see [`examples/attestation-walkthrough.md`](./examples/attestation-walkthrough.md).

---

## Related work

I surveyed the field before publishing. CSAE sits in an active area; the closest pieces:

**[in-toto](https://in-toto.io)** is the closest sibling — an attestation framework for software supply chains with a chain-of-custody model that generalizes well. CSAE could be implemented as an in-toto layout; the differences are scope (CSAE is commit-level, in-toto spans pipelines) and audience (CSAE targets AI-assisted teams; in-toto targets supply-chain security teams). If you adopt CSAE and need broader supply-chain attestation, in-toto is the natural next layer.

**[Sigstore](https://www.sigstore.dev)** provides signing infrastructure (Cosign for artifacts, Gitsign for commits) and a transparency log (Rekor). CSAE chains can be cryptographically grounded in Sigstore primitives — the bundle itself can be a Cosign-signed artifact, the audit mirror can be a Rekor entry. CSAE is the methodology; Sigstore is one possible implementation substrate.

**GitHub-native CI/CD (Actions OIDC + keyless Cosign + protected branches)** is the integrated stack a DevSecOps engineer reaches for first, and the closest thing to a turnkey alternative. Protected branches with required status checks enforce that review happened before a merge; keyless [Cosign](https://docs.sigstore.dev/cosign/signing/overview/) signing under the workflow's [OIDC](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect) identity ties an artifact to the pipeline that produced it; Rekor logs it. It's strong, low-friction, and the right default if you already live in GitHub Actions. Where it stops is CSAE's specific binding: branch protection attests *that a review occurred*, not *that this was the scope authorized before any code was written*, and the platform's provenance is artifact-centric — it doesn't record the *commit-range → canonical-main* correspondence to a named reviewer verdict at the granularity CSAE chains. It also couples the audit trail to GitHub. CSAE is platform-neutral methodology that sits on top of exactly these primitives: use Actions OIDC + Cosign as the substrate, and CSAE for the scope-claim / verdict / commit-range binding the platform leaves implicit.

**[SLSA](https://slsa.dev)** (Supply-chain Levels for Software Artifacts) is broader-scope than CSAE — it addresses build provenance from source to deployment. CSAE addresses the source-to-main slice that SLSA largely assumes is solved. The two are complementary; teams running both get end-to-end attestation from operator intent through deployed artifact.

**[Developer Certificate of Origin (DCO)](https://developercertificate.org)** is a lighter-weight attestation pattern — each commit carries a `Signed-off-by` line claiming the contributor has the right to submit. CSAE's scope-claim primitive is a richer version of the same insight: a per-commit assertion isn't enough; you need a per-workstream scope claim that survives time.

**`git commit -S`** is the cryptographic primitive that signs an individual commit. CSAE chains signed commits into a higher-level structure with predecessors and successors, scope claims and review verdicts. The primitive is necessary but not sufficient.

**Anthropic's [Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams)** (April 2026) provides intra-team coordination at the platform level, including some attestation at the agent-handoff layer. CSAE addresses the higher-level question of how those handoffs become a durable audit chain that survives the team's existence. The two compose: Agent Teams handles the within-team handoff; CSAE handles the audit chain that records what happened.

If you know of closer prior art, please open an issue — I'd genuinely like to position this against it.

---

## Related

This is one of a series of methodology pieces from building [ORCA](#about-orca):

- **[Russian Judge](https://github.com/moranbickel/russian-judge)** — adversarial AI review with structured verdicts.
- **[Three-Body Protocol](https://github.com/moranbickel/three-body-protocol)** — coordination across sessions in time.
- **[Peer-Worker Convergence](https://github.com/moranbickel/peer-worker-convergence)** — coordination across sessions in parallel.
- **CSAE** — *this repo.* Continuous Session-Attested Evidence: attestation chains for AI-generated commits.
- **[Pre-IMPL Forensic Discipline](https://github.com/moranbickel/Pre-IMPL-Forensic-Discipline)** — catching wrong premises before they become wrong commits (v0.1 draft).

More pieces as they're written.

## About ORCA

ORCA — Orchestrated Reasoning for Civil Action — is an AI legal reasoning system I'm building for Israeli civil litigation. It's a decision system, not a document generator: it reasons about which causes of action hold, which elements the evidence supports, and what relief follows. A programmer builds a document generator; a litigator builds a decision system. The system is closed-source; the methodology that produced it is open. This repo publishes the attestation methodology, not ORCA's product internals — no source code, knowledge bases, prompts, customer data, or implementation roadmap.

See my [GitHub profile](https://github.com/moranbickel) for the full body of work and how to follow ORCA's progress.

---

## License

- Prose: [CC BY 4.0](./LICENSE-CC-BY-4.0)
- Templates and code: [MIT](./LICENSE-MIT)

— Moran Bickel
