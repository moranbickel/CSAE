# CSAE - Continuous Session-Attested Evidence

A protocol for attaching a durable audit trail to AI-generated commits, so the
record is still there when someone asks about it months later. When AI-assisted
commits land on main without verifiable provenance, a gap opens: who approved
this, against what scope, under which reviewer's verdict? git log does not
capture that. CSAE does, with a chain - intent registration before the work, a
bundle at the end, and a separate audit mirror.

I built it developing ORCA, a closed-source legal-AI system. It is one of a
series; it composes with Russian Judge (the review it points at) and
Peer-Worker-Convergence (the merge it rides on), but it stands alone.

## The failure it solves

Three months into a project, someone asked who had approved a particular schema migration.

The commit message said the AI assistant authored it. There was no PR, because the team had been bundling commits in a workflow that skipped code review by design. The reviewer's verdict was in a Slack thread that had aged out of the search window. `git log` knew nothing useful.

The change was correct. The audit trail wasn't there.

When the team looked back, they found the same gap on every commit since they'd started using AI-assisted work. Hundreds of commits with no verifiable record of who reviewed what, under whose authorization, against which scope claim. The work was probably fine. There was just no way to show it.

That's the failure CSAE fixes, and it fixes it before anyone has to ask the question.

The gap isn't about *whether* the work was good. It's about whether a record exists to show that it was. Once AI assistants are doing real authoring, the meaningful authorial decision is the operator's: *what scope, what review, what authorization*. `git log` doesn't capture that. CSAE does.

---


## What CSAE is not

