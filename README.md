# CSAE: records for AI-assisted commits

[![smoke](https://github.com/moranbickel/CSAE/actions/workflows/smoke.yml/badge.svg)](https://github.com/moranbickel/CSAE/actions/workflows/smoke.yml)

Templates and a validator hook for recording what work was authorized, which
commits implemented it, and which review covered those commits.
CSAE stands for Continuous Session-Attested Evidence.

## Start with a record

Read the [worked example](examples/attestation-walkthrough.md), then inspect:

- [Intent registration](templates/intent-registration-template.md): scope recorded
  before implementation.
- [Bundle](templates/bundle-template.md): commit range and review references.
- [Audit mirror setup](templates/audit-mirror-setup.md): retaining the records
  separately from the working repository.
- [Validator hook](templates/validator-hook.sh): the checks and configuration
  needed before adopting it.

Synthetic example of the problem:

```text
Review: PASS, covers revision A
Proposed release: revision B
Result: the supplied review does not cover this release
```

Try the [stale-review crash test](https://github.com/moranbickel/agent-crash-tests/tree/main/cases/stale-review).
It demonstrates this binding with a file hash. It is a small teaching example,
not an implementation of the full CSAE chain.

## What the record establishes

A bundle connects an earlier scope statement, a specific change, and a review
record. The [protocol](PROTOCOL.md) defines coverage, publication order,
self-inclusion, recovery, and the audit mirror.

That connection does not establish that the review was accurate or the scope
was honestly stated. Resistance to tampering depends on the actual signing,
storage, access controls, and external anchors you configure. A separate Git
repository alone does not make a record immutable.

Use the workflow when you need this correspondence later. If retained pull
requests already answer your audit questions, an additional mirror and bundle
process may not be worth maintaining.

For broader supply-chain provenance, see [in-toto](https://in-toto.io),
[Sigstore](https://www.sigstore.dev), and [SLSA](https://slsa.dev).
For a structured review format, see [Russian-Judge](https://github.com/moranbickel/Russian-Judge).

Maintained by [Moran Bickel](https://github.com/moranbickel).
Prose: [CC BY 4.0](LICENSE-CC-BY-4.0). Templates and code: [MIT](LICENSE-MIT).
