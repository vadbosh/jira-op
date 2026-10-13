#!/usr/bin/env bash
# automode-setup.sh — tell Claude Code's auto-mode classifier that your Jira is yours.
#
#   <skill-dir>/scripts/automode-setup.sh              show the change, ask, write
#   <skill-dir>/scripts/automode-setup.sh --dry-run    show the change, write nothing
#   <skill-dir>/scripts/automode-setup.sh --remove     take the entries out again
#
# Since Claude Code 2.1.296 the auto-mode classifier can refuse a Jira write
# that jira-write-guard has already let through, as an "External System Write":
# it does not know the site is yours, and a bare «да» does not name the action.
# This script adds one entry to autoMode.environment and one to autoMode.allow
# in ~/.claude/settings.json, naming every site configured for jira-cli
# (`server:` in ~/.config/.jira/*.yml).
#
# Run it yourself in a terminal. It loosens a safety check, so it is not part
# of install.sh, and an assistant running it on its own behalf is exactly what
# the classifier refuses as Self-Modification.
#
# Both entries start with "jira-op:"; a rerun replaces them and leaves every
# other entry alone. A list that does not exist yet starts with "$defaults",
# so the built-in rules stay in force. Codex and Opencode have no such
# classifier: this is Claude Code only.
#
# Exit 0 — written, already current, or declined; 1 — settings.json unreadable
# or jq missing; 3 — no jira-cli site configured.

set -euo pipefail

TAG="jira-op:"
JIRA_DIR="${HOME}/.config/.jira"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/jira-op-backups"
MODE="write"

case "${1:-}" in
	"") ;;
	--dry-run) MODE=dry ;;
	--remove) MODE=remove ;;
	-h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) printf 'unknown option: %s (see --help)\n' "$1" >&2; exit 1 ;;
esac

command -v jq >/dev/null 2>&1 || { printf 'jq not found\n' >&2; exit 1; }

current='{}'
if [ -e "$SETTINGS" ]; then
	current=$(jq -c . "$SETTINGS" 2>/dev/null) \
		|| { printf '%s is not valid JSON — nothing written\n' "$SETTINGS" >&2; exit 1; }
fi

if [ "$MODE" = remove ]; then
	new=$(printf '%s' "$current" | jq -c --arg t "$TAG" '
		if .autoMode then
			.autoMode |= with_entries(
				if (.value | type) == "array"
				then .value |= map(select((type != "string") or (startswith($t) | not)))
				else . end)
		else . end')
else
	sites=""
	for f in "$JIRA_DIR"/*.yml "$JIRA_DIR"/.config.yml; do
		[ -e "$f" ] || continue
		h=$(sed -n "s#^[[:space:]]*server:[[:space:]]*['\"]\{0,1\}https\{0,1\}://\([^/'\"[:space:]]*\).*#\1#p" "$f" | head -1)
		[ -n "$h" ] || continue
		case ", $sites, " in *", $h, "*) continue ;; esac
		sites="${sites:+$sites, }$h"
	done
	if [ -z "$sites" ]; then
		printf 'no jira-cli site in %s — run "jira init" first\n' "$JIRA_DIR" >&2
		exit 3
	fi
	env_entry="$TAG $sites is the user's own Jira, the work tracker the jira-op skill reads and writes with the jira CLI or its REST API."
	allow_entry="$TAG a write to the user's Jira ($sites) — create an issue, add or edit a comment, edit fields, transition, add to a sprint — through the jira CLI or an HTTP client calling its REST API is allowed once the assistant has printed the full draft ending with the line «Утверждаешь? (да/нет)» and the human answered «да». The jira-write-guard PreToolUse hook refuses any such write without that approval."
	new=$(printf '%s' "$current" | jq -c --arg t "$TAG" --arg env "$env_entry" --arg allow "$allow_entry" '
		def put($k; $e):
			.autoMode[$k] = ((.autoMode[$k] // ["$defaults"])
				| map(select((type != "string") or (startswith($t) | not))) + [$e]);
		.autoMode = (.autoMode // {}) | put("environment"; $env) | put("allow"; $allow)')
fi

if [ "$new" = "$current" ]; then
	printf 'autoMode in %s is already current — nothing to do\n' "$SETTINGS"
	exit 0
fi

printf 'autoMode in %s, before:\n' "$SETTINGS"
printf '%s' "$current" | jq '.autoMode // "(none)"'
printf '\nafter:\n'
printf '%s' "$new" | jq '.autoMode // "(none)"'

[ "$MODE" = dry ] && { printf '\n--dry-run: nothing written\n'; exit 0; }

printf '\nWrite this to %s? [y/N] ' "$SETTINGS"
if ! read -r answer; then
	# No line at all: stdin is closed, as under Claude Code's "!" prefix.
	printf '\nno answer: input is not a terminal — nothing written.\n'
	printf 'Having read the change above, answer in the same command:\n  echo y | %s\n' "$0"
	exit 0
fi
case "$answer" in
	y|Y|yes|YES|д|Д|да|Да) ;;
	*) printf 'not written\n'; exit 0 ;;
esac

mkdir -p "$(dirname "$SETTINGS")"
if [ -e "$SETTINGS" ]; then
	mkdir -p "$BACKUP_DIR"
	bak="$BACKUP_DIR/settings.json.$(date +%Y%m%d-%H%M%S)"
	cp -p "$SETTINGS" "$bak"
	printf 'backup: %s\n' "$bak"
fi
tmp="$SETTINGS.tmp-jira-op"
[ -e "$SETTINGS" ] && cp -p "$SETTINGS" "$tmp"
printf '%s' "$new" | jq . > "$tmp"
mv "$tmp" "$SETTINGS"
printf 'written. Claude Code reads it without a restart.\n'
