# Site values

Copy this file to `SITE.md` next to it and fill it in. Everything else in the
skill refers to these names instead of hard-coding a site, so the skill works
against your Jira without editing five files.

`SITE.md` is git-ignored: it describes your instance, not this repository.

**Every value below comes from a command.** Do not guess any of them, and
re-run the command when a create or a transition starts failing — field
configuration changes without notice and nothing announces it.

```bash
set -a; . ~/.config/.jira/token.env; set +a
SITE=https://example.atlassian.net        # your site
E=$(jira me)
```

## Site and project

| Name used in the skill | Value | Where it comes from |
|---|---|---|
| `<SITE>` | `https://example.atlassian.net` | your browser's address bar |
| `<PROJECT>` | `PROJ` | the prefix of your issue keys, `PROJ-123` → `PROJ` |
| `<LOGIN>` | `you@example.com` | `jira me` |
| `<BOARD_ID>` | `1` | `jira board list -p <PROJECT>` |
| `<BOARD_NAME>` | `PROJ Sprint board` | same command; a scrum board, or sprint commands do nothing |
| `<ACCOUNT_ID>` | `5f…` | `curl -s -u "$E:$JIRA_API_TOKEN" "$SITE/rest/api/3/myself" \| jq -r .accountId` |

## Issue type

```bash
curl -s -u "$E:$JIRA_API_TOKEN" "$SITE/rest/api/3/issue/createmeta/<PROJECT>/issuetypes" \
  | jq -r '.issueTypes[] | "\(.id)\t\(.name)"'
```

| Name used in the skill | Value |
|---|---|
| `<ISSUE_TYPE>` | `Task` |
| `<TYPE_ID>` | `10001` |

The type name is not portable between projects. A project may have no `Task`
and no `Story` at all, and use something of its own instead.

## Required fields

```bash
curl -s -u "$E:$JIRA_API_TOKEN" \
  "$SITE/rest/api/3/issue/createmeta/<PROJECT>/issuetypes/<TYPE_ID>" \
  | jq -r '.fields[] | select(.required) | "\(.fieldId)\t\(.name)"'
```

Whatever this prints is the real list. Record it here, and note that the API
list and the team's expectations differ: assignee, sprint and story points are
often required by the team and optional to the API.

| Name used in the skill | Field id | Field name |
|---|---|---|
| `<CF_STORY_POINTS>` | `customfield_10016` | Story Points |
| `<CF_SPRINT>` | `customfield_10020` | Sprint |
| `<CF_RISKS>` | `customfield_…` | your project's risk field, if it has one |
| `<CF_ACCEPTANCE>` | `customfield_…` | your project's acceptance field, if it has one |
| `<CF_EPIC_LINK>` | `customfield_…` | Epic Link, when the project is company-managed |
| `<CF_END_DATE>` | `customfield_…` | End Date, if used |

`jira issue create --custom` takes the field **name**, lowercased with spaces
replaced by hyphens — `story-points`. The `customfield_*` id is what REST
calls need, and what a value read back is keyed by.

Check the storage format of any text field before writing to it:

```bash
curl -s -u "$E:$JIRA_API_TOKEN" "$SITE/rest/api/3/issue/<KEY>?fields=<CF_RISKS>" \
  | jq -r '.fields.<CF_RISKS> | type'
```

`string` — write it through the v3 API. `object` — it is an ADF document, and
the simplest way to set it is `PUT /rest/api/2/issue/<KEY>` with plain text,
which the server converts.

## Statuses

```bash
curl -s -u "$E:$JIRA_API_TOKEN" "$SITE/rest/api/3/issue/<KEY>/transitions" \
  | jq -r '.transitions[] | "\(.id)\t\(.name)"'
```

| Name used in the skill | Value |
|---|---|
| `<STATUS_IN_PROGRESS>` | `In Progress` |
| `<STATUS_DONE>` | `Done` |

Transition names are per-workflow. `Done` may not exist; `Completed`,
`Closed`, `Resolved` and localised names are all common.

## Sprints

| Name used in the skill | Value |
|---|---|
| `<SPRINT_PREFIX>` | `PROJ Sprint` |

Boards accumulate sprints left in state `active` by other teams, so the weekly
report picks the sprint whose name starts with this prefix **and** whose date
window contains today:

```bash
curl -s -u "$E:$JIRA_API_TOKEN" \
  "$SITE/rest/agile/1.0/board/<BOARD_ID>/sprint?state=active" \
  | jq -r '.values[] | "\(.id)\t\(.name)\t\(.startDate[:10])..\(.endDate[:10])"'
```

## Permissions

```bash
curl -s -u "$E:$JIRA_API_TOKEN" \
  "$SITE/rest/api/3/mypermissions?projectKey=<PROJECT>&permissions=CREATE_ISSUES,EDIT_ISSUES,DELETE_ISSUES,TRANSITION_ISSUES,ASSIGN_ISSUES,MODIFY_REPORTER,ADD_COMMENTS" \
  | jq -r '.permissions | to_entries[] | "\(.key)\t\(.value.havePermission)"'
```

Record the answer, and `DELETE_ISSUES` in particular. When it is `false`, a
ticket created by mistake stays on the board until an administrator removes
it — which is why the skill never creates one to test itself.
