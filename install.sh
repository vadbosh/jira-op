#!/usr/bin/env bash
# Install the jira-op skill into every coding assistant found under $HOME.
#
#   ./install.sh                  install into every assistant detected
#   ./install.sh --dry-run        print what would happen, change nothing
#   ./install.sh --skills-dir D   install into D instead of auto-detecting
#
# Idempotent. A destination that differs from the source is copied to
# <dir>.bak.<timestamp> first — a local edit is the one thing git cannot give
# back. Nothing outside $HOME is touched, and no credential is read or written.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$SRC/skills/jira-op"
STAMP="$(date +%Y%m%d-%H%M%S)"

DRY_RUN=0
SKILLS_DIR=""

while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run)    DRY_RUN=1 ;;
		--skills-dir) shift; SKILLS_DIR="${1:?--skills-dir needs a path}" ;;
		-h|--help)    sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
		*)            echo "unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done

[ -d "$SKILL_SRC" ] || { echo "not found: $SKILL_SRC" >&2; exit 1; }

run() {
	if [ "$DRY_RUN" = 1 ]; then
		printf '  would: %s\n' "$*"
	else
		"$@"
	fi
}

targets=()
if [ -n "$SKILLS_DIR" ]; then
	targets=("$SKILLS_DIR")
else
	for d in "$HOME/.claude/skills" \
	         "$HOME/.config/opencode/skills" \
	         "$HOME/.codex/skills"; do
		[ -d "$(dirname "$d")" ] && targets+=("$d")
	done
fi

[ ${#targets[@]} -gt 0 ] || {
	echo "no assistant directory found under $HOME." >&2
	echo "use --skills-dir <path> to say where the skills live." >&2
	exit 1
}

for dir in "${targets[@]}"; do
	dest="$dir/jira-op"
	printf '%s\n' "$dest"
	run mkdir -p "$dir"
	if [ -e "$dest" ] && ! diff -rq "$SKILL_SRC" "$dest" >/dev/null 2>&1; then
		printf '  differs from source — keeping a copy\n'
		run cp -r "$dest" "$dest.bak.$STAMP"
	fi
	run rm -rf "$dest"
	run cp -r "$SKILL_SRC" "$dest"
	printf '  installed\n'
done

cat <<EOF

Next:
  1. jira init                 configure jira-cli for your site
  2. store the token           see docs/setup.en.md, or docs/setup.ru.md
  3. optional, several sites:  . $SRC/tools/jira_site.sh
                               $SRC/tools/add-site.sh <name>
EOF
