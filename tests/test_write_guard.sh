#!/usr/bin/env bash
# Tests for skills/jira-op/scripts/jira-write-guard.
#   tests/test_write_guard.sh        run all, print failures and a summary
#   tests/test_write_guard.sh -q     only the summary line
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/skills/jira-op/scripts/jira-write-guard"
QUIET=0; [ "${1:-}" = "-q" ] && QUIET=1
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0

MARK='Черновик: Summary: X ... Утверждаешь? (да/нет)'

# --- transcript builders -----------------------------------------------------
cc() {  # cc <file> <kind:text> ... ; kinds: u=typed user, a=assistant text, q=dialog answer (tool_result)
	local f="$1"; shift; : >"$f"
	for item in "$@"; do
		local kind="${item%%:*}" text="${item#*:}"
		case "$kind" in
			u) jq -cn --arg t "$text" '{type:"user",message:{role:"user",content:$t}}' >>"$f" ;;
			a) jq -cn --arg t "$text" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >>"$f" ;;
			q) jq -cn --arg t "$text" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"x",content:$t}]}}' >>"$f" ;;
		esac
	done
}
codex() {  # same kinds, Codex rollout format; first line is the injected AGENTS.md
	local f="$1"; shift
	jq -cn '{type:"response_item",payload:{type:"message",role:"user",content:[{type:"input_text",text:"# AGENTS.md instructions\nда"}]}}' >"$f"
	for item in "$@"; do
		local kind="${item%%:*}" text="${item#*:}"
		case "$kind" in
			u) jq -cn --arg t "$text" '{type:"response_item",payload:{type:"message",role:"user",content:[{type:"input_text",text:$t}]}}' >>"$f" ;;
			a) jq -cn --arg t "$text" '{type:"response_item",payload:{type:"message",role:"assistant",content:[{type:"output_text",text:$t}]}}' >>"$f" ;;
		esac
	done
}

# expect <name> <0|2> <command> <transcript|-> [messages-json]
expect() {
	local name="$1" want="$2" cmd="$3" tr="$4" msgs="${5:-}" payload got
	if [ -n "$msgs" ]; then
		payload="$(jq -cn --arg c "$cmd" --argjson m "$msgs" '{tool_name:"bash",tool_input:{command:$c},messages:$m}')"
	elif [ "$tr" = "-" ]; then
		payload="$(jq -cn --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c},transcript_path:null}')"
	else
		payload="$(jq -cn --arg c "$cmd" --arg p "$tr" '{tool_name:"Bash",tool_input:{command:$c},transcript_path:$p}')"
	fi
	printf '%s' "$payload" | "$GUARD" >/dev/null 2>&1; got=$?
	if [ "$got" = "$want" ]; then pass=$((pass+1)); else
		fail=$((fail+1)); [ "$QUIET" = 1 ] || echo "FAIL $name: want $want, got $got"
	fi
}

CREATE='curl -s -X POST -u "$E:$T" -H "Content-Type: application/json" --data-binary @/tmp/op.json https://x.atlassian.net/rest/api/2/issue'

# --- approval logic, Claude Code transcript -----------------------------------
cc "$T/ok.jsonl" "u:заведи тикет" "a:$MARK" "u:да"
expect "cc: typed да after marker" 0 "$CREATE" "$T/ok.jsonl"
cc "$T/ok2.jsonl" "u:заведи тикет" "a:$MARK" "u:  Да! " "a:создаю"
expect "cc: Да! with spaces, later writes of the turn" 0 "jira issue move OP-1 'In Progress' </dev/null" "$T/ok2.jsonl"
cc "$T/dialog.jsonl" "u:заведи тикет" "a:$MARK" "q:Story Points=3, Sprint=OP Sprint 7"
expect "cc: dialog answer is not approval (the 2026-10-01 case)" 2 "$CREATE" "$T/dialog.jsonl"
cc "$T/nomark.jsonl" "u:заведи тикет" "a:вот черновик без вопроса" "u:да"
expect "cc: да without marker" 2 "$CREATE" "$T/nomark.jsonl"
cc "$T/more.jsonl" "u:заведи тикет" "a:$MARK" "u:да, но поменяй summary"
expect "cc: да with extra words" 2 "$CREATE" "$T/more.jsonl"
cc "$T/stale.jsonl" "u:заведи тикет" "a:$MARK" "u:да" "a:создал" "u:теперь заведи второй"
expect "cc: earlier да does not carry over" 2 "$CREATE" "$T/stale.jsonl"
cc "$T/oldmark.jsonl" "u:t" "a:$MARK" "u:нет" "a:ок, правлю" "u:да"
expect "cc: marker must be in the reply before the да" 2 "$CREATE" "$T/oldmark.jsonl"
cc "$T/en.jsonl" "u:file it" "a:Summary: X ... Approve? (yes/no)" "u:yes"
expect "cc: English marker and yes" 0 "$CREATE" "$T/en.jsonl"

