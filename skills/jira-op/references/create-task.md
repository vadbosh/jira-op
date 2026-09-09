# Creating an <PROJECT> ticket for work already done

The common case in this project: work is finished, and a ticket has to exist
to record it. The ticket is created, filled, moved to `In Progress`, and put
in the active sprint.

## Issue type

`<ISSUE_TYPE>` (id `<TYPE_ID>`) — the type this project's tickets use, from
`SITE.md`. Do not assume `Task` or `Story` exist: a project may have neither,
and offer its own types instead. The list is per project:

```bash
curl -s -u "$E:$JIRA_API_TOKEN" "$SITE/rest/api/3/issue/createmeta/<PROJECT>/issuetypes" \
  | jq -r '.issueTypes[] | "\(.id)\t\(.name)"'
```

Each type has its own required set. A recipe written for one type does not
transfer to its neighbour — re-read `createmeta` before filing a different
kind of ticket.

## Mandatory fields

**Do not copy a field list from anywhere, including this file.** Custom fields
are per project and per issue type: a field that is required here may not exist
at all in the next project, and passing `--custom` for a field that does not
exist fails the create.

Three fields are required everywhere — `summary`, `project`, `issuetype`.
Everything else comes from `createmeta`, and it is the only authority:

```bash
set -a; . ~/.config/.jira/token.env; set +a
E=$(jira me); SITE=<SITE>

curl -s -u "$E:$JIRA_API_TOKEN" \
  "$SITE/rest/api/3/issue/createmeta/<PROJECT>/issuetypes/<TYPE_ID>" \
  | jq -r '.fields[] | select(.required) | "\(.fieldId)\t\(.name)"'
```

### The ids are what the create uses

The create goes through REST (see Procedure), so the `customfield_*` ids above
are what the request carries — nothing has to be derived.

`--custom` on the CLI is the other convention: it takes the field **name**,
lowercased with spaces replaced by hyphens. Only needed on the CLI fallback,
and this prints both, so neither is typed by hand:

```bash
curl -s -u "$E:$JIRA_API_TOKEN" \
  "$SITE/rest/api/3/issue/createmeta/<PROJECT>/issuetypes/<TYPE_ID>" \
| jq -r '.fields[] | select(.required) | select(.fieldId|startswith("customfield_"))
    | "  --custom \(.name|ascii_downcase|gsub(" ";"-"))=\"...\"   # \(.fieldId), \(.schema.custom|split(":")|last)"'
```

On the project this was written against it prints two lines; on the neighbouring
issue type in the *same* project it prints two entirely different ones. That is
the reason this is a command and not a table.

### A required field is not always free text

The generator prints the field's type after the id. It decides how the value is
written:

- `textfield`, `float`, `datepicker` — pass the value as it is.
- `select`, `radiobuttons`, `multiselect` — only a listed option is accepted.
  Ask for the options, and never invent one:
  ```bash
  curl -s -u "$E:$JIRA_API_TOKEN" \
    "$SITE/rest/api/3/issue/createmeta/<PROJECT>/issuetypes/<TYPE_ID>" \
  | jq -r '.fields[] | select(.required) | select(.allowedValues)
      | "\(.name): " + ([.allowedValues[] | .value // .name] | join(", "))'
  ```
- `textarea` — may be stored as an ADF document rather than a string. `create`
  handles it; a later **edit** does not, see the section on editing below.

When a required field has no sensible value from the work being recorded, ask
the user. Do not fill it with `N/A` to get past the create screen.

### Team convention on top of the API

These are not API-required, and the create still succeeds without them — the
team is what requires them. Values live in `SITE.md`.

| Field | Value | How it is set |
|---|---|---|
| Summary | one line, what was done | `-s` on create |
| Status | `<STATUS_IN_PROGRESS>` | `jira issue move` after create |
| Assignee | the token owner | `-a$(jira me)` on create |
| Reporter | the token owner | automatic; see below |
| Sprint | current `<SPRINT_PREFIX> N` — confirm with the user | `jira sprint add` after create |
| Story Points | **ask the user**, no default | `--custom story-points=<N>` |

`Story Points` is itself a custom field and is not guaranteed to exist either.
If the generator above does not list it and `jira issue create --custom
story-points=…` is rejected, the project does not use estimation — say so and
drop the flag rather than hunting for an id.

## Procedure

The create goes through **REST**, not through `jira issue create`. That is not
a preference: the CLI hangs when stdin is not a terminal, which is every
command an assistant, a CI job or an editor plugin runs — see "Why not the
CLI" below. The CLI stays for reads and for transitions, where it is the
shorter tool.

