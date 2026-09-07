# Commands Reference

Complete reference for the `jira` CLI.

---

## Viewing Issues

```bash
# View single issue
jira issue view ISSUE-KEY

# View with more comments — DEFAULT IS 1, so a plain view hides the discussion
jira issue view ISSUE-KEY --comments 5

# Get raw JSON
jira issue view ISSUE-KEY --raw
```

---

## Listing Issues

```bash
# List all issues in project
jira issue list

# List my issues
jira issue list -a$(jira me)

# Filter by status (use quotes for multi-word statuses)
jira issue list -s"In Progress"
jira issue list -s"To Do"
jira issue list -sDone

# Filter by type
jira issue list -tBug
jira issue list -tStory
jira issue list -tTask
jira issue list -tEpic

# Filter by priority
jira issue list -yHigh
jira issue list -yCritical

# Filter by label
jira issue list -lurgent -lbug

# Combine filters
jira issue list -a$(jira me) -s"In Progress" -yHigh

# Search with text
jira issue list "login error"

# Recently accessed
jira issue list --history

# Issues I'm watching
jira issue list -w

# Created/updated filters
jira issue list --created today
jira issue list --created week
jira issue list --updated -2d

# Plain output for scripting
jira issue list --plain --no-headers

# Specific columns
jira issue list --plain --columns key,summary,status,assignee

# Raw JQL query
jira issue list -q"status = 'In Progress' AND assignee = currentUser()"

# Paginate results
jira issue list --paginate 20
jira issue list --paginate 10:50 # start:limit

# Sort — ORDER BY inside -q is rejected, this is the way
jira issue list --order-by updated --reverse
```

Verified on jira-cli 1.7.0: `--order-by` defaults to `created`, `--reverse`
flips the direction.

---

## Creating Issues

```bash
# Interactive creation
jira issue create

# Non-interactive with all fields
jira issue create \
    -tBug \
    -s"Login button not working" \
    -b"Users cannot click the login button on Safari" \
    -yHigh \
    -lbug -lurgent

# Create and assign to self
jira issue create -tTask -s"Summary" -a$(jira me)

# Create subtask (requires parent)
jira issue create -tSub-task -P"PROJ-123" -s"Subtask summary"

# Create with custom fields
jira issue create -tStory -s"Summary" --custom story-points=3

# Skip prompts for optional fields
jira issue create -tTask -s"Quick task" --no-input

# Open in browser after creation
jira issue create -tBug -s"Bug title" --web

# Read description from file
jira issue create -tStory -s"Summary" --template /path/to/template.md

# Read description from stdin
echo "Description here" | jira issue create -tTask -s"Summary"
```

**Multi-line content:** The CLI chokes on multi-line strings. Write to `/tmp` first:

```bash
cat > /tmp/jira_body.md <<'EOF'
## Description
User needs ability to export data...

## Acceptance Criteria
- Export works for CSV
- Export works for JSON
EOF

jira issue create --no-input \
  -tStory \
  -pPROJ \
  -s"Add export functionality" \
  -b"$(cat /tmp/jira_body.md)"
```

---

## Transitioning Issues

```bash
# Move to a state
jira issue move ISSUE-KEY "In Progress"
jira issue move ISSUE-KEY "Done"
jira issue move ISSUE-KEY "To Do"

# Move with comment
jira issue move ISSUE-KEY "Done" --comment "Completed the implementation"

# Move and set resolution
jira issue move ISSUE-KEY "Done" -R"Fixed"

# Move and reassign
jira issue move ISSUE-KEY "In Review" -a"reviewer@example.com"

# Open in browser after transition
jira issue move ISSUE-KEY "Done" --web
```

---

## Assigning Issues

```bash
# Assign to specific user
jira issue assign ISSUE-KEY "user@example.com"
jira issue assign ISSUE-KEY "John Doe"

# Assign to self
jira issue assign ISSUE-KEY $(jira me)

# Assign to default assignee
jira issue assign ISSUE-KEY default

# Unassign
jira issue assign ISSUE-KEY x
```

---

## Comments

```bash
# Add comment — body is POSITIONAL, there is no -b flag on this subcommand
jira issue comment add ISSUE-KEY "This is my comment"

# Add comment from file — the normal path for anything multi-line
jira issue comment add ISSUE-KEY --template /path/to/comment.md

# Internal (service-desk) comment
jira issue comment add ISSUE-KEY --template /tmp/c.md --internal
```

Verified against jira-cli 1.7.0: `comment add` accepts `-T/--template`,
`--internal`, `--no-input`, `--web`. `-b` belongs to `issue create` and
`issue edit`, not here — using it fails.

---

## Sprints

```bash
# List sprints
jira sprint list

# Active sprint only
jira sprint list --state active

# Add issue to sprint
jira sprint add SPRINT-ID ISSUE-KEY

# Close sprint
jira sprint close SPRINT-ID
```

---

## Linking Issues

| Relationship | Meaning |
|--------------|---------|
| `Blocks` | First ticket blocks second |
| `Relates` | General relationship |
| `Duplicate` | Same work |
| `Epic-Story` | Story belongs to Epic |

```bash
# Basic link
jira issue link PROJ-123 PROJ-456 "Relates"

# Blocker (blocker comes first)
jira issue link PROJ-100 PROJ-200 "Blocks"
# Meaning: PROJ-100 blocks PROJ-200

# Epic membership is NOT an issue link — it has its own subcommand
jira epic add EPIC-KEY ISSUE-KEY [ISSUE-KEY...]
jira epic remove ISSUE-KEY
jira epic list
```

`jira issue link` creates relationships between peers (`Blocks`, `Relates`,
`Duplicate`). Putting an issue under an epic goes through `jira epic add`, or
through the epic-link custom field on a REST call. Mixing the two produces a
link that looks right in the CLI and leaves the epic empty on the board.

---

## Other Commands

```bash
# Open issue in browser
jira open ISSUE-KEY

# Show current user
jira me

# Server info
jira serverinfo

# List projects
jira project list

# List boards — for the project in the config, or -p for another one
jira board list
jira board list -p OTHER-KEY
```

`board list` takes no output flags at all: its only own flag is `-h`, plus the
inherited `-c/--config`, `--debug` and `-p/--project`. `--plain` fails with
`Error: unknown flag: --plain`. The table it prints does include the board id.

Its "No boards found in project X" names the project **from the config**, not
the one you meant — pass `-p` when the default project is not the one in
question. That message is what a wrong default looks like, not an empty
project.

For scripting, filtering by type, or sprint date windows, go to REST:

```bash
curl -s -u "$(jira me):$JIRA_API_TOKEN" \
  "$SITE/rest/agile/1.0/board?projectKeyOrId=<KEY>" \
  | jq -r '.values[] | "\(.id)\t\(.type)\t\(.name)"'
```

