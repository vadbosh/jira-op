# Fast start

One screen. Full guide: [docs/setup.en.md](docs/setup.en.md) ·
[по-русски](FAST-START.RU.md)

## Once

```bash
umask 077; read -r -s -p 'token: ' T \
  && printf 'JIRA_API_TOKEN=%s\n' "$T" > ~/.config/.jira/token.env && unset T
set -a; . ~/.config/.jira/token.env; set +a
jira init          # Cloud, site URL, login email, project key, board
./install.sh       # skill into every assistant found; also reads your field ids
jira me            # prints your login = it works

SKILL=~/.claude/skills/jira-op   # or ~/.codex/… or ~/.config/opencode/skills/…
```

The token goes first: `jira init` authenticates while it asks its questions.

## Then talk to the assistant

| You say | What happens |
|---|---|
| `show my open tickets` | list, nothing else |
| `what's in the active sprint` | the sprint that actually contains today |
| `investigate PROJ-123` | read-only: facts, hypotheses, what could not be checked |
| `file a ticket: <what you did>` | draft first — nothing is created until you say yes |
| `weekly report` | writes a `.txt` into the project directory, answers with its path |

## Filing a ticket

Three questions: **story points**, **which sprint**, **End Date** (`none` is
fine). Then the whole draft is printed — description, risks, acceptance
criteria — and nothing is created until you approve it. The draft is in English
whatever language you asked in; the summary stays generic, with counts and
versions in the body.

The epic is never set — attach it in the UI. **A create cannot be undone** on
most accounts, so there are no test tickets.

## Weekly report

Calendar week, Monday–Sunday; run it Friday evening or Saturday morning. You
are asked whether the window contained vacation.

It writes a plain-text file into the project directory and answers with the
path alone — the content is not printed into the chat, and an existing file is
never overwritten (a second run writes `-2`):

```
weekly-update-2026-08-31_2026-09-06.txt
```

Shape: [docs/example-weekly-update.txt](docs/example-weekly-update.txt). It
reports facts of the work — not ticket age, sprint carry-overs or empty fields
— and unstarted work never appears.

## Several Jira sites

```bash
$SKILL/scripts/add-site.sh acme     # asks for the token, runs init, writes SITE.acme.md
. $SKILL/scripts/jira_site.sh       # put this line in ~/.bashrc
jira_site acme                      # switch      jira_site default — switch back
```

## When something breaks

```bash
jira me                                     # 401 = token or email wrong
$SKILL/scripts/site-probe.sh --all --check  # the project changed fields or statuses
```

A create failing on an unknown `customfield_*` means the schema moved: run
`--write` and try again.
