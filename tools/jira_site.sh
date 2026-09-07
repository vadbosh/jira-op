# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091   # the token files are per-site and per-user
# jira_site — switch jira-cli between Atlassian sites.
#
# Source it from ~/.bash_aliases (or wherever your shell keeps its functions):
#
#   . /path/to/jira-op/tools/jira_site.sh
#
# jira-cli reads one config file (JIRA_CONFIG_FILE, default
# ~/.config/.jira/.config.yml) and one token (JIRA_API_TOKEN). Those are two
# separate mechanisms, so the pair has to switch in one step: a config from one
# site with a token from another returns 401, which reads as an expired token
# rather than as a wrong pairing.
#
#   jira_site default   the default pair — .config.yml + token.env
#                       ('wl' is accepted as a synonym)
#   jira_site acme      ~/.config/.jira/acme.yml + acme.token.env
#
# It prints the login, and that is the proof the switch happened. The effect is
# limited to the current shell: an assistant process started earlier keeps
# whatever it inherited at launch.
#
# Register a new site with add-site.sh; never hand-write the config.

jira_site() {
	local d=~/.config/.jira name=${1:?usage: jira_site <default|site-name>}
	local cfg tok self
	if [ "$name" = default ] || [ "$name" = wl ]; then
		cfg="$d/.config.yml"; tok="$d/token.env"
		unset JIRA_CONFIG_FILE
	else
		cfg="$d/$name.yml"; tok="$d/$name.token.env"
		[ -r "$cfg" ] || {
			self="${BASH_SOURCE[0]}"
			command -v readlink >/dev/null && self="$(readlink -f "$self" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
			echo "no config: $cfg" >&2
			echo "create it: $(dirname "$self")/add-site.sh $name" >&2
			return 1
		}
		export JIRA_CONFIG_FILE="$cfg"
	fi
	[ -r "$tok" ] || { echo "no token file: $tok" >&2; return 1; }
	set -a; . "$tok" || return 1; set +a

	# Say which pair is now active. Paths only — the token value is never
	# printed, and a switch that says nothing is a switch nobody can verify.
	# The label is 'env file', not 'token': a secret-scanning shell hook masks
	# whatever follows a 'token:' label, path or not, and the masked line looks
	# like the switch went wrong.
	printf 'config:   %s\nenv file: %s\n' "$cfg" "$tok"
	jira me
}
