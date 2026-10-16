import { spawn } from "node:child_process"
import { accessSync, constants } from "node:fs"
import type { Plugin } from "@opencode-ai/plugin"

// jira-write-guard OpenCode plugin — refuses a Jira write the human has not
// approved. Thin delegating plugin: the decision lives in the `jira-write-guard`
// script shipped inside the jira-op skill (the same file the Claude Code and
// Codex hooks run). Opencode has no transcript file, so the plugin passes the
// session's messages to the guard as `messages`.
//
// Only typed text counts as the human's words: tool results and synthetic
// parts are left out, so an answer picked in a question dialog is never an
// approval — the case the guard exists for.
//
// Dual-shape, like rtk.ts: OpenCode 2.x calls setup(), 1.x calls server().
//   1.x  the messages are read through the client.
//   2.x  there is no such read in the plugin context, so the plugin keeps its
//        own log: the `prompt` hook sees what the human typed, and
//        session.text.ended carries each text block of a reply. A plugin that
//        starts in the middle of a session has no earlier history, and the
//        guard then refuses a write — the safe direction: ask again.
// The shell tool is `shell` in 2.x and `bash` in 1.x.

const GUARD = `${process.env.HOME ?? ""}/.config/opencode/skills/jira-op/scripts/jira-write-guard`

// Cheap pre-filter: only commands that mention Jira can be Jira writes. The same
// pattern as MENTION in the guard; tests/test_write_guard.sh checks they agree.
// Quotes and backslashes are removed first, as the guard does: bash drops them,
// so ji''ra still runs jira.
const MENTION = /\bjira\b(?!-)|\/rest\/(?:api|agile)\/|atlassian\.(?:net|com)/i
const mentions = (command: string) => MENTION.test(command.replace(/[\\'"]/g, ""))

type Msg = { role: string; text: string }

const hasGuard = () => {
  try {
    accessSync(GUARD, constants.X_OK)
    return true
  } catch {
    return false
  }
}

// The payload goes on stdin: as an argument, a long session hits the 128 KiB
// limit of one argv string and the guard never runs.
function runGuard(stdin: string, timeout = 30000): Promise<{ code: number; stderr: string }> {
  return new Promise((resolve) => {
    const p = spawn(GUARD, [], { stdio: ["pipe", "ignore", "pipe"] })
    let stderr = ""
    const t = setTimeout(() => p.kill(), timeout)
    p.stderr.on("data", (d) => (stderr += d))
    p.on("error", () => (clearTimeout(t), resolve({ code: 127, stderr })))
    p.on("close", (c) => (clearTimeout(t), resolve({ code: c ?? 1, stderr })))
    p.stdin.on("error", () => {})
    p.stdin.end(stdin)
  })
}

// Throws when the Jira write is refused.
async function check(tool: unknown, args: any, getMessages: () => Promise<Msg[]>): Promise<void> {
  const t = String(tool ?? "").toLowerCase()
  if (t !== "bash" && t !== "shell") return
  const command = args?.command
  if (typeof command !== "string" || !command) return
  if (!mentions(command)) return

  if (!hasGuard()) {
    // No guard, no way to tell a read from a write: refuse anything that names Jira.
    throw new Error(`jira-write-guard: ${GUARD} is missing; run jira-op/install.sh.`)
  }
  let messages: Msg[] = []
  try {
    messages = await getMessages()
  } catch {
    messages = [] // unreadable conversation: the guard refuses a write
  }
  const res = await runGuard(JSON.stringify({ tool_name: "bash", tool_input: { command }, messages }))
  // 0 is the only "allowed": a crash, a missing python3 or an exec failure refuses.
  if (res.code !== 0) throw new Error(res.stderr.trim() || `jira-write-guard: refused (exit ${res.code}).`)
}

export const JiraWriteGuardPlugin: Plugin = async ({ client }: any) => {
  if (!hasGuard()) {
    console.warn(`[jira-write-guard] ${GUARD} not found — Jira commands are refused; run jira-op/install.sh`)
  }
  return {
    "tool.execute.before": async (input: any, output: any) =>
      check(input?.tool, output?.args, async () => {
        const messages: Msg[] = []
        const res = await client.session.messages({ path: { id: input.sessionID } })
        for (const m of (res?.data ?? []) as any[]) {
          const role = String(m?.info?.role ?? "")
          const text = ((m?.parts ?? []) as any[])
            .filter((p) => p?.type === "text" && !p?.synthetic)
            .map((p) => String(p?.text ?? ""))
            .join("\n")
          if (role && text) messages.push({ role, text })
        }
        return messages
      }),
  }
}

export default {
  id: "jira-write-guard",
  setup(ctx: any) {
    if (!hasGuard()) {
      console.warn(`[jira-write-guard] ${GUARD} not found — Jira commands are refused; run jira-op/install.sh`)
    }
    const log = new Map<string, Msg[]>()
    const seen = new Set<string>() // the stream delivers each event more than once
    const controller = new AbortController()
    const push = (sessionID: string, m: Msg) => {
      if (!sessionID || !m.text) return
      const list = log.get(sessionID) ?? []
      list.push(m)
      log.set(sessionID, list)
    }

    void (async () => {
      for await (const ev of ctx.event.subscribe({ signal: controller.signal })) {
        if (ev?.type !== "session.text.ended" || !ev?.id || seen.has(ev.id)) continue
        seen.add(ev.id)
        push(String(ev.data?.sessionID ?? ""), { role: "assistant", text: String(ev.data?.text ?? "") })
      }
    })().catch(() => {})

    return Promise.all([
      ctx.session.hook("prompt", (e: any) => {
        // Typed text only: files and skills are not the human's words.
        push(String(e?.sessionID ?? ""), { role: "user", text: String(e?.prompt?.text ?? "") })
      }),
      ctx.tool.hook("execute.before", (e: any) =>
        check(e?.tool, e?.input, async () => log.get(String(e?.sessionID ?? "")) ?? []),
      ),
    ]).then(() => () => controller.abort())
  },
  server: JiraWriteGuardPlugin,
}
