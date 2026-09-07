# Weekly engineering update from <PROJECT> tickets

Produced at the end of the week from the tickets touched that week. It is a
written report for people, not a ticket dump: every bullet says what changed
and why it matters, and no bullet exists only because a ticket moved.

## 1. Fix the reporting window

The window is a **calendar week, Monday to Sunday**. Sprints on this board are
dynamic and do not align to weeks, so the sprint window is not the report
window — the sprint name only labels the report.

```bash
date -I
WEEK_START=$(date -d 'last monday' +%F)
WEEK_END=$(date -d "$WEEK_START +6 days" +%F)
NEXT_MON=$(date -d "$WEEK_START +7 days" +%F)
echo "$WEEK_START .. $WEEK_END"
```

The report is delivered **Friday evening or Saturday morning**, so the normal
run lands inside the week it reports and `last monday` returns that week's
Monday. Run on a Monday, it returns the *previous* Monday — also correct,
because a Monday report closes the week that just ended.

Never write the date from memory of the conversation. A resumed session can be
days later than it feels.

## 1a. Was the person there?

Before reading anything into an empty week, ask whether the window includes
vacation, public holidays or sick leave. An absence is not a delivery problem
and must never be written up as a risk.

An absent week gets one line under **What went well** — `Vacation from
<date> to <date>; no engineering activity planned or expected.` — and
`None this week.` in every other section. Do not fill it with carried-over
tickets to make it look busy.

## 2. Gather the week's material

```bash
set -a; . ~/.config/.jira/token.env; set +a

# everything of mine that moved in the window
jira issue list -q"project = <PROJECT> AND assignee = currentUser() AND updated >= \"$WEEK_START\" AND updated < \"$NEXT_MON\" AND status != \"To Do\"" \
  --plain --columns key,type,status,summary,updated --paginate 15

# what actually finished — the terminal status here is "<STATUS_DONE>", not "Done"
jira issue list -q"project = <PROJECT> AND assignee = currentUser() AND status CHANGED TO \"<STATUS_DONE>\" DURING (\"$WEEK_START\", \"$NEXT_MON\")" \
  --plain --columns key,status,summary --paginate 15

# what was in flight at any point in the window — the backbone of the report
jira issue list -q"project = <PROJECT> AND assignee = currentUser() AND status WAS \"<STATUS_IN_PROGRESS>\" DURING (\"$WEEK_START\", \"$NEXT_MON\")" \
  --plain --columns key,status,summary --paginate 15

# what is still open right now and carries into next week
jira issue list -q'project = <PROJECT> AND assignee = currentUser() AND status = "<STATUS_IN_PROGRESS>"' \
  --plain --columns key,status,summary --paginate 15

# the sprint the week belongs to
jira sprint list --state active --plain
```

Two constraints on these queries:

- **`To Do` tickets never appear in the report** — not in What went well, not
  in Risks, not in Decisions Needed. Unstarted work is sprint planning, not a
  week's engineering record. Filter it out at the query, so it cannot leak in
  through a carried-over ticket.
- **`ORDER BY` inside `-q` fails.** jira-cli appends its own clause and the
  server answers `400 Bad Request: Expecting ',' but got 'ORDER'`. Sort with
  `--order-by`, or leave the rows unsorted.

Default page size for these listings is `--paginate 15`; the CLI default of 8
silently truncates a normal week.

For anything that needs the reasoning, not the title, read the ticket:

```bash
jira issue view PROJ-123 --comments 5 --plain
```

Comments are where decisions and their owners live. A decision without a named
decision maker is not a decision, it is a rumour — go find who approved it, or
leave the item out.

### Decisions recorded in the description

This project records decisions as `Update <YYYY-MM-DD>:` lines inside the
ticket description. Extract the ones that fall inside the reporting window:

