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
jira issue list -q"project = <PROJECT> AND assignee = currentUser() AND updated >= \"$WEEK_START\" AND updated < \"$NEXT_MON\" AND status NOT IN (<STATUS_NEW>)" \
  --plain --columns key,type,status,summary,updated --paginate 15

# what closed in the window — every status in the Closed group, not just one:
# a ticket closed as Duplicate closed
jira issue list -q"project = <PROJECT> AND assignee = currentUser() AND status CHANGED TO (<STATUS_TERMINAL>) DURING (\"$WEEK_START\", \"$NEXT_MON\")" \
  --plain --columns key,status,summary --paginate 15

# what was in flight at any point in the window — the backbone of the report.
# Every working status, not only "In Progress": a week spent in Team Review or
# Blocked is a week of work, and on some boards the ticket never passes through
# a status literally called In Progress at all.
jira issue list -q"project = <PROJECT> AND assignee = currentUser() AND status WAS IN (<STATUS_ACTIVE>) DURING (\"$WEEK_START\", \"$NEXT_MON\")" \
  --plain --columns key,status,summary --paginate 15

# what is still open right now and carries into next week
jira issue list -q'project = <PROJECT> AND assignee = currentUser() AND status IN (<STATUS_ACTIVE>)' \
  --plain --columns key,status,summary --paginate 15

# the sprint the week belongs to
jira sprint list --state active --plain
```

Two constraints on these queries:

- **Unstarted work never appears in the report** — not in What went well, not
  in Risks, not in Decisions Needed. That is the whole `To Do` **category**
  (`statusCategory` `new`), which on some boards is nine status names, not one.
  Filter it out at the query, so it cannot leak in through a carried-over
  ticket.
- **Statuses come in three groups, and `SITE.md` lists them** —
  `<STATUS_NEW>` (unstarted), `<STATUS_ACTIVE>` (working) and
  `<STATUS_TERMINAL>` (closed), exactly as Jira categorises them. Use the groups,
  never a single hardcoded name: `In Progress` and `Done` do not exist on every
  board, and a ticket that sat in `Ready for QA` all week did not stop being
  worked on.
- **`ORDER BY` inside `-q` fails.** jira-cli appends its own clause and the
  server answers `400 Bad Request: Expecting ',' but got 'ORDER'`. Sort with
  `--order-by`, or leave the rows unsorted.

Default page size for these listings is `--paginate 15`; the CLI default of 8
silently truncates a normal week.

For a ticket that runs across several weeks, the week's delta comes from its
changelog — see section 3c. Do not build the report on the previous report
file: it is an ordinary file in a working directory and may not be there.

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

  Two cases where an in-flight ticket is *not* written up as work here. The
  window is an absence — then it is named as carried, in the single line that
  section 1a describes. Or the ticket has already appeared in earlier reports
  and nothing moved this week — then section 3c applies and it goes to
  `🔭 Next week` as one line.
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

## 3c. A ticket that spans many weeks

Infrastructure work runs for a month or more, so the same key appears in report
after report. What makes that read as a stalled ticket is not its length — it
is the paragraph repeating itself. Section 3b already bans the tracker facts
that would say "this is old"; this section is about the sentence that says it
by accident.

**Such a ticket is not split up to make the report easier.** One ticket
covering a month of scheduled work is a legitimate shape, and the report adapts
to it rather than the other way round. Do not propose sub-tasks or phase
tickets for reporting reasons; propose them only when the *work* needs separate
owners, sprints or estimates.

**It appears in every report that its window touches — without exception.**
A long ticket that quietly drops out of a report reads as abandoned, and the
next report that mentions it has to explain a gap that never existed. It is in
`✅ What went well` when something moved, in `🔭 Next week` when nothing did,
and in `⚠️ Risks` or `🚩 Decisions Needed` when something holds it. Never in
none of them.

**Recognise the shape from the ticket, not from a list of keys.** Any one of
these is enough, and all three come from Jira:

- its End Date or target date falls beyond the end of the window being reported;
- it entered a working status before the window started — the changelog dates
  that;
- it has carried across more than one sprint, which the changelog also dates.

**The baseline is the changelog, not the last report.** Everything that carries
a timestamp inside the window is this week; everything older was reported
before, by construction. Nothing needs to be remembered and nothing needs to be
compared against a file:

```bash
curl -s -u "$EMAIL:$JIRA_API_TOKEN" \
  "$SITE/rest/api/3/issue/<KEY>/changelog?maxResults=100" > /tmp/cl.json

jq -r --arg a "$WEEK_START" --arg b "$NEXT_MON" '
  .values[]
  | select(.created[0:10] >= $a and .created[0:10] < $b)
  | .created[0:10] as $d
  | .items[]
  | "\($d)  \(.field)  \((.fromString//"")|length) -> \((.toString//"")|length)"
