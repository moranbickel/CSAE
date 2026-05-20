#!/usr/bin/env bash
# validator-hook.sh
# CSAE validator — pre-push hook (or CI required check) on canonical main.
#
# Refuses pushes to canonical main whose commits are not covered by an
# attested bundle in the audit mirror. This is the enforcer that closes
# the trust gap — without it, the discipline is voluntary and erodes under
# operator fatigue. With it, the discipline is mechanical and survives.
#
# Install: as a pre-push hook in the primary repo (NOT in worker trees;
# only the canonical-receiving repo needs this enforcement). Or wire as a
# CI required check on the main branch.
#
# Exit codes:
#   0 — push allowed (all commits covered, chain integrity intact)
#   1 — push rejected (uncovered commits or chain integrity broken)
#   2 — error (audit mirror unreachable, configuration broken)
#
# Bypass: BYPASS_CSAE=1 in environment allows push without coverage check.
# The bypass is intentionally awkward (env var, not a CLI flag); routine
# use erodes the discipline. If you find yourself bypassing often, the
# protocol isn't fitting the work — investigate, don't keep bypassing.

set -euo pipefail

# Configuration (adjust per project)
AUDIT_MIRROR_REPO="${CSAE_AUDIT_MIRROR:-../audit-mirror}"
COVERAGE_TOOL="${CSAE_COVERAGE_TOOL:-csae-verify}"

# Read commit range from stdin (Git pre-push hook protocol).
# Format: <local_ref> <local_sha> <remote_ref> <remote_sha>
read -r local_ref local_sha remote_ref remote_sha

# Only check pushes to main (the canonical branch). Other branches push freely.
if [[ "$remote_ref" != "refs/heads/main" ]]; then
  exit 0
fi

# Bypass check
if [[ "${BYPASS_CSAE:-}" == "1" ]]; then
  cat >&2 <<EOF
csae-validator: BYPASSED (BYPASS_CSAE=1).

Push allowed without coverage check. Recommended follow-up:
  1. Document the bypass rationale in DECISIONS_LOG.
  2. Consider whether a logged bypass-record commit on the audit mirror
     is required for audit-trail integrity.

If you reach for BYPASS_CSAE routinely, the protocol isn't fitting your
work — investigate the misfit, don't normalize the bypass.
EOF
  exit 0
fi

# Verify audit mirror is reachable
if [[ ! -d "$AUDIT_MIRROR_REPO" ]]; then
  cat >&2 <<EOF
csae-validator: ERROR — audit mirror not found at $AUDIT_MIRROR_REPO.

Set CSAE_AUDIT_MIRROR to the path of the audit-mirror repository
(typically a sibling clone of the primary repo).
EOF
  exit 2
fi

# Verify the coverage tool is available
if ! command -v "$COVERAGE_TOOL" >/dev/null 2>&1; then
  echo "csae-validator: ERROR — coverage tool '$COVERAGE_TOOL' not found in PATH" >&2
  exit 2
fi

# For each commit in the push range, verify coverage
COMMITS=$(git rev-list "$remote_sha".."$local_sha")
UNCOVERED=()

for commit in $COMMITS; do
  if ! "$COVERAGE_TOOL" --commit "$commit" --audit-mirror "$AUDIT_MIRROR_REPO" >/dev/null 2>&1; then
    UNCOVERED+=("$commit")
  fi
done

# All commits covered → accept
if [[ ${#UNCOVERED[@]} -eq 0 ]]; then
  TOTAL=$(echo "$COMMITS" | wc -l)
  echo "csae-validator: ACCEPT — all $TOTAL commit(s) covered."
  exit 0
fi

# Reject with diagnostic
cat >&2 <<EOF
csae-validator: REJECTED — ${#UNCOVERED[@]} commit(s) not covered by any bundle in audit mirror.

Uncovered commits:
$(printf '  %s\n' "${UNCOVERED[@]}")

Likely causes:
  1. Bundle not yet pushed to audit mirror — sequence the publish before
     the canonical push, then re-attempt.
  2. Coverage gap from a prior unlogged bypass — see PROTOCOL.md §Recovery
     for retroactive-attestation procedure.
  3. Validator misconfiguration — verify CSAE_AUDIT_MIRROR path is correct.

See PROTOCOL.md §"Validator semantics" + §Recovery for diagnostics.
EOF
exit 1
