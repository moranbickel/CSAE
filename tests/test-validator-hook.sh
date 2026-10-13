#!/usr/bin/env bash
# test-validator-hook.sh - multi-ref behaviour tests for templates/validator-hook.sh.
#
# Git's pre-push protocol supplies ONE stdin line PER REF being pushed:
#   <local_ref> <local_sha> <remote_ref> <remote_sha>
# so `git push origin feature main` sends a feature line and a main line. The
# hook must inspect every line, not just the first. These tests drive the hook
# directly with hand-built stdin (LF line endings only, never CRLF) against a
# throwaway git repo, a throwaway audit-mirror directory, and stub coverage
# tools placed on PATH:
#   - a stub that rejects every commit
#   - a stub that accepts every commit
#   - a stub that rejects only the commits named in $STUB_REJECT
#
# Run from anywhere:  bash tests/test-validator-hook.sh
#
# Exit codes: 0 - every test held; 1 - one or more failed.
# Portable to bash 3.2+. Requires: git.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/templates/validator-hook.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Hermetic git: ignore ambient global/system config (hooksPath, autocrlf...).
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$WORK/gitconfig"
: > "$GIT_CONFIG_GLOBAL"

PASS=0
FAIL=0
pass() { echo "  ok    $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1" >&2; FAIL=$((FAIL + 1)); }

g() {
  git -c user.email=test@example.com -c user.name=test \
      -c commit.gpgsign=false -c core.autocrlf=false "$@"
}

# Repo with two commits: base <- head.
repo="$WORK/repo"
g init -q -b main "$repo"
echo a > "$repo/f"; g -C "$repo" add f; g -C "$repo" commit -q -m base
base="$(g -C "$repo" rev-parse HEAD)"
echo b > "$repo/f"; g -C "$repo" add f; g -C "$repo" commit -q -m head
head="$(g -C "$repo" rev-parse HEAD)"
ZERO="0000000000000000000000000000000000000000"

mirror="$WORK/mirror"
mkdir -p "$mirror"

# Stub coverage tools, each named csae-verify in its own PATH directory.
mkdir -p "$WORK/reject" "$WORK/accept" "$WORK/select"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/reject/csae-verify"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/accept/csae-verify"
# Selective: invoked as `csae-verify --commit <sha> --audit-mirror <dir>`;
# rejects when <sha> (the second argument) is listed in $STUB_REJECT.
cat > "$WORK/select/csae-verify" <<'STUB'
#!/usr/bin/env bash
for r in ${STUB_REJECT:-}; do
  [ "$r" = "$2" ] && exit 1
done
exit 0
STUB
chmod +x "$WORK/reject/csae-verify" "$WORK/accept/csae-verify" "$WORK/select/csae-verify"

# run_hook <stub-dir-name> <stdin-text> [VAR=value ...]
# Runs the hook inside $repo as `validator-hook.sh origin`, sets LAST_RC and
# LAST_ERR (stderr). stdout is discarded.
LAST_RC=0
LAST_ERR=""
run_hook() {
  local stubdir="$1" input="$2"
  shift 2
  LAST_ERR="$(cd "$repo" && printf '%s' "$input" \
    | env PATH="$WORK/$stubdir:$PATH" CSAE_AUDIT_MIRROR="$mirror" "$@" \
        bash "$HOOK" origin 2>&1 >/dev/null)"
  LAST_RC=$?
}

expect_rc() {
  local want="$1" label="$2"
  if [ "$LAST_RC" -eq "$want" ]; then
    pass "$label (exit $LAST_RC)"
  else
    fail "$label (expected exit $want, got $LAST_RC; stderr: $LAST_ERR)"
  fi
}

MAIN="refs/heads/main $head refs/heads/main $base"
FEAT="refs/heads/feature $head refs/heads/feature $base"
NL=$'\n'

echo "test-validator-hook: multi-ref semantics"

# (a) Baseline. Protects: the single-line case that always worked. Without it
# a refactor to the loop could break the simple path and nothing below would
# say so.
run_hook reject "$MAIN$NL"
expect_rc 1 "(a) main-only, uncovered -> rejected"

# (b) THE REGRESSION. A feature line precedes the main line. The old hook read
# only the first line, saw a non-main ref, and exited 0, accepting an
# uncovered main update. Protects: every stdin line is inspected.
run_hook reject "$FEAT$NL$MAIN$NL"
expect_rc 1 "(b) feature line THEN main line, uncovered -> rejected"

# (c) Mirror of (b): main first, feature second. Protects: a fix that stops
# after the first protected line, or lets a trailing non-protected line
# overwrite the verdict, would pass (a) and (b) yet accept here.
run_hook reject "$MAIN$NL$FEAT$NL"
expect_rc 1 "(c) main line THEN feature line, uncovered -> rejected"

