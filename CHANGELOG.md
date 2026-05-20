# Changelog

All notable changes to CSAE — Continuous Session-Attested Evidence — are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-05-20

Initial draft release. Private — pending outside review, walkthrough example, templates, and final polish before public flip.

### Added
- `README.md` — protocol overview, failure-it-solves narrative (the attribution-dispute schema-migration story), what CSAE is and is not, vs-alternatives table (ad-hoc audit / git signed commits / SLSA / Sigstore / in-toto / CSAE), composition with Russian Judge and Peer-Worker Convergence (attestation triangle framing), protocol at a glance (intent registration / bundle authoring / audit mirror + validator), worked example, four recovery scenarios, related-work survey.
- `PROTOCOL.md` — formal specification with vocabulary, preconditions/procedure/postconditions/invariants for the three concepts, bundle field requirements (MUST/MAY/MUST NOT), validator semantics, self-attestation mechanics (non-circular argument with chain-bottoms-out-at-first-scope-claim framing), composition with verdict references and β.2 ceremony integration, six anti-patterns, four recovery scenarios expanded, explicit threat model (what CSAE defends against and doesn't), verification incantations, glossary.

### Pending
- `examples/attestation-walkthrough.md` — end-to-end walkthrough with coverage-gap recovery
- `templates/` — intent-registration template, bundle template, validator-hook template, audit-mirror-setup notes
- `diagram.svg` — protocol-topology diagram

### Context
Fourth of six methodology pieces from ORCA — Orchestrated Reasoning for Civil Action. Composes with [Russian Judge](https://github.com/moranbickel/russian-judge) (adversarial review) and [Peer-Worker Convergence](https://github.com/moranbickel/peer-worker-convergence) (topology convergence). Together the three form an attestation triangle covering review-substance + commit-topology + chain-of-custody.

Authored at Path A discipline level: methodology + workflow + invariants, no specific cryptographic-substrate recommendations. Point at [in-toto](https://in-toto.io), [Sigstore](https://www.sigstore.dev), and [SLSA](https://slsa.dev) for primitive layer.

[0.1.0]: https://github.com/moranbickel/csae/releases/tag/v0.1.0
