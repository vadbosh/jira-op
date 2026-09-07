# Writing a ticket someone else can execute

For a ticket that describes work **to be done** by anyone — including you next
month. A ticket that records work already finished uses `create-task.md`
instead; this file is about the body text, and it applies in any project.

The reader has no context. That is the whole rule; everything below follows
from it.

## Title

- an action verb first: `Add`, `Update`, `Implement`, `Fix`, `Investigate`,
  `Migrate`
- name the surface: the service, the cluster, the page, the module
- 70–80 characters, no more
- a domain marker (`[BE]`, `[FE]`, `[QA]`, `[Spike]`) **only if the project
  already uses them** — check existing tickets, do not introduce a convention

```
good   Migrate EKS node groups to AL2023 AMI in the staging cluster
bad    AL2023                                (a noun, answers nothing)
bad    Fix the thing that broke yesterday    (no surface, no verb, no date)
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
