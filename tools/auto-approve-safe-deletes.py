#!/usr/bin/env python3
"""auto-approve-safe-deletes.py — PreToolUse(Bash) hook: never prompt for temp deletes.

Auto-approves `rm` commands whose every target provably lives inside
session-temp territory, so deleting Claude's own scratch work never prompts.
Anything it cannot positively verify falls through silently to the normal
permission flow — this hook allows or abstains, it never denies.

Wire it from settings.json (user scope):
  "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command",
    "command": "python3 /Users/jay/claude/agent-workforce/tools/auto-approve-safe-deletes.py",
    "if": "Bash(rm *)", "timeout": 10}]}]

Safe territory:
  - /private/tmp/claude-*/...            (per-uid Claude scratchpad roots)
  - /private/var/folders/*/*/T/...       (macOS per-user temp, $TMPDIR)
  - ~/.claude*/backups/...               (workforce install backups)
  - anywhere inside a LINKED git worktree (a checkout whose .git is a file
    pointing at <main>/.git/worktrees/<name>) — committed content is
    recoverable from the main repo, and worktrees are the designated agent
    blast radius. Main checkouts (.git is a directory) never qualify.

Abstains on: compound commands (;, &&, |, $(), backticks, redirection),
unexpanded variables, any `..` component, targets whose resolved real path
escapes safe territory (symlink defense), non-rm commands.

This is a convenience gate, not a security boundary: an agent that can
already write files could forge a .git pointer file. Roles that bypass
permissions never consult it; it only spares the human rote prompts.
"""
import json
import os
import re
import shlex
import sys

SAFE_PATTERNS = (
    # /tmp and /var are macOS symlinks into /private — accept both spellings,
    # since the literal (unresolved) path is checked before realpath.
    re.compile(r"^/(private/)?tmp/claude-[^/]+/."),
    re.compile(r"^/(private/)?var/folders/[^/]+/[^/]+/T/."),
    re.compile(re.escape(os.path.expanduser("~")) + r"/\.claude[^/]*/backups/."),
)
METACHARS = re.compile(r"[;&|`$<>\n\\]")
GLOB_CHARS = re.compile(r"[*?\[]")
WORKTREE_GITDIR = re.compile(r"^gitdir: .*/\.git/worktrees/[^/\s]+\s*$")


def in_linked_worktree(path):
    """True iff path is inside (or is) a linked git worktree checkout."""
    d = path
    while True:
        git_marker = os.path.join(d, ".git")
        if os.path.isdir(git_marker):
            return False  # main checkout — not disposable territory
        if os.path.isfile(git_marker):
            try:
                with open(git_marker) as f:
                    return bool(WORKTREE_GITDIR.match(f.readline()))
            except OSError:
                return False
        parent = os.path.dirname(d)
        if parent == d:
            return False
        d = parent


def in_safe_territory(path):
    return any(p.match(path) for p in SAFE_PATTERNS) or in_linked_worktree(path)


def existing_ancestor(path):
    while path and not os.path.exists(path):
        parent = os.path.dirname(path)
        if parent == path:
            break
        path = parent
    return path


def target_is_safe(raw, cwd):
    if ".." in raw.split("/"):
        return False
    path = raw if os.path.isabs(raw) else os.path.join(cwd, raw)
    path = os.path.normpath(path)
    m = GLOB_CHARS.search(path)
    literal = os.path.dirname(path[:m.start()] + "x") if m else path
    if not in_safe_territory(literal if m else path):
        return False
    # Symlink defense: resolve the deepest existing ancestor, reattach the
    # not-yet-existing remainder, and require the recomposed path to still be
    # in safe territory. Defeats a symlink smuggled anywhere along the path.
    anchor = existing_ancestor(literal)
    recomposed = os.path.realpath(anchor) + literal[len(anchor):]
    return in_safe_territory(recomposed)


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    if payload.get("tool_name") != "Bash":
        return
    command = (payload.get("tool_input") or {}).get("command") or ""
    cwd = payload.get("cwd") or os.getcwd()
    if METACHARS.search(command):
        return
    try:
        tokens = shlex.split(command)
    except ValueError:
        return
    if not tokens or tokens[0] != "rm":
        return
    targets = [t for t in tokens[1:] if not t.startswith("-")]
    if not targets:
        return
    if all(target_is_safe(t, cwd) for t in targets):
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason":
                    "rm confined to session-temp paths (scratchpad/tmp/backups) "
                    "— auto-approved by auto-approve-safe-deletes.py",
            }
        }))


if __name__ == "__main__":
    main()
