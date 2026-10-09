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

DRAFT=$'Summary:      Fix the build\nType:         Task\n\nDescription:\nWhat was done.\n\n'
MARK="${DRAFT}Утверждаешь? (да/нет)"

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
	raw "$name" "$want" "$payload"
}
# raw <name> <0|2> <payload> — any stdin, as the host would send it
raw() {
	local got
	printf '%s' "$3" | "$GUARD" >/dev/null 2>&1; got=$?
	tally "$1" "$2" "$got"
}
tally() {  # tally <name> <want> <got>
	if [ "$3" = "$2" ]; then pass=$((pass+1)); else
		fail=$((fail+1)); [ "$QUIET" = 1 ] || echo "FAIL $1: want $2, got $3"
	fi
}

jq -n '{fields:{summary:"Fix the build"}}' >"$T/op.json"
CREATE="curl -s -X POST -u a:b -H 'Content-Type: application/json' --data-binary @$T/op.json https://x.atlassian.net/rest/api/2/issue"

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
cc "$T/en.jsonl" "u:file it" "a:${DRAFT}Approve? (yes/no)" "u:yes"
expect "cc: English marker and yes" 0 "$CREATE" "$T/en.jsonl"
cc "$T/slash.jsonl" "u:заведи тикет" "a:$MARK" "u:<command-name>/compact</command-name>" "a:контекст сжат" "u:да"
expect "cc: a slash command closes the draft's window" 2 "$CREATE" "$T/slash.jsonl"
cc "$T/intr.jsonl" "u:заведи тикет" "a:$MARK" "u:[Request interrupted by user]" "a:новый ответ" "u:да"
expect "cc: an interrupt closes the draft's window" 2 "$CREATE" "$T/intr.jsonl"
cc "$T/inj.jsonl" "u:заведи тикет" "a:$MARK" "u:<system-reminder>x</system-reminder>" "u:да"
expect "cc: injected text does not close the window" 0 "$CREATE" "$T/inj.jsonl"
cc "$T/quoted.jsonl" "u:как работает guard?" "a:Он ждёт строку Утверждаешь? (да/нет) в конце черновика. Понятно?" "u:да"
expect "cc: marker quoted mid-reply is not the question" 2 "$CREATE" "$T/quoted.jsonl"
cc "$T/second.jsonl" "u:заведи тикет" "a:$MARK"$'\n\nИ ещё: ставить в спринт?' "u:да"
expect "cc: another question after the marker" 2 "$CREATE" "$T/second.jsonl"
cc "$T/bold.jsonl" "u:заведи тикет" "a:${DRAFT}**Утверждаешь? (да/нет)**" "u:да"
expect "cc: marker in bold still ends the reply" 0 "$CREATE" "$T/bold.jsonl"

# --- a create: the approved reply is its draft -------------------------------------
cc "$T/nodraft.jsonl" "u:заведи тикет" "a:Тикет готов. Утверждаешь? (да/нет)" "u:да"
expect "create: marker with no draft" 2 "$CREATE" "$T/nodraft.jsonl"
expect "create: jira-cli, marker with no draft" 2 "jira issue create -pOP -s'Fix the build' --no-input" "$T/nodraft.jsonl"
expect "other writes need no draft" 0 "jira issue move OP-5 Done" "$T/nodraft.jsonl"
expect "create: jira-cli -s matches the draft" 0 "jira issue create -pOP -tTask -s'Fix the build' --no-input" "$T/ok.jsonl"
expect "create: jira-cli glued -s, other case and spacing" 0 "jira issue create -pOP -s'fix  the BUILD'" "$T/ok.jsonl"
expect "create: jira-cli --summary= differs from the draft" 2 "jira issue create -pOP --summary='Fix the tests'" "$T/ok.jsonl"
expect "create: epic create, summary differs" 2 "jira epic create -pOP -n E -s'Other'" "$T/ok.jsonl"
expect "create: clone without -s, draft shown" 0 "jira issue clone OP-1" "$T/ok.jsonl"
expect "create: clone without a draft" 2 "jira issue clone OP-1" "$T/nodraft.jsonl"
jq -n '{fields:{summary:"Fix the tests"}}' >"$T/other.json"
expect "create: body file sends another summary" 2 \
	"curl -s -X POST --data-binary @$T/other.json \"\$SITE/rest/api/2/issue\"" "$T/ok.jsonl"
