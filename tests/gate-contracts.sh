#!/usr/bin/env bash
# gate-contracts.sh - exit-code contract test for the CSAE validator hook.
#
# validator-hook.sh is the gate: a pre-push hook on canonical main that
# refuses a push whose commits are not covered by an attested bundle. A
# gate that fails open (accepts an uncovered push) silently defeats the
# whole discipline, so its exit-code contract is worth pinning.
#
# The hook DELEGATES the per-commit coverage verdict to an external tool
# ($CSAE_COVERAGE_TOOL). The test provides a stub coverage tool and drives
# both verdicts: swapping the stub from "covered" to "uncovered" is exactly
# "neutralize the gate's core check", which is what makes the accept/reject
# pair a real discrimination rather than a coincidence.
#
# Covered:
#   - templates/validator-hook.sh  (CSAE validator, pre-push)
#
# The fixtures are hermetic: they neutralize any global/system git config
# so an ambient hooksPath or autocrlf setting cannot interfere.
#
# Run from anywhere:  bash tests/gate-contracts.sh
#
# Exit codes:
#   0 - every contract held
#   1 - one or more contracts were violated
#
# Portable to bash 3.2+ (no mapfile). Requires: git.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT/templates/validator-hook.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$WORK/gitconfig"
: > "$GIT_CONFIG_GLOBAL"

PASS=0
FAIL=0
pass() { echo "  ok    $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1" >&2; FAIL=$((FAIL + 1)); }

# Assert a command exits with an exact code. Usage: expect <code> <label> -- <cmd...>
expect() {
  local want="$1" label="$2"
  shift 3 # drop want, label, and the literal "--"
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then
    pass "$label (exit $got)"
  else
    fail "$label (expected exit $want, got $got)"
  fi
}

g() {
  git -c user.email=test@example.com -c user.name=test \
      -c commit.gpgsign=false -c core.autocrlf=false "$@"
}

# A repo with two commits, so the push range base..head holds one commit.
repo="$WORK/repo"
g init -q -b main "$repo"
echo a > "$repo/f"; g -C "$repo" add f; g -C "$repo" commit -q -m "base commit"
base="$(g -C "$repo" rev-parse HEAD)"
echo b > "$repo/f"; g -C "$repo" add f; g -C "$repo" commit -q -m "head commit"
head="$(g -C "$repo" rev-parse HEAD)"

# An existing audit-mirror directory. The hook only checks that it exists;
# coverage itself is delegated to the coverage tool below.
mirror="$WORK/mirror"
mkdir -p "$mirror"

# Two stub coverage tools: one reports every commit covered, one reports
# every commit uncovered. They ignore their arguments and just exit.
covered="$WORK/covered.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$covered"
chmod +x "$covered"
uncovered="$WORK/uncovered.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$uncovered"
chmod +x "$uncovered"

# Git pre-push stdin format: <local_ref> <local_sha> <remote_ref> <remote_sha>
PUSHLINE="refs/heads/main $head refs/heads/main $base"

echo "gate-contracts: validator-hook.sh (CSAE validator)"

# ACCEPT: coverage tool reports the commit covered.
expect 0 "covered commit is accepted" -- \
  bash -c "cd '$repo' && printf '%s\n' '$PUSHLINE' | CSAE_AUDIT_MIRROR='$mirror' CSAE_COVERAGE_TOOL='$covered' bash '$VALIDATOR'"

# REJECT: coverage tool reports the commit uncovered. Only the stub differs
# from the ACCEPT case above - this is the discrimination proof.
expect 1 "uncovered commit is rejected" -- \
  bash -c "cd '$repo' && printf '%s\n' '$PUSHLINE' | CSAE_AUDIT_MIRROR='$mirror' CSAE_COVERAGE_TOOL='$uncovered' bash '$VALIDATOR'"

# PASS-THROUGH: a push to a non-main ref is not coverage-checked. The
# uncovered stub would reject if it were reached; exit 0 proves it is not.
expect 0 "push to a non-main ref is passed through" -- \
  bash -c "cd '$repo' && printf 'refs/heads/feature %s refs/heads/feature %s\n' '$head' '$base' | CSAE_AUDIT_MIRROR='$mirror' CSAE_COVERAGE_TOOL='$uncovered' bash '$VALIDATOR'"

# BYPASS: BYPASS_CSAE=1 allows the push even with an uncovered stub.
expect 0 "BYPASS_CSAE=1 is allowed" -- \
  bash -c "cd '$repo' && printf '%s\n' '$PUSHLINE' | BYPASS_CSAE=1 CSAE_AUDIT_MIRROR='$mirror' CSAE_COVERAGE_TOOL='$uncovered' bash '$VALIDATOR'"

# MISCONFIG: audit mirror absent => error (2), never a silent accept.
expect 2 "missing audit mirror is an error" -- \
  bash -c "cd '$repo' && printf '%s\n' '$PUSHLINE' | CSAE_AUDIT_MIRROR='$WORK/does-not-exist' CSAE_COVERAGE_TOOL='$covered' bash '$VALIDATOR'"

# MISCONFIG: coverage tool not found => error (2), never a silent accept.
expect 2 "missing coverage tool is an error" -- \
  bash -c "cd '$repo' && printf '%s\n' '$PUSHLINE' | CSAE_AUDIT_MIRROR='$mirror' CSAE_COVERAGE_TOOL='csae-verify-absent-xyz' bash '$VALIDATOR'"

# EDGE: an empty push range (local == remote) has no commits to cover and is
# vacuously accepted. Pinned so a future refactor cannot quietly widen this
# into "accept everything".
expect 0 "empty push range is accepted (nothing to cover)" -- \
  bash -c "cd '$repo' && printf 'refs/heads/main %s refs/heads/main %s\n' '$head' '$head' | CSAE_AUDIT_MIRROR='$mirror' CSAE_COVERAGE_TOOL='$covered' bash '$VALIDATOR'"

echo ""
echo "gate-contracts: $PASS passed, $FAIL failed."
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
