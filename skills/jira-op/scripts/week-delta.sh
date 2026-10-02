#!/usr/bin/env bash
# shellcheck disable=SC1090   # the token file is per-site and per-user
# week-delta.sh — everything the reporting window added to the tickets, in full.
#
#   week-delta.sh WEEK_START WEEK_END [KEY ...]
#
# WEEK_START and WEEK_END are the first and the last day of the window, both
# included (YYYY-MM-DD), as the person picked them in step 1 of
# references/weekly-report.md. Without keys, the tickets are the ones step 2
# lists: assigned to the token owner, and either updated inside the window
# outside the unstarted category, or in a working status at any point of it.
#
# Per ticket it prints what carries a date inside the window, and nothing is
# shortened — a cut comment is how a risk or a decision drops out of a report:
#   - status, sprint, assignee and other one-line changes from the changelog;
#   - the text added to the description and to every text custom field
#     (the first change in the window against the last, as section 3c does);
#   - every comment written in the window;
#   - `Update <date>:` lines of the description dated inside the window;
#   - for a ticket created inside the window, its whole description.
# A ticket with nothing dated inside the window says so: section 3c's
# long-running default applies to it.
#
# Read-only: GET requests and one POST search. The site, login and project come
# from the jira-cli config (JIRA_CONFIG_FILE or ~/.config/.jira/.config.yml), the
# token from JIRA_API_TOKEN or the token file paired with that config.
set -euo pipefail

die() { echo "week-delta: $*" >&2; exit 1; }

