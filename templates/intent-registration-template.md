# Intent Registration Template

A registration commit's message embeds the scope claim — what work was authorized, by whom, when, against which workstream. The registration must precede substantive work (eager-registration discipline; see [`PROTOCOL.md`](../PROTOCOL.md) §"Intent registration").

The exact tooling format depends on your project. The minimum-viable commit message:

```
[csae-reg] <workstream-id>: <one-sentence intent>

workstream-id: <unique-within-project>
intent: <one to three sentences describing what was authorized>
operator: <signing-key-fingerprint-or-name>
timestamp: <ISO-8601 UTC>
```

## Required fields

| Field | Purpose |
|---|---|
| `workstream-id` | Unique within the project's workstream namespace |
| `intent` | One sentence minimum; ≤ 3 sentences for compactness |
| `operator` | Who is authorizing |
| `timestamp` | When (ISO-8601, UTC) |

## Optional fields

- `predecessor-workstream` — if this work follows a prior workstream and the chain reference matters
- `estimated-scope` — rough commit count or files touched (advisory, not binding)
- `cluster-or-domain` — project-level taxonomy tag for cross-workstream search

## What the registration commit should NOT contain

- Substantive work content (registration precedes work; commit message describes intent, not implementation)
- Reviewer assignments (the verdict comes later in the chain, signed independently)
- Detailed acceptance criteria (those are review-time concerns)

The registration is intentionally small: it asserts authorization, not execution.

## Example

```
[csae-reg] ws-auth-refactor: extract OAuth flow from monolithic auth module

workstream-id: ws-auth-refactor
intent: Extract the OAuth flow (token exchange + refresh) from the monolithic auth module into a separate service-boundary; touches oauth/, tests/oauth/, and the consumer at api/middleware/auth.py. Estimated 4-6 commits.
operator: alice@example (key fingerprint: AB12 CD34 EF56 7890)
timestamp: 2026-05-20T091500Z
```

## Tooling integration

Most teams wrap this in a small CLI/script (`csae-register-intent` or similar) that:

1. Takes workstream ID + intent statement as arguments
2. Constructs the standardized commit message
3. Produces an empty commit (no file changes, just the registration record) on the current worker branch
4. Returns the commit hash for downstream bundle-authoring reference

The hash returned is the `C_scope` reference that subsequent bundles use as their scope-claim reference.
