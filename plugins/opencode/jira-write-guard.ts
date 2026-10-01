import type { Plugin } from "@opencode-ai/plugin"

// jira-write-guard OpenCode plugin — refuses a Jira write the human has not
// approved. Thin delegating plugin: the decision lives in the
// `jira-write-guard` script shipped inside the jira-op skill (the same file the
// Claude Code and Codex hooks run). Opencode has no transcript file, so the
// plugin reads the session's messages and passes them as `messages`.
//
// Only typed text parts count as the human's words: tool results and synthetic
// parts are left out, so an answer picked in a question dialog is never an
// approval — the case the guard exists for.

export const JiraWriteGuardPlugin: Plugin = async ({ $, client }) => {
  const guard = `${process.env.HOME ?? ""}/.config/opencode/skills/jira-op/scripts/jira-write-guard`
  const probe = await $`test -x ${guard}`.quiet().nothrow()
  if (probe.exitCode !== 0) {
    console.warn(`[jira-write-guard] ${guard} not found — plugin disabled; run jira-op/install.sh`)
    return {}
  }

  return {
    "tool.execute.before": async (input, output) => {
      if (String(input?.tool ?? "").toLowerCase() !== "bash") return
      const command = (output?.args as Record<string, unknown> | undefined)?.command
      if (typeof command !== "string" || !command) return

      // Cheap pre-filter: only commands that mention Jira can be Jira writes.
      if (!/\bjira\b|atlassian\.net\/rest\//.test(command)) return

      let messages: { role: string; text: string }[] = []
      try {
        const res = await client.session.messages({ path: { id: input.sessionID } })
        for (const m of (res?.data ?? []) as any[]) {
          const role = String(m?.info?.role ?? "")
          const text = ((m?.parts ?? []) as any[])
            .filter((p) => p?.type === "text" && !p?.synthetic)
            .map((p) => String(p?.text ?? ""))
            .join("\n")
          if (role && text) messages.push({ role, text })
        }
      } catch {
        messages = [] // unreadable conversation: the guard refuses a write
      }

      const payload = JSON.stringify({ tool_name: "bash", tool_input: { command }, messages })
      const res = await $`printf %s ${payload} | ${guard}`.quiet().nothrow()
      if (res.exitCode === 2) {
        throw new Error(String(res.stderr).trim() || "jira-write-guard: Jira write not approved.")
      }
    },
  }
}
