# Writing a ticket someone else can execute

For a ticket that describes work **to be done** by anyone — including you next
month. A ticket that records work already finished uses `create-task.md`
instead; this file is about the body text, and it applies in any project.

The reader has no context. That is the whole rule; everything below follows
from it.

## Title

- an action verb first: `Add`, `Update`, `Implement`, `Fix`, `Investigate`,
  `Migrate`
- name the surface — the service, the cluster, the page, the module — and stop
  there
- **generic, not parametric.** Counts, versions, hostnames, dates and component
  lists go in the body, not the title. A board is read at a glance, and a title
  carrying four facts is read as none; worse, those facts go stale while the
  body is still correct
- 70–80 characters, no more
- a domain marker (`[BE]`, `[FE]`, `[QA]`, `[Spike]`) **only if the project
  already uses them** — check existing tickets, do not introduce a convention

```
good   Migrate EKS node groups to a new AMI in the staging cluster
bad    AL2023                                     (a noun, answers nothing)
bad    Fix the thing that broke yesterday         (no surface, no verb)
bad    Migrate 12 EKS node groups to AL2023 v1.31 across three clusters
                                                  (the body's job, and it rots)
```

## Body sections

Include the ones that carry information; delete the rest rather than filling
them with `N/A`.

**Context / problem** — why this exists now, what happens today, what is wrong.
For a bug: current behaviour, expected behaviour, steps to reproduce, and the
environment it was seen in.

**Scope** — what must be true when this is done. Behaviour, data rules, API
contracts, permissions, edge cases. Tell the implementer *what*, not which
lines to edit.

**Out of scope** — the neighbouring work this ticket deliberately does not
cover. One line here prevents a week of scope drift.

**Dependencies** — other tickets, other teams, an access that must exist
first. Link them as issue links; a sentence naming a team is not a dependency.

**Acceptance criteria** — a checklist, testable without a meeting:

```md
- [ ] <observable happy-path result>
- [ ] <observable negative / permission / error result>
- [ ] <empty, loading or failure state where it applies>
```

For infrastructure work, an acceptance criterion is a command and its expected
shape of output — `terraform plan` clean, pods `Running`, an endpoint
answering — never "works fine".

**Definition of done** — the completion bar the team actually holds: reviewed,
verified in a named environment, no unresolved regressions, docs updated when
behaviour or operations changed.

## Kinds that need something extra

- **Spike** — a timebox, the research question, the artefact it must produce,
  and the decision that follows. Without a timebox it is not a spike.
- **Bug** — reproduction steps and the environment, or it will be closed as
  "cannot reproduce".
- **Epic** — objective, business outcome, scope and out-of-scope, dependency
  summary, exit criteria. Shorter than the tickets under it, not longer.

## Before creating

- **Read the required fields of the issue type from `createmeta`, never from a
  remembered set** — they differ per project and per type. Print them in the
  draft only when the list has something to say: a field still without a value,
  or a set that disagrees with what the site file records. A field without a
  value is a question for the user, and the create waits for the answer.
- **Print the content checklist with the draft**, one line per item, before
  anything is created:

  ```
  Distinct parts:         <n> repositories · <n> decisions · <n> risks · reversible
  Cause / mechanism:      present | absent — <one phrase why>
  Deciding constraint:    present | absent — <one phrase why>
  Out of scope + reason:  present | absent — <one phrase why>
  Risk condition + cost:  present | absent — <one phrase why>
  How it is verified:     present | absent — <one phrase why>
  ```

  Length follows that first line: one sentence per part the reader has to tell
  apart, plus the five items. A ticket is long because it has many separable
  parts, never because the work felt important.

  These five are what a short ticket loses first, and losing them is invisible
  in a text that reads well. The last two lines have no `absent` where the issue
  type requires a risk and an acceptance field — `createmeta` says which types
  do, and the fields differ between types in one project. Where they are
  required they cannot be skipped and `N/A` is not an answer: a low risk is
  written as what makes it low. The first three may be `absent` with a reason
  after them. A missing line is never fine.
- **Search for it first.** A duplicate costs more than the search:
  `jira issue list -q'project = <KEY> AND text ~ "<subject>"' --plain --paginate 15`
- Check the project's required fields — they differ per issue type.
- Confirm the issue type exists in that project; type names are not portable
  between projects.

## Failures that keep recurring

- "implement according to the backend" / "make it like the design" — the
  ticket carries no information
- two unrelated changes in one ticket, so neither can be released alone
- no negative path, so QA validates only that the happy case works
- the surface is missing: no page, no service, no cluster named
- tribal knowledge assumed — a name, an internal acronym, a decision taken in
  a call nobody linked

## Snapshot before you write, compare after