**The summary is generic; the detail lives in the body.**

A summary names the work, not its parameters. Cluster counts, version numbers,
component lists, hostnames, ticket-specific values — none of that belongs in
the title; it belongs in the description and the fields, which is what the
issue view groups under *Key details*.

```
good   Scheduled EKS cluster maintenance
good   Terraform (IaaC) tasks: current and permanent
bad    Scheduled EKS maintenance: node AMI and add-on updates across three clusters
bad    Rotate passwords for 47 users in us-east-1 before 2026-09-30
```

Two reasons it matters here. A board is read at a glance, and a title carrying
four facts is read as none. And a detail in the title goes stale the moment the
work changes — three clusters become four, and the title now lies while the
description is still right.

**0. Ask three questions before drafting.** All three in one go, and none of
them guessed:

| Ask | Why it cannot be defaulted |
|---|---|
| **Story points** | the estimate is the author's, not the tool's |
| **Which sprint** | boards keep stale sprints `active` and the current one may not be open yet |
| **End Date** | a date nobody set is better than a date invented; `none` is a valid answer |

`End Date` is asked every time, not offered as an afterthought — it is the
field a team lead reads first when scanning a board, and it cannot be set on
the create screen, so forgetting it means a second write later.

Do not ask about the epic; see "Fields that are not on the create screen"
below. Everything written into the ticket is English — translate the user's
Russian input and show the English draft for approval.

**1. Write the description as a file, in Jira wiki markup.**

The description reaches Jira through the v2 API, which converts plain text
server-side — by **wiki** rules, not Markdown. `## Scope` becomes a numbered
list; `**bold**` stays literal asterisks. Measured on a real create: a Markdown
body produced `orderedList, paragraph, orderedList, bulletList…` where headings
were meant.

```bash
cat > /tmp/op_body.txt <<'EOF'
h3. Context

Why this exists now, and what happens today.

h3. Scope

* What must be true when this is done.
* One bullet per outcome, not per keystroke.

h3. Out of scope

* The neighbouring work this ticket deliberately does not cover.

h3. Acceptance criteria

* {{terraform plan}} reports no pending changes.
* {{kubectl get nodes}} shows every node Ready.

h3. Notes

Anything the implementer needs and nobody would guess.
EOF
```

Wiki markup in one line: `h3.` heading, `*` bullet, `#` numbered, `{{code}}`
inline, `{code}…{code}` block, `[text|url]` link, `*bold*`, `_italic_`.

**2. Print the whole draft and wait.** Not a summary of it, not "drafted a
ticket about X" — the text that is about to be sent, in the reply, so the user
reads exactly what will exist:

```
Summary:      <one line>
Type:         <ISSUE_TYPE>        Assignee: <who>
Sprint:       <name (id)>         Points: <N>        End Date: <date | none>

Description:
<the full body, as written>

Potential Risks:
<the full text>

Acceptance Test:
<the full text>
```

**Every field, including the ones the assistant wrote itself.** Risks and
acceptance criteria are usually drafted from the work rather than dictated —
that is fine, and it is exactly why they have to be read before they are
published. A field nobody read is a field nobody agreed to.

This is the one thing the report of the create cannot make up for. Afterwards
the text is on a board other people watch, and on most accounts here it cannot
be deleted: `DELETE_ISSUES: false` (see `SITE.md`). Never create a ticket to
test the recipe.

A clone of an existing ticket is not an exception. "Same as PROJ-123" hides
whichever sentence was rewritten, and the rewrite is the part worth reading.

**3. Find the sprint id.** A board accumulates sprints left in state `active`
by other teams, sometimes years after they ended, so `--state active` alone
picks the wrong one. Take the sprint whose name starts with `<SPRINT_PREFIX>`
**and** whose date window contains today:

```bash
set -a; . ~/.config/.jira/token.env; set +a
TODAY=$(date -I); E=$(jira me); SITE=<SITE>
curl -s -u "$E:$JIRA_API_TOKEN" \
  "$SITE/rest/agile/1.0/board/<BOARD_ID>/sprint?state=active" \
| jq -r --arg d "$TODAY" '.values[]
    | select(.name | startswith("<SPRINT_PREFIX>"))
    | select(.startDate[:10] <= $d and .endDate[:10] >= $d)
    | "\(.id)\t\(.name)\t\(.startDate[:10])..\(.endDate[:10])"'
```