expect "create: inline JSON body matches" 0 \
	"curl -s -X POST -d '{\"fields\":{\"summary\":\"Fix the build\"}}' \"\$SITE/rest/api/2/issue\"" "$T/ok.jsonl"
expect "create: jq --arg in the same command wins over a stale file" 0 \
	"jq -n --arg summary 'Fix the build' '{fields:{summary:\$summary}}' > $T/other.json && curl -s -X POST --data-binary @$T/other.json \"\$SITE/rest/api/2/issue\"" "$T/ok.jsonl"
expect "create: jq --arg differs from the draft" 2 \
	"jq -n --arg summary 'Fix the tests' '{}' > $T/n.json && curl -s -X POST --data-binary @$T/n.json \"\$SITE/rest/api/2/issue\"" "$T/ok.jsonl"
expect "create: body file not there yet, draft shown" 0 \
	"curl -s -X POST --data-binary @$T/missing.json \"\$SITE/rest/api/2/issue\"" "$T/ok.jsonl"
expect "create: a comment is not a create" 0 \
	"curl -s -X POST -d '{\"body\":\"x\"}' \"\$SITE/rest/api/2/issue/OP-1/comment\"" "$T/nodraft.jsonl"

# --- a delete or a sprint close: the approved draft names every target -------------
cc "$T/del.jsonl" "u:удали дубль" $'a:Удалю OP-1 (дубль OP-7), sprint 42 закрою.\n\nУтверждаешь? (да/нет)' "u:да"
expect "delete: key named in the draft" 0 "jira issue delete OP-1" "$T/del.jsonl"
expect "delete: alias rm, key named" 0 "jira issues rm op-1" "$T/del.jsonl"
expect "delete: key not named (the D3 case)" 2 "jira issue delete OP-2" "$T/del.jsonl"
expect "delete: one of two keys not named" 2 "jira issue delete OP-1 OP-2" "$T/del.jsonl"
expect "delete: OP-1 in the draft is not OP-17" 2 "jira issue delete OP-17" "$T/del.jsonl"
expect "delete: a key in a variable" 2 'jira issue delete $KEY' "$T/del.jsonl"
expect "delete: a loop" 2 'for k in OP-1; do jira issue delete $k; done' "$T/del.jsonl"
expect "delete: after another write in the same command" 2 \
	"jira issue move OP-1 Done; jira issue delete OP-2" "$T/del.jsonl"
expect "sprint close: id named" 0 "jira sprint close 42" "$T/del.jsonl"
expect "sprint complete: id not named" 2 "jira sprint complete 43" "$T/del.jsonl"
expect "HTTP DELETE: key named" 0 'curl -s -X DELETE -u "$E:$T" "$SITE/rest/api/2/issue/OP-1"' "$T/del.jsonl"
expect "HTTP DELETE: key not named" 2 'curl -sXDELETE "$SITE/rest/api/2/issue/OP-2?deleteSubtasks=true"' "$T/del.jsonl"
expect "HTTP DELETE: key in a variable" 2 'curl -X DELETE "$SITE/rest/api/2/issue/$K"' "$T/del.jsonl"
expect "other writes still need no key" 0 "jira issue move OP-5 Done" "$T/del.jsonl"
expect "delete: no approval at all" 2 "jira issue delete OP-1" -

# --- Codex rollout ----------------------------------------------------------------
codex "$T/cx.jsonl" "u:заведи тикет" "a:$MARK" "u:утверждаю"
expect "codex: утверждаю after marker" 0 "$CREATE" "$T/cx.jsonl"
codex "$T/cx2.jsonl" "u:заведи тикет" "a:$MARK"
expect "codex: injected AGENTS.md line is not a human да" 2 "$CREATE" "$T/cx2.jsonl"

# --- Opencode messages ------------------------------------------------------------
expect "opencode: messages, да" 0 "jira issue create -pOP" - \
	"$(jq -cn --arg d "$MARK" '[{role:"user",text:"заведи"},{role:"assistant",text:$d},{role:"user",text:"да"}]')"