Jira has no undo, and an edit replaces the whole field. Keep the original
locally, in the same command sequence as the change:

```bash
jira issue view PROJ-123 --raw > /tmp/PROJ-123-before.json
# ... the approved change ...
jira issue view PROJ-123 --raw > /tmp/PROJ-123-after.json
diff <(jq -S '.fields' /tmp/PROJ-123-before.json) \
     <(jq -S '.fields' /tmp/PROJ-123-after.json)
```

The diff is the evidence that only the intended field moved. Timestamps and
history change on their own — everything else should not.

Two flag facts, verified on jira-cli 1.7.0:

- `jira issue edit` has **no** `--template`. The description comes from `-b`,
  or on stdin: `jira issue edit PROJ-123 --no-input < draft.md`.
- `jira issue comment add` has no `-b`; it takes the body positionally or with
  `-T/--template`.

Write the final text to a file first either way. It is what gets reviewed, and
it survives a failed command.

## Comments while the work runs

A comment written at the moment something happens costs nothing and answers
the question everyone asks later — where did this stand, and when. Jira is
where that survives; a chat message is not.

| Moment | What goes on the ticket |
|---|---|
| work starts | the branch, and what is about to be attempted |
| approach chosen or changed | the decision and **who approved it** |
| blocked | what blocks it, who owns the blocker, what was tried |
| PR opened | the link, and what still needs to happen |
| tests or checks pass | the command and its result — not "works" |
| handed over | what is verified, what is not, next owner |

Short forms, each one file for `--template`:

```md
Started. Branch: feat/PROJ-123-short-name
Approach: <one line — what is being changed and where>
```

```md
Blocked by <what>. Owner: <who>.
Tried: <what was attempted and what it produced>
Needs: <the decision, access or fix that unblocks it>
```

```md
PR: <url>
Scope: <what the PR does and does not cover>
Checks: <command → result>
```

Rules that keep these useful rather than noisy:

- **One comment per event, not per hour.** A ticket read six months later is
  ruined by a running commentary and helped by five dated facts.
- **Name people for decisions**, never for blame.
- **Never paste a token, a full log or a stack trace.** Link the build, quote
  the decisive line.
- **A comment does not change status.** Transition separately, and only when
  asked — see the safety rules in `SKILL.md`.
- **Ask before publishing.** Drafting is free; publishing notifies watchers.

## When the work continues on an existing ticket

A ticket filed last week, and the work moved on: "add today's work to it as a
continuation". A comment alone is not enough. The description and the
risk/acceptance fields — what the issue view groups under *Key details* — are
the ticket's **current** claim about the work, and the new work makes parts of
them false. Measured on one ticket: the scope named scripts that no longer
existed, *out of scope* named work already done, and the acceptance test
checked a file that had been deleted — run as written, it would fail.

1. **Read every field in its stored form**, not through `jira issue view`:
   `GET /rest/api/2/issue/<KEY>?fields=description,<risk field>,<acceptance field>,<date fields>`
   returns wiki markup. Name to the user each sentence the new work makes
   wrong.
2. **Do not rewrite the description.** Keep the original sections word for
   word, add `h3. Update <YYYY-MM-DD>` with what changed, and correct *out of
   scope* if part of it is now done. The date heading is what a weekly report
   looks for.
3. **Replace the risk and acceptance fields** when they describe what no longer
   exists. An acceptance test is only useful if it can be run today.
4. **Keep the comment** as the record of the step — it carries author and time.
5. **Write the fields in one call**: `PUT /rest/api/2/issue/<KEY>` with
   `{"fields": {...}}`. One change, one notification to the watchers.
6. **Read back** with `?expand=renderedFields` and show what a reader sees.

Description edits have no undo, so all drafts are shown before the write.

**"Move the closing date" means whichever date the project tracks.** A project
may have both the system `duedate` and its own end-date field (see `SITE.md`);
on the ticket this was written from, `duedate` was empty and the end-date field
held the date the user meant. Read both before writing, and write the one that
is set.

**Text with angle brackets goes through REST v2 in wiki markup**, comments
included — `comment add --template` converts Markdown and drops `<…>` without
an error. See `SKILL.md`, next to `jira issue comment add`.

## The verification comment

When the work is done, the evidence goes on the ticket as a comment, not into
a chat message that disappears:

```md
## Outcome
<what changed, or what the investigation established>

## Evidence
- Scope / acceptance criteria: <references>
- Repository / PR / commit: <references, or not applicable>
- Environment and revision: <verified value, or unverified>
- Checks executed: <commands and their results>

## Remaining work
<unverified scenarios, blockers, next owner — "none" only when true>
```

```bash
jira issue comment add <KEY> --template /tmp/verification.md
```

Publishing this comment does not transition the ticket, and it does not
authorise transitioning it.
