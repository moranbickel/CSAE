#!/usr/bin/env bash
# validator-hook.sh
# CSAE validator - pre-push hook (or CI required check) on canonical main.
#
# Refuses pushes to canonical main whose commits are not covered by an
# attested bundle in the audit mirror. This is the enforcer that closes
# the trust gap - without it, the discipline is voluntary and erodes under
# operator fatigue. With it, the discipline is mechanical and survives.
#
# Install: as a pre-push hook in the primary repo (NOT in worker trees;
# only the canonical-receiving repo needs this enforcement). Or wire as a
# CI required check on the main branch.
#
# External dependency: the per-commit coverage verdict is delegated to a
# coverage tool ($CSAE_COVERAGE_TOOL, default `csae-verify`) that this
# repository does NOT ship. The adopter must supply it. The hook calls
#   <tool> --commit <sha> --audit-mirror <dir>
# and treats exit 0 as "covered" and any non-zero exit as "not covered".
#
# Multi-ref pushes: Git supplies one stdin line per ref being pushed
# (`git push origin feature main` sends two lines). The hook reads EVERY
# line, checks every update whose remote ref is the protected ref, pools the
# uncovered commits across all of them, and decides once at the end. Updates
# to other refs are not checked, whatever their position in the input.
#
# Exit codes:
#   0 - push allowed (all commits covered, or no protected ref is updated)
#   1 - push rejected (uncovered commits, or deletion of the protected ref)
#   2 - error (audit mirror unreachable, coverage tool missing, commit
#       range cannot be computed, configuration broken)
#
# Bypass: BYPASS_CSAE=1 in environment allows push without coverage check.
# The bypass is intentionally awkward (env var, not a CLI flag); routine
# use erodes the discipline. If you find yourself bypassing often, the
# protocol isn't fitting the work - investigate, don't keep bypassing.

set -euo pipefail

# Configuration (adjust per project)
AUDIT_MIRROR_REPO="${CSAE_AUDIT_MIRROR:-../audit-mirror}"
COVERAGE_TOOL="${CSAE_COVERAGE_TOOL:-csae-verify}"
PROTECTED_REF="${CSAE_PROTECTED_REF:-refs/heads/main}"

# Git passes the remote name (or URL) as $1 to a pre-push hook.
REMOTE_NAME="${1:-}"

# True when $1 is an all-zero object id (any hash length).
is_zero() { [[ "$1" =~ ^0+$ ]]; }

# Read every line of the push (Git pre-push hook protocol).
# Format: <local_ref> <local_sha> <remote_ref> <remote_sha>
# `|| [[ -n ... ]]` keeps a final line that lacks a trailing newline.
# Updates to the protected ref are queued as "local_sha remote_sha"; the
# coverage tool runs only after stdin is fully consumed, so it can never
# swallow the remaining lines.
PROTECTED_UPDATES=()
DELETES_PROTECTED=0
while read -r local_ref local_sha remote_ref remote_sha || [[ -n "${local_ref:-}" ]]; do
  remote_sha="${remote_sha%$'\r'}"
  [[ "$remote_ref" == "$PROTECTED_REF" ]] || continue
  if is_zero "$local_sha"; then
    DELETES_PROTECTED=1
  else
    PROTECTED_UPDATES+=("$local_sha $remote_sha")
  fi
done

# Nothing touches the protected ref (this includes empty stdin): allow.
if [[ "$DELETES_PROTECTED" -eq 0 && ${#PROTECTED_UPDATES[@]} -eq 0 ]]; then
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
work - investigate the misfit, don't normalize the bypass.
EOF
  exit 0
fi

# Deleting the protected ref is never covered: there is no bundle that can
# attest the removal of canonical main.
if [[ "$DELETES_PROTECTED" -eq 1 ]]; then
  cat >&2 <<EOF
csae-validator: REJECTED - this push deletes the protected ref ($PROTECTED_REF).

Deleting the canonical branch is never covered by a bundle. If the deletion
is intended, use BYPASS_CSAE=1 and record the rationale (see PROTOCOL.md
§Recovery).
EOF
  exit 1
fi

# Verify audit mirror is reachable
if [[ ! -d "$AUDIT_MIRROR_REPO" ]]; then
  cat >&2 <<EOF
csae-validator: ERROR - audit mirror not found at $AUDIT_MIRROR_REPO.

Set CSAE_AUDIT_MIRROR to the path of the audit-mirror repository
(typically a sibling clone of the primary repo).
EOF
  exit 2
fi

# Verify the coverage tool is available
if ! command -v "$COVERAGE_TOOL" >/dev/null 2>&1; then
  echo "csae-validator: ERROR - coverage tool '$COVERAGE_TOOL' not found in PATH" >&2
  exit 2
fi

# Collect the commits to cover across every protected update.
#   - Existing ref (remote_sha non-zero): the new commits are
#     `remote_sha..local_sha`.
#   - New ref (remote_sha all zeros): there is no base to subtract, and
#     `0000..local_sha` is not a valid range. The new commits are those
#     reachable from local_sha but from no remote-tracking ref of the pushed
#     remote: `rev-list local_sha --not --remotes=<remote>`. If $1 is a URL
#     rather than a configured remote name the glob matches nothing and the
#     whole history is checked - the fail-closed direction.
ALL_COMMITS=""
for update in "${PROTECTED_UPDATES[@]}"; do
  local_sha="${update%% *}"
  remote_sha="${update##* }"
  if is_zero "$remote_sha"; then
    if [[ -n "$REMOTE_NAME" ]]; then
      range=(git rev-list "$local_sha" --not "--remotes=$REMOTE_NAME")
    else
      range=(git rev-list "$local_sha" --not --remotes)
    fi
  else
    range=(git rev-list "$remote_sha..$local_sha")
  fi
  if ! commits=$("${range[@]}" 2>&1); then
    echo "csae-validator: ERROR - cannot compute commit range for $PROTECTED_REF update ($local_sha): $commits" >&2
    exit 2
  fi
  ALL_COMMITS+="$commits"$'\n'
done

# De-duplicate (two updates of the protected ref can overlap) and drop blanks.
COMMITS=$(printf '%s' "$ALL_COMMITS" | awk 'NF && !seen[$0]++')

# Verify coverage of each commit. </dev/null: the tool must not read the
# hook's stdin.
UNCOVERED=()
TOTAL=0
if [[ -n "$COMMITS" ]]; then
  while IFS= read -r commit; do
    TOTAL=$((TOTAL + 1))
    if ! "$COVERAGE_TOOL" --commit "$commit" --audit-mirror "$AUDIT_MIRROR_REPO" >/dev/null 2>&1 </dev/null; then
      UNCOVERED+=("$commit")
    fi
  done <<<"$COMMITS"
fi

# All commits covered → accept
if [[ ${#UNCOVERED[@]} -eq 0 ]]; then
  echo "csae-validator: ACCEPT - all $TOTAL commit(s) covered."
  exit 0
fi

# Reject with diagnostic
cat >&2 <<EOF
csae-validator: REJECTED - ${#UNCOVERED[@]} commit(s) not covered by any bundle in audit mirror.

Uncovered commits:
$(printf '  %s\n' "${UNCOVERED[@]}")

Likely causes:
  1. Bundle not yet pushed to audit mirror - sequence the publish before
     the canonical push, then re-attempt.
  2. Coverage gap from a prior unlogged bypass - see PROTOCOL.md §Recovery
     for retroactive-attestation procedure.
  3. Validator misconfiguration - verify CSAE_AUDIT_MIRROR path is correct.

See PROTOCOL.md §"Validator semantics" + §Recovery for diagnostics.
EOF
exit 1
