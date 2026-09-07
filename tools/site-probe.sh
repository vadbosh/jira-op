#!/usr/bin/env bash
# site-probe.sh — generate a SITE.md for the Jira site the CLI is pointed at.
#
#   ./tools/site-probe.sh                 print SITE.md for the current site
#   ./tools/site-probe.sh --site acme     switch to that site first
#   ./tools/site-probe.sh --write         write it next to the installed skill
#   ./tools/site-probe.sh --check         compare the installed one with reality
#   ./tools/site-probe.sh --all --check   every registered site
#   ./tools/site-probe.sh --skill-dir D   use D instead of auto-detecting
#
# JIRA_OP_SKILL_DIR sets that directory once, for machines where the skill is
# not edited in place: a config canon that is synced into the assistants, a
# checkout, a shared directory. The flag still wins over the variable.
#
# Read-only against Jira. It creates nothing, edits nothing, and never prints
# the token.
#
# One file per site, named after the site the way jira_site names it:
#
#   SITE.md            the default config (~/.config/.jira/.config.yml)
#   SITE.<name>.md     ~/.config/.jira/<name>.yml
#
# Re-run it when a create or a transition starts failing: field configuration
# changes without notice and nothing announces it.
#
# Linux and macOS. Needs jira-cli, jq and curl.

# Backticks below are Markdown in generated output, not command substitution;
# the token files are per-site and cannot be followed statically.
# shellcheck disable=SC2016,SC1090,SC1091

set -euo pipefail

SITE_NAME=""
MODE="print"
SKILL_DIR="${JIRA_OP_SKILL_DIR:-}"
ALL=0

die() { printf '%s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case "$1" in
		--site)      shift; SITE_NAME="${1:?--site needs a name}" ;;
		--write)     MODE="write" ;;
		--check)     MODE="check" ;;
		--all)       ALL=1 ;;
		--skill-dir) shift; SKILL_DIR="${1:?--skill-dir needs a path}" ;;
		-h|--help)   sed -n '2,21p' "${BASH_SOURCE[0]}"; exit 0 ;;
		*)           die "unknown argument: $1" ;;
	esac
	shift
done

command -v jira >/dev/null || die "jira CLI not found in PATH"
command -v jq   >/dev/null || die "jq not found in PATH"

JDIR="$HOME/.config/.jira"

# --all: run once per registered site. Each site has its own file, because
# field ids, issue types and statuses are not shared between them.
if [ "$ALL" = 1 ]; then
	self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
	rc=0
	sites=""
	[ -r "$JDIR/.config.yml" ] && sites="default"
	for f in "$JDIR"/*.yml; do
		[ -e "$f" ] || continue
		sites="$sites $(basename "$f" .yml)"
	done
	[ -n "$sites" ] || die "no jira-cli config found under $JDIR"
	for site in $sites; do
		printf '\n===== %s =====\n' "$site"
		case "$MODE" in
			print) "$self" --site "$site" || rc=$? ;;
			write) "$self" --site "$site" --write ${SKILL_DIR:+--skill-dir "$SKILL_DIR"} || rc=$? ;;
			check) "$self" --site "$site" --check ${SKILL_DIR:+--skill-dir "$SKILL_DIR"} || rc=$? ;;
		esac
	done
	exit "$rc"
fi
command -v jq   >/dev/null || die "jq not found in PATH"

JDIR="$HOME/.config/.jira"

# Load the requested site's pair, or use whatever the environment already has.
if [ -n "$SITE_NAME" ] && [ "$SITE_NAME" != default ] && [ "$SITE_NAME" != wl ]; then
	[ -r "$JDIR/$SITE_NAME.yml" ] || die "no config: $JDIR/$SITE_NAME.yml"
	export JIRA_CONFIG_FILE="$JDIR/$SITE_NAME.yml"
	# shellcheck disable=SC1090
	set -a; . "$JDIR/$SITE_NAME.token.env"; set +a
elif [ -n "$SITE_NAME" ]; then
	unset JIRA_CONFIG_FILE
	# shellcheck disable=SC1091
	set -a; . "$JDIR/token.env"; set +a
fi

if [ -z "${JIRA_API_TOKEN:-}" ]; then
	TOKF="${JIRA_CONFIG_FILE:+${JIRA_CONFIG_FILE%.yml}.token.env}"
	TOKF="${TOKF:-$JDIR/token.env}"
	[ -r "$TOKF" ] || die "no token: set JIRA_API_TOKEN, or create $TOKF"
	# shellcheck disable=SC1090
	set -a; . "$TOKF"; set +a
fi

CFG="${JIRA_CONFIG_FILE:-$JDIR/.config.yml}"
[ -r "$CFG" ] || die "no config file: $CFG"

# The file name follows the config the way jira_site does.
if [ "$CFG" = "$JDIR/.config.yml" ]; then
	OUT_NAME="SITE.md"; SITE_LABEL="default"
else
	SITE_LABEL="$(basename "$CFG" .yml)"; OUT_NAME="SITE.$SITE_LABEL.md"
fi

# --- values that jira-cli already stored, no API call needed ----------------
# jira-cli writes a fixed two-space-indented shape; read the few keys we need.
cfg_top()   { awk -v k="$1" '$1==k":" {sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$CFG"; }
cfg_child() { awk -v s="$1" -v k="$2" '
	$0 ~ "^"s":" {inb=1; next}
	inb && /^[^[:space:]]/ {inb=0}
	inb && $1==k":" {sub(/^[[:space:]]*[^:]*:[[:space:]]*/,""); print; exit}' "$CFG"; }