[ $# -ge 2 ] || die "usage: week-delta.sh WEEK_START WEEK_END [KEY ...]"
WEEK_START="$1"; WEEK_END="$2"; shift 2
for d in "$WEEK_START" "$WEEK_END"; do
	[[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && date -d "$d" >/dev/null 2>&1 \
		|| die "not a date: $d"
done
[[ ! "$WEEK_END" < "$WEEK_START" ]] || die "the last day $WEEK_END is before the first $WEEK_START"
AFTER_END="$(date -d "$WEEK_END +1 day" +%F)"

for c in curl jq diff; do command -v "$c" >/dev/null || die "$c not found"; done

JDIR=~/.config/.jira
CFG="${JIRA_CONFIG_FILE:-$JDIR/.config.yml}"
[ -r "$CFG" ] || die "no config file: $CFG"
if [ -z "${JIRA_API_TOKEN:-}" ]; then
	TOKF="${JIRA_CONFIG_FILE:+${JIRA_CONFIG_FILE%.yml}.token.env}"
	TOKF="${TOKF:-$JDIR/token.env}"
	[ -r "$TOKF" ] || die "no token: set JIRA_API_TOKEN, or create $TOKF"
	set -a; . "$TOKF"; set +a
fi

cfg_top()   { awk -v k="$1" '$1==k":" {sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$CFG"; }
cfg_child() { awk -v s="$1" -v k="$2" '
	$0 ~ "^"s":" {inb=1; next}
	inb && /^[^[:space:]]/ {inb=0}
	inb && $1==k":" {sub(/^[[:space:]]*[^:]*:[[:space:]]*/,""); print; exit}' "$CFG"; }

SITE="$(cfg_top server)"; LOGIN="$(cfg_top login)"; PROJECT="$(cfg_child project key)"
[ -n "$SITE" ] && [ -n "$LOGIN" ] && [ -n "$PROJECT" ] || die "server, login or project key missing in $CFG"

api() { curl -sf -u "$LOGIN:$JIRA_API_TOKEN" "$SITE$1"; }
api /rest/api/3/myself >/dev/null || die "authentication failed for $LOGIN at $SITE"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- which tickets --------------------------------------------------------------
if [ $# -eq 0 ]; then
	active="$(api "/rest/api/3/project/$PROJECT/statuses" | jq -r '
		[.[].statuses[] | select(.statusCategory.key == "indeterminate") | .name]
		| unique | map("\"" + . + "\"") | join(", ")')"
	jql="project = \"$PROJECT\" AND assignee = currentUser() AND (
		(updated >= \"$WEEK_START\" AND updated < \"$AFTER_END\" AND statusCategory != new)"
	[ -n "$active" ] && jql="$jql OR status WAS IN ($active) DURING (\"$WEEK_START\", \"$AFTER_END\")"
	jql="$jql)"
	mapfile -t KEYS < <(curl -sf -u "$LOGIN:$JIRA_API_TOKEN" -X POST \
		-H 'Content-Type: application/json' \
		-d "$(jq -n --arg q "$jql" '{jql: $q, fields: ["key"], maxResults: 100}')" \
		"$SITE/rest/api/3/search/jql" | jq -r '.issues[].key')
else
	KEYS=("$@")
fi
[ ${#KEYS[@]} -gt 0 ] || die "no tickets in $WEEK_START .. $WEEK_END"

echo "window $WEEK_START .. $WEEK_END (both included), $SITE, project $PROJECT"
echo "tickets: ${KEYS[*]}"

# --- one ticket -------------------------------------------------------------------
# One-line fields; any other field whose text is long or multi-line is diffed.
SHORT='["status","resolution","Sprint","assignee","reporter","Story Points","End Date",
        "duedate","issuetype","Link","Epic Link","Parent","IssueParentAssociation",
        "labels","priority","Fix Version","Component","summary","Rank","Flagged"]'

for k in "${KEYS[@]}"; do
	api "/rest/api/2/issue/$k?fields=summary,status,issuetype,parent,created,description,comment" \
		>"$TMP/i.json" || { echo; echo "==== $k: cannot be read"; continue; }
	# the changelog, every page
	: >"$TMP/cl.jsonl"; at=0
	while :; do
		api "/rest/api/3/issue/$k/changelog?startAt=$at&maxResults=100" >"$TMP/p.json"
		jq -c '.values[]' "$TMP/p.json" >>"$TMP/cl.jsonl"
		n="$(jq '.values | length' "$TMP/p.json")"
		[ "$(jq '.isLast // true' "$TMP/p.json")" = true ] || [ "$n" = 0 ] && break
		at=$((at + n))
	done

	echo
	jq -r '.fields as $f | "==== \(.key) [\($f.status.name)] \($f.summary)\n" +
		"type \($f.issuetype.name), created \($f.created[:10])" +
		(if $f.parent then ", parent \($f.parent.key) \"\($f.parent.fields.summary)\"" else "" end)' \
		"$TMP/i.json"
	found=0

	created="$(jq -r '.fields.created[:10]' "$TMP/i.json")"
	new=0
	if [[ ! "$created" < "$WEEK_START" ]] && [[ "$created" < "$AFTER_END" ]]; then
		found=1; new=1
		echo "-- created inside the window; its whole description:"
		jq -r '.fields.description // "(empty)"' "$TMP/i.json"
	fi

	# one-line changes
	lines="$(jq -r --arg a "$WEEK_START" --arg b "$AFTER_END" --argjson short "$SHORT" '
		select(.created[:10] >= $a and .created[:10] < $b) | .created[:10] as $d
		| .items[] | select(.field as $x | $short | index($x))
		| "\($d)  \(.field): \(.fromString // "" | tojson) -> \(.toString // "" | tojson)"' \
		"$TMP/cl.jsonl")"
	if [ -n "$lines" ]; then found=1; echo "-- changes:"; echo "$lines"; fi

	# text fields: first state in the window against the last, added lines in full
	jq -r --arg a "$WEEK_START" --arg b "$AFTER_END" --argjson short "$SHORT" '
		select(.created[:10] >= $a and .created[:10] < $b) | .items[]
		| select(.field as $x | $short | index($x) | not) | .field' "$TMP/cl.jsonl" \
		| awk '!seen[$0]++' >"$TMP/fields"
	while IFS= read -r fld; do
		# a new ticket's description is printed whole above
		[ "$new" = 1 ] && [ "$fld" = description ] && continue
		jq -rs --arg a "$WEEK_START" --arg b "$AFTER_END" --arg f "$fld" '
			[.[] | select(.created[:10] >= $a and .created[:10] < $b) | .items[]
			 | select(.field == $f)] | .[0].fromString // ""' "$TMP/cl.jsonl" >"$TMP/before"
		jq -rs --arg a "$WEEK_START" --arg b "$AFTER_END" --arg f "$fld" '
			[.[] | select(.created[:10] >= $a and .created[:10] < $b) | .items[]
			 | select(.field == $f)] | last | .toString // ""' "$TMP/cl.jsonl" >"$TMP/after"
		found=1
		echo "-- text added to \"$fld\" inside the window:"
		diff "$TMP/before" "$TMP/after" | sed -n 's/^> //p' || true
	done <"$TMP/fields"

	# comments written in the window
	comments="$(jq -r --arg a "$WEEK_START" --arg b "$AFTER_END" '
		.fields.comment.comments[]? | select(.created[:10] >= $a and .created[:10] < $b)
		| "\(.created[:16]) \(.author.displayName):\n\(.body)\n"' "$TMP/i.json")"
	if [ -n "$comments" ]; then found=1; echo "-- comments:"; echo "$comments"; fi

	# Update <date>: lines dated inside the window
	upd="$(jq -r '.fields.description // ""' "$TMP/i.json" \
		| grep -oE 'Update *[0-9]{4}-[0-9]{2}-[0-9]{2} *:?.*' \
		| awk -v a="$WEEK_START" -v b="$WEEK_END" '
			match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/) { d = substr($0, RSTART, RLENGTH)
			if (d >= a && d <= b) print }' || true)"
	if [ -n "$upd" ]; then found=1; echo "-- Update lines dated inside the window:"; echo "$upd"; fi

	[ "$found" = 1 ] || echo "-- nothing dated inside the window: the long-running default of section 3c applies"
done
