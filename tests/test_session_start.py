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
        self.env.pop("WORKFORCE_LAUNCH_MODE", None)

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

    # --- reconcile (dead-orchestrator detection, issue #8) ----------------

    def write_jsonl(self, path: Path, records: list) -> None:
        with open(path, "w", encoding="utf-8") as f:
            for rec in records:
                f.write(json.dumps(rec) + "\n")

    def dispatch_rec(self, role: str = "builder", tid: str = "t1") -> dict:
        return {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Agent", "id": tid,
             "input": {"subagent_type": role}}]}}

    def tool_result_rec(self, tid: str = "t1") -> dict:
        return {"type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": tid, "content": "done"}]}}

    def assistant_text_rec(self, text: str) -> dict:
        return {"type": "assistant", "message": {"content": [
            {"type": "text", "text": text}]}}

    def txdir(self) -> Path:
        d = self.root / "transcripts"
        d.mkdir(exist_ok=True)
        return d

    def with_transcript(self, transcript: Path) -> str:
        return json.dumps({"cwd": str(self.root),
                           "transcript_path": str(transcript)})

    def test_reconcile_dead_session_warns(self) -> None:
        d = self.txdir()
        dead = d / "dead.jsonl"
        self.write_jsonl(dead, [
            self.dispatch_rec("builder", "t1"),
            self.tool_result_rec("t1"),
            self.assistant_text_rec(
                "Now the cost report. Locating my transcript to run the "
                "reporter."),
            {"type": "assistant", "isApiErrorMessage": True,
             "message": {"content": [{"type": "text", "text":
                "API Error: Connection closed mid-response."}]}},
        ])
        current = d / "current.jsonl"
        current.write_text("", encoding="utf-8")
        os.utime(dead, (1000, 1000))
        os.utime(current, (2000, 2000))
        ctx = self.context(self.run_hook(self.root,
                                         raw=self.with_transcript(current)))
        self.assertIn("reconcile:", ctx)
        self.assertIn("dead.jsonl", ctx)
        self.assertIn("died mid-closeout", ctx)

    def test_reconcile_paused_session_no_warn(self) -> None:
        d = self.txdir()
        prior = d / "paused.jsonl"
        self.write_jsonl(prior, [
            self.dispatch_rec("architect", "t1"),
            self.tool_result_rec("t1"),
            self.assistant_text_rec(
                "Design done. WORKFORCE_PAUSE: HUMAN_DECISION — awaiting gate."),
        ])
        current = d / "current.jsonl"
        current.write_text("", encoding="utf-8")
        os.utime(prior, (1000, 1000)); os.utime(current, (2000, 2000))
        ctx = self.context(self.run_hook(self.root,
                                         raw=self.with_transcript(current)))
        self.assertNotIn("reconcile:", ctx)

    def test_reconcile_no_dispatch_session_no_warn(self) -> None:
        d = self.txdir()
        prior = d / "chat.jsonl"
        self.write_jsonl(prior, [
            self.assistant_text_rec("Just a conversation, no dispatches.")])
        current = d / "current.jsonl"
        current.write_text("", encoding="utf-8")
        os.utime(prior, (1000, 1000)); os.utime(current, (2000, 2000))
        ctx = self.context(self.run_hook(self.root,
                                         raw=self.with_transcript(current)))
        self.assertNotIn("reconcile:", ctx)

    def test_reconcile_completed_closeout_no_warn(self) -> None:
        d = self.txdir()
        prior = d / "done.jsonl"
        self.write_jsonl(prior, [
            self.dispatch_rec("builder", "t1"),
            self.tool_result_rec("t1"),
            self.assistant_text_rec(
                "All shipped.\n\n## Cost report\n| total | $1.23 |"),
        ])
        current = d / "current.jsonl"
        current.write_text("", encoding="utf-8")
        os.utime(prior, (1000, 1000)); os.utime(current, (2000, 2000))
        ctx = self.context(self.run_hook(self.root,
                                         raw=self.with_transcript(current)))
        self.assertNotIn("reconcile:", ctx)

    def test_reconcile_current_session_not_flagged(self) -> None:
        d = self.txdir()
        current = d / "current.jsonl"
        self.write_jsonl(current, [
            self.dispatch_rec("builder", "t1"),
            self.tool_result_rec("t1"),
            self.assistant_text_rec("Working... no closeout yet."),
        ])
        ctx = self.context(self.run_hook(self.root,
                                         raw=self.with_transcript(current)))
        self.assertNotIn("reconcile:", ctx)

    def test_reconcile_missing_transcript_path_no_warn(self) -> None:
        ctx = self.context(self.run_hook(self.root))
        self.assertNotIn("reconcile:", ctx)

    def test_reconcile_garbage_prior_fails_open(self) -> None:
        d = self.txdir()
        prior = d / "garbage.jsonl"
        prior.write_text("not json\n\x00 broken line\n", encoding="latin-1")
        current = d / "current.jsonl"
        current.write_text("", encoding="utf-8")
        os.utime(prior, (1000, 1000)); os.utime(current, (2000, 2000))
        result = self.run_hook(self.root, raw=self.with_transcript(current))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("reconcile:", self.context(result))

    def test_reconcile_recent_clean_masks_older_dead(self) -> None:
        d = self.txdir()
        dead = d / "dead.jsonl"
        self.write_jsonl(dead, [
            self.dispatch_rec("builder", "t1"),
            self.tool_result_rec("t1"),
            self.assistant_text_rec("No closeout — I died."),
        ])
        clean = d / "clean.jsonl"
        self.write_jsonl(clean, [
            self.assistant_text_rec("Quick chat, nothing dispatched.")])
        current = d / "current.jsonl"
        current.write_text("", encoding="utf-8")
        os.utime(dead, (1000, 1000)); os.utime(clean, (2000, 2000))
        os.utime(current, (3000, 3000))
        ctx = self.context(self.run_hook(self.root,
                                         raw=self.with_transcript(current)))
        self.assertNotIn("reconcile:", ctx)

    # --- added 2026-07-26 (plan-critique SHIP-WITH-FIXES, AC9/AC10) -------

    def test_reconcile_dead_newest_among_several_warns(self) -> None:
        d = self.txdir()
        older_clean = d / "older_clean.jsonl"
        self.write_jsonl(older_clean, [
            self.assistant_text_rec("Quick chat, nothing dispatched.")])
        newest_dead = d / "newest_dead.jsonl"
        self.write_jsonl(newest_dead, [
            self.dispatch_rec("builder", "t1"),
            self.tool_result_rec("t1"),
            self.assistant_text_rec("No closeout — I died too."),
        ])
        current = d / "current.jsonl"
        current.write_text("", encoding="utf-8")
        os.utime(older_clean, (1000, 1000))
        os.utime(newest_dead, (2000, 2000))
        os.utime(current, (3000, 3000))
        ctx = self.context(self.run_hook(self.root,
                                         raw=self.with_transcript(current)))
        self.assertIn("reconcile:", ctx)
        self.assertIn("newest_dead.jsonl", ctx)

    def test_reconcile_empty_last_text_death_warns(self) -> None:
        d = self.txdir()
        dead = d / "silent_death.jsonl"
        self.write_jsonl(dead, [
            self.dispatch_rec("builder", "t1"),
            self.tool_result_rec("t1"),
        ])
        current = d / "current.jsonl"
        current.write_text("", encoding="utf-8")
        os.utime(dead, (1000, 1000)); os.utime(current, (2000, 2000))
        ctx = self.context(self.run_hook(self.root,
                                         raw=self.with_transcript(current)))
        self.assertIn("reconcile:", ctx)
        self.assertIn("silent_death.jsonl", ctx)

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

    # --- launch-mode tripwire ---------------------------------------------

    def test_direct_launch_without_launcher_warns_loudly(self) -> None:
        plain = self.root / "direct"
        plain.mkdir()
        ctx = self.context(self.run_hook(plain))
        self.assertIn("DEGRADED", ctx)
        self.assertIn("bin/agent-workforce", ctx)
        self.assertIn("permission prompts", ctx)

    def test_snapshot_launch_via_launcher_stays_silent(self) -> None:
        plain = self.root / "snap"
        plain.mkdir()
        self.env["WORKFORCE_LAUNCH_MODE"] = "snapshot"
        ctx = self.context(self.run_hook(plain))
        self.assertNotIn("DEGRADED", ctx)

    def test_plugin_launch_notes_expected_prompts(self) -> None:
        plain = self.root / "plug"
        plain.mkdir()
        self.env["WORKFORCE_LAUNCH_MODE"] = "plugin"
        ctx = self.context(self.run_hook(plain))
        self.assertNotIn("DEGRADED", ctx)
        self.assertIn("plugin mode", ctx)
        self.assertIn("permission prompts", ctx)

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

    def fake_gh(self, script_body: str) -> None:
        """Put a fake `gh` first on PATH for the hook subprocess."""
        bindir = self.root / "bin"
        bindir.mkdir(exist_ok=True)
        gh = bindir / "gh"
        gh.write_text("#!/bin/sh\n" + script_body + "\n", encoding="utf-8")
        gh.chmod(0o755)
        self.env["PATH"] = f"{bindir}:{self.env['PATH']}"

    def test_github_tracker_lists_open_workforce_issues(self) -> None:
        """Downstream work filed as 'workforce'-labeled issues is surfaced at
        every session start — nobody hunts for it (decision 2026-07-22)."""
        cwd = self.root / "proj"
        (cwd / ".workforce").mkdir(parents=True)
        (cwd / ".workforce" / "project.json").write_text(
            json.dumps({"tracker": "github"}), encoding="utf-8")
        self.fake_gh(
            "echo '[{\"number\": 7, \"title\": \"Fix cost attribution\"}]'")
        ctx = self.context(self.run_hook(cwd))
        self.assertIn("#7: Fix cost attribution", ctx)
        self.assertIn("workforce", ctx)

    def test_github_tracker_no_open_issues_is_stated(self) -> None:
        cwd = self.root / "proj2"
        (cwd / ".workforce").mkdir(parents=True)
        (cwd / ".workforce" / "project.json").write_text(
            json.dumps({"tracker": "github"}), encoding="utf-8")
        self.fake_gh("echo '[]'")
        ctx = self.context(self.run_hook(cwd))
        self.assertIn("no open 'workforce'", ctx)

    def test_github_tracker_gh_failure_is_soft_and_says_unknown(self) -> None:
        cwd = self.root / "proj3"
        (cwd / ".workforce").mkdir(parents=True)
        (cwd / ".workforce" / "project.json").write_text(
            json.dumps({"tracker": "github"}), encoding="utf-8")
        self.fake_gh("exit 1")
        result = self.run_hook(cwd)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("UNKNOWN", self.context(result))

    def test_non_github_tracker_skips_issue_probe(self) -> None:
        cwd = self.root / "proj4"
        (cwd / ".workforce").mkdir(parents=True)
        (cwd / ".workforce" / "project.json").write_text(
            json.dumps({"tracker": "asana"}), encoding="utf-8")
        self.fake_gh("echo should-not-run; exit 1")
        ctx = self.context(self.run_hook(cwd))
        self.assertNotIn("should-not-run", ctx)
        self.assertNotIn("UNKNOWN", ctx)

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