CSAE is **not** full supply-chain attestation. [SLSA](https://slsa.dev) covers build systems, dependency chains, and artifact provenance from source to deployment. CSAE is narrower. It covers the moment a commit lands on `main`, not the whole build-and-distribute chain. If you need both, run both.

It's **not** a substitute for code review. A signed bundle that points at a reviewer's verdict doesn't replace the verdict; it carries the verdict into a durable chain. The review still has to happen. [Russian Judge](https://github.com/moranbickel/Russian-Judge) is one structured review that composes cleanly with CSAE; informal PR comments are another. The bundle attests *that* review happened and *what it concluded*. It does not attest *that the review was good*.

It's **not** commit-signing on its own. `git commit -S` verifies that the commit's claimed author held the signing key at the time. That's a primitive. CSAE chains primitives like that into a larger structure: scope claim, commit range, verdict reference, self-attestation, all linked to predecessors and successors. The chain is the contribution; the primitives are inputs.

It's **not** cryptographic anti-fraud. A determined adversary with key access can forge a bundle. CSAE's threat model is honest teams operating in good faith who need verifiable records for later questions: audit, attribution disputes, compliance review, due diligence. If your threat model includes adversarial signing, CSAE adds defense in depth but isn't the last line.

And it's **not** a complete attestation solution by itself. It's one layer in a stack that, in my own practice, also includes adversarial review ([Russian Judge](https://github.com/moranbickel/Russian-Judge)) and topology convergence ([Peer-Worker Convergence](https://github.com/moranbickel/Peer-Worker-Convergence)). Each layer answers a different question, and the stack answers more than any layer does alone.

---


## CSAE vs. alternatives

| Dimension | Ad-hoc audit (`git log` + memory) | `git commit -S` (signed commits) | [SLSA](https://slsa.dev) | [Sigstore](https://www.sigstore.dev) / [in-toto](https://in-toto.io) | GitHub-native CI/CD | CSAE |
|---|---|---|---|---|---|---|
| Scope | Per-commit, informal | Per-commit, cryptographic | Build pipeline → artifact | Build artifact → consumer | Source → merge gate → artifact | Commit-range → canonical main |
| What's attested | Whatever `git log` recorded | Authorship (key held the commit) | Build provenance | Artifact provenance + transparency log | Workflow identity + artifact signature + "checks passed" | Scope claim + review verdict + self-attestation |
| Trust root | Memory, Slack search, PRs | The key trust hierarchy | Build platform attestation | Sigstore transparency log + Fulcio | GitHub OIDC issuer + Fulcio/Rekor + branch-protection config | Predecessor bundle + reviewer verdict + operator scope claim |
| Recovery from "who approved this?" | Often impossible | Author yes; reviewer no | N/A - different question | Artifact-level; commit-level limited | Review occurred (branch protection); scope/authorization not recorded | The bundle carries the answer |
| Operational burden | Zero (until you need it) | Low (one config flag) | Medium-high (build infra changes) | Medium (signing + verification) | Low-medium (platform-provided) | Medium-high (eager intent registration + bundle authoring + separate audit mirror + pre-push hook) |
| Best for | Solo dev, low-stakes work | Teams that just want authorship | Regulated build pipelines | Open-source artifact distribution | Teams already all-in on GitHub Actions | AI-assisted teams needing commit-level provenance |

*"GitHub-native CI/CD" is the integrated stack a DevSecOps reader reaches for first: protected branches plus required status checks (review happened) plus keyless [Cosign](https://docs.sigstore.dev/cosign/signing/overview/) signing under the [Actions OIDC](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect) identity (artifact tied to the workflow). See [Related work](#related-work) for where it stops and CSAE begins.*

CSAE doesn't replace the others. It fills the gap at the commit-landing layer that the others either don't address or address at the wrong granularity. If your project also distributes artifacts, you probably want both CSAE (commits → main) and SLSA-or-equivalent (main → release).

---


## Composition with [Russian Judge](https://github.com/moranbickel/Russian-Judge) and [Peer-Worker Convergence](https://github.com/moranbickel/Peer-Worker-Convergence)

The three pieces form an attestation triangle. Each answers a different question; together they make AI-assisted work auditable end to end.

- **Russian Judge** answers *was the work reviewed, and to what bar?* Its verdicts are structured: score, defect classification, pass floor. A verdict is an artifact you can point at.
- **Peer-Worker Convergence** answers *how did the work land on main without scope blur?* Its side-branch β bundles a worker's commits into a precision-target branch that's exact in attribution.
- **CSAE** answers *can anyone verify, months later, that the right work landed under the right review and the right authorization?* It chains the RJ verdict and the PWC bundle into a durable record.

In practice it goes like this: a peer-worker session ends, the side-branch β runs, the branch carries exactly that session's commits, and the CSAE bundle authored as part of β references the RJ verdict that cleared the work plus the operator's scope claim from session start. Three layers, one ceremony.

You can run CSAE on its own. Informal review feeds the bundle, single-worker setups skip the convergence layer, and you still get most of the audit-trail benefit. But the trio compounds. With all three running, *"who approved this, against what, under whose authorization?"* is answerable in seconds instead of an afternoon of digging.

---


## The protocol, at a glance

Three concepts, one mechanical-enforcement layer, one audit-trail repo.

**1. Intent registration.** Before substantive work, the operator registers a scope claim: a workstream identifier and a one-sentence intent statement. This produces a small registration commit on the worker branch that marks what the operator authorized, before any work happened. The "eager" part matters. Registration at session end, after the work is done, is just a description of the work. Registration before the work is an authorization. Only the second one has the temporal property that makes the scope claim load-bearing.

**2. Bundle authoring.** When a logical workstream finishes (typically at session end, or when a coherent commit range is ready to land), the operator authors a bundle. The bundle carries:

- The scope claim from the intent registration (*what was authorized*)
- The commit range the bundle covers (*what shipped*)
- References to the reviewer verdict(s) at floor (*what passed review*)
- A self-attestation commit inside the bundle's own commit range (see below)

The bundle is a markdown file or signed manifest with these fields. The exact format is the operator's choice; the content matters more than the encoding.

**3. Self-include attestation.** The bundle's attestation commit lives *inside* the commit range the bundle attests. That sounds circular but isn't, and the difference is what lets the chain be self-referential rather than depend on an outside authority.

Here's why it isn't circular. The attestation references (a) the *prior* reviewer verdict, which already exists and is signed, and (b) the scope claim from registration, which *preceded* the work. The self-include commit doesn't claim authority over the work it's attesting. It claims correspondence: *these commits map to that scope claim, were reviewed under that verdict, and I, the bundle author, certify the correspondence is honest.* The chain extends one link forward by pointing one link backward. No outside authority is needed, because the chain's authority comes from the predecessors it links to.

Outside reviewers tend to read this move as either elegant or suspicious on first encounter. The elegant reading: the chain supports itself, since any link can be verified by walking back to the predecessor verdict and the predecessor scope claim, neither of which depended on the current bundle existing. The suspicious reading: "but who attests the attestation?" The answer is the previous link did, recursively, and the chain bottoms out at the first scope claim, which is an operator-authored decision.

Be precise about what that buys you. "Non-circular" means no link needs itself or a successor to be validated. It does not mean the chain is independently authoritative. To a third party who doesn't trust the operator, the first scope claim is still just *"I scoped this honestly."* CSAE gives that auditor **internal consistency and tamper-evidence**, not **proof the scope claim is true**. Where you need the latter (compliance, due diligence, litigation), anchor the head of the chain to an authority they already trust: an RFC-3161 timestamp or a Sigstore/Rekor transparency-log entry. See [`PROTOCOL.md`](./PROTOCOL.md) §Self-attestation mechanics.

**4. Audit mirror.** Bundles publish to a separate tamper-evident repository, the audit-trail mirror, where they're append-only and cryptographically linkable to each other. The mirror does two jobs. It survives a compromise of the primary repo (an attacker would have to compromise both repos to forge the chain), and it gives downstream audit, due-diligence, or attribution work a stable place to read from.

**Mechanical enforcement: the validator.** A pre-push hook on canonical `main` (or an equivalent CI-level required check) verifies that every commit being pushed is covered by an attested bundle already in the audit mirror. Pushes that fail coverage are rejected. The operator's bypass, for legitimate exceptions like release tags, manual recovery, and ceremonial commits, is deliberately awkward and produces a logged bypass record that itself becomes an audit-chain entry.

**Three integrity properties sit on top of the core loop** (full treatment in [`PROTOCOL.md`](./PROTOCOL.md)):

- **Detached-mirror publishing.** The audit-mirror push runs from a dedicated, ref-isolated worktree in a detached-HEAD state at the canonical tip. It's separated from the working clone, so the audit trail never stalls behind a dirty or mid-ceremony working tree. (§"Audit mirror" → "Detached-mirror publishing".)
- **Closure-SHA canonical binding.** When a work item is recorded as closed "verified by commit X," the cited SHA has to be an ancestor of the canonical branch, and the closure note is written *after* the merge. That way it cites the canonical commit, not a pre-merge working-branch SHA that disappears under cherry-pick or rebase. (§"Closure-SHA canonical binding".)
- **No-vacuous-attestation floor.** A closure orchestrator conforms the review receipts to the bundle schema and refuses to attest an empty range, a placeholder verdict, or an aggregate that doesn't meet the floor. An attestation has to cover real work bound to a named verdict. (§"Closure orchestration and the no-vacuous-attestation floor".)

---


## A worked example

A complete narrative walkthrough - a schema-refactor session from intent
registration through canonical push and a three-months-later chain walk - is in
[`PROTOCOL.md`](./PROTOCOL.md) (Worked example), and a fuller example including a
coverage-gap recovery is in [`examples/attestation-walkthrough.md`](./examples/attestation-walkthrough.md).

## Where teams actually break the chain

The operational failure signals - forgotten intent registration, uncovered
commits landing on main, and a bundle published after the canonical push instead
of before - and their recovery are specified in [`PROTOCOL.md`](./PROTOCOL.md)
(Anti-patterns and Recovery).

## Recovery

The four recovery classes - stranded intent, coverage gap, compromised key or
tampered mirror, and cascading break - are specified in
[`PROTOCOL.md`](./PROTOCOL.md) (Recovery). The discipline across all of them is the
same: a break in the chain is converged back through the protocol, not routed around.

## When to use it, and when not to

**Use it when:**
- Your team produces AI-assisted commits on a canonical `main` that may later need provenance reconstruction.
- The main branch is retained past the working memory or chat-search reach of the operators.
- The cost of *"we can't reconstruct who approved this"* is higher than the ceremony cost.
- Several operators or AI assistants share commit authority against the same canonical `main`.

**Don't use it when:**
- You're doing casual solo work or hobby branches, with no shared attention and no retention need.
- Your team already runs disciplined PR review with decent retention. PRs and indexed search do the same job.
- You use short-lived feature branches where the audit need ends at merge.
- It's experimental or scratch work where the ceremony cost outweighs the audit value.

The real question isn't "do you use AI?" It's "will someone need to reconstruct, months later, who authorized what under whose review?" If yes, CSAE earns its weight. If no, the ceremony isn't worth it.

---


## Adopt the mechanics in 30 minutes; internalize the discipline over a week

1. **Decide the scope.** Which commits need attestation? Usually all AI-assisted commits, plus anything landing on canonical `main`. If you're starting on an existing project, declare a cutover date and accept that pre-cutover commits don't have CSAE attestation. That's the honest starting state.
2. **Set up the audit-mirror repository.** A separate Git repo (private or public, depending on your audit needs) that holds the bundle files. It should be tamper-evident: append-only via branch protection, or signed by a key separate from the primary repo's keys.
3. **Adopt the intent-registration habit.** Register intent at session start, before the first non-trivial commit. The eager part is what makes the scope claim load-bearing.
4. **Adopt the bundle format.** Decide what fields your bundles carry. Minimum viable: scope claim, commit range, verdict reference, self-attestation. Standardize it so any future operator can read a bundle without context.
5. **Install the pre-push validator.** A Git hook or CI required check on canonical `main` that verifies every push's commits are covered by a bundle already in the audit mirror.

Setup takes about 30 minutes. The discipline takes a week to settle. The first time you forget to register intent and have to author a retroactive bundle, you'll feel the cost. By the third time you reach for a release-tag bypass and don't take it, the discipline feels automatic.

For the formal protocol (invariants, bundle field requirements, validator semantics, audit-mirror discipline, recovery procedures), see [`PROTOCOL.md`](./PROTOCOL.md). For a complete walkthrough including a coverage-gap recovery, see [`examples/attestation-walkthrough.md`](./examples/attestation-walkthrough.md).

---


## Related work

I surveyed the field before publishing. CSAE sits in an active area; the closest pieces:

**[in-toto](https://in-toto.io)** is the closest sibling, an attestation framework for software supply chains with a chain-of-custody model that generalizes well. CSAE could be implemented as an in-toto layout. The differences are scope (CSAE is commit-level, in-toto spans pipelines) and audience (CSAE targets AI-assisted teams, in-toto targets supply-chain security teams). If you adopt CSAE and later need broader supply-chain attestation, in-toto is the natural next layer.

**[Sigstore](https://www.sigstore.dev)** provides signing infrastructure (Cosign for artifacts, Gitsign for commits) and a transparency log (Rekor). CSAE chains can be cryptographically grounded in Sigstore primitives: the bundle can be a Cosign-signed artifact, the audit mirror can be a Rekor entry. CSAE is the methodology; Sigstore is one possible implementation substrate.

**GitHub-native CI/CD (Actions OIDC plus keyless Cosign plus protected branches)** is the integrated stack a DevSecOps engineer reaches for first, and the closest thing to a turnkey alternative. Protected branches with required status checks enforce that review happened before a merge; keyless [Cosign](https://docs.sigstore.dev/cosign/signing/overview/) signing under the workflow's [OIDC](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect) identity ties an artifact to the pipeline that produced it; Rekor logs it. It's strong, low-friction, and the right default if you already live in GitHub Actions. Where it stops is CSAE's specific binding. Branch protection attests *that a review occurred*, not *that this was the scope authorized before any code was written*, and the platform's provenance is artifact-centric: it doesn't record the *commit-range → canonical-main* correspondence to a named reviewer verdict at the granularity CSAE chains. It also couples the audit trail to GitHub. CSAE is platform-neutral methodology that sits on top of exactly these primitives. Use Actions OIDC plus Cosign as the substrate, and CSAE for the scope-claim, verdict, and commit-range binding the platform leaves implicit.

**[SLSA](https://slsa.dev)** (Supply-chain Levels for Software Artifacts) is broader-scope than CSAE; it covers build provenance from source to deployment. CSAE covers the source-to-main slice that SLSA largely assumes is solved. The two are complementary, and teams running both get end-to-end attestation from operator intent through deployed artifact.

**[Developer Certificate of Origin (DCO)](https://developercertificate.org)** is a lighter attestation pattern: each commit carries a `Signed-off-by` line claiming the contributor has the right to submit it. CSAE's scope-claim primitive is a richer version of the same insight. A per-commit assertion isn't enough; you need a per-workstream scope claim that survives time.

**`git commit -S`** is the cryptographic primitive that signs an individual commit. CSAE chains signed commits into a larger structure with predecessors and successors, scope claims and review verdicts. The primitive is necessary but not sufficient.

**Anthropic's [Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams)** (April 2026) provides intra-team coordination at the platform level, including some attestation at the agent-handoff layer. CSAE covers the higher-level question of how those handoffs become a durable audit chain that survives the team's existence. The two compose: Agent Teams handles the within-team handoff, CSAE handles the audit chain that records what happened.

If you know of closer prior art, please open an issue. I'd genuinely like to position this against it.

---


## Related

This is one of a series of methodology pieces from building [ORCA](#about-orca):

- **[Russian Judge](https://github.com/moranbickel/Russian-Judge)** - adversarial AI review with structured verdicts.
- **[Three-Body Protocol](https://github.com/moranbickel/Three-Body-Protocol)** - coordination across sessions in time.
- **[Peer-Worker Convergence](https://github.com/moranbickel/Peer-Worker-Convergence)** - coordination across sessions in parallel.
- **CSAE** - *this repo.* Continuous Session-Attested Evidence: attestation chains for AI-generated commits.
- **[Pre-IMPL Forensic Discipline](https://github.com/moranbickel/Pre-IMPL-Forensic-Discipline)** - catching wrong premises before they become wrong commits (v0.1 draft).

More pieces as they're written.


## About ORCA

ORCA (Orchestrated Reasoning for Civil Action) is an AI legal reasoning system I'm building for Israeli civil litigation. It's a decision system, not a document generator: it reasons about which causes of action hold, which elements the evidence supports, and what relief follows. A programmer builds a document generator; a litigator builds a decision system. The system is closed-source; the methodology behind it is open. This repo publishes the attestation methodology, not ORCA's internals: no source code, knowledge bases, prompts, customer data, or roadmap.

See my [GitHub profile](https://github.com/moranbickel) for the full body of work and how to follow ORCA's progress.

---


## License

- Prose: [CC BY 4.0](./LICENSE-CC-BY-4.0)
- Templates and code: [MIT](./LICENSE-MIT)

- Moran Bickel