```bash
for k in $KEYS; do
  curl -s -u "$E:$JIRA_API_TOKEN" "$S/rest/api/3/issue/$k?fields=description" \
  | jq -r '[.fields.description | .. | .text? // empty] | join("\n")' \
  | grep -oE 'Update *[0-9]{4}-[0-9]{2}-[0-9]{2} *:.*' \
  | awk -v k="$k" -v a="$WEEK_START" -v b="$WEEK_END" \
      '{ if (match($0,/[0-9]{4}-[0-9]{2}-[0-9]{2}/)) { d=substr($0,RSTART,RLENGTH);
         if (d>=a && d<=b) print k"\t"$0 } }'
done
```

A hit is a decision with a date but no author — the description carries no
`author` field. Name the decision maker from the user, or write the item
without a name and say the approval is not recorded on the ticket.

### Getting decisions into the record

The description convention works, but only after the fact. A decision written
as a **ticket comment at the moment it is taken** carries the author and the
timestamp for free, and the weekly gather picks it up with no parsing:

```bash
jira issue comment add PROJ-123 --template /tmp/decision.md
```

Suggest this once when a decision surfaces in conversation. Do not lecture
about it in the report.

## 3. Where the report goes

**A file in the project working directory, and only its path in the reply.**

```
./weekly-update-<WEEK_START>_<WEEK_END>.txt      e.g. weekly-update-2026-08-31_2026-09-06.txt
```

That is the project directory the assistant was started in — `pwd` at the
start of the session. Do not choose another, do not create a folder for it, do
not put it in a temporary directory, and never write it under `~/.claude`,
`~/.codex` or `~/.config/opencode`: those hold the skill, not the work.

- **Plain text, `.txt`.** No Markdown: no `**bold**`, no backticks, no `#`
  headings, no tables, no bullet characters other than a plain `-`. The section
  markers are emoji, exactly as below, because the destination renders them.
- **Never overwrite.** The name exists already → write
  `weekly-update-<WEEK_START>_<WEEK_END>-2.txt`, then `-3`, and say which one
  was written.
- **Do not print the report in the reply.** Not the whole thing, not the first
  lines, not a summary of it. The answer is one line:

  ```
  weekly-update-2026-08-31_2026-09-06.txt
  ```

  Add at most one short sentence when something needs a decision — a section
  left empty for lack of input, a second file written because the first
  existed. Everything else the reader gets by opening the file.

The reason is not tidiness: the report is written to be read once, in the tool
it is pasted into. Printing it twice makes the chat the place people read it
from, and the file goes stale the moment the draft is corrected.

## 3a. Structure

```
Engineering Weekly Update — <area / component> — <Month D, YYYY>
Boards: <PROJECT>

🚩 Decisions Needed
🆘 Escalations / Help Needed
✅ What went well
⚠️ What didn't go well / Risks
📌 Key decisions made this week
🔭 Next week
```

Section by section:

- **🚩 Decisions Needed** — open questions that block work and need someone
  else to answer. `None this week.` when there are none. Do not invent items.
- **🆘 Escalations / Help Needed** — where the team is stuck and needs a
  person, an access, or a priority call. Same rule.
- **✅ What went well** — one paragraph per item, starting with the key and
  the ticket title in quotes, then a short label of the nature of the work
  (`Query optimization`, `Production issue investigation`, `Cross-team
  coordination`), then what was investigated or built and what came out of it.
  Work with no ticket — coordination, sprint scoping, reviews — gets a
  paragraph with a label instead of a key. Past tense, no first person.

  **A ticket that was in flight during the window belongs here even if nothing
  moved on the board.** `status WAS "<STATUS_IN_PROGRESS>" DURING (...)` is the
  list; a status change is not required. Write what the ticket is about and say
  plainly that it is in progress. Do not invent progress, do not claim an
  outcome the ticket does not show, and do not pad the paragraph to match the
  finished items — two honest sentences are the right length.

  The one case where an in-flight ticket is *not* written up as work: the
  window is an absence. Then it is named as carried, in the single line that
  section 1a describes.
