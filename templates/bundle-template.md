# Bundle Template

A bundle is the markdown file (or signed manifest) that links a commit range to its scope claim and verdict reference(s), with a self-attestation commit inside the covered range.

See [`PROTOCOL.md`](../PROTOCOL.md) §"Bundle field requirements" for the formal MUST/MAY/MUST-NOT specification.

## Minimal viable bundle

```markdown
# Bundle: <workstream-id>

bundle-id: <content-hash-or-uuid>
workstream-id: <from scope claim>
scope-claim-ref: <hash of registration commit C_scope>
commit-range: <C_scope>..<C_attest>
verdict-refs:
  - <verdict-id-1>:<path-or-hash>
self-attestation-ref: <hash of C_attest>
predecessor-bundle: <previous bundle id, or null for chain start>
bundle-author: <signing-key-fingerprint>
timestamp: <ISO-8601 UTC>

## Description

<one paragraph max — bundle is metadata, not narrative>

## Annotations (optional)

<bypass-acknowledgments, retroactive-status declarations, chain-repair markers, etc.>
```

## Required fields (MUST)

9 fields, all required:

| Field | Purpose |
|---|---|
| `bundle-id` | Unique within the audit mirror; typically content hash |
| `workstream-id` | From the scope claim; enables cross-bundle search |
| `scope-claim-ref` | Hash of the registration commit `C_scope` |
| `commit-range` | `[C_scope..C_attest]`, inclusive of registration and self-attestation |
| `verdict-refs` | One or more verdict identifiers (content hash + path) |
| `self-attestation-ref` | Hash of `C_attest`, which lives inside the commit range |
| `predecessor-bundle` | Previous bundle in the chain, or `null` for the chain's first bundle |
| `bundle-author` | Typically the operator's signing key fingerprint |
| `timestamp` | When the bundle was authored (ISO-8601, UTC) |

## Optional fields (MAY)

- **Description** — free-form, one paragraph max. The bundle is metadata; long narrative belongs in commit messages and PR descriptions, not in the bundle.
- **Bypass acknowledgments** — when some commits in the range weren't reviewed at floor; each acknowledgment names the commit, the reason, and the operator's explicit authorization.
- **Annotations** — exceptional-circumstance flags like *"retroactive attestation; chain-repair predecessor"* or *"first bundle after key rotation."*

## MUST NOT contain

- **Reviewer credentials directly.** The verdict references stand in. The verdict has its own signing key + attestation; the bundle references it, doesn't embed it.
- **Operator credentials directly.** The bundle is signed by the author; key material is not embedded in the bundle file.
- **Substantive content of the work.** No diffs, no source code. The bundle references the commit range; the primary repo carries the content.
- **References to bundles in other projects' audit chains.** Chains don't cross-link between projects; each project's chain is self-contained.

## Naming convention

Suggested: `bundles/<workstream-id>-<ISO-8601-timestamp>.md`

Or organized by month for filesystem performance at scale: `bundles/<YYYY-MM>/<workstream-id>-<timestamp>.md`.

The timestamp suffix matters: failed-and-retried bundles get distinct timestamps, so failed bundles remain visible in the audit-mirror history for forensic recovery.

## Example bundle

```markdown
# Bundle: ws-auth-refactor

bundle-id: bundle_X10
workstream-id: ws-auth-refactor
scope-claim-ref: a1b2c3d
commit-range: a1b2c3d..7e8f9a0
verdict-refs:
  - c3d4e5f-6789-abcd-ef01-234567890abc:verdicts/oauth-refactor-2026-05-20T140000Z.md
self-attestation-ref: 7e8f9a0
predecessor-bundle: bundle_X9
bundle-author: AB12 CD34 EF56 7890
timestamp: 2026-05-20T143500Z

## Description

OAuth flow extracted from monolithic auth module into service-boundary. 6 work commits + 1 fix-up + 1 self-attestation. RJ verdict 9.4, pass at floor.
```