' /tmp/cl.json
```

A text edit stores **both** versions in full, so the week's additions are a
plain diff — the `fromString` of the first change in the window against the
`toString` of the last. The field name is a parameter, so the same pair of
commands works for the description and for any text custom field the first
listing showed as changed:

```bash
F=description            # the field name exactly as the first listing printed it
                         # system fields are lower-case; a custom field is its
                         # display name, e.g. "Potential Risks"

jq -r --arg a "$WEEK_START" --arg b "$NEXT_MON" --arg f "$F" '
  [ .values[] | select(.created[0:10] >= $a and .created[0:10] < $b)
    | .items[] | select(.field == $f) ] as $d
  | if ($d|length) == 0 then "" else ($d[0].fromString // "") end' /tmp/cl.json > /tmp/before.txt

jq -r --arg a "$WEEK_START" --arg b "$NEXT_MON" --arg f "$F" '
  [ .values[] | select(.created[0:10] >= $a and .created[0:10] < $b)
    | .items[] | select(.field == $f) ] | last | .toString // ""
' /tmp/cl.json > /tmp/after.txt

diff /tmp/before.txt /tmp/after.txt | grep '^>'
```

Measured: a ticket whose description went from 5 lines to 66 inside one window
returned exactly the 61 added lines.

The changelog labels a field by **name**, never by id: lower-case for system
fields, the display name for custom ones. Take it from the first listing rather
than guessing.

A heading in the create screen is not a field. Text typed under a section
heading normally lands in the description, and the changelog is what settles
which field actually moved — measured once where a similarly named custom field
existed in the project, was absent from the create screen, and was `null` on
every ticket.

A previous report file, if one is still on disk, is a convenience for wording —
never the source. Files get deleted and directories move; the changelog is the
record.

**One consequence worth stating:** the window is the *record* date, not the day
the work happened. Work done in week 1 and written into the ticket in week 3
belongs to week 3's report. That is the honest reading — it is when the fact
entered the record — and it is another reason to write the ticket as the work
runs.

**The paragraph reports the week's delta, not the ticket.** What the ticket is
about is stated once, in the first report it appears in. After that the
paragraph opens with what changed inside the window:

```
week 1  PROJ-123 "Gateway controller implementation": Gateway API objects
        declared for all five entrypoints and applied with every entrypoint
        disabled — an empty plan, nothing switched yet.
week 2  PROJ-123: first entrypoint switched, DNS weight raised to 10 for one
        host; no change in 5xx on either data plane.
week 3  PROJ-123: two of five entrypoints fully migrated, the nginx side
        drained.
```

**Carry a count when the work has countable parts** — entrypoints, clusters,
services, migrations. "Two of five" moves on its own from week to week and
shows a rate; prose about the same subject does not. The count is a fact of the
work, not tracker bookkeeping, so 3b does not touch it.

**Where the delta comes from**, in order: comments written in the window,
`Update <date>:` lines in the description dated inside it, the changelog, and
what the user says. If all four are empty, do not restate the ticket in new
words — ask the user what moved. A paragraph assembled without a source is how
an invented outcome gets into a report.

**When the user keeps the ticket current, the ticket is the source.** Some
tickets are maintained as the work runs: the user asks for the real work to be
written into the description as it happens, so the description accumulates
dated blocks. For those, the week's delta is whatever carries a date inside the
window — no interviewing needed, and nothing that is not there may be added.

Report it as an outcome, in the report's own words. Never paste the ticket text
into the file: the ticket is written for whoever implements it, the report for
whoever reads the week, and the two need different sentences. Two or three
sentences per ticket, the same length as any other item.

If the description grew inside the window but names no result — a path added,
a scope note, a link — that is still a fact of the week and gets one sentence
saying what was established, not a claim that something was delivered.

**A week with no movement is one line, not a paragraph** — and one line means
the ticket is still in the report. It goes to `🔭 Next week` as the committed
next step, and is left out of `✅ What went well` for that week only. Repeating
last week's paragraph is exactly the effect this section exists to prevent;
dropping the ticket altogether is the other one.

**Two such weeks in a row are a finding, not a line.** Something is holding the
work: a decision, an access, another team, a window that never opened. Name it
in `🚩 Decisions Needed` or in `⚠️ Risks` with its Impact and what would
unblock it. A named blocker reads as control of the situation; a third
identical paragraph reads as drift.

**Leave the trace during the week, not on Friday.** One comment on the ticket
at the end of the week — two or three sentences, what changed — makes the next
report mechanical: last week's comment against this week's. It is also the only
source that survives a compacted session.

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
