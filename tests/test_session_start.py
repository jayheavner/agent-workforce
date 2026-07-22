#!/usr/bin/env python3
"""Behavior tests for the SessionStart hook (hooks/session_start.py).

Driven exactly as the harness drives it: payload JSON on stdin, context out as
{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext"}}
on stdout, exit 0 always (the hook must never block a session start).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / "hooks" / "session_start.py"


class SessionStartHookTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ)
        self.env["WORKFORCE_FETCH_TIMEOUT"] = "10"
        self.env["WORKFORCE_READY_CHECK_TIMEOUT"] = "5"

    def run_hook(self, cwd: Path, raw: str | None = None):
        payload = raw if raw is not None else json.dumps({"cwd": str(cwd)})
        return subprocess.run(
            [sys.executable, str(HOOK)],
            input=payload, text=True, capture_output=True,
            env=self.env, timeout=120,
        )

    def context(self, result) -> str:
        self.assertEqual(result.returncode, 0, result.stderr)
        if not result.stdout.strip():
            return ""
        doc = json.loads(result.stdout)
        return doc["hookSpecificOutput"]["additionalContext"]

    def git(self, repo: Path, *args: str) -> str:
        out = subprocess.run(["git", "-C", str(repo), *args],
                             capture_output=True, text=True, check=True)
        return out.stdout.strip()

    def make_repo(self, name: str) -> Path:
        repo = self.root / name
        repo.mkdir()
        self.git(repo, "init", "-q", "-b", "main")
        self.git(repo, "config", "user.email", "t@example.invalid")
        self.git(repo, "config", "user.name", "Session Start Test")
        (repo / "a.txt").write_text("a\n", encoding="utf-8")
        self.git(repo, "add", "a.txt")
        self.git(repo, "commit", "-qm", "seed")
        return repo

    # --- resilience -------------------------------------------------------

    def test_garbage_stdin_allows(self) -> None:
        result = self.run_hook(self.root, raw="not json")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_plain_dir_reports_undeclared_tracker(self) -> None:
        plain = self.root / "plain"
        plain.mkdir()
        ctx = self.context(self.run_hook(plain))
        self.assertIn("UNDECLARED", ctx)
        self.assertIn("/onboard-project", ctx)
        self.assertNotIn("git sync", ctx)

    # --- git sync ---------------------------------------------------------

    def test_behind_origin_is_reported_as_fact(self) -> None:
        seed = self.make_repo("seed")
        origin = self.root / "origin.git"
        subprocess.run(["git", "clone", "-q", "--bare", str(seed), str(origin)],
                       check=True, capture_output=True)
        checkout = self.root / "checkout"
        subprocess.run(["git", "clone", "-q", str(origin), str(checkout)],
                       check=True, capture_output=True)
        # origin advances by one commit the checkout has not pulled.
        self.git(seed, "remote", "add", "origin", str(origin))
        (seed / "b.txt").write_text("b\n", encoding="utf-8")
        self.git(seed, "add", "b.txt")
        self.git(seed, "commit", "-qm", "advance")
        self.git(seed, "push", "-q", "origin", "main")
        ctx = self.context(self.run_hook(checkout))
        self.assertIn("git sync: fetched origin", ctx)
        self.assertIn("0 ahead / 1 behind origin/main", ctx)

    def test_unreachable_origin_is_soft_and_says_unknown(self) -> None:
        repo = self.make_repo("island")
        self.git(repo, "remote", "add", "origin",
                 str(self.root / "missing.git"))
        ctx = self.context(self.run_hook(repo))
        self.assertIn("could not reach origin", ctx)
        self.assertIn("UNKNOWN", ctx)

    def test_no_remote_is_named_local_only(self) -> None:
        repo = self.make_repo("solo")
        ctx = self.context(self.run_hook(repo))
        self.assertIn("no origin remote", ctx)

    # --- onboarding probe -------------------------------------------------

    def write_project(self, cwd: Path, doc: dict) -> None:
        wf = cwd / ".workforce"
        wf.mkdir(exist_ok=True)
        (wf / "project.json").write_text(json.dumps(doc), encoding="utf-8")

    def test_declared_tracker_is_stated(self) -> None:
        plain = self.root / "declared"
        plain.mkdir()
        self.write_project(plain, {"tracker": "github"})
        ctx = self.context(self.run_hook(plain))
        self.assertIn("tracker = github", ctx)
        self.assertNotIn("UNDECLARED", ctx)

    def test_ready_checks_report_ok_and_fail_by_name(self) -> None:
        plain = self.root / "checks"
        plain.mkdir()
        self.write_project(plain, {
            "tracker": "none",
            "ready_checks": [
                {"name": "echo works", "command": "echo ready-to-go",
                 "expect": "ready-to-go"},
                {"name": "wrong output", "command": "echo something-else",
                 "expect": "the-right-answer"},
                {"name": "broken tool", "command": "exit 3"},
            ],
        })
        ctx = self.context(self.run_hook(plain))
        self.assertIn("ready: echo works — OK.", ctx)
        self.assertIn("ready: wrong output — FAIL (expected output not found", ctx)
        self.assertIn("ready: broken tool — FAIL (exit 3)", ctx)

    def test_malformed_project_file_reads_as_undeclared(self) -> None:
        plain = self.root / "malformed"
        plain.mkdir()
        wf = plain / ".workforce"
        wf.mkdir()
        (wf / "project.json").write_text("{not json", encoding="utf-8")
        ctx = self.context(self.run_hook(plain))
        self.assertIn("UNDECLARED", ctx)


if __name__ == "__main__":
    unittest.main()
