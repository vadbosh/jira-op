# Setup — jira-cli, credentials, and the skill

Everything needed to get from an empty machine to a working `jira me`. The
skill drives jira-cli; if jira-cli is not configured, nothing else here works.

- [1. Install jira-cli](#1-install-jira-cli)
- [2. Get an API token](#2-get-an-api-token)
- [3. Store the token](#3-store-the-token)
- [4. Run jira init](#4-run-jira-init)
- [5. Verify](#5-verify)
- [6. Install the skill](#6-install-the-skill)
- [7. More than one Jira site](#7-more-than-one-jira-site)
- [Keeping the site files current](#keeping-the-site-files-current)
- [Troubleshooting](#troubleshooting)
- [Removing it](#removing-it)

## 1. Install jira-cli

Packaged binaries for Linux, macOS and Windows are on the
[releases page](https://github.com/ankitpokhrel/jira-cli/releases). Homebrew,
Nix and distribution packages are listed in the project's
[installation guide](https://github.com/ankitpokhrel/jira-cli/wiki/Installation).

To try it without installing anything:

```bash
docker run -it --rm ghcr.io/ankitpokhrel/jira-cli:latest
```

Check what you ended up with — this documentation was written against 1.7.0,
and the flags below were verified on it:

```bash
jira version
```

Older versions differ in flag names. When a command here is rejected, read
`jira <command> --help` before assuming the documentation is wrong.

## 2. Get an API token

For **Jira Cloud**, create a token at
<https://id.atlassian.com/manage-profile/security/api-tokens>.

Two things decide whether it will work:

- **Use a classic token — the kind created without scopes.** Scoped tokens are
  not accepted by every endpoint jira-cli uses.
- **The login email must be the account that created the token.** A mismatch
  produces `401 Unauthorized`, which reads like a bad token and is not one.

For an **on-premises** Jira, jira-cli takes either your login password (auth
type `basic`) or a personal access token (auth type `bearer`, with
`JIRA_AUTH_TYPE=bearer` exported). mTLS with client certificates is also
supported; pick auth type `mtls` during init.

## 3. Store the token

jira-cli reads the token **only** from the `JIRA_API_TOKEN` environment
variable. It is never written into the config file.

```bash
umask 077
read -r -s -p 'token: ' T \
  && printf 'JIRA_API_TOKEN=%s\n' "$T" > ~/.config/.jira/token.env \
  && unset T
```

`read -s` keeps the value off the screen and out of shell history. Load it in
any shell that needs it:

```bash
set -a; . ~/.config/.jira/token.env; set +a
```

Upstream suggests exporting the variable straight from `~/.bashrc`, and
supports `.netrc` and keychains as alternatives. A separate `600` file is used
here for one reason: it can be swapped per site, which an export in `.bashrc`
cannot.

**A coding assistant snapshots its environment at startup.** A variable
exported in the terminal after the assistant launched does not reach it —
which is why the skill sources the file inside each command rather than
relying on an inherited value.

## 4. Run jira init

Export the token first. `jira init` authenticates against the site while it
asks its questions, so without a token in the environment it fails with `401`
halfway through and leaves nothing behind.

```bash
set -a; . ~/.config/.jira/token.env; set +a
jira init
```

Answer:

| Question | Answer |
|---|---|
| Installation type | `Cloud` for `*.atlassian.net`, `Local` for on-premises |
| Link to Jira server | the full site URL, e.g. `https://example.atlassian.net` |
| Login email | the account that created the token |
| Default project | the **project key**, not its display name — `OPS`, not `Operations` |
| Default board | pick the board you actually work on |

Two answers people get wrong:

- **Project key, not project name.** If Jira's own left sidebar shows the work
  under *Spaces*, that is Confluence, and a Confluence space is not a Jira
  project. The key is the prefix of your ticket keys: `ABC-1234` → `ABC`.
- **The board matters.** With no board, or with the wrong one, every sprint
  command answers `No result found`.

Everything can be passed as flags for an unattended run:

```bash
jira init --force --installation cloud \
  --server https://example.atlassian.net \
  --login you@example.com \
  --auth-type basic \
  --project ABC --board "ABC Sprint board"
```

The config lands in `~/.config/.jira/.config.yml`. It contains no credentials.

## 5. Verify

```bash
jira me                                  # prints your login — authentication works
jira project list | head                 # project access
jira issue list -a"$(jira me)" --plain --paginate 15
jira sprint list --state active --plain  # needs a board in the config
```

`jira me` proves the credentials, nothing more. Permission on a specific
project or issue is a separate question, and `jira project list` is the cheap
way to ask it.

To see what your account may actually do in a project:

```bash
SITE=https://example.atlassian.net
curl -s -u "$(jira me):$JIRA_API_TOKEN" \
  "$SITE/rest/api/3/mypermissions?projectKey=ABC&permissions=CREATE_ISSUES,EDIT_ISSUES,DELETE_ISSUES,TRANSITION_ISSUES" \
  | jq -r '.permissions | to_entries[] | "\(.key)\t\(.value.havePermission)"'
```

Worth running once. `DELETE_ISSUES: false` is common, and it means a ticket
created by mistake stays on the board until an administrator removes it.

## 6. Install the skill

```bash
./install.sh              # into every assistant directory found under $HOME
./install.sh --dry-run    # print what would happen, change nothing
./install.sh --skills-dir ~/somewhere/skills
```

It looks for `~/.claude/skills`, `~/.config/opencode/skills` and
`~/.codex/skills`, and only writes where the parent directory already exists.
A destination that differs from the source is copied to `<dir>.bak.<timestamp>`
before being replaced.

**Linux and macOS only** — it is a bash script. Under Windows use WSL or Git
Bash, or copy the folder by hand:

```
skills\jira-op  ->  %USERPROFILE%\.claude\skills\jira-op
                ->  %USERPROFILE%\.codex\skills\jira-op
                ->  %APPDATA%\opencode\skills\jira-op
```

The skill is Markdown; only the installer is shell. `tools/add-site.sh` and
`tools/jira_site.sh` are bash as well, so multi-site switching on native
Windows means setting `JIRA_CONFIG_FILE` and `JIRA_API_TOKEN` yourself.

Restart the assistant, or start a new session, so it re-reads its skills.

## 7. More than one Jira site

One config file describes one site, and the token is global to the process.
They must switch together: a config from one site with a token from another
returns `401`, which reads as an expired token rather than a wrong pairing.

Register a site — `install.sh` put the command on your PATH, so this works
from anywhere and does not care where the clone is:

```bash
jira-op-add-site acme          # or ./tools/add-site.sh from the clone
```

It asks for the token first, exports it, runs `jira init` against
`~/.config/.jira/acme.yml`, and — only after init succeeds — writes
`~/.config/.jira/acme.token.env` with mode `600`. Then it re-verifies the saved
pair in a clean environment, so what gets checked is what is on disk. If init
fails, the config is removed and no token is written.

```bash
jira-op-add-site --list        # what is registered
```

Switch with the shell function. `install.sh` puts a copy under `$HOME` —
source **that**, never the clone: an rc file pointing into a checkout breaks
the day the checkout moves.

```bash
. ~/.local/share/jira-op/jira_site.sh    # add this to ~/.bashrc or ~/.zshrc

jira_site acme      # ~/.config/.jira/acme.yml + acme.token.env
jira_site default   # back to .config.yml + token.env
```

It prints the config and env-file paths it loaded, then your login. A switch
that prints nothing cannot be told from a no-op — and a config from one site
with a token from another is exactly what `401` looks like.

It prints the login, and that is the proof the switch happened. The effect is
limited to the current shell.

**Everything project-specific in the skill stops applying on another site** —
issue type, custom field ids, statuses, board number. Re-read `createmeta`
before writing anything there; see *Adapting it to your Jira* in the README.

## Keeping the site files current

`SITE.md` is a snapshot of a Jira project's configuration, and Jira changes
without telling anyone. Three things keep it honest:

```bash
jira-op-site-probe --write          # regenerate for the current site
jira-op-site-probe --all --write    # every registered site
jira-op-site-probe --all --check    # report drift, write nothing
```

`--check` exits `3` when the live API disagrees with what is on disk, so it
works as a cron job. **Nothing installs one for you** — a clone should not
touch your crontab. Add it yourself if you want it, adjusting the paths:

```cron
# weekly, read-only; exit 3 and a diff in the log when a project changed
23 9 * * 1 PATH=/usr/local/bin:/usr/bin:/bin HOME=/home/you \
  /path/to/jira-op/tools/site-probe.sh --all --check \
  >> /home/you/.local/state/jira-op/site-check.log 2>&1
```

cron runs with a minimal environment: set `PATH` so `jira` and `jq` are found,
and `HOME` so the config and token files resolve.

`add-site.sh` and `install.sh` generate the file on their own when there is
none, so the usual case needs no command at all.

### When the skill is not edited in place

**Most people never set anything.** A plain bash setup with no dotfile
machinery works as it is: with no variable, the tool finds the assistant
directories itself and writes to all of them:

```
$ tools/site-probe.sh --check
no drift: ~/.claude/skills/jira-op/SITE.md
no drift: ~/.config/opencode/skills/jira-op/SITE.md
no drift: ~/.codex/skills/jira-op/SITE.md
```

It matters only when the skill is kept in one directory and *copied* into the
assistants — a config canon, a dotfiles repository, chezmoi, a shared folder.
There, writing into an assistant's copy is undone by the next sync. Point the
tool at the source instead:

```bash
export JIRA_OP_SKILL_DIR=~/config-canon/skills/jira-op
```

Put that wherever your shell keeps exports — `~/.bashrc`, `~/.zshrc`,
`~/.bash_aliases`; the tool does not care which. `--skill-dir` overrides it for
one run.

**The symptom, if you skip this:** the site file is written, everything works,
and after the next sync or dotfiles apply the skill is back to placeholders.
`tools/site-probe.sh --check` names it — `missing: <path> — run with --write`.
Every write prints the paths it touched, so comparing them once with where your
skill actually lives settles it.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `401 Unauthorized` during `jira init` | no token in the environment, or the login email is not the account that created it. Export the token, re-check the email |
| `401` after a site switch | config and token from different sites. Load the pair together |
| `403` on a project | the account has no access. Ask a Jira administrator |
| `✗ Missing configuration file.` | `JIRA_CONFIG_FILE` points at a file that does not exist. `unset` it, or run `jira init` for that path |
| `No result found for given query in project "X"` | the config's default project is not the one you meant. Pass `-p KEY`, or re-run `jira init --force` |
| `No boards found in project "X"` | same cause. The message names the project from the config, not the one you asked about |
| Sprint commands return nothing | no board in the config, or a kanban board where a scrum one is needed |
| `400 Bad Request: Expecting ',' but got 'ORDER'` | `ORDER BY` inside `-q`. Use `--order-by` |
| `Error: unknown flag: --plain` | `board list` has no output flags. Read it as a table, or use the Agile REST API |
| A list looks short | `--paginate` defaults to 8. Pass `--paginate 15` |
| A discussed ticket shows no discussion | `issue view` shows one comment. Pass `--comments 10` |
| It works in the terminal, not in the assistant | the assistant snapshotted its environment at launch. Source the token file inside the command |

## Removing it

```bash
rm -rf ~/.claude/skills/jira-op ~/.config/opencode/skills/jira-op ~/.codex/skills/jira-op
```

The jira-cli config and the token files are separate and are not touched by
that. Delete them deliberately:

```bash
rm -i ~/.config/.jira/.config.yml ~/.config/.jira/token.env
```

Revoke the API token itself at
<https://id.atlassian.com/manage-profile/security/api-tokens> — deleting the
local file does not invalidate it.
