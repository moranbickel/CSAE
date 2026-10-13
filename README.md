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

The hook does not decide coverage itself. It calls an external coverage tool
(`csae-verify` by default, or whatever `CSAE_COVERAGE_TOOL` names) once per
commit, as `<tool> --commit <sha> --audit-mirror <dir>`, and treats exit 0 as
covered. **That tool is not part of this repository; you must supply it.**
Without one the hook exits 2 (configuration error).

On a push that updates several refs, Git sends the hook one line per ref. The
hook reads every line and checks every update to the protected ref
(`refs/heads/main`, or `CSAE_PROTECTED_REF`), wherever it appears in the list.
Uncovered commits from all of those updates are pooled and the push is
accepted or rejected once. Updates to other refs are not checked. `CSAE_PROTECTED_REF`
takes a branch name without a slash (`main`) or a full ref (`refs/heads/main`,
`refs/heads/release/1.0`); any other value (`origin/main`, `heads/main`, a tag)
is a configuration error (exit 2), as is an input line that does not have four
fields. Deleting the protected ref is rejected. `BYPASS_CSAE=1` skips the
coverage check, the deletion rejection and the audit-mirror and coverage-tool
checks; it does not override an invalid `CSAE_PROTECTED_REF` or a malformed
input line, which still exit 2.

When the protected ref is created, only commits not already reachable from the
pushed remote's remote-tracking refs are checked. Otherwise a new ref would
demand coverage for the entire history, including everything that predates
adoption. The consequence: a commit first pushed to an unprotected branch (which
is never checked) is not checked again when the protected branch is created from
it. If you need full-history coverage at creation, run your coverage tool over
the whole history before creating the ref. Tests:
`bash tests/test-validator-hook.sh`.

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