Empty result means no sprint is currently open — it happens on the day one
window closes and the next has not been started. Ask; do not drop the ticket
into a stale sprint, and do not silently create it outside every sprint.

**4. Create.** One request, every required field in it:

```bash
jq -n \
  --arg summary "<summary>" \
  --arg desc    "$(cat /tmp/op_body.txt)" \
  --arg risks   "<risks>" \
  --arg acc     "<how it is verified>" \
  '{fields:{
     project:   {key: "<PROJECT>"},
     issuetype: {id:  "<TYPE_ID>"},
     summary:   $summary,
     description: $desc,
     assignee:  {id: "<ACCOUNT_ID>"},
     <CF_STORY_POINTS>: <N>,
     <CF_RISKS>:      $risks,
     <CF_ACCEPTANCE>: $acc
  }}' > /tmp/op_create.json

curl -s -X POST -u "$E:$JIRA_API_TOKEN" -H 'Content-Type: application/json' \
  --data-binary @/tmp/op_create.json "$SITE/rest/api/2/issue" \
  | jq -c '{key, errors, errorMessages}'
```

`/rest/api/2/`, deliberately: v2 accepts plain strings for the ADF text fields
and converts them. v3 rejects a string where it wants a document.

A `400` comes back with `errors` naming the field — read it rather than
guessing. A timeout is the one case that needs care: **read before retrying**,
the ticket may already exist.

```bash
jira issue list -q'project = <PROJECT> AND reporter = currentUser() AND created >= "'"$(date -I)"'"' \
  --plain --no-headers --columns key,summary --paginate 5
```

**5. Put it in the sprint:**

```bash
jira sprint add <SPRINT_ID> <KEY>
```

**6. Set the End Date** if one was given — it is not on the create screen:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X PUT -u "$E:$JIRA_API_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"fields":{"<CF_END_DATE>":"YYYY-MM-DD"}}' "$SITE/rest/api/2/issue/<KEY>"
```

`204` means applied.

**7. Move it to the right status.** A ticket recording finished work goes to
`<STATUS_IN_PROGRESS>` or straight to `<STATUS_DONE>`; a ticket describing work
about to start stays where the create left it. Ask if it is not obvious from
what the user said — the status is what a team lead reads first.

```bash
jira issue move <KEY> "<STATUS_IN_PROGRESS>"
```

Transition names are per-workflow and listed in `SITE.md`. `Done` frequently
does not exist; `Completed`, `Closed` and localised names are all common.

**8. Read back and report.** An exit code is not evidence:

```bash
curl -s -u "$E:$JIRA_API_TOKEN" \
  "$SITE/rest/api/3/issue/<KEY>?expand=renderedFields&fields=summary,status,assignee,<CF_STORY_POINTS>,<CF_SPRINT>,<CF_END_DATE>,<CF_RISKS>,<CF_ACCEPTANCE>" \
  | jq -r '.fields | "status: \(.status.name)  points: \(.<CF_STORY_POINTS>)  end: \(.<CF_END_DATE> // "-")"'

# headings survived the conversion?
curl -s -u "$E:$JIRA_API_TOKEN" "$SITE/rest/api/3/issue/<KEY>?fields=description" \
  | jq -r '[.fields.description.content[] | if .type=="heading" then "H(\(.content[0].text))" else .type end] | join(", ")'
```

Report the stored status, assignee, sprint, points and End Date, plus one line
saying the ticket is not linked to an epic.

## Why not the CLI

`jira issue create` hangs forever when stdin is not a terminal — a subprocess,
a CI runner, an editor integration. `StdinHasData()` returns true for any
non-terminal descriptor, including the socket a subprocess gets, and the CLI
then blocks in `io.ReadAll(os.Stdin)`. `--no-input` skips the TUI, not this
path. Upstream:
[ankitpokhrel/jira-cli#948](https://github.com/ankitpokhrel/jira-cli/issues/948),
open, reproduced on 1.7.0:

```
$ timeout 15 jira issue create -pPROJ -t"..." -s"probe" -b"x" --no-input
rc=124                          # hung, nothing created

