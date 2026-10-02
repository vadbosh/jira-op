# jira-op Auto-Trigger

Any Jira work — "jira", "тикет", "таска", "задача в Jira", "оформи в Jira", a sprint, a
comment, a transition, or an issue key like `OP-123` → invoke the `jira-op` skill BEFORE
the first Jira command, **every time**, even if it was loaded earlier in the session.

**MANDATORY — no discretion.** Working from memory of an earlier load is how a ticket got
filed without approval on 2026-10-01: the draft and the field questions went out in one
message, and the answers to the questions were taken as consent to publish.

A write to Jira — create, edit, transition, sprint, comment — happens only after:

1. the full draft (or the before/after of the change) is printed,
2. the message ends with the line `Утверждаешь? (да/нет)` and the turn stops there,
3. the human types «да».

**No ticket without a draft, ever** — a clone and an epic included. The draft has the
`Summary:` and `Description:` lines and the summary exactly as the create sends it. A
delete or a sprint close also needs the draft to name every issue key or sprint id, and
the command to name them literally: no variables or loops.

Questions with answers to pick — the weekly report's period and absence, story points,
sprint, End Date — go through the question tool in one dialog (`AskUserQuestion`,
`question`, `request_user_input`), never as prose. The approval «да» is never one of them.

Answers in a question dialog — story points, sprint, dates — are not approval.
`jira-write-guard` (PreToolUse hook, installed by jira-op) refuses a write that skips this
when it goes through `jira`, `curl`, `wget`, `httpie` or `xh`; its refusal means: print the
draft with the question and wait. It does not see a write from a script file or another
language (`python3 -c`, `node -e`), so never route one that way.
