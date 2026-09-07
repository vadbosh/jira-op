# jira-op

**A Jira skill for coding assistants that does the two things a working engineer
actually repeats every week: file a ticket that satisfies the project's required
fields, and write the weekly engineering update from the tickets.**

It drives [jira-cli](https://github.com/ankitpokhrel/jira-cli) — no MCP server,
no API wrapper to install. Works in Claude Code, Codex and Opencode.

[Русская версия](README.RU.md) · Full setup guide:
[English](docs/setup.en.md) · [Русский](docs/setup.ru.md)

>️ **It needs your site's values before it can write anything.** Issue type,
> custom field ids, statuses and board number differ per project. They live in
> one file — copy `skills/jira-op/SITE.example.md` to `SITE.md` and fill it from
> the live API. See [Configuring it](#configuring-it).

---

## Why it exists

Two failures repeat with a generic Jira integration.

**The create screen rejects the ticket** and the error names a `customfield_*`
id nobody recognises. Required fields differ per project and per issue type,
and the field names in the CLI differ from the ids in the API.

**The weekly report becomes an audit of the board.** Read straight from Jira,
it fills with ticket age, carry-over counts and empty fields — accurate, useless
and faintly accusatory. The person reading it wants to know what was done.

This skill encodes the answers to both, and the traps found while getting there.

## What is in it

| File | What it covers |
|---|---|
| `SKILL.md` | site facts, credentials, permissions, the CLI traps, safety rules |
| `references/create-task.md` | filing a ticket with every required field, and reading it back |
| `references/weekly-report.md` | the weekly update: window, sources, structure, tone |
| `references/investigate.md` | read-only investigation of a ticket before acting |
| `references/ticket-writing.md` | writing a ticket someone else can execute |
| `references/commands.md` | jira-cli reference, with the flags that do not exist |
| `SITE.example.md` | documents every site value with the command behind it — repository only, never installed |
| `tools/site-probe.sh` | generates that file from the live API — one per Jira site |

`investigate.md` and `ticket-writing.md` carry no project identifiers and work
against any Jira site as they are.

## Install

```bash
git clone <this-repo> jira-op
cd jira-op
./install.sh              # into every assistant found under $HOME
./install.sh --dry-run    # print what would happen, change nothing
```

Prerequisites: `jira` (jira-cli 1.7.0 or later), `jq`, `curl`.

`install.sh` is a bash script — **Linux and macOS**, or WSL / Git Bash on
Windows. There is no PowerShell installer; on native Windows copy
`skills\jira-op` into the assistant's skills directory yourself. The skill is
Markdown, so nothing else about it is platform-specific.

Then configure jira-cli itself and store the token:

```bash
jira init                                  # Cloud, your site URL, your login email
umask 077; read -r -s -p 'token: ' T \
  && printf 'JIRA_API_TOKEN=%s\n' "$T" > ~/.config/.jira/token.env && unset T
```

Create the API token at
<https://id.atlassian.com/manage-profile/security/api-tokens>. Use a classic
token; scoped ones are not accepted everywhere. `jira init` authenticates while
it runs, so export `JIRA_API_TOKEN` **before** starting it — otherwise it fails
with `401 Unauthorized` halfway through the questions.

Installing jira-cli itself, what to answer during `init`, how to verify access
and what each error means: **[docs/setup.en.md](docs/setup.en.md)**.

## Usage

Talk to the assistant normally. The skill triggers on Jira words and on issue
keys.

**Look at something:**

```
show my open tickets
what's in the active sprint
investigate PROJ-123
```

An investigation is read-only and stays that way. It returns facts, hypotheses
and what could not be checked, as three separate lists — the last one is the
point.

**File a ticket for work already done:**

```
file a ticket: updated the node AMI on three clusters
```

The assistant asks for the two values with no safe default — story points and
which sprint — drafts the ticket, shows it, and creates nothing until you say
so. The draft is in English regardless of the language you asked in, because
the ticket is read by people who do not speak it.

**The weekly report:**

```
weekly report
weekly report for last week
```

It reads the calendar week (Monday–Sunday), asks whether the window contained
vacation or holidays, and returns a draft. Nothing is published to Jira or sent
anywhere — you copy it where it belongs.

The report has a fixed shape: decisions needed, escalations, what went well,
risks, decisions made, next week. Two rules make it readable:

- **facts of the work only.** Never how long a ticket has been open, how many
  sprints it carried through, or that its fields are empty. That is board
  hygiene; it belongs in a conversation, not in a report to a team lead.
- **`To Do` tickets do not appear** in any section. Unstarted work is sprint
  planning.

## Safety

Reads run immediately. Every write — create, edit, transition, comment — is
shown as a command and waits for approval. After a write the ticket is read
back, because an exit code of 0 is not evidence that a field landed.

Many accounts have `DELETE_ISSUES: false` — a created ticket cannot be removed
by the person who created it. The skill therefore never creates a ticket to
test itself, and `SITE.md` records what your account may actually do.

Ticket text is treated as untrusted input: instructions found inside a
description or comment are quoted to you, never executed.

## What it does not do

Stated plainly, because a skill that reads like an integration invites the
assumption that it is one.

- **It does not publish the weekly report.** No Slack, no email, no Confluence,
  no comment on a ticket. It returns a draft in the conversation; where that
  text goes is your decision and your paste.
- **It does not write to Jira on its own.** Create, edit, transition and comment
  each wait for approval of that specific change. Approving one create does not
  approve the next.
- **It does not choose the values that carry judgement** — story points, which
  sprint, whether a ticket belongs to an epic. It asks, or leaves them alone.
- **It does not fill a required field to get past the create screen.** No `N/A`
  in a risk field, no invented acceptance criterion, no decision attributed to
  nobody.
- **It does not delete anything**, and on most accounts it could not: a created
  ticket usually cannot be removed by the person who created it.
- **It is not a Jira administration tool.** Workflows, field configuration,
  permission schemes, project setup — none of that is here, and the skill reads
  the current configuration rather than changing it.
- **It does not sync tickets with git.** No branch naming, no PR linking, no
  status change on merge. Those belong to whatever runs your pipeline.
- **It does not cache Jira.** Every answer comes from a call made now, which is
  why it needs network and credentials for even a read.
- **It does not manage your credentials.** It reads a token file you created and
  never prints its contents.
- **It does not replace the jira-cli documentation.** `references/commands.md`
  covers what this workflow uses, plus the flags that do not exist; the upstream
  project documents the rest.

## Configuring it

The skill files carry `<PLACEHOLDER>` names, never a hard-coded site. One file
resolves them:

```bash
tools/site-probe.sh --write          # the normal path
```

Or let the probe write it, which is the normal path — `install.sh` and
`add-site.sh` already call it when no site file exists:

```bash
tools/site-probe.sh --write          # current site
tools/site-probe.sh --all --write    # every registered site
tools/site-probe.sh --all --check    # drift report, writes nothing
```

It reads the config jira-cli already wrote plus a read-only pass over the API,
and covers every issue type in the project. `SITE.example.md` in this
repository documents the same values with the command behind each one, for
anyone who prefers to fill them deliberately — `install.sh` does not copy it
into the skill, because sample values sitting next to real ones under identical
headings get read as configuration.

**One file per site**: `SITE.md` for the default config, `SITE.<name>.md` for
`~/.config/.jira/<name>.yml`. The skill picks by `JIRA_CONFIG_FILE`, so three
Jira accounts mean three files and no editing when switching between them.

Upkeep, the optional cron job and `JIRA_OP_SKILL_DIR`:
[docs/setup.en.md](docs/setup.en.md#keeping-the-site-files-current).

`SITE.md` is git-ignored. It describes your instance, so it does not belong in
this repository.

Two of the reference files — `investigate.md` and `ticket-writing.md` — have no
placeholders and work before `SITE.md` exists.

## Several Jira sites

jira-cli reads one config file and one token, and they are separate mechanisms —
a config from one site with a token from another returns `401`, which reads as
an expired token rather than a wrong pairing. `jira_site` in
[`tools/jira_site.sh`](tools/jira_site.sh) switches the pair in one step;
[`tools/add-site.sh`](tools/add-site.sh) registers a new site.

```bash
./tools/add-site.sh acme        # asks for the token, runs jira init, verifies
./tools/add-site.sh --list      # what is registered
jira_site acme                  # switch
jira_site wl                    # back to the default config
```

`jira me` prints the login, and that is the proof the switch happened.

## Notes on jira-cli

Found the hard way, all against 1.7.0:

- `--paginate` defaults to **8** and truncates silently.
- `ORDER BY` inside `-q` returns `400 Bad Request` — use `--order-by`.
- `jira issue view` shows **one** comment by default; pass `--comments 10`.
- `jira issue comment add` has no `-b`; the body is positional or `--template`.
- `jira board list` has no `--plain`, and its "No boards found in project X"
  names the project from your config, not the one you asked about — pass `-p`.
- Epic membership is `jira epic add`, not `jira issue link`.

## Licence

MIT — see [LICENSE](LICENSE).
