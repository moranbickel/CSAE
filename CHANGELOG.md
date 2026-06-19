# Changelog

All notable changes to CSAE — Continuous Session-Attested Evidence — are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] — 2026-06-19

Three protocol-level integrity properties added on top of the core loop — detached-mirror publishing, closure-SHA canonical binding, and the no-vacuous-attestation floor — plus the previously-unreleased vs-alternatives column. Additive throughout (no breaking changes to the bundle schema, validator semantics, or recovery procedures); minor version bump per SemVer.

### Added
- `PROTOCOL.md` — new §"Closure-SHA canonical binding": a closure SHA cited as verification for a closed work-item MUST be an ancestor of the canonical branch, and the closure note is authored *after* the work lands on canonical main (cites the canonical commit, not a pre-merge working-branch SHA that evaporates via cherry-pick/rebase). Documents the SHA-evaporation failure, the land-first/cite-second sequencing, binding-to-the-chain-by-construction (closures derived from the bundle's post-landing range), three invariants, and the content-twin remediation path.
- `PROTOCOL.md` — new §"Closure orchestration and the no-vacuous-attestation floor": a fail-closed orchestrator for the deterministic tail (conform receipts → author bundle → publish → record closures) that refuses to attest an empty range, a placeholder verdict, or a below-floor aggregate. Defines what a vacuous attestation is, the three-part floor gate (non-empty range / named-not-placeholder verdict / aggregate-meets-floor keyed off lane terminals), truthful receipt conformance (derived pass/fail, surgical field insertion, fail-closed on un-derivable fields), SHA canonicalization at closure time, and the preview-only human boundaries.
- `PROTOCOL.md` — new §"Detached-mirror publishing" under §"Audit mirror": the audit-mirror push SHOULD run from a dedicated ref-isolated worktree in a detached-HEAD state at the canonical tip, decoupled from the working clone. Documents the publish-stalls-behind-working-tree problem, the detached-HEAD mechanism (push `HEAD:main`, never advance the working clone's branch ref), why-detached-specifically (shared refs), and detached-mirror-specific invariants. Legacy sibling-clone flow preserved for single-clone setups.
- `PROTOCOL.md` — vocabulary gains *Closure*, *Closure SHA*, *Mirror worktree*; anti-patterns expand from six to eight (#7 pre-merge working-branch SHA in a closure note; #8 vacuous attestation over an empty range / placeholder verdict).
- `README.md` — *at-a-glance* section gains a "three integrity properties on top of the core loop" block summarizing detached-mirror publishing, closure-SHA canonical binding, and the no-vacuous-attestation floor, each cross-linked to its `PROTOCOL.md` section.
- `templates/audit-mirror-setup.md` — new §"Publishing to the mirror: the detached mirror worktree": why-publish-from-detached, provision/reset commands, the `HEAD:main` push, and the three publishing invariants (refuse-attached-HEAD, push-not-advance-local-ref, reset-clean-before-each-publish). Legacy sibling-clone flow noted as valid for single-clone setups.
- `examples/attestation-walkthrough.md` — new "Recording the closure" step demonstrating the canonical-binding property end-to-end (ancestry verification before citation; cite the canonical twin, not the working-branch SHA); "What was non-obvious" expands from three moves to four.
- README — *vs-alternatives* table gains a **GitHub-native CI/CD** column (Actions OIDC + keyless Cosign + protected branches), the integrated stack a DevSecOps reader reaches for first, plus a Related-work entry that concedes its strengths and names the precise gap CSAE fills (scope-claim-before-work + commit-range→canonical binding to a named verdict; platform-neutral). Closes systemic-review finding S-6.

### Note
- `diagram.svg` was not updated in this release; the architecture diagram does not yet depict detached-mirror publishing or the closure tail. Follow-up.

[0.2.0]: https://github.com/moranbickel/csae/releases/tag/v0.2.0

## [0.1.2] — 2026-05-20

Walkthrough + templates shipped. Closes the broken internal links from README + PROTOCOL.md to previously-pending walkthrough.

### Added
- `examples/attestation-walkthrough.md` — end-to-end walkthrough showing eager-attestation cycle (intent → work → review → bundle → audit-mirror publish → canonical push) plus a coverage-gap recovery scenario (retroactive attestation honest about being retroactive + sub-floor). Resolves the broken internal links from README + PROTOCOL.md.
- `templates/intent-registration-template.md` — registration commit message structure with required + optional fields and example
- `templates/bundle-template.md` — bundle markdown file structure mapping to 9-field MUST list + naming conventions + example
- `templates/validator-hook.sh` — pre-push hook (or CI required check) for canonical main; rejects pushes whose commits aren't covered; bypass mechanism for legitimate exceptional cases
- `templates/audit-mirror-setup.md` — notes for setting up the separate audit-mirror repository (branch protection, key separation, write access restriction, replication, file layout, verification)

### Context
Closes the cadence inherited from PWC: review-pass → walkthrough → templates → repo creation. CSAE arc now substantively complete; subsequent revisions reactive (issues, PRs from real adopters) rather than proactive.

[0.1.2]: https://github.com/moranbickel/csae/releases/tag/v0.1.2

## [0.1.1] — 2026-05-20

Sharpening pass after a first outside review flagged three quality improvements.

### Changed
- README — operational burden in vs-alternatives table corrected from "low-medium" to "medium-high." Eager intent registration + bundle authoring + separate audit mirror + pre-push hook is materially more burden than the prior wording suggested.
- README — new section *"Where teams actually break the chain"* (field-manual format: failure mode + signal + why broke + how to recover, for three common failure modes — forgot intent registration / landed uncovered commits / bundle published after canonical push). Positioned between worked example and Recovery; surfaces operational signals alongside the abstract anti-patterns in [`PROTOCOL.md`](./PROTOCOL.md).
- README — new section *"When to use it — and when not to"* with sharpened audience exclusion (not for casual solo work, hobby branches, or teams already running disciplined PR review with decent retention). Positioned before Adopt-the-mechanics so readers know the audience-fit before investing.

### Unchanged
- Self-attestation mechanics framing — outside reviewer confirmed the non-circular argument lands on first read.
- Threat model — outside reviewer confirmed the explicit out-of-scope list is the right humility posture.
- MUST NOT bundle field list — four exclusions sufficient.
- Path A discipline — no cryptographic-substrate recommendations added; pointers to in-toto / Sigstore / SLSA preserved.

### Discipline note
A working hypothesis from this drafting process: loading constraints up front (acronym lock, scope discipline, firewall posture, structure sketch) seemed to produce a cleaner first draft than iterating from a rough one. That's an impression from a single project with self-selected review — a hypothesis worth testing, not a measured result.

[0.1.1]: https://github.com/moranbickel/csae/releases/tag/v0.1.1

## [0.1.0] — 2026-05-20

Initial draft release. Private — pending outside review, walkthrough example, templates, and final polish before public flip.

### Added
- `README.md` — protocol overview, failure-it-solves narrative (the attribution-dispute schema-migration story), what CSAE is and is not, vs-alternatives table (ad-hoc audit / git signed commits / SLSA / Sigstore / in-toto / CSAE), composition with Russian Judge and Peer-Worker Convergence (attestation triangle framing), protocol at a glance (intent registration / bundle authoring / audit mirror + validator), worked example, four recovery scenarios, related-work survey.
- `PROTOCOL.md` — formal specification with vocabulary, preconditions/procedure/postconditions/invariants for the three concepts, bundle field requirements (MUST/MAY/MUST NOT), validator semantics, self-attestation mechanics (non-circular argument with chain-bottoms-out-at-first-scope-claim framing), composition with verdict references and β.2 ceremony integration, six anti-patterns, four recovery scenarios expanded, explicit threat model (what CSAE defends against and doesn't), verification incantations, glossary.

### Pending (shipped in 0.1.2)
- `examples/attestation-walkthrough.md`
- `templates/` directory

### Context
One of a series of methodology pieces from ORCA — Orchestrated Reasoning for Civil Action. Composes with [Russian Judge](https://github.com/moranbickel/russian-judge) (adversarial review) and [Peer-Worker Convergence](https://github.com/moranbickel/peer-worker-convergence) (topology convergence). Together the three form an attestation triangle covering review-substance + commit-topology + chain-of-custody.

Authored at Path A discipline level: methodology + workflow + invariants, no specific cryptographic-substrate recommendations. Point at [in-toto](https://in-toto.io), [Sigstore](https://www.sigstore.dev), and [SLSA](https://slsa.dev) for primitive layer.

[0.1.0]: https://github.com/moranbickel/csae/releases/tag/v0.1.0
