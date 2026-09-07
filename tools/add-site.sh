#!/usr/bin/env bash
# add-site.sh — register one more Atlassian site for jira-cli.
#
#   ~/.config/.jira/add-site.sh acme
#
# Produces the pair that `jira_site` (in ~/.bash_aliases) loads together:
#
#   ~/.config/.jira/acme.yml            written by `jira init`
#   ~/.config/.jira/acme.token.env      mode 600, one line JIRA_API_TOKEN=...
#
# The token is asked FIRST and exported before `jira init` runs, because init
# authenticates against the site while it works: without the token in the
# environment it fails with "401 Unauthorized" halfway through the questions.
#
# Run it yourself in a terminal — it is interactive, and the token must not
# pass through an assistant's session.

set -euo pipefail

DIR="${HOME}/.config/.jira"
NAME="${1:-}"

die() { printf '%s\n' "$*" >&2; exit 1; }

if [ "$NAME" = --list ] || [ "$NAME" = -l ]; then
	printf 'registered sites:\n'
	[ -e "$DIR/.config.yml" ] && printf '  wl\t%s\n' "$DIR/.config.yml"
	for f in "$DIR"/*.yml; do
		[ -e "$f" ] || continue
		s=$(basename "$f" .yml)
		if [ -e "$DIR/$s.token.env" ]; then
			printf '  %s\t%s\n' "$s" "$f"
		else
			printf '  %s\t%s\t(no token file — jira_site %s will fail)\n' "$s" "$f" "$s"
		fi
	done
	exit 0
fi

[ -n "$NAME" ] || die "usage: $0 <site-name> | --list
  Run it once per site; any number of sites can coexist, the name only
  distinguishes their files.
  'wl' is taken: it means the default config, ~/.config/.jira/.config.yml"

case "$NAME" in
	wl) die "'wl' is reserved for the default site (.config.yml + token.env)" ;;
	*[!a-z0-9._-]*) die "site name must be lowercase letters, digits, . _ - only" ;;
esac

command -v jira >/dev/null || die "jira CLI not found in PATH"

CFG="$DIR/$NAME.yml"
TOK="$DIR/$NAME.token.env"

[ -e "$CFG" ] && die "already exists: $CFG
  delete it first, or pick another name."
[ -e "$TOK" ] && die "already exists: $TOK
  delete it first, or pick another name."

mkdir -p "$DIR"
chmod 700 "$DIR"

cat <<EOF
Site '$NAME'
  config -> $CFG
  token  -> $TOK

Create the API token first, on the account you will log in with:
  https://id.atlassian.com/manage-profile/security/api-tokens
Use a classic token (no scopes); scoped tokens are not accepted everywhere.

EOF

# Read the token before init: init authenticates while it runs.
IFS= read -r -s -p 'Paste the API token (input hidden): ' TOKEN
printf '\n'
[ -n "$TOKEN" ] || die "empty token, nothing done"

export JIRA_API_TOKEN="$TOKEN"
export JIRA_CONFIG_FILE="$CFG"

printf '\nRunning jira init for %s. Answer: Cloud, the site URL, your login email.\n\n' "$NAME"

if ! jira init; then
	rm -f "$CFG"
	unset TOKEN JIRA_API_TOKEN
	die "jira init failed — nothing was saved.
  401 means the email and the token belong to different accounts, or the
  token is a password. 403 means the account has no access to the project."
fi

# init succeeded, so the pair is known good — persist the token.
( umask 077; printf 'JIRA_API_TOKEN=%s\n' "$TOKEN" > "$TOK" )
unset TOKEN JIRA_API_TOKEN

printf '\nVerifying the saved pair in a clean environment...\n'
if OUT=$(env -u JIRA_API_TOKEN bash -c "set -a; . '$TOK'; set +a; JIRA_CONFIG_FILE='$CFG' jira me" 2>&1); then
	printf 'jira me -> %s\n' "$OUT"
else
	printf '%s\n' "$OUT" >&2
	die "the saved pair does not authenticate. Files kept for inspection:
  $CFG
  $TOK"
fi

# The skill needs a site file for this site before it can write anything, and
# generating it is the same read-only pass site-probe.sh does. Best effort:
# a failure here costs one manual command, not the registration.
PROBE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/site-probe.sh"
if [ -x "$PROBE" ]; then
	printf '\nGenerating the site file for the skill...\n'
	if "$PROBE" --site "$NAME" --write; then
		:
	else
		printf 'site file not generated — run it yourself:\n  %s --site %s --write\n' "$PROBE" "$NAME" >&2
	fi
fi

cat <<EOF

Done. Use it from any shell:

  jira_site $NAME      # switch to this site
  jira_site default    # back to the default one ('wl' also accepted)

The config and the token stay out of git and out of any assistant session.
EOF
