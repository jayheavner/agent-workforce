#!/usr/bin/env python3
"""Behavior tests for the Agent Workforce closeout Stop hook.

The hook (hooks/agent_team_closeout.py) is a single Stop-hook entrypoint: it
reads the Stop payload JSON on stdin, scans the session transcript for Agent
dispatches, and either allows the stop (exit 0, no output) or emits a
{"decision": "block", "reason": ...} JSON on stdout. These tests exercise it
exactly the way the harness does — as a subprocess with the payload on stdin —
with AGENT_TEAM_CLOSEOUT_STATE and AGENT_TEAM_COST_DIR pointed at temp dirs.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / "hooks" / "agent_team_closeout.py"

# When the shell runner drives this file under coverage, subprocess invocations
# of the hook must be measured too: run them via coverage's parallel mode so
# their data files land beside the parent's (COVERAGE_FILE is inherited) and
# the runner can `coverage combine` them afterwards.
COVERAGE_SUBPROCESS = os.environ.get("COVERAGE_HOOK_SUBPROCESS") == "1"


def hook_command() -> list[str]:
    """Command line that runs the Stop hook, under coverage when requested."""
    if COVERAGE_SUBPROCESS:
        return [
            sys.executable,
            "-m",
            "coverage",
            "run",
            "--parallel-mode",
            f"--source={ROOT / 'hooks'}",
            str(HOOK),
        ]
    return [sys.executable, str(HOOK)]


class CloseoutStopHookTest(unittest.TestCase):
    """Drive the Stop hook end to end through stdin/stdout/exit code."""

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.state_dir = root / "state"
        self.cost_dir = root / "cost"
        self.data_dir = root / "data"
        self.cwd_dir = root / "cwd"
        for d in (self.state_dir, self.cost_dir, self.data_dir, self.cwd_dir):
            d.mkdir()
        self.env = dict(os.environ)
        self.env["AGENT_TEAM_CLOSEOUT_STATE"] = str(self.state_dir)
        self.env["AGENT_TEAM_COST_DIR"] = str(self.cost_dir)

    # --- hook invocation -------------------------------------------------

    def run_hook(self, payload: object = None, raw: str | None = None):
        """echo payload | python3 hooks/agent_team_closeout.py"""
        text = raw if raw is not None else json.dumps(payload)
        return subprocess.run(
            hook_command(),
            input=text,
            text=True,
            capture_output=True,
            env=self.env,
            timeout=180,
        )

    def payload(self, transcript: str, cwd: str | None = None,
                session_id: str = "session-1") -> dict[str, object]:
        return {
            "session_id": session_id,
            "transcript_path": transcript,
            "cwd": cwd or str(self.cwd_dir),
        }

    # --- transcript building ---------------------------------------------

    @staticmethod
    def assistant_text(text: str, msg_id: str = "msg_1") -> dict[str, object]:
        """Assistant record shape reused from tests/fixtures/cost/good."""
        return {
            "type": "assistant",
            "timestamp": "2026-07-18T00:00:00.000Z",
            "message": {
                "id": msg_id,
                "model": "claude-sonnet-5",
                "content": [{"type": "text", "text": text}],
                "usage": {
                    "input_tokens": 100,
                    "output_tokens": 50,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 0,
                },
            },
        }

    @staticmethod
    def dispatch(tool_id: str = "tu_1", role: str = "scribe") -> dict[str, object]:
        return {
            "type": "assistant",
            "message": {
                "content": [
                    {
                        "type": "tool_use",
                        "id": tool_id,
                        "name": "Agent",
                        "input": {"subagent_type": role, "prompt": "x"},
                    }
                ]
            },
        }

    @staticmethod
    def result(tool_id: str = "tu_1") -> dict[str, object]:
        return {
            "type": "user",
            "message": {
                "content": [
                    {"type": "tool_result", "tool_use_id": tool_id, "content": "done"}
                ]
            },
        }

    def write_transcript(self, records: list[dict[str, object]],
                         name: str = "transcript.jsonl") -> str:
        path = self.data_dir / name
        path.write_text(
            "".join(json.dumps(r) + "\n" for r in records), encoding="utf-8"
        )
        return str(path)

    # --- state file ------------------------------------------------------

    def state_file(self, session_id: str = "session-1") -> Path:
        digest = hashlib.sha256(session_id.encode()).hexdigest()
        return self.state_dir / (digest + ".json")

    def seed_state(self, blocks: int, session_id: str = "session-1") -> None:
        self.state_file(session_id).write_text(
            json.dumps({"blocks": blocks}), encoding="utf-8"
        )

    # --- scenarios -------------------------------------------------------

    def test_empty_stdin_allows(self) -> None:
        """(a) Empty stdin -> exit 0, no output."""
        result = self.run_hook(raw="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_invalid_stdin_allows(self) -> None:
        """(a) Non-JSON stdin -> exit 0, no output."""
        result = self.run_hook(raw="not json at all")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_zero_dispatches_allows(self) -> None:
        """(b) A plain Q&A turn with no Agent dispatches is never intercepted."""
        transcript = self.write_transcript(
            [self.assistant_text("Just an ordinary answer.")]
        )
        result = self.run_hook(self.payload(transcript))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_inflight_dispatch_allows(self) -> None:
        """(c) An Agent tool_use with no tool_result is a wait, not a closeout."""
        transcript = self.write_transcript(
            [
                self.assistant_text("Dispatching now.", "msg_1"),
                self.dispatch("tu_1", "builder"),
            ]
        )
        result = self.run_hook(self.payload(transcript))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_missing_cost_report_blocks_with_computed_table(self) -> None:
        """(d) Resolved dispatch + final message without the marker -> block."""
        transcript = self.write_transcript(
            [
                self.assistant_text("Dispatching now.", "msg_1"),
                self.dispatch("tu_1", "scribe"),
                self.result("tu_1"),
                self.assistant_text("All delivered.", "msg_2"),
            ]
        )
        result = self.run_hook(self.payload(transcript))
        self.assertEqual(result.returncode, 0, result.stderr)
        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("Cost report", decision["reason"])
        self.assertTrue(self.state_file().is_file(), "block must be recorded")
        state = json.loads(self.state_file().read_text(encoding="utf-8"))
        self.assertEqual(state["blocks"], 1)

    def test_cost_report_marker_allows_and_clears_state(self) -> None:
        """(e) Final message carrying the marker -> allow, state removed."""
        self.seed_state(blocks=1)
        transcript = self.write_transcript(
            [
                self.assistant_text("Dispatching now.", "msg_1"),
                self.dispatch("tu_1", "scribe"),
                self.result("tu_1"),
                self.assistant_text(
                    "All delivered.\n\n## Cost report\n\n| Model | Cost |\n", "msg_2"
                ),
            ]
        )
        result = self.run_hook(self.payload(transcript))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertFalse(self.state_file().exists(), "state must be cleared")

    def test_block_cap_fails_open(self) -> None:
        """(f) After MAX_BLOCKS blocks the hook allows rather than wedging."""
        self.seed_state(blocks=3)
        transcript = self.write_transcript(
            [
                self.assistant_text("Dispatching now.", "msg_1"),
                self.dispatch("tu_1", "scribe"),
                self.result("tu_1"),
                self.assistant_text("All delivered, no marker.", "msg_2"),
            ]
        )
        result = self.run_hook(self.payload(transcript))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("enforcement cap", result.stderr)

    def _make_dirty_repo(self) -> Path:
        repo = Path(self.temp.name) / "repo"
        repo.mkdir()

        def git(*args: str) -> None:
            subprocess.run(
                ["git", "-C", str(repo), *args],
                check=True,
                capture_output=True,
            )

        git("init", "-q", "-b", "main")
        git("config", "user.email", "test@example.invalid")
        git("config", "user.name", "Closeout Test")
        (repo / "base.txt").write_text("base\n", encoding="utf-8")
        git("add", "base.txt")
        git("commit", "-qm", "test: baseline")
        (repo / "residue.txt").write_text("left behind\n", encoding="utf-8")
        return repo

    def build_and_verify(self) -> list[dict[str, object]]:
        """builder then verifier, both resolved — the contract-correct shape."""
        return [
            self.dispatch("tu_1", "builder"),
            self.result("tu_1"),
            self.dispatch("tu_2", "verifier"),
            self.result("tu_2"),
        ]

    def test_dirty_tree_after_mutating_dispatch_blocks(self) -> None:
        """(g) builder ran, tree dirty, final message silent -> block mentions it."""
        repo = self._make_dirty_repo()
        transcript = self.write_transcript(
            [
                self.assistant_text("Dispatching now.", "msg_1"),
                *self.build_and_verify(),
                self.assistant_text("Feature finished.", "msg_2"),
            ]
        )
        result = self.run_hook(self.payload(transcript, cwd=str(repo)))
        self.assertEqual(result.returncode, 0, result.stderr)
        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("uncommitted", decision["reason"])

    def test_dirty_tree_acknowledged_with_report_allows(self) -> None:
        """(g) Marker plus an honest uncommitted acknowledgment -> allow."""
        repo = self._make_dirty_repo()
        transcript = self.write_transcript(
            [
                self.assistant_text("Dispatching now.", "msg_1"),
                *self.build_and_verify(),
                self.assistant_text(
                    "Feature finished. residue.txt remains uncommitted because the "
                    "human opted out of the commit.\n\n## Cost report\n\n"
                    "| Model | Cost |\n",
                    "msg_2",
                ),
            ]
        )
        result = self.run_hook(self.payload(transcript, cwd=str(repo)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    # --- the delivery ledger: machine-verifiable checks only --------------

    def _make_clean_repo(self) -> Path:
        repo = self._make_dirty_repo()
        subprocess.run(["git", "-C", str(repo), "add", "-A"],
                       check=True, capture_output=True)
        subprocess.run(["git", "-C", str(repo), "commit", "-qm", "test: residue"],
                       check=True, capture_output=True)
        return repo

    def closeout_text(self, extra: str = "") -> str:
        return (
            "Delivered. " + extra + "\n\n## Cost report\n\n| Model | Cost |\n"
        )

    def test_builder_without_verifier_blocks(self) -> None:
        """(h) Code work with no fresh verification -> block demands the verifier."""
        transcript = self.write_transcript(
            [
                self.dispatch("tu_1", "builder"),
                self.result("tu_1"),
                self.assistant_text(self.closeout_text(), "msg_2"),
            ]
        )
        result = self.run_hook(self.payload(transcript))
        self.assertEqual(result.returncode, 0, result.stderr)
        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("verifier", decision["reason"])

    def test_builder_then_verifier_allows(self) -> None:
        """(h) Verifier dispatched after the last builder -> no ledger block."""
        transcript = self.write_transcript(
            [
                *self.build_and_verify(),
                self.assistant_text(self.closeout_text(), "msg_2"),
            ]
        )
        result = self.run_hook(self.payload(transcript))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_verifier_before_final_builder_blocks(self) -> None:
        """(h) Verification predating the last code edit is stale."""
        transcript = self.write_transcript(
            [
                self.dispatch("tu_1", "verifier"),
                self.result("tu_1"),
                self.dispatch("tu_2", "builder"),
                self.result("tu_2"),
                self.assistant_text(self.closeout_text(), "msg_2"),
            ]
        )
        result = self.run_hook(self.payload(transcript))
        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("verifier", decision["reason"])

    def test_pause_marker_skips_verify_requirement(self) -> None:
        """(h) An intentional WORKFORCE_PAUSE is not a completion claim."""
        transcript = self.write_transcript(
            [
                self.dispatch("tu_1", "builder"),
                self.result("tu_1"),
                self.assistant_text(
                    "WORKFORCE_PAUSE: HUMAN_DECISION — awaiting the gate."
                    "\n\n## Cost report\n\n| Model | Cost |\n",
                    "msg_2",
                ),
            ]
        )
        result = self.run_hook(self.payload(transcript))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_phantom_commit_hash_blocks(self) -> None:
        """(i) A claimed commit hash absent from the object store -> block."""
        repo = self._make_clean_repo()
        transcript = self.write_transcript(
            [
                *self.build_and_verify(),
                self.assistant_text(
                    self.closeout_text("Committed as deadbee12345."), "msg_2"
                ),
            ]
        )
        result = self.run_hook(self.payload(transcript, cwd=str(repo)))
        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("deadbee12345", decision["reason"])

    def test_real_commit_hash_allows(self) -> None:
        """(i) A hash that exists in the checkout passes."""
        repo = self._make_clean_repo()
        head = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        transcript = self.write_transcript(
            [
                *self.build_and_verify(),
                self.assistant_text(
                    self.closeout_text(f"Committed as {head}."), "msg_2"
                ),
            ]
        )
        result = self.run_hook(self.payload(transcript, cwd=str(repo)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_missing_status_note_blocks(self) -> None:
        """(j) A cited docs/STATUS-*.md that is not on disk -> block."""
        transcript = self.write_transcript(
            [
                self.dispatch("tu_1", "scribe"),
                self.result("tu_1"),
                self.assistant_text(
                    self.closeout_text("Status note: docs/STATUS-csv-tool.md."),
                    "msg_2",
                ),
            ]
        )
        result = self.run_hook(self.payload(transcript))
        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("docs/STATUS-csv-tool.md", decision["reason"])

    def test_existing_status_note_allows(self) -> None:
        """(j) The cited status note exists -> no ledger block."""
        (self.cwd_dir / "docs").mkdir()
        (self.cwd_dir / "docs" / "STATUS-csv-tool.md").write_text(
            "outcome\n", encoding="utf-8"
        )
        transcript = self.write_transcript(
            [
                self.dispatch("tu_1", "scribe"),
                self.result("tu_1"),
                self.assistant_text(
                    self.closeout_text("Status note: docs/STATUS-csv-tool.md."),
                    "msg_2",
                ),
            ]
        )
        result = self.run_hook(self.payload(transcript))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_deployed_claim_without_deployer_blocks(self) -> None:
        """(k) "deployed" with no deployer dispatch -> block."""
        transcript = self.write_transcript(
            [
                *self.build_and_verify(),
                self.assistant_text(
                    self.closeout_text("Deployed to production."), "msg_2"
                ),
            ]
        )
        result = self.run_hook(self.payload(transcript))
        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("deployer", decision["reason"])

    def test_deployed_claim_with_deployer_allows(self) -> None:
        """(k) "deployed" after an actual deployer dispatch passes."""
        transcript = self.write_transcript(
            [
                *self.build_and_verify(),
                self.dispatch("tu_3", "deployer"),
                self.result("tu_3"),
                self.assistant_text(
                    self.closeout_text("Deployed and smoke-checked."), "msg_2"
                ),
            ]
        )
        result = self.run_hook(self.payload(transcript))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
