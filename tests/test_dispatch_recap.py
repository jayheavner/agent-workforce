#!/usr/bin/env python3
"""Behavior tests for hooks/agent_team_dispatch_recap.py — the tool that reads
an interrupted dispatch's own raw transcript and produces what it had already
found, so a resume does not have to guess or repeat the work.
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "hooks"))

from agent_team_dispatch_recap import build_recap  # noqa: E402


def write_transcript(lines) -> str:
    f = tempfile.NamedTemporaryFile(mode="w", suffix=".jsonl", delete=False, encoding="utf-8")
    for rec in lines:
        f.write(json.dumps(rec) + "\n")
    f.close()
    return f.name


def assistant_tool_use(name, input_):
    return {"type": "assistant", "message": {"content": [
        {"type": "tool_use", "name": name, "input": input_}]}}


def assistant_text(text):
    return {"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}}


class RecapTests(unittest.TestCase):
    def test_distinct_read_files_kept_in_first_seen_order(self):
        path = write_transcript([
            assistant_tool_use("Read", {"file_path": "/a.py"}),
            assistant_tool_use("Grep", {"pattern": "x", "path": "/a.py"}),
            assistant_tool_use("Read", {"file_path": "/b.py"}),
            assistant_tool_use("Read", {"file_path": "/a.py"}),  # already seen
        ])
        recap, _ = build_recap(path)
        self.assertIn("Files read or searched (2 distinct)", recap)
        self.assertIn("/a.py", recap)
        self.assertIn("/b.py", recap)
        self.assertLess(recap.index("/a.py"), recap.index("/b.py"))

    def test_written_files_are_tracked_separately_from_reads(self):
        path = write_transcript([
            assistant_tool_use("Read", {"file_path": "/a.py"}),
            assistant_tool_use("Edit", {"file_path": "/a.py", "old_string": "x", "new_string": "y"}),
        ])
        recap, _ = build_recap(path)
        self.assertIn("Files read or searched (1 distinct)", recap)
        self.assertIn("Files written or edited (1 distinct)", recap)

    def test_only_git_visible_bash_commands_are_kept(self):
        path = write_transcript([
            assistant_tool_use("Bash", {"command": "pytest -q"}),
            assistant_tool_use("Bash", {"command": "git status"}),
            assistant_tool_use("Bash", {"command": "git commit -am wip"}),
        ])
        recap, _ = build_recap(path)
        self.assertIn("git-visible commands run (2 distinct)", recap)
        self.assertIn("git status", recap)
        self.assertIn("git commit -am wip", recap)
        self.assertNotIn("pytest -q", recap)

    def test_reasoning_capped_to_the_most_recent_n(self):
        path = write_transcript([assistant_text(f"turn {i}") for i in range(1, 8)])
        recap, _ = build_recap(path, max_reasoning=3)
        self.assertIn("last 3 reasoning turns", recap)
        self.assertIn("turn 5", recap)
        self.assertIn("turn 6", recap)
        self.assertIn("turn 7", recap)
        self.assertNotIn("turn 4", recap)

    def test_ended_with_report_is_false_for_a_genuinely_interrupted_dispatch(self):
        path = write_transcript([
            assistant_text("still working on it"),
            assistant_tool_use("Read", {"file_path": "/a.py"}),
        ])
        _, ended = build_recap(path)
        self.assertFalse(ended)

    def test_ended_with_report_is_true_when_the_marker_is_present(self):
        path = write_transcript([
            assistant_text("Delivered.\n\nWORKFORCE_REPORT: builder | complete"),
        ])
        _, ended = build_recap(path)
        self.assertTrue(ended)

    def test_unreadable_transcript_raises_oserror(self):
        with self.assertRaises(OSError):
            build_recap("/no/such/file/at/all.jsonl")

    def test_malformed_lines_are_skipped_not_fatal(self):
        f = tempfile.NamedTemporaryFile(mode="w", suffix=".jsonl", delete=False, encoding="utf-8")
        f.write("not json at all\n")
        f.write(json.dumps(assistant_tool_use("Read", {"file_path": "/a.py"})) + "\n")
        f.close()
        recap, _ = build_recap(f.name)
        self.assertIn("/a.py", recap)


if __name__ == "__main__":
    unittest.main()
