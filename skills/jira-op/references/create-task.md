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

The create screen rejects a ticket without `summary`, `project`, `issuetype`
and whatever else `createmeta` marks `required` — for this project that
includes `<CF_RISKS>` and `<CF_ACCEPTANCE>`. The other rows below are the
team's working convention, not an API constraint: the API accepts a ticket
without them, the team does not.

| Field | Value | How it is set |
|---|---|---|
| Summary | one line, what was done | `-s` on create |
| Status | `In Progress` | `jira issue move` after create |
| Assignee | <YOUR NAME> (`<ACCOUNT_ID>`) | `-a$(jira me)` on create |
| Reporter | <YOUR NAME> | defaults to the token owner; see below |
| Sprint | current `<SPRINT_PREFIX> N` — confirm with the user | `jira sprint add` after create |
| Story Points | **ask the user**, no default | `--custom story-points=<N>` |
| Potential Risks | free text, never empty | `--custom potential-risks=...` |
| Acceptance Test | free text, never empty | `--custom acceptance-test=...` |

Custom field ids for this project — the real values live in `SITE.md`:

| Field | Id | Type |
|---|---|---|
| Story Points | `<CF_STORY_POINTS>` | number |
| Sprint | `<CF_SPRINT>` | array |
| Potential Risks | `<CF_RISKS>` | string |
| Acceptance Test | `<CF_ACCEPTANCE>` | string |
| Epic Name | `<CF_EPIC_NAME>` | string |
| Epic Link | `<CF_EPIC_LINK>` | string |

`jira issue create --custom <key>=<value>` takes the field **name**,
lowercased with spaces as hyphens — `story-points`, `potential-risks`,
`acceptance-test` — not the `customfield_*` id. The ids matter for REST calls
and for reading values back.

## Confirm what the create screen really requires

Field configuration changes without notice. Before the first create of a
session, and whenever a create fails on a field, ask the API which fields are
required for the issue type:

```bash
set -a; . ~/.config/.jira/token.env; set +a
EMAIL=$(jira me)
SITE=https://example.atlassian.net

# issue type ids for <PROJECT>
curl -s -u "$EMAIL:$JIRA_API_TOKEN" \
  "$SITE/rest/api/3/issue/createmeta/<PROJECT>/issuetypes" \
  | jq -r '.issueTypes[] | "\(.id)\t\(.name)"'

# required fields for one issue type (substitute the id)
curl -s -u "$EMAIL:$JIRA_API_TOKEN" \
  "$SITE/rest/api/3/issue/createmeta/<PROJECT>/issuetypes/<TYPE_ID>" \
  | jq -r '.fields[] | select(.required) | "\(.fieldId)\t\(.name)"'
```

The list this returns wins over the table above.

## Procedure

**0. Ask for the values that have no safe default:** the story points, which
sprint, and — optionally — an End Date. Nothing here may be guessed. Do not ask
about the epic; see "Fields that are not on the create screen" below.
Everything written into the ticket is English — translate the user's Russian
input and show the English draft for approval.

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

**3. Create:**

```bash
jira issue create --no-input \
  -p<PROJECT> -t"<ISSUE_TYPE>" \
  -s"<summary>" \
  -a"$(jira me)" \
  -b"$(cat /tmp/op_body.md)" \
  --custom story-points=<N> \
  --custom potential-risks="<risks>" \
  --custom acceptance-test="<how it is verified>"
```

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

## Editing Potential Risks / Acceptance Test on an existing ticket

Both are `textarea` custom fields (`customfieldtypes:textarea`), and Jira
Cloud may store them as ADF documents rather than plain strings:

```json
{"<CF_RISKS>":{"type":"doc","version":1,
 "content":[{"type":"paragraph","content":[{"type":"text","text":"None"}]}]}}
```

`editmeta` reports `operations: ["set"]` for both, so an edit overwrites the
whole value. Read the current value first and show it to the user — there is
no undo.

The straightforward path is the **v2 API**, which accepts plain text for these
fields and does the ADF conversion server-side:

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

`jira issue edit <KEY> --custom potential-risks="..."` exists and is shorter,
but it sends a plain string to the v3 endpoint, which rejects ADF fields. Try
it only if the REST path is unavailable, and check the exit status.

Add `--skip-notify` to `jira issue edit`, or accept that every watcher gets a
mail for a field cleanup.

## Values that are never empty

`Potential Risks` and `Acceptance Test` are mandatory on this screen, so a
placeholder is tempting. Do not write `N/A`. If there is genuinely no risk,
say what makes it low — "config-only change, no runtime path touched" — and
for the acceptance test, name the command or the observation that proves the
work: what was run, where, and what it printed.
