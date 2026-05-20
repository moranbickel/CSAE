# Changelog

All notable changes to CSAE — Continuous Session-Attested Evidence — are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

Sharpening pass after first outside review (GPT 9.0/10) flagged three quality improvements.

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
First-review score (9.0) is higher than [Peer-Worker Convergence](https://github.com/moranbickel/peer-worker-convergence)'s second-review score (8.9, post-corrections) and substantially higher than PWC's first review (8.6). Empirical support for the constraint-loaded-drafting hypothesis: pre-drafting constraint loading (acronym lock, scope discipline, firewall posture, structure sketch) produces measurably better first-draft quality than iteration-style drafting.

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
Fourth of six methodology pieces from ORCA — Orchestrated Reasoning for Civil Action. Composes with [Russian Judge](https://github.com/moranbickel/russian-judge) (adversarial review) and [Peer-Worker Convergence](https://github.com/moranbickel/peer-worker-convergence) (topology convergence). Together the three form an attestation triangle covering review-substance + commit-topology + chain-of-custody.

Authored at Path A discipline level: methodology + workflow + invariants, no specific cryptographic-substrate recommendations. Point at [in-toto](https://in-toto.io), [Sigstore](https://www.sigstore.dev), and [SLSA](https://slsa.dev) for primitive layer.

[0.1.0]: https://github.com/moranbickel/csae/releases/tag/v0.1.0
