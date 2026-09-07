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
#   jira_site wl        the default pair — .config.yml + token.env
#   jira_site acme      ~/.config/.jira/acme.yml + acme.token.env
#
# It prints the login, and that is the proof the switch happened. The effect is
# limited to the current shell: an assistant process started earlier keeps
# whatever it inherited at launch.
#
# Register a new site with add-site.sh; never hand-write the config.

jira_site() {
	local d=~/.config/.jira name=${1:?usage: jira_site <wl|site-name>}
	if [ "$name" = wl ]; then
		unset JIRA_CONFIG_FILE
		set -a; . "$d/token.env" || return 1; set +a
	else
		[ -r "$d/$name.yml" ] || {
			echo "no config: $d/$name.yml" >&2
			echo "create it: $(dirname "${BASH_SOURCE[0]}")/../add-site.sh $name" >&2
			return 1
		}
		export JIRA_CONFIG_FILE="$d/$name.yml"
		set -a; . "$d/$name.token.env" || return 1; set +a
	fi
	jira me
}