SITE="$(cfg_top server)"
LOGIN="$(cfg_top login)"
PROJECT="$(cfg_child project key)"
BOARD_ID="$(cfg_child board id)"
BOARD_NAME="$(cfg_child board name)"
BOARD_TYPE="$(cfg_child board type)"

[ -n "$SITE" ]    || die "no 'server' in $CFG — run jira init"
[ -n "$PROJECT" ] || die "no project key in $CFG — run jira init"

api() { curl -sf -u "$LOGIN:$JIRA_API_TOKEN" "$SITE$1"; }

api /rest/api/3/myself >/dev/null || die "authentication failed for $LOGIN at $SITE"

MYSELF="$(api /rest/api/3/myself)"
ACCOUNT_ID="$(printf '%s' "$MYSELF" | jq -r '.accountId')"
DISPLAY_NAME="$(printf '%s' "$MYSELF" | jq -r '.displayName')"

# A recent issue, used to read the workflow's transition names.
SAMPLE="$(jira issue list -p "$PROJECT" --plain --no-headers --columns key --paginate 1 2>/dev/null | awk 'NR==1{print $1}')"

# Every list below is sorted explicitly. The API returns object keys and array
# members in no guaranteed order, and an unsorted list makes --check report
# drift on a reordering that changed nothing.
generate() {
	cat <<EOF
# Site values — $SITE_LABEL

Generated by \`tools/site-probe.sh\` on $(date -I). Read-only probe of the live
API; re-run it when a create or a transition starts failing.

## Site and project

| Placeholder | Value |
|---|---|
| \`<SITE>\` | \`$SITE\` |
| \`<PROJECT>\` | \`$PROJECT\` |
| \`<LOGIN>\` | \`$LOGIN\` |
| \`<BOARD_ID>\` | \`${BOARD_ID:-— none in the config; sprint commands will not work}\` |
| \`<BOARD_NAME>\` | \`${BOARD_NAME:-—}\`${BOARD_TYPE:+, $BOARD_TYPE} |
| \`<ACCOUNT_ID>\` | \`$ACCOUNT_ID\` ($DISPLAY_NAME) |

## Issue types and their required fields

EOF

	local types
	types="$(api "/rest/api/3/issue/createmeta/$PROJECT/issuetypes" | jq -r '.issueTypes | sort_by(.id|tonumber)[] | "\(.id)\t\(.name)"')"
	[ -n "$types" ] || { echo "_No issue types readable — check project permissions._"; return; }

	printf '| Id | Name |\n|---|---|\n'
	printf '%s\n' "$types" | awk -F'\t' '{printf "| `%s` | %s |\n", $1, $2}'
	printf '\n'

	printf '%s\n' "$types" | while IFS=$'\t' read -r tid tname; do
		printf '### %s (`%s`)\n\n' "$tname" "$tid"
		local meta req custom
		meta="$(api "/rest/api/3/issue/createmeta/$PROJECT/issuetypes/$tid" || true)"
		if [ -z "$meta" ]; then printf '_createmeta unreadable for this type._\n\n'; continue; fi

		req="$(printf '%s' "$meta" | jq -r '[.fields[] | select(.required) | .fieldId] | join(" ")')"
		printf 'Required: `%s`\n\n' "$req"

		custom="$(printf '%s' "$meta" | jq -r '.fields[] | select(.required) | select(.fieldId|startswith("customfield_"))
			| "  --custom \(.name|ascii_downcase|gsub(" ";"-"))=\"...\"   # \(.fieldId), \(.schema.custom|split(":")|last)"')"
		if [ -n "$custom" ]; then
			printf 'Flags for `jira issue create`:\n\n```\n%s\n```\n\n' "$custom"
			printf '%s' "$meta" | jq -r '.fields[] | select(.required) | select(.allowedValues)
				| select(.fieldId|startswith("customfield_"))
				| "- **\(.name)** accepts only: " + ([.allowedValues[] | .value // .name] | join(", "))'
			printf '\n'
		else
			printf 'No required custom fields — the create carries no `--custom` flag.\n\n'
		fi
	done

	printf '## Statuses\n\n'
	if [ -n "$SAMPLE" ]; then
		printf 'Transitions available on `%s`:\n\n```\n' "$SAMPLE"
		api "/rest/api/3/issue/$SAMPLE/transitions" | jq -r '.transitions | sort_by(.id|tonumber)[] | "\(.id)\t\(.name)"'
		printf '```\n\nTransition names are per-workflow, so this is one issue'"'"'s list, not the\nproject'"'"'s. Re-read it whenever a move is refused.\n\n'
	else
		printf '_No issue readable in %s, so the workflow could not be sampled._\n\n' "$PROJECT"
	fi

	printf '## Sprints\n\n'
	if [ -n "$BOARD_ID" ]; then
		printf 'Sprints in state `active` on board `%s`:\n\n```\n' "$BOARD_ID"
		api "/rest/agile/1.0/board/$BOARD_ID/sprint?state=active" \
		 | jq -r '.values | sort_by(.id)[] | "\(.id)\t\(.name)\t\(.startDate[:10] // "-")..\(.endDate[:10] // "-")"' || true
		printf '```\n\nBoards keep stale sprints in state `active`, so pick by name prefix **and**\ndate window. `<SPRINT_PREFIX>` is the common prefix of the rows above that\nbelong to this team.\n\n'
	else
		printf '_No board in the config — `jira sprint` commands will not work here._\n\n'
	fi

	printf '## Permissions\n\n| Permission | Value |\n|---|---|\n'
	api "/rest/api/3/mypermissions?projectKey=$PROJECT&permissions=CREATE_ISSUES,EDIT_ISSUES,DELETE_ISSUES,TRANSITION_ISSUES,ASSIGN_ISSUES,MODIFY_REPORTER,ADD_COMMENTS,SCHEDULE_ISSUES" \
	 | jq -r '.permissions | to_entries | sort_by(.key)[] | "| \(.key) | \(.value.havePermission) |"'
	printf '\nWhen `DELETE_ISSUES` is `false`, a ticket created by mistake stays on the\nboard until an administrator removes it — which is why the skill never creates\none to test itself.\n'
}