expect "opencode: messages, да without a draft" 2 "jira issue create -pOP" - \
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
	"curl -sXDELETE https://x.atlassian.net/rest/api/2/issue/OP-1" \
	$'cat > /tmp/d.md <<\'EOF\'\nDraft text\nEOF\njira issue create -pOP -s x --template /tmp/d.md --no-input' \
	$'cat > /tmp/d.md <<\'EOF\'\nIt\'s a draft\nEOF\njira issue create -pOP -s x --template /tmp/d.md --no-input' \
	$'cat <<EOF\nno terminator, so this is not a body\njira issue edit OP-1 -b x' \
	"curl -s -X POST -d x https://x.atlassian.net/rest/api/3/search/jql https://x.atlassian.net/rest/api/2/issue" \
	"jira issue create -pOP -s x --no-input" \
	"echo it's ready; jira issue create -pOP -s x --no-input"; do
	expect "write: $c" 2 "$c" -
done
for c in \
	"echo it's ready" \
	"jira issue view OP-1" \
	"jira issue list -a me --plain --paginate 15 </dev/null" \
	"jira sprint list --state active" \
	"jira me" \
	"curl -s -u a:b https://x.atlassian.net/rest/api/3/issue/OP-1?fields=summary" \
	"curl -s -u a:b 'https://x.atlassian.net/rest/agile/1.0/board/1/sprint?state=active' | jq -r ." \
	"rg -n 'jira issue create' references/create-task.md" \
	"echo 'jira issue create -pOP'" \
	"curl -s -X POST -d x https://example.com/api" \
	"git commit -m 'document jira issue edit'" \
	"jira issue create --help" \
	"jira issue link -h" \
	"jira sprint add --help" \
	"jira help issue link" \
	$'git commit -F - <<\'EOF\'\nDocument the create command\n\njira issue create -pOP -s x is what the skill runs.\nEOF' \
	$'git commit -m "$(cat <<\'EOF\'\nDocument the edit command\n\njira issue edit OP-1 -b x\nEOF\n)"' \
	$'cat > /tmp/notes.md <<\'EOF\'\njira issue edit OP-1 -b x\nEOF' \
	$'cat > /tmp/d.md <<\'EOF\'\nIt\'s a draft\nEOF' \
	"curl -s -X POST -u a:b -H 'Content-Type: application/json' -d '{\"jql\":\"project = OP\"}' https://x.atlassian.net/rest/api/3/search/jql"; do
	expect "not a write: $c" 0 "$c" -
done

# --- command shapes: tests/guard_cases.jsonl, one {want, name, cmd} per line --------
while IFS= read -r row; do
	expect "$(jq -r .name <<<"$row")" "$(jq -r .want <<<"$row")" "$(jq -r .cmd <<<"$row")" -
done <"$ROOT/tests/guard_cases.jsonl"

# --- a write the guard fails on is refused, not let through -------------------------
printf '[]\n"x"\n' >"$T/notobj.jsonl"
expect "crash: transcript lines are not objects" 2 "jira issue create -pX" "$T/notobj.jsonl"
printf '\xff\n' >"$T/utf.jsonl"
expect "crash: invalid UTF-8 in the transcript" 2 "jira issue create -pX" "$T/utf.jsonl"
mkdir "$T/dir.jsonl"
expect "crash: transcript path is a directory" 2 "jira issue create -pX" "$T/dir.jsonl"
raw "crash: tool_input is a string" 2 '{"tool_name":"Bash","tool_input":"jira issue create -pX"}'
raw "crash: opencode text is a number" 2 \
	'{"tool_name":"bash","tool_input":{"command":"jira issue create -pX"},"messages":[{"role":"user","text":5}]}'

# --- not a hook payload -----------------------------------------------------------
raw "garbage stdin" 0 'garbage'
raw "payload is an array" 0 '[1]'

