#!/usr/bin/env bash
# Install the jira-op skill into every coding assistant found under $HOME.
#
# Linux and macOS. On Windows use WSL or Git Bash, or copy skills/jira-op by
# hand into the assistant's skills directory — the script only copies files,
# there is nothing platform-specific about the skill itself.
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
# Backups go OUTSIDE any skills directory. A copy left as
# <skills>/jira-op.bak.<stamp> is itself loaded as a skill by every assistant
# that scans the directory — a duplicate of this one, under a nonsense name.
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/jira-op-backups"

DRY_RUN=0
SKILLS_DIR=""

while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run)    DRY_RUN=1 ;;
		--skills-dir) shift; SKILLS_DIR="${1:?--skills-dir needs a path}" ;;
		-h|--help)    sed -n '2,14p' "${BASH_SOURCE[0]}"; exit 0 ;;
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

	# SITE*.md describes the user's Jira and is not in this repository. It lives
	# inside the skill directory because that is where the skill reads it, so a
	# plain replace would delete it — carry it across instead.
	keep=""
	if [ -e "$dest" ]; then
		for f in "$dest"/SITE.md "$dest"/SITE.*.md; do
			[ -e "$f" ] || continue
			case "$(basename "$f")" in SITE.example.md) continue ;; esac
			keep="$keep $f"
		done
	fi
	if [ -n "$keep" ] && [ "$DRY_RUN" = 0 ]; then
		tmpkeep="$(mktemp -d)"
		# shellcheck disable=SC2086
		cp $keep "$tmpkeep/"
	fi

	if [ -e "$dest" ] && ! diff -rq "$SKILL_SRC" "$dest" >/dev/null 2>&1; then
		bak="$BACKUP_DIR/$(basename "$(dirname "$dir")")-jira-op.bak.$STAMP"
		printf '  differs from source — copy kept at %s\n' "$bak"
		run mkdir -p "$BACKUP_DIR"
		run cp -r "$dest" "$bak"
	fi
	run rm -rf "$dest"
	run cp -r "$SKILL_SRC" "$dest"

	# SITE.example.md is documentation for this repository, not for the skill.
	# Installed, it sits beside the real SITE.md with identical headings and
	# plausible sample values — PROJ, Task, 10001, Done — and is read as
	# configuration. It stays in the clone.
	run rm -f "$dest/SITE.example.md"

	if [ -n "$keep" ]; then
		if [ "$DRY_RUN" = 1 ]; then
			printf '  would: preserve%s\n' "$keep"
		else
			cp "$tmpkeep"/* "$dest/"
			rm -rf "$tmpkeep"
			printf '  preserved:%s\n' "$(printf '%s' "$keep" | tr ' ' '\n' | sed 's|.*/| |' | tr -d '\n')"
		fi
	fi
	printf '  installed\n'
done

# A skill with no site file for the active site cannot write anything, so
# generate one where none exists yet. Per destination, and always with an
# explicit --skill-dir: without it the probe auto-detects the assistants and
# would write outside the directory this run was asked to install into.
# Best effort — jira-cli may not be configured yet, which is fine.
if [ "$DRY_RUN" = 0 ]; then
	for dir in "${targets[@]}"; do
		dest="$dir/jira-op"
		have_site=0
		for f in "$dest"/SITE.md "$dest"/SITE.*.md; do
			[ -e "$f" ] || continue
			case "$(basename "$f")" in SITE.example.md) continue ;; esac
			have_site=1
		done
		[ "$have_site" = 1 ] && continue

		printf '\n%s: no site file yet — probing the configured Jira...\n' "$dest"
		if ! "$SRC/tools/site-probe.sh" --write --skill-dir "$dest"; then
			printf 'not generated (jira-cli not configured yet?). After jira init, run:\n  %s --write\n' \
			       "$SRC/tools/site-probe.sh"
		fi
	done
fi

# Same reasoning as the shell function: a cron line or a note in a runbook that
# points into a clone breaks when the clone moves. Put the two commands on PATH
# under stable names; they stay next to each other, which is how add-site finds
# the probe.
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
if [ "$DRY_RUN" = 1 ]; then
	printf '\n  would: cp tools/site-probe.sh %s/jira-op-site-probe\n' "$BIN_DIR"
	printf '  would: cp tools/add-site.sh   %s/jira-op-add-site\n' "$BIN_DIR"
else
	mkdir -p "$BIN_DIR"
	cp "$SRC/tools/site-probe.sh" "$BIN_DIR/jira-op-site-probe"
	cp "$SRC/tools/add-site.sh"   "$BIN_DIR/jira-op-add-site"
	chmod 755 "$BIN_DIR/jira-op-site-probe" "$BIN_DIR/jira-op-add-site"
	printf '\ncommands: %s/jira-op-site-probe, %s/jira-op-add-site\n' "$BIN_DIR" "$BIN_DIR"
	case ":$PATH:" in
		*":$BIN_DIR:"*) : ;;
		*) printf '  %s is not on your PATH — add it, or call them by full path\n' "$BIN_DIR" ;;
	esac
fi

# The shell function is sourced from a shell rc file, so it cannot live at the
# path of a clone either. Install a copy under $HOME and let the rc file point
# there. It stays in share/, not bin/: it is sourced, not executed.
SHELL_LIB="${XDG_DATA_HOME:-$HOME/.local/share}/jira-op"
if [ "$DRY_RUN" = 1 ]; then
	printf '\n  would: cp %s/tools/jira_site.sh %s/\n' "$SRC" "$SHELL_LIB"
else
	mkdir -p "$SHELL_LIB"
	cp "$SRC/tools/jira_site.sh" "$SHELL_LIB/jira_site.sh"
	printf '\nshell helper: %s/jira_site.sh\n' "$SHELL_LIB"
	if grep -rqs "jira-op/jira_site.sh" "$HOME/.bashrc" "$HOME/.bash_aliases" "$HOME/.zshrc" 2>/dev/null; then
		printf '  already sourced from your shell config\n'
	else
		printf '  add this line to ~/.bashrc, ~/.zshrc or ~/.bash_aliases:\n'
		printf '    . %s/jira_site.sh\n' "$SHELL_LIB"
	fi
fi

cat <<EOF

Next:
  1. jira init                 configure jira-cli for your site
  2. store the token           see docs/setup.en.md, or docs/setup.ru.md
  3. site values               jira-op-site-probe --write
                               (re-run when a create or a transition fails)
  4. several sites             jira-op-add-site <name>
                               . $SHELL_LIB/jira_site.sh
EOF