# Every installed copy, for --write and --check. The skill is usually installed
# into several assistants, and a SITE.md written into one of them leaves the
# others reading placeholders — so all of them are updated.
find_skill_dirs() {
	[ -n "$SKILL_DIR" ] && { printf '%s\n' "$SKILL_DIR"; return 0; }
	local found=1 d
	for d in "$HOME/.claude/skills/jira-op" \
	         "$HOME/.config/opencode/skills/jira-op" \
	         "$HOME/.codex/skills/jira-op"; do
		[ -d "$d" ] && { printf '%s\n' "$d"; found=0; }
	done
	return $found
}

dirs=""
if [ "$MODE" != print ]; then
	dirs="$(find_skill_dirs)" || die "no installed skill found; pass --skill-dir"
fi

case "$MODE" in
	print) generate ;;

	write)
		tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
		generate > "$tmp"
		printf '%s\n' "$dirs" | while read -r dir; do
			[ -n "$dir" ] || continue
			cp "$tmp" "$dir/$OUT_NAME"
			printf 'written: %s\n' "$dir/$OUT_NAME" >&2
		done
		;;

	check)
		tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
		generate > "$tmp"
		rc=0
		while read -r dir; do
			[ -n "$dir" ] || continue
			if [ ! -r "$dir/$OUT_NAME" ]; then
				printf 'missing: %s/%s — run with --write\n' "$dir" "$OUT_NAME" >&2
				rc=3; continue
			fi
			# The header carries the generation date; ignore it when comparing.
			if diff -u --label "$dir/$OUT_NAME (on disk)" --label "live API" \
			     <(grep -v '^Generated by' "$dir/$OUT_NAME") \
			     <(grep -v '^Generated by' "$tmp"); then
				printf 'no drift: %s\n' "$dir/$OUT_NAME"
			else
				rc=3
			fi
		done <<EOF
$dirs
EOF
		[ "$rc" = 0 ] || printf '\ndrift above — rerun with --write to update\n' >&2
		exit "$rc"
		;;
esac
