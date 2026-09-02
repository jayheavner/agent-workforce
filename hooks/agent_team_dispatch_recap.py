#!/usr/bin/env python3
"""agent_team_dispatch_recap.py — what an interrupted dispatch had already
found, read straight from its own raw transcript.

WHY THIS EXISTS. The reconcile-and-resume protocol (agents/orchestrator.md,
"Interrupted dispatches") has always said to re-dispatch a cut-off specialist
with a summary of what stands. In practice that summary was prose the
orchestrator wrote from memory or a quick skim, and this session found a
real, measured case of what that costs: a second reviewer attempt, told
explicitly not to repeat the first attempt's ground, still reopened 61% of
the same files and ran several of the same commands word for word, then ran
out of its own turn budget re-confirming something the first attempt had
already settled. It had a prose summary. It did not have the first attempt's
actual work.

This tool replaces the guess with the record: every file the dying dispatch
already opened or changed, every git-visible command it ran, and its own last
few reasoning turns — the closest thing to "the thing it already found" that
its raw transcript still holds after a silent kill. It is deliberately not a
full re-read of the transcript; a resumed dispatch that has to read a wall of
its predecessor's history to find the one useful fact has just spent the
turns this tool exists to save.

Usage: agent_team_dispatch_recap.py --transcript <path> [--max-files N]
                                     [--max-commands N] [--max-reasoning N]
Prints a plain-text recap to stdout. Exit 0 always for a readable transcript;
exit 2 only when the transcript cannot be opened at all.
"""
import argparse
import json
import sys

READ_TOOLS = {"Read", "Grep", "Glob"}
WRITE_TOOLS = {"Write", "Edit", "NotebookEdit"}
GIT_MARKERS = ("git status", "git diff", "git log", "git show", "git commit", "git add")


def _tool_use_blocks(rec):
    if not isinstance(rec, dict) or rec.get("type") != "assistant":
        return []
    content = (rec.get("message") or {}).get("content")
    if not isinstance(content, list):
        return []
    return [b for b in content if isinstance(b, dict) and b.get("type") == "tool_use"]


def _text_blocks(rec):
    if not isinstance(rec, dict) or rec.get("type") != "assistant":
        return []
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, str):
        return [content] if content.strip() else []
    if not isinstance(content, list):
        return []
    return [b.get("text", "") for b in content
            if isinstance(b, dict) and b.get("type") == "text" and b.get("text", "").strip()]


def build_recap(path, max_files=25, max_commands=15, max_reasoning=5):
    """Return (recap_text, ended_with_report). Raises OSError if unreadable."""
    files_read = []
    files_written = []
    commands = []
    reasoning = []  # most recent kept, oldest dropped
    seen_read, seen_written, seen_cmd = set(), set(), set()

    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue

            for block in _tool_use_blocks(rec):
                name = block.get("name")
                inp = block.get("input") or {}
                if name in READ_TOOLS:
                    # file_path (Read) or path (Grep/Glob) — never `pattern`,
                    # which is the search string, not a target the resume
                    # should treat as a file already covered.
                    target = inp.get("file_path") or inp.get("path")
                    if target and target not in seen_read:
                        seen_read.add(target)
                        files_read.append(target)
                elif name in WRITE_TOOLS:
                    target = inp.get("file_path") or inp.get("notebook_path")
                    if target and target not in seen_written:
                        seen_written.add(target)
                        files_written.append(target)
                elif name == "Bash":
                    cmd = (inp.get("command") or "").strip()
                    if cmd and any(m in cmd for m in GIT_MARKERS) and cmd not in seen_cmd:
                        seen_cmd.add(cmd)
                        commands.append(cmd)

            texts = _text_blocks(rec)
            if texts:
                reasoning.append("\n".join(texts))

    ended_with_report = False
    if reasoning:
        tail_lines = [ln for ln in reasoning[-1].splitlines() if ln.strip()][-3:]
        ended_with_report = any("WORKFORCE_REPORT:" in ln for ln in tail_lines)

    lines = ["# Recap of an interrupted dispatch", ""]
    lines.append(f"Ended with its own closing report: {ended_with_report}")
    lines.append("")
    lines.append(f"## Files read or searched ({len(files_read)} distinct)")
    for p in files_read[-max_files:]:
        lines.append(f"- {p}")
    lines.append("")
    lines.append(f"## Files written or edited ({len(files_written)} distinct)")
    for p in files_written[-max_files:]:
        lines.append(f"- {p}")
    lines.append("")
    lines.append(f"## git-visible commands run ({len(commands)} distinct)")
    for c in commands[-max_commands:]:
        lines.append(f"- `{c}`")
    lines.append("")
    lines.append(f"## Its own last {min(max_reasoning, len(reasoning))} reasoning turns, most recent last")
    for r in reasoning[-max_reasoning:]:
        lines.append("---")
        lines.append(r.strip())
    return "\n".join(lines), ended_with_report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--transcript", required=True)
    ap.add_argument("--max-files", type=int, default=25)
    ap.add_argument("--max-commands", type=int, default=15)
    ap.add_argument("--max-reasoning", type=int, default=5)
    args = ap.parse_args()
    try:
        recap, _ = build_recap(args.transcript, args.max_files, args.max_commands, args.max_reasoning)
    except OSError as e:
        print(f"agent_team_dispatch_recap: cannot read {args.transcript}: {e}", file=sys.stderr)
        return 2
    print(recap)
    return 0


if __name__ == "__main__":
    sys.exit(main())
