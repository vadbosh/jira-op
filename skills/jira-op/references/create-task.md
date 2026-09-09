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

### Generate the flags instead of typing them

`--custom` takes the field **name**, lowercased with spaces replaced by
hyphens. Deriving that by hand is where the typos live, so let the API write
the flags:

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

**1. Draft, and show the draft.** Nothing is created before the user approves
this specific ticket. **A create cannot be undone here** — the account has
`DELETE_ISSUES: false` on this project (see `SITE.md`), so a mistaken ticket stays
on the board until an administrator removes it. Never create a ticket to test
the recipe. Write the description to a file — the CLI mangles
multi-line strings on the command line:

```bash
cat > /tmp/op_body.md <<'EOF'
## What was done
...

## Why
...

## Evidence
- commit / MR / command output
EOF
```

**2. Find the sprint id.** A board accumulates sprints left in state `active`
by other teams, sometimes years after they ended, so `--state active` alone
picks the wrong one. Take the sprint whose name starts with `<SPRINT_PREFIX>`
**and** whose date window contains today:

```bash
set -a; . ~/.config/.jira/token.env; set +a
TODAY=$(date -I)
curl -s -u "$(jira me):$JIRA_API_TOKEN" \
  'https://example.atlassian.net/rest/agile/1.0/board/<BOARD_ID>/sprint?state=active' \
| jq -r --arg d "$TODAY" '.values[]
    | select(.name | startswith("<SPRINT_PREFIX>"))
    | select(.startDate[:10] <= $d and .endDate[:10] >= $d)
    | "\(.id)\t\(.name)\t\(.startDate[:10])..\(.endDate[:10])"'
```

Empty result means the sprint rolled over and none is open — ask the user
rather than dropping the ticket into a stale sprint.

**2a. `jira issue create` hangs when it is not run from a terminal.**

An assistant runs commands in a subprocess, so this is the normal case, not an
edge case. Measured on jira-cli 1.7.0:

```
$ timeout 15 jira issue create -pPROJ -t"..." -s"probe" -b"x" --no-input
rc=124            # nothing printed, nothing created — it hung

$ timeout 15 jira issue create -pPROJ -t"..." -s"probe" -b"x" --no-input </dev/null
jira: Received unexpected response '400 Bad Request'.
rc=1              # reached the API, which is the point
```

Upstream bug, open at the time of writing:
[ankitpokhrel/jira-cli#948](https://github.com/ankitpokhrel/jira-cli/issues/948).
`StdinHasData()` returns true for any non-terminal descriptor — including the
socket a subprocess gets — and the CLI then blocks in `io.ReadAll(os.Stdin)`
forever. `--no-input` does not help: the flag skips the TUI, not this path.

**Always redirect stdin: `</dev/null`.** It applies to `issue create`,
`issue edit` and `comment add` — anything that might ask a question.

If it hangs anyway, do not retry blindly: read first, the ticket may exist.
The REST path below has no such problem and is the more predictable choice for
a scripted create.

**2b. Creating through REST instead**

```bash
jq -n --arg summary "<summary>" --arg desc "$(cat /tmp/op_body.txt)" \
      --arg risks "<risks>" --arg acc "<acceptance>" \
  '{fields:{project:{key:"<PROJECT>"},issuetype:{id:"<TYPE_ID>"},
    summary:$summary, description:$desc,
    assignee:{id:"<ACCOUNT_ID>"}, <CF_STORY_POINTS>:<N>,
    <CF_RISKS>:$risks, <CF_ACCEPTANCE>:$acc}}' > /tmp/op_create.json

curl -s -X POST -u "$E:$JIRA_API_TOKEN" -H 'Content-Type: application/json' \
  --data-binary @/tmp/op_create.json "$SITE/rest/api/2/issue" \
  | jq -c '{key, errors, errorMessages}'
```

**v2, and the description is Jira wiki markup — not Markdown.** v2 converts
plain text server-side, which is what makes the ADF text fields easy, but it
reads the text by wiki rules: `## Scope` becomes a *numbered list*, not a
heading. Use `h3. Scope`, `*` for bullets, `{{code}}` for inline code. Measured:
a Markdown body produced `orderedList, paragraph, orderedList, bulletList…`
where headings were meant.

Check what actually landed before declaring it done:

```bash
curl -s -u "$E:$JIRA_API_TOKEN" "$SITE/rest/api/3/issue/<KEY>?fields=description" \
  | jq -r '[.fields.description.content[] | if .type=="heading" then "H(\(.content[0].text))" else .type end] | join(", ")'
```

**3. Create:**

```bash
jira issue create --no-input \
  -p<PROJECT> -t"<ISSUE_TYPE>" \
  -s"<summary>" \
  -a"$(jira me)" \
  -b"$(cat /tmp/op_body.md)" \
  --custom story-points=<N> \
  <the --custom lines the generator printed, filled in>
```

Nothing in that command is fixed except the first four lines. The `--custom`
flags are whatever `createmeta` said is required for **this** issue type, and
they change with the type.

Keep the returned key. If the command times out, **read before retrying** —
the ticket may already exist.

**4. Put it in the active sprint:**

```bash
jira sprint add <SPRINT_ID> PROJ-123
```

**5. Move to In Progress:**

```bash
jira issue view PROJ-123 --plain      # current status
jira issue move PROJ-123 "In Progress"
```

Transition names are per-workflow; the ones for this project are recorded in
`SITE.md`. Finished work is `<STATUS_DONE>`, which is frequently *not* `Done` —
`Completed`, `Closed`, `Resolved` and localised names are all common, and a
wrong name fails the move. Re-read the list for the specific issue whenever a
move is refused:

```bash
curl -s -u "$(jira me):$JIRA_API_TOKEN" \
  "https://example.atlassian.net/rest/api/3/issue/PROJ-123/transitions" \
  | jq -r '.transitions[] | "\(.id)\t\(.name)"'
```

**6. Read back and report:**

```bash
jira issue view PROJ-123 --plain
```

Report the stored status, assignee, sprint and story points, plus one line
saying the ticket is not linked to an epic. An exit code of 0 is not evidence
that the fields landed.

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