- **⚠️ What didn't go well / Risks** — one line per risk, prefixed with a
  severity marker (🔴 / 🟡), naming the ticket where there is one. Each item
  states **Impact:** and **Mitigation:**. A risk belongs here only when it
  comes out of the work done this week: something that failed, blocked,
  regressed, or was left unresolved in a task that was actually worked on.
- **📌 Key decisions made this week** — what was decided, **Why:** the reason,
  **Decision maker:** the names. Include product decisions and scope decisions,
  not implementation details. Built from three sources, in order: ticket
  comments, `Update <date>:` lines in descriptions that fall inside the
  window, and whatever the user supplies from meetings and chat.

  When none of the three yields anything, the section says so **and states
  what the week was spent on instead**, so the absence of decisions does not
  read as an absence of work:

  ```
  No new decisions this week; work continued within the scope already agreed
  for PROJ-123 and PROJ-124.
  ```

  Name the tickets that were actually worked on in the window — the same ones
  that appear under What went well. Two or three keys, no more; beyond that
  write "the agreed sprint scope" without the list.

  Use the short form alone —

  ```
  No new decisions this week.
  ```

  — only when there was genuinely no work to point at: a vacation week, a
  holiday week, or a week whose whole scope sat untouched. Never claim
  continued work during an absence.

  Always this wording. Not "none recorded", not "nothing was documented" —
  those read as a complaint about bookkeeping and put the reader on the
  defensive about a process they own. A week with no decisions is an ordinary
  week.
- **🔭 Next week** — planned work as an action with an **Owner:** on each item.
  Not a wish list: only work that is actually committed.

## 3b. Facts of the week only — never board hygiene

The report states what was worked on and what came out of it. It is **not** an
audit of the board. Ticket metadata is not a finding.

Never write, in any section:

- how long a ticket has been open, or how many sprints it has been carried
  through
- that a ticket's fields are empty, contain `None`, or are poorly filled
- that no comments, transitions or updates were recorded in the window
- estimate accuracy, story-point totals as a judgement, or velocity commentary
- anything else derived from *the state of the tracker* rather than from
  *the work*

These read as an accusation, they are usually an artefact of how the team uses
Jira, and they push the reader's attention off the engineering content. If the
week genuinely produced nothing to report, say so in one line and leave the
other sections at `None this week.` A short honest report is fine; a padded
one is not.

Ticket hygiene worth fixing is raised with the user directly, outside the
report.

**This is not a rule against mentioning open work.** That a ticket was in
progress during the window is a fact about the work, and it belongs in What
went well — see that section. What is banned is the tracker's *bookkeeping*:
ages, carry-over counts, empty fields, missing comments. The test is simple —
would the sentence survive if the team used a whiteboard instead of Jira? "The
gateway rollout is in progress" survives. "This has been open since November"
does not.

## 4. Style rules

- Neutral, factual, third person. No "I", no marketing adjectives, no emoji
  beyond the section markers.
- Ticket keys always in the form `PROJ-123` followed by the title in quotes.
- A paragraph explains the *outcome*, not the activity: "identified the
  performance limitation and addressed it" rather than "worked on the ticket".
- Findings discovered mid-investigation belong in the same paragraph as the
  ticket that produced them — that is how scope growth becomes visible.
- Never claim something is fixed unless a ticket, a comment or a command
  output says so. Partially resolved goes under Risks, with what remains.
- Length: an item that needs more than four sentences is probably two items.
- **The file is plain text.** Labels that appear in bold in this reference —
  Impact, Mitigation, Why, Decision maker, Owner — are written as
  `Impact:` in the file, with no asterisks and no backticks. Wrap at about 80
  characters so it stays readable in a plain-text field.

## 5. Before writing the file

- Every key in the report exists and its status matches what the report claims.
- Every named decision maker actually appears in the ticket or was confirmed
  by the user.
- `None this week.` appears only where it was checked, not where it was
  convenient.
- The date came from `date -I` in this session.
- No Markdown survived into the text: no `**`, no `` ` ``, no `#`, no table
  pipes.
- The reply carries the path and nothing of the content.
