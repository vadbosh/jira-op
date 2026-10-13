#!/usr/bin/env bash
# Tests for skills/jira-op/scripts/automode-setup.sh, in a throw-away HOME.
#   tests/test_automode_setup.sh        run all, print failures and a summary
#   tests/test_automode_setup.sh -q     only the summary line
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/skills/jira-op/scripts/automode-setup.sh"
QUIET=0; [ "${1:-}" = "-q" ] && QUIET=1
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0

ok()  { pass=$((pass + 1)); [ "$QUIET" = 1 ] || printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

fresh() {  # fresh [settings-json] — new HOME with one jira-cli site
	export HOME="$T/h$RANDOM"; unset CLAUDE_CONFIG_DIR XDG_STATE_HOME
	mkdir -p "$HOME/.config/.jira" "$HOME/.claude"
	printf 'installation: Cloud\nserver: https://acme.atlassian.net\nlogin: a@b.c\n' \
		>"$HOME/.config/.jira/.config.yml"
	[ -n "${1:-}" ] && printf '%s\n' "$1" >"$HOME/.claude/settings.json"
	S="$HOME/.claude/settings.json"
}
run() { printf '%s\n' "$1" | bash "$SCRIPT" "${@:2}" >"$T/out" 2>&1; echo $?; }

# 1. no autoMode yet: both lists start with $defaults, other keys kept
fresh '{"hooks":{"PreToolUse":[]},"model":"opus"}'
rc=$(run y)
got=$(jq -c '[.autoMode.environment[0], (.autoMode.allow|length), .model, (.hooks|type)]' "$S")
[ "$rc" = 0 ] && [ "$got" = '["$defaults",2,"opus","object"]' ] \
	&& ok "new autoMode starts with \$defaults, other keys kept" \
	|| bad "new autoMode starts with \$defaults, other keys kept" "rc=$rc got=$got"
jq -e '.autoMode.allow[1] | startswith("jira-op: a write to the user'"'"'s Jira (acme.atlassian.net)")' "$S" >/dev/null \
	&& ok "allow entry names the site" || bad "allow entry names the site" "$(jq -c .autoMode.allow "$S")"

# 2. rerun: nothing to do, file byte-identical
cp "$S" "$T/before"; rc=$(run y)
cmp -s "$S" "$T/before" && grep -q 'already current' "$T/out" \
	&& ok "rerun is a no-op" || bad "rerun is a no-op" "$(cat "$T/out")"

# 3. user entries kept, our old entry replaced, no $defaults added to a list the user wrote
fresh '{"autoMode":{"allow":["mine","jira-op: stale"],"soft_deny":["$defaults","x"]}}'
rc=$(run y)
got=$(jq -c '[.autoMode.allow[0], (.autoMode.allow|length), (.autoMode.allow|map(select(.=="jira-op: stale"))|length), .autoMode.soft_deny]' "$S")
[ "$got" = '["mine",2,0,["$defaults","x"]]' ] \
	&& ok "user entries kept, stale jira-op entry replaced" || bad "user entries kept, stale jira-op entry replaced" "$got"

# 4. answer no: unchanged
fresh '{"model":"opus"}'; cp "$S" "$T/before"; rc=$(run n)
cmp -s "$S" "$T/before" && [ "$rc" = 0 ] && grep -q 'not written' "$T/out" \
	&& ok "answer n writes nothing" || bad "answer n writes nothing" "rc=$rc"

# 4b. no input at all (Claude Code's "!" prefix): unchanged, names the echo y form
fresh '{"model":"opus"}'; cp "$S" "$T/before"
bash "$SCRIPT" </dev/null >"$T/out" 2>&1; rc=$?
cmp -s "$S" "$T/before" && [ "$rc" = 0 ] && grep -q 'echo y | ' "$T/out" \
	&& ok "closed stdin writes nothing and names echo y" || bad "closed stdin writes nothing and names echo y" "rc=$rc $(tail -2 "$T/out")"

# 5. --dry-run: unchanged, shows the after
fresh '{"model":"opus"}'; cp "$S" "$T/before"; rc=$(run y --dry-run)
cmp -s "$S" "$T/before" && grep -q 'jira-op: acme.atlassian.net' "$T/out" \
	&& ok "--dry-run shows and writes nothing" || bad "--dry-run shows and writes nothing" "rc=$rc"

# 6. no site configured: exit 3, unchanged
fresh '{"model":"opus"}'; rm "$HOME/.config/.jira/.config.yml"; cp "$S" "$T/before"; rc=$(run y)
[ "$rc" = 3 ] && cmp -s "$S" "$T/before" \
	&& ok "no site: exit 3" || bad "no site: exit 3" "rc=$rc"

# 7. invalid settings.json: exit 1, unchanged
fresh '{"model": '; cp "$S" "$T/before"; rc=$(run y)
[ "$rc" = 1 ] && cmp -s "$S" "$T/before" \
	&& ok "invalid JSON: exit 1, untouched" || bad "invalid JSON: exit 1, untouched" "rc=$rc"

# 8. several sites, one entry naming both; a backup is made
fresh '{"model":"opus"}'
printf 'server: "https://other.atlassian.net"\n' >"$HOME/.config/.jira/other.yml"
rc=$(run y)
jq -e '.autoMode.environment[1] | contains("acme.atlassian.net, other.atlassian.net") or contains("other.atlassian.net, acme.atlassian.net")' "$S" >/dev/null \
	&& ls "$HOME/.local/state/jira-op-backups/"settings.json.* >/dev/null 2>&1 \
	&& ok "several sites in one entry, backup made" || bad "several sites in one entry, backup made" "$(jq -c .autoMode.environment "$S")"

# 9. --remove takes out only the jira-op entries
fresh '{"autoMode":{"allow":["$defaults","mine"]}}'; run y >/dev/null; rc=$(run y --remove)
got=$(jq -c '.autoMode.allow' "$S")
[ "$got" = '["$defaults","mine"]' ] && ok "--remove keeps the rest" || bad "--remove keeps the rest" "$got"

# 10. no settings.json at all: created
fresh; rc=$(run y)
[ "$rc" = 0 ] && jq -e '.autoMode.allow[1]' "$S" >/dev/null \
	&& ok "missing settings.json is created" || bad "missing settings.json is created" "rc=$rc"

printf 'automode-setup: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