# --- Codex rollout ----------------------------------------------------------------
codex "$T/cx.jsonl" "u:заведи тикет" "a:$MARK" "u:утверждаю"
expect "codex: утверждаю after marker" 0 "$CREATE" "$T/cx.jsonl"
codex "$T/cx2.jsonl" "u:заведи тикет" "a:$MARK"
expect "codex: injected AGENTS.md line is not a human да" 2 "$CREATE" "$T/cx2.jsonl"

# --- Opencode messages ------------------------------------------------------------
expect "opencode: messages, да" 0 "jira issue create -pOP" - \
	'[{"role":"user","text":"заведи"},{"role":"assistant","text":"Утверждаешь? (да/нет)"},{"role":"user","text":"да"}]'
expect "opencode: messages, no approval" 2 "jira issue create -pOP" - \
	'[{"role":"user","text":"заведи"},{"role":"assistant","text":"черновик"}]'

# --- no conversation: writes refused, reads allowed -------------------------------
expect "null transcript, write" 2 "$CREATE" -
expect "missing transcript file, write" 2 "$CREATE" "$T/nope.jsonl"
expect "null transcript, read" 0 "jira issue view OP-1 --comments 10" -

# --- what is a write ----------------------------------------------------------------
for c in \
	"jira issue create -pOP -tTask -s x --no-input </dev/null" \
	"jira issue edit OP-1 -b x </dev/null" \
	"rtk jira issue move OP-1 Completed" \
	"timeout 15 jira issue comment add OP-1 -T /tmp/c.md </dev/null" \
	"set -a; . ~/.config/.jira/token.env; set +a; jira sprint add 4945 OP-1" \
	"jira epic add OP-9 OP-1" \
	"curl -s -X PUT -u a:b -d '{\"fields\":{}}' https://x.atlassian.net/rest/api/2/issue/OP-1" \
	"curl -s -u a:b --data-binary @/tmp/c.json https://x.atlassian.net/rest/api/2/issue/OP-1/comment" \
	"curl -sXDELETE https://x.atlassian.net/rest/api/2/issue/OP-1"; do
	expect "write: $c" 2 "$c" -
done
for c in \
	"jira issue view OP-1" \
	"jira issue list -a me --plain --paginate 15 </dev/null" \
	"jira sprint list --state active" \
	"jira me" \
	"curl -s -u a:b https://x.atlassian.net/rest/api/3/issue/OP-1?fields=summary" \
	"curl -s -u a:b 'https://x.atlassian.net/rest/agile/1.0/board/1/sprint?state=active' | jq -r ." \
	"rg -n 'jira issue create' references/create-task.md" \
	"echo 'jira issue create -pOP'" \
	"curl -s -X POST -d x https://example.com/api" \
	"git commit -m 'document jira issue edit'"; do
	expect "not a write: $c" 0 "$c" -
done

# --- not a hook payload -----------------------------------------------------------
printf 'garbage' | "$GUARD" >/dev/null 2>&1 && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL garbage stdin"; }

echo "jira-write-guard: $pass passed, $fail failed"
[ "$fail" = 0 ]
