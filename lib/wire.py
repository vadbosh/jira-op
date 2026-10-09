#!/usr/bin/env python3
"""Wire jira-write-guard and the jira-trigger rule into the assistants.

    wire.py <claude|opencode|codex> --src <repo> [--dry-run]

Idempotent: an entry that is already there is left alone, nothing is
reordered, and a configuration file is backed up before its first change (to
~/.local/state/jira-op-backups, outside every directory an assistant scans).

  claude    settings.json  PreToolUse/Bash → <skills>/jira-op/scripts/jira-write-guard-hook
            rules/jira-trigger.md
  codex     hooks.json     PreToolUse/^Bash$ → the same script in ~/.codex/skills
            memories/jira-trigger.md + an @-line in ~/.codex/AGENTS.md
  opencode  plugins/jira-write-guard.ts
            instructions/jira-trigger.md + an entry in opencode.json instructions[]

Each assistant runs its own installed copy of the skill's script, so the hook
lives wherever that assistant's skill lives. The hook command is the launcher
jira-write-guard-hook, not the guard itself: Claude Code and Codex block only on
exit 2, and the launcher turns a missing python3, a crash or a deadline into a
refusal (see its header).

Exit 0 — wired or already current; 3 — the assistant is not installed; 1 — a
configuration file could not be read, nothing was written for that assistant.
"""
import argparse
import json
import os
import shutil
import sys
import time

H = os.path.expanduser("~")
BACKUP_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.join(H, ".local/state")),
                          "jira-op-backups")
RULE = "jira-trigger.md"
STAMP = time.strftime("%Y%m%d-%H%M%S")

IDE = {
    "claude": {
        "home": f"{H}/.claude",
        "guard": f"{H}/.claude/skills/jira-op/scripts/jira-write-guard-hook",
        "hooks_file": f"{H}/.claude/settings.json",
        "matcher": "Bash",
        "rule_dir": f"{H}/.claude/rules",
    },
    "codex": {
        "home": f"{H}/.codex",
        "guard": f"{H}/.codex/skills/jira-op/scripts/jira-write-guard-hook",
        "hooks_file": f"{H}/.codex/hooks.json",
        "matcher": "^Bash$",
        "rule_dir": f"{H}/.codex/memories",
        "agents_md": f"{H}/.codex/AGENTS.md",
    },
    "opencode": {
        "home": f"{H}/.config/opencode",
        "plugin_dir": f"{H}/.config/opencode/plugins",
        "config": f"{H}/.config/opencode/opencode.json",
        "rule_dir": f"{H}/.config/opencode/instructions",
    },
}

DRY = False
# Above the launcher's own 20 s deadline, so the launcher answers first.
HOOK_TIMEOUT = 30


def say(msg):
    print(f"    {'would: ' if DRY else ''}{msg}")


def backup(path):
    if DRY or not os.path.exists(path):
        return
    os.makedirs(BACKUP_DIR, exist_ok=True)
    shutil.copy2(path, os.path.join(BACKUP_DIR, f"{os.path.basename(path)}.{STAMP}"))


def copy_if_changed(src, dst):
    new = open(src, "rb").read()
    if os.path.exists(dst) and open(dst, "rb").read() == new:
        return False
    say(f"write {dst}")
    if not DRY:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as fh:
            fh.write(new)
    return True


def load_json(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def save_json(path, data):
    if DRY:
        return
    backup(path)
    tmp = path + ".tmp-jira-op"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)


def wire_hook(cfg):
    """Add one PreToolUse entry running the guard, unless one is there already."""
    path = cfg["hooks_file"]
    data = load_json(path)
    pre = data.setdefault("hooks", {}).setdefault("PreToolUse", [])
    for group in pre:
        for h in group.get("hooks", []):
            if "jira-write-guard" in str(h.get("command", "")):
                if h["command"] != cfg["guard"] or h.get("timeout") != HOOK_TIMEOUT:
                    say(f"update hook command and timeout in {path}")
                    h["command"] = cfg["guard"]
                    h["timeout"] = HOOK_TIMEOUT
                    save_json(path, data)
                return
    pre.append({"matcher": cfg["matcher"], "hooks": [{
        "type": "command", "command": cfg["guard"], "timeout": HOOK_TIMEOUT,
        "statusMessage": "jira-write-guard...",
    }]})
    say(f"add PreToolUse hook to {path}")
    save_json(path, data)


def wire_codex_ref(cfg):
    path, ref = cfg["agents_md"], f"@{cfg['rule_dir']}/{RULE}"
    text = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    if any(line.strip().startswith("@") and line.strip().endswith("/" + RULE)
           for line in text.splitlines()):
        return
    say(f"add {ref} to {path}")
    if not DRY:
        backup(path)
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(("" if text.endswith("\n") or not text else "\n") + ref + "\n")


def wire_opencode_instruction(cfg):
    path, entry = cfg["config"], f"~/.config/opencode/instructions/{RULE}"
    data = load_json(path)
    arr = data.setdefault("instructions", [])
    if entry in arr:
        return
    arr.append(entry)
    say(f"add {entry} to {path} instructions[]")
    save_json(path, data)


def main():
    global DRY
    ap = argparse.ArgumentParser()
    ap.add_argument("ide", choices=sorted(IDE))
    ap.add_argument("--src", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    DRY = a.dry_run
    cfg = IDE[a.ide]
    if not os.path.isdir(cfg["home"]):
        return 3
    try:
        copy_if_changed(os.path.join(a.src, "rules", RULE), os.path.join(cfg["rule_dir"], RULE))
        if a.ide == "opencode":
            copy_if_changed(os.path.join(a.src, "plugins/opencode/jira-write-guard.ts"),
                            os.path.join(cfg["plugin_dir"], "jira-write-guard.ts"))
            wire_opencode_instruction(cfg)
        else:
            wire_hook(cfg)
            if a.ide == "codex":
                wire_codex_ref(cfg)
    except (OSError, ValueError) as exc:
        print(f"    ! {a.ide}: {exc} — not wired", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