# (d) Feature-only push stays free. Protects: the pass-through for
# non-protected branches; the reject stub would fail the push if it were ever
# consulted.
run_hook reject "$FEAT$NL"
expect_rc 0 "(d) feature-only push, reject stub -> allowed"

# (e) Covered main passes, with and without a leading feature line. Protects:
# the loop does not over-reject; (b) is only a discrimination if this is 0.
run_hook accept "$MAIN$NL"
expect_rc 0 "(e1) main-only, covered -> accepted"
run_hook accept "$FEAT$NL$MAIN$NL"
expect_rc 0 "(e2) feature then main, covered -> accepted"

# (f) Deletion of the protected ref (local_sha all zeros) is never covered,
# even though there are no commits to check and the accept stub says yes.
# Protects: deleting canonical main cannot be waved through as an empty range.
run_hook accept "(delete) $ZERO refs/heads/main $head$NL"
expect_rc 1 "(f1) delete main -> rejected"
case "$LAST_ERR" in
  *delet*) pass "(f1) rejection message names the deletion" ;;
  *) fail "(f1) deletion message missing; stderr: $LAST_ERR" ;;
esac
run_hook accept "$FEAT$NL(delete) $ZERO refs/heads/main $head$NL"
expect_rc 1 "(f2) feature then delete main -> rejected"

# (g) Creation of the protected ref (remote_sha all zeros).
run_hook reject "refs/heads/main $head refs/heads/main $ZERO$NL"
expect_rc 1 "(g1) create main, uncovered -> rejected"
# The creation range is "new commits only": with a remote-tracking ref for
# the pushed remote already at $base, only $head is new. Rejecting ONLY $base
# must therefore pass; rejecting $head must fail. Protects: the range is
# neither empty (accepting everything) nor the whole history (re-demanding
# coverage of commits the remote already has).
g -C "$repo" update-ref refs/remotes/origin/other "$base"
run_hook select "refs/heads/main $head refs/heads/main $ZERO$NL" STUB_REJECT="$base"
expect_rc 0 "(g2) create main, only already-remote commit uncovered -> accepted"
run_hook select "refs/heads/main $head refs/heads/main $ZERO$NL" STUB_REJECT="$head"
expect_rc 1 "(g3) create main, new commit uncovered -> rejected"
g -C "$repo" update-ref -d refs/remotes/origin/other

# (h) Bypass is honoured with multi-line input and the reject stub.
run_hook reject "$FEAT$NL$MAIN$NL" BYPASS_CSAE=1
expect_rc 0 "(h) BYPASS_CSAE=1 -> allowed"

# (i) Accumulation across protected updates: two lines name the protected ref
# (unusual, but the hook must decide once over all of them); only the commit
# in the SECOND line is uncovered. Protects: a verdict overwritten by the last
# line, or taken from the first, instead of accumulated.
run_hook select "refs/heads/main $base refs/heads/main $ZERO$NL$MAIN$NL" STUB_REJECT="$head"
expect_rc 1 "(i) uncovered commit only in the later protected line -> rejected"
case "$LAST_ERR" in
  *"$head"*) pass "(i) diagnostic names the uncovered commit" ;;
  *) fail "(i) diagnostic does not name $head; stderr: $LAST_ERR" ;;
esac

# (j) Empty stdin: nothing is being pushed.
run_hook reject ""
expect_rc 0 "(j) empty stdin -> allowed"

# (k) CSAE_PROTECTED_REF retargets the protected branch. Protects: the knob is
# real - the configured ref is enforced and the default main line is then free.
REL="refs/heads/release $head refs/heads/release $base"
run_hook reject "$REL$NL" CSAE_PROTECTED_REF=refs/heads/release
expect_rc 1 "(k1) custom protected ref, uncovered -> rejected"
run_hook reject "$MAIN$NL" CSAE_PROTECTED_REF=refs/heads/release
expect_rc 0 "(k2) custom protected ref set, main line not protected -> allowed"

# (l) A final line with no trailing newline is still read. Protects: the
# `while read` loop does not drop an unterminated last line.
run_hook reject "$MAIN"
expect_rc 1 "(l) main line without trailing newline -> rejected"

# (m) Existing exit-code contract: with a protected update, a missing audit
# mirror is an error (2), never a silent accept.
LAST_ERR="$(cd "$repo" && printf '%s\n' "$MAIN" \
  | env PATH="$WORK/accept:$PATH" CSAE_AUDIT_MIRROR="$WORK/nope" bash "$HOOK" origin 2>&1 >/dev/null)"
LAST_RC=$?
expect_rc 2 "(m) missing audit mirror -> error"

echo ""
echo "test-validator-hook: $PASS passed, $FAIL failed."
[ "$FAIL" -eq 0 ]
