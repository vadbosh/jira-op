# Fast start

One screen. Full guide: [docs/setup.en.md](docs/setup.en.md) ·
[по-русски](FAST-START.RU.md)

## Once

```bash
umask 077; read -r -s -p 'token: ' T \
  && printf 'JIRA_API_TOKEN=%s\n' "$T" > ~/.config/.jira/token.env && unset T
set -a; . ~/.config/.jira/token.env; set +a
jira init                     # Cloud, site URL, login email, project key, board
./install.sh                  # skill into every assistant found
jira me                       # prints your login = it works
```

The token goes first: `jira init` authenticates while it asks its questions,
and without it in the environment it fails with `401` halfway through.

**You do not run the site probe.** `install.sh` reads your project's real field
ids by itself when no site file exists yet, and `add-site.sh` does the same for
a new site. `tools/site-probe.sh --write` is only for later — when Jira's
configuration changed under you:

```bash
jira-op-site-probe --all --check   # did anything change? writes nothing
jira-op-site-probe --all --write   # refresh every site
```

## Then just talk to the assistant

| You say | What happens |
|---|---|
| `show my open tickets` | list, nothing else |
| `what's in the active sprint` | the sprint that actually contains today |
| `investigate PROJ-123` | read-only: facts, hypotheses, what could not be checked |
| `file a ticket: <what you did>` | draft first — nothing is created until you say yes |
| `weekly report` | writes a `.txt` into the project working directory, answers with its path |

## Filing a ticket

You will be asked exactly two things: **story points** and **which sprint**.
Everything else is derived or drafted. The epic is never set — attach it in the
UI if it needs one.

The draft is in English whatever language you asked in. Review it, then say
create. After the write the ticket is read back and the stored values reported.

**A create cannot be undone** on most accounts — no test tickets.

## Weekly report

Calendar week, Monday to Sunday; run it Friday evening or Saturday morning.
You will be asked whether the window contained vacation or holidays.

**It writes a file and tells you the path — nothing else.** Plain text with the
emoji section markers, in the project working directory — the one the assistant
was started in:

```
weekly-update-2026-08-31_2026-09-06.txt
```

What it looks like: [docs/example-weekly-update.txt](docs/example-weekly-update.txt)

The content is not printed in the chat, and an existing file is never
overwritten — a second run writes `-2`.

What it will not do: publish anywhere, mention how long a ticket has been open,
count sprint carry-overs, or complain about empty fields. Facts of the work
only. `To Do` tickets never appear.

## Several Jira sites

```bash
jira-op-add-site acme      # asks for the token, runs init, writes SITE.acme.md
jira_site acme             # switch  (needs: . ~/.local/share/jira-op/jira_site.sh)
jira_site default          # switch back
```

## When something breaks

```bash
jira me                            # 401 = token or email wrong
jira-op-site-probe --all --check   # the project changed its fields or statuses
```

A create that fails on an unknown `customfield_*` means the schema moved: run
`--write` and try again.