# --- the Opencode pre-filter is the guard's MENTION pattern -----------------------
g="$(sed -n 's/^MENTION = re.compile(r"\(.*\)", re.I)$/\1/p' "$GUARD")"
p="$(sed -n 's#^const MENTION = /\(.*\)/i$#\1#p' "$ROOT/plugins/opencode/jira-write-guard.ts" | sed 's#\\/#/#g')"
if [ -n "$g" ] && [ "$g" = "$p" ]; then tally "plugin pre-filter" 0 0; else tally "plugin pre-filter = MENTION ('$p' vs '$g')" 0 1; fi
# …and both strip the same characters before matching it.
gq="$(sed -n 's/^QUOTES = re.compile(r"""\(.*\)""")$/\1/p' "$GUARD")"
pq="$(sed -n 's#.*command\.replace(/\(.*\)/g, "").*#\1#p' "$ROOT/plugins/opencode/jira-write-guard.ts")"
if [ -n "$gq" ] && [ "$gq" = "$pq" ]; then tally "plugin strips quotes" 0 0; else tally "plugin strips quotes = QUOTES ('$pq' vs '$gq')" 0 1; fi

# --- the hook launcher: a guard that cannot answer refuses a Jira command ----------
# hook <name> <want> <launcher> <command> [env…] — runs the launcher as the host would
hook() {
	local name="$1" want="$2" launcher="$3" cmd="$4" got; shift 4
	jq -cn --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c},transcript_path:null}' |
		env "$@" "$launcher" >/dev/null 2>&1; got=$?
	tally "hook: $name" "$want" "$got"
}
LAUNCHER="$ROOT/skills/jira-op/scripts/jira-write-guard-hook"
hook "real guard, unapproved write" 2 "$LAUNCHER" "jira issue create -pX"
hook "real guard, read" 0 "$LAUNCHER" "jira issue view X-1"
hook "real guard, unrelated command" 0 "$LAUNCHER" "ls -la"

mkdir -p "$T/nopy" "$T/crash" "$T/slow" "$T/gone"
for t in sh dirname cat tr grep timeout env; do ln -s "$(command -v "$t")" "$T/nopy/$t"; done
hook "no python3, Jira write" 2 "$LAUNCHER" "jira issue create -pX" PATH="$T/nopy"
hook "no python3, unrelated command runs" 0 "$LAUNCHER" "ls -la" PATH="$T/nopy"
hook "no python3, quoted ji''ra" 2 "$LAUNCHER" "ji''ra issue move OP-1 Done" PATH="$T/nopy"

cp "$LAUNCHER" "$T/crash/"; printf 'import sys\nsys.exit(1)\n' >"$T/crash/jira-write-guard"
hook "guard crashes, Jira write" 2 "$T/crash/jira-write-guard-hook" "jira issue create -pX"
hook "guard crashes, unrelated command runs" 0 "$T/crash/jira-write-guard-hook" "ls -la"

cp "$LAUNCHER" "$T/slow/"; printf 'import time\ntime.sleep(5)\n' >"$T/slow/jira-write-guard"
hook "guard past the deadline, Jira write" 2 "$T/slow/jira-write-guard-hook" "jira issue create -pX" JIRA_GUARD_DEADLINE=1

cp "$LAUNCHER" "$T/gone/"
hook "guard missing, Jira write" 2 "$T/gone/jira-write-guard-hook" "jira issue create -pX"
hook "guard missing, unrelated command runs" 0 "$T/gone/jira-write-guard-hook" "ls -la"

# …and the launcher's pre-filter is the guard's MENTION, written for grep -E.
lm="$(sed -n "s/.*grep -Eiq '\(.*\)'.*/\1/p" "$LAUNCHER")"
if [ "$lm" = 'jira|/rest/(api|agile)/|atlassian\.(net|com)' ] &&
	[ "$(sed -n 's/^MENTION = re.compile(r"\(.*\)", re.I)$/\1/p' "$GUARD")" = '\bjira\b|/rest/(?:api|agile)/|atlassian\.(?:net|com)' ]; then
	tally "launcher pre-filter tracks MENTION" 0 0
else
	tally "launcher pre-filter tracks MENTION (update both together)" 0 1
fi

echo "jira-write-guard: $pass passed, $fail failed"
[ "$fail" = 0 ]