$ timeout 15 jira issue create ... --no-input </dev/null
jira: Received unexpected response '400 Bad Request'.
rc=1                            # reached the API
```

So the CLI *can* create with `</dev/null` appended. It is still the second
choice: the redirect is easy to forget, the failure mode is a silent hang
rather than an error, and `--custom` takes field names that have to be derived
while REST takes the ids `createmeta` already printed.

**The same redirect applies to every CLI command that might ask a question** —
`issue edit`, `comment add`, `issue move` with no state given. Append
`</dev/null` there too.

## Fields that are not on the create screen

`Epic Link` (`<CF_EPIC_LINK>`) and `End Date` (`<CF_END_DATE>`) exist on
this project's tickets but are absent from its create screen — found by
diffing the populated fields of six tickets against `createmeta`. They can only
be set after the ticket exists.

**Epic Link — never set it.** There is no default epic in this project, and
whether a task belongs to one is decided case by case by someone who knows the
current epic structure. Do not guess, do not ask for the epic on every create,
do not offer a list. Say one line in the final report — *the ticket is not
linked to an epic* — and leave it; attaching it in the UI takes seconds and is
the user's call.

**End Date — ask, once, and accept "no".** It is optional. When a date is
given:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X PUT -u "$E:$JIRA_API_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"fields":{"<CF_END_DATE>":"2026-09-30"}}' \
  "$S/rest/api/2/issue/PROJ-123"
```

`204` means applied. Format is `YYYY-MM-DD`.

## Reporter

`jira issue create` has no reporter flag: the reporter is the account that
owns the API token, which is already <YOUR NAME>. Nothing to do in the normal
case.

If a ticket ever needs a different reporter, and the account has the
*Modify Reporter* permission:

```bash
curl -s -X PUT -u "$EMAIL:$JIRA_API_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"fields":{"reporter":{"id":"<ACCOUNT_ID>"}}}' \
  "$SITE/rest/api/3/issue/PROJ-123"
```

## Editing a textarea custom field on an existing ticket

Check the storage format before writing — it is per field, and it decides
which API to use:

```bash
curl -s -u "$E:$JIRA_API_TOKEN" "$SITE/rest/api/3/issue/<KEY>?fields=<FIELD_ID>" \
  | jq -r '.fields.<FIELD_ID> | type'
```

`string` — the v3 API accepts a plain string. `object` — it is an ADF document,
and v3 rejects a plain string for it. Example of what `object` looks like:

```json
{"<CF_RISKS>":{"type":"doc","version":1,
 "content":[{"type":"paragraph","content":[{"type":"text","text":"None"}]}]}}
```

`editmeta` says what an edit may do to the field. `operations: ["set"]` means
an edit overwrites the whole value. Read the current value first and show it to the user — there is
no undo.

For an ADF field the straightforward path is the **v2 API**, which accepts
plain text and does the conversion server-side:

```bash
set -a; . ~/.config/.jira/token.env; set +a
S=https://example.atlassian.net; E=$(jira me)

curl -s -o /dev/null -w '%{http_code}\n' -X PUT -u "$E:$JIRA_API_TOKEN" \
  -H 'Content-Type: application/json' \
  --data-binary @/tmp/op_fields.json \
  "$S/rest/api/2/issue/PROJ-123"
```

with `/tmp/op_fields.json` written by `jq` so quoting and newlines survive:

```bash
jq -n --arg risks "$(cat /tmp/risks.txt)" --arg acc "$(cat /tmp/acceptance.txt)" \
  '{fields:{<CF_RISKS>:$risks, <CF_ACCEPTANCE>:$acc}}' > /tmp/op_fields.json
```

`204` means applied. Read the value back and show what is now stored:

```bash
curl -s -u "$E:$JIRA_API_TOKEN" \
  "$S/rest/api/3/issue/PROJ-123?fields=<CF_RISKS>,<CF_ACCEPTANCE>" \
  | jq -r '.fields | to_entries[] | "\(.key): \([.value | .. | .text? // empty] | join(" "))"'
```

`jira issue edit <KEY> --custom <field-name>="..."` exists and is shorter, but
it sends a plain string to the v3 endpoint, which rejects ADF fields. It works
for a `string` field and fails for an `object` one — check the exit status
rather than assuming.

Add `--skip-notify` to `jira issue edit`, or accept that every watcher gets a
mail for a field cleanup.

## Values that are never empty

A required field the create screen will not let past is exactly where a
placeholder is tempting. Do not write `N/A`.

Two shapes recur across projects, whatever the field is called:

- **a risk field.** If the risk is genuinely low, say what makes it low —
  "config-only change, no runtime path touched" — not "none".
- **an acceptance or test field.** Name the command or the observation that
  proves the work: what was run, where, and what it printed. "Works" is not an
  acceptance criterion.

Both are read months later by someone deciding whether the ticket can be
closed. `N/A` makes that decision impossible and the field pointless.
