# Audit Mirror Setup

Notes for setting up the separate audit-mirror repository that holds the CSAE attestation chain.

See [`PROTOCOL.md`](../PROTOCOL.md) §"Audit mirror" for formal invariants.

## Why separate

The audit mirror lives in a separate Git repository from the primary repo. Two reasons:

- **Compromise isolation.** A compromise of one repo's signing keys doesn't compromise both. An attacker would need to compromise both repos' keys to forge the chain across the boundary.
- **Different lifecycle.** The primary repo evolves (history can occasionally rewrite for legitimate reasons — squash-merges, rebases). The audit mirror is append-only forever. Mixing them invites accidents.

## Setup steps

### 1. Create the audit-mirror repository

Typically private. Public mirrors are possible if the audit trail itself can be public — depends on whether bundle contents (workstream IDs, scope claims, verdict references) are sensitive. **Default to private** unless you've explicitly decided otherwise.

```bash
gh repo create org/csae-audit-mirror --private \
  --description "Audit chain mirror — bundle entries linking commits to verdicts and scope claims. Append-only."
```

### 2. Configure branch protection on main

Required protections:

- **No force-push** — history rewriting forbidden
- **No branch deletion** — main cannot be removed
- **Require signed commits** — all bundle entries must be cryptographically signed
- **Linear history** (optional but recommended) — keeps the chain trivially linearizable for audit walk-back

```bash
gh api -X PUT repos/org/csae-audit-mirror/branches/main/protection \
  --input - <<EOF
{
  "required_status_checks": null,
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_signatures": true
}
EOF
```

### 3. Generate distinct signing keys

The audit-mirror author keys should be different from the primary repo's commit-signing keys. Different operators may have different keys for the two repos. Key rotation policies should be independent.

Standard discipline: see [Sigstore](https://www.sigstore.dev) Gitsign for keyless ephemeral signing, or PGP for long-lived keys. CSAE itself doesn't mandate a specific signing scheme; pick a standard and apply it consistently.

### 4. Restrict write access

Write access to the audit mirror: only authorized bundle authors. Read access can be broader (audit consumers, due-diligence reviewers, attribution investigators).

GitHub: configure team permissions accordingly. The "write" role should be small and explicit.

### 5. Configure the validator

The validator on canonical main (pre-push hook or CI required check) needs read access to the audit mirror to perform coverage checks.

Set `CSAE_AUDIT_MIRROR` to the local clone path or remote URL the validator should read.

## Replication (high-stakes contexts)

For projects where audit-trail tampering is a real threat, replicate the audit mirror to one or more secondary mirrors. If the primary mirror is suspected tampered, forensic reconstruction depends on independent replicas.

Standard tooling: GitHub's repository-mirror feature, or a scheduled job that pushes the mirror's main to a secondary remote.

## File layout (suggestion)

```
csae-audit-mirror/
├── bundles/
│   ├── 2026-05/
│   │   ├── ws-auth-refactor-2026-05-20T143500Z.md
│   │   ├── ws-schema-cleanup-2026-05-21T091500Z.md
│   │   └── ...
│   ├── 2026-06/
│   │   └── ...
│   └── ...
├── verdicts/                 # if verdicts live in the audit mirror rather than the primary repo
│   ├── 2026-05/
│   │   └── ...
│   └── ...
├── bypass-records/           # logged bypasses become themselves audit-chain entries
│   └── ...
└── README.md                 # brief description of the mirror's role + chain-walk pointers
```

Organize by month for filesystem performance at scale (some teams hit thousands of bundles over a project's lifetime).

## What gets written to the mirror

- **Bundle files** — one per workstream
- **Bypass-record commits** — when applicable; see [`PROTOCOL.md`](../PROTOCOL.md) §"Validator semantics" — bypass-record
- **Chain-repair bundles** — when applicable; see [`PROTOCOL.md`](../PROTOCOL.md) §"Recovery"

## What does NOT get written to the mirror

- **Source code from the primary repo** — the bundle references commit ranges in the primary; it doesn't carry them
- **Substantive work content** — bundle is metadata
- **Operator or reviewer key material directly** — bundles are signed by keys, but key material itself stays in standard key-management infrastructure (PGP keyring, Sigstore, etc.)

## Verification

Quick health-check commands to verify the audit mirror is functioning correctly:

```bash
# Verify branch protection is intact
gh api repos/org/csae-audit-mirror/branches/main/protection \
  --jq '{linear: .required_linear_history.enabled, force: .allow_force_pushes.enabled, sigs: .required_signatures.enabled}'
# Expected: linear=true, force=false, sigs=true

# Verify no history rewriting has occurred
git -C csae-audit-mirror log --diff-filter=DM origin/main -- bundles/ | head
# Expected: empty (no deletions or modifications under bundles/)

# Verify chain head is reachable
git -C csae-audit-mirror log -1 --format="%H %s" -- bundles/
# Expected: most recent bundle's commit
```

Run these monthly, and immediately after any suspected tampering.
