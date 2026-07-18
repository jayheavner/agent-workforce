#!/usr/bin/env python3
"""Behavior tests for the Agent Workforce closeout hook."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / "hooks" / "agent_team_closeout.py"
LINTER = ROOT / "tools" / "lint_completion_claims.py"

SPEC = importlib.util.spec_from_file_location("agent_team_closeout", HOOK)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load closeout hook from {HOOK}")
guard = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = guard
SPEC.loader.exec_module(guard)


SHIPPABLE = """Closeout complete.

## Delivery receipt

- delivery-target: artifact
- shipment-verdict: SHIPPABLE
- verification: pass — focused and full suite green
- review: pass — approved
- documentation: pass — status recorded
- memory: not applicable
- commit: pass — scoped commit created
- integration: not applicable
- deployment: not applicable
- cleanup: pass — task-created resources removed
- cost-report: pass — see session cost file
"""

NOT_SHIPPABLE = """Implemented, but an external release action remains blocked.

## Delivery receipt

- delivery-target: integrated-code
- shipment-verdict: NOT SHIPPABLE
- verification: pending — environment unavailable
- review: pass — approved
- documentation: pass — status recorded
- memory: not applicable
- commit: pending — external signing unavailable
- integration: pending — external approval required
- deployment: not applicable
- cleanup: pending — waits for integration
"""


class CloseoutHookTest(unittest.TestCase):
    """Exercise hook behavior through its event-processing interface."""

    def setUp(self) -> None:
        """Create an isolated Git repository and hook state directory."""
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.repo = root / "repo"
        self.state_dir = root / "state"
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Closeout Test")
        (self.repo / "README.md").write_text("base\n", encoding="utf-8")
        self.git("add", "README.md")
        self.git("commit", "-qm", "test: baseline")

    def git(self, *args: str) -> str:
        """Run Git in the fixture repository and return stdout."""
        return subprocess.run(
            ["git", "-C", str(self.repo), *args],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout.strip()

    def event(self, mode: str, payload: dict[str, object]):
        """Process one hook event with fixture-local state and linter paths."""
        return guard.process_event(
            mode,
            payload,
            state_dir=self.state_dir,
            linter_path=LINTER,
        )

    def dispatch(self, role: str = "scribe") -> None:
        """Record a mutating specialist dispatch for the fixture session."""
        result = self.event(
            "dispatch",
            {
                "session_id": "session-1",
                "cwd": str(self.repo),
                "tool_name": "Agent",
                "tool_input": {"subagent_type": role},
            },
        )
        self.assertEqual(result.exit_code, 0, result.stderr)

    def stop(self, message: str = SHIPPABLE, transcript_path: str = ""):
        """Evaluate a main-agent Stop event."""
        payload = {
            "session_id": "session-1",
            "cwd": str(self.repo),
            "stop_hook_active": False,
            "last_assistant_message": message,
        }
        if transcript_path:
            payload["transcript_path"] = transcript_path
        return self.event("stop", payload)

    def write_transcript(self, *, resolved: bool) -> str:
        """Write a fixture JSONL transcript with one Agent dispatch.

        `resolved=False` leaves the tool_use without a matching tool_result
        (an in-flight subagent dispatch); `resolved=True` pairs it.
        """
        path = Path(self.temp.name) / "transcript.jsonl"
        tool_use_id = "toolu_fixture0000000000000000000001"
        lines = [
            json.dumps(
                {
                    "type": "assistant",
                    "message": {
                        "role": "assistant",
                        "content": [
                            {
                                "type": "tool_use",
                                "id": tool_use_id,
                                "name": "Agent",
                                "input": {"subagent_type": "builder"},
                            }
                        ],
                    },
                }
            )
        ]
        if resolved:
            lines.append(
                json.dumps(
                    {
                        "type": "user",
                        "message": {
                            "role": "user",
                            "content": [
                                {
                                    "type": "tool_result",
                                    "tool_use_id": tool_use_id,
                                    "content": [{"type": "text", "text": "done"}],
                                }
                            ],
                        },
                    }
                )
            )
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return str(path)

    def subagent_stop(self, role: str, message: str):
        """Record one specialist terminal response."""
        return self.event(
            "subagent-stop",
            {
                "session_id": "session-1",
                "cwd": str(self.repo),
                "agent_type": role,
                "last_assistant_message": message,
            },
        )

    def test_stop_blocks_task_owned_uncommitted_file(self) -> None:
        """A file created after the baseline must be finalized before stopping."""
        self.dispatch()
        (self.repo / "docs.md").write_text("task artifact\n", encoding="utf-8")

        result = self.stop()

        self.assertEqual(result.exit_code, 0, result.stderr)
        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("uncommitted", decision["reason"].lower())
        self.assertIn("executor", decision["reason"].lower())

    def test_stop_never_attributes_ownership_it_cannot_know(self) -> None:
        """The hook cannot know which process wrote a changed baseline-dirty path."""
        (self.repo / "README.md").write_text("user dirt\n", encoding="utf-8")
        self.dispatch("scribe")
        (self.repo / "README.md").write_text("user dirt plus task edit\n", encoding="utf-8")

        result = self.stop()

        decision = json.loads(result.stdout)
        self.assertIn("README.md", decision["reason"])
        self.assertNotIn("Task-owned", decision["reason"])
        self.assertIn("cannot attribute", decision["reason"].lower())

    def test_stop_labels_new_file_as_created_this_session_not_task_owned(self) -> None:
        """A path absent at baseline is reported as created, never claimed as task-owned."""
        self.dispatch()
        (self.repo / "newfile.png").write_bytes(b"\x89PNG\r\n")

        result = self.stop()

        decision = json.loads(result.stdout)
        self.assertIn("newfile.png", decision["reason"])
        self.assertIn("created during this session", decision["reason"])
        self.assertNotIn("Task-owned", decision["reason"])

    def test_stop_requires_delivery_receipt_for_active_repository_task(self) -> None:
        """An active task cannot end with an unstructured completion report."""
        self.dispatch()

        result = self.stop("Everything is finished.")

        self.assertEqual(result.exit_code, 0, result.stderr)
        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("delivery receipt", decision["reason"].lower())

    def test_stop_allows_explicit_human_decision_pause(self) -> None:
        """A genuine decision gate may pause without pretending delivery is complete."""
        self.dispatch()

        result = self.stop("WORKFORCE_PAUSE: HUMAN_DECISION\nChoose the release window.")

        self.assertEqual(result.exit_code, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_stop_allows_waiting_on_inflight_dispatch_despite_dirty_tree(self) -> None:
        """An unresolved subagent dispatch is waiting, not a completion claim."""
        self.dispatch("builder")
        (self.repo / "docs.md").write_text("task artifact\n", encoding="utf-8")
        transcript = self.write_transcript(resolved=False)

        result = self.stop("", transcript_path=transcript)

        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")

    def test_stop_blocks_normally_once_dispatch_resolves(self) -> None:
        """Once the tool_result lands, ordinary Stop enforcement resumes."""
        self.dispatch("builder")
        (self.repo / "docs.md").write_text("task artifact\n", encoding="utf-8")
        transcript = self.write_transcript(resolved=True)

        result = self.stop("", transcript_path=transcript)

        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")

    def test_shippable_verdict_blocked_while_dispatch_in_flight(self) -> None:
        """A SHIPPABLE claim cannot be final while a dispatch is still running."""
        self.dispatch("builder")
        (self.repo / "feature.py").write_text("VALUE = 1\n", encoding="utf-8")
        self.git("add", "feature.py")
        self.git("commit", "-qm", "feat: add fixture feature")
        transcript = self.write_transcript(resolved=False)

        result = self.stop(SHIPPABLE, transcript_path=transcript)

        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("flight", decision["reason"].lower())

    def test_shippable_builder_work_requires_fresh_verifier(self) -> None:
        """A committed Builder change is not shippable before verification."""
        self.dispatch("builder")
        (self.repo / "feature.py").write_text("VALUE = 1\n", encoding="utf-8")
        self.git("add", "feature.py")
        self.git("commit", "-qm", "feat: add fixture feature")

        result = self.stop()

        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("verifier", decision["reason"].lower())

    def test_passing_verifier_and_reviewer_unlock_shippable_stop(self) -> None:
        """Fresh terminal markers satisfy the Builder evidence boundary."""
        self.dispatch("builder")
        (self.repo / "feature.py").write_text("VALUE = 1\n", encoding="utf-8")
        self.git("add", "feature.py")
        self.git("commit", "-qm", "feat: add fixture feature")

        verify = self.subagent_stop(
            "verifier",
            "WORKFORCE_VERIFICATION: verdict=SHIPPABLE; full_suite=pass",
        )
        review = self.subagent_stop(
            "reviewer",
            "WORKFORCE_REVIEW: verdict=approve",
        )
        result = self.stop()

        self.assertEqual(verify.stdout, "")
        self.assertEqual(review.stdout, "")
        self.assertEqual(result.stdout, "")

    def test_allowed_terminal_stop_clears_session_state(self) -> None:
        """A later ordinary turn is not captured by a completed task's state."""
        self.dispatch("scribe")
        (self.repo / "task.md").write_text("task artifact\n", encoding="utf-8")
        self.git("add", "task.md")
        self.git("commit", "-qm", "docs: add task artifact")

        completed = self.stop()
        (self.repo / "later.txt").write_text("unrelated later turn\n", encoding="utf-8")
        later = self.stop("Ordinary response after completion.")

        self.assertEqual(completed.stdout, "")
        self.assertEqual(later.stdout, "")

    def test_shippable_repository_task_requires_a_new_commit(self) -> None:
        """A clean tree alone cannot satisfy the task's commit receipt."""
        self.dispatch("scribe")

        result = self.stop()

        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("commit", decision["reason"].lower())

    def test_shippable_requires_a_commit_descended_from_the_baseline(self) -> None:
        """Switching to an unrelated pre-existing commit cannot satisfy delivery."""
        self.git("checkout", "-qb", "side")
        (self.repo / "side.md").write_text("side history\n", encoding="utf-8")
        self.git("add", "side.md")
        self.git("commit", "-qm", "test: add side history")
        self.git("checkout", "-q", "main")
        self.dispatch("scribe")
        self.git("checkout", "-q", "side")

        result = self.stop()

        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("commit", decision["reason"].lower())

    def test_committed_task_preserves_preexisting_dirty_file(self) -> None:
        """Unchanged baseline dirt may coexist with a properly committed task."""
        (self.repo / "README.md").write_text("user dirt\n", encoding="utf-8")
        self.dispatch("scribe")
        (self.repo / "task.md").write_text("task artifact\n", encoding="utf-8")
        self.git("add", "task.md")
        self.git("commit", "-qm", "docs: add task artifact")

        result = self.stop()

        self.assertEqual(result.stdout, "")
        self.assertIn("README.md", self.git("status", "--short"))

    def test_changed_preexisting_dirty_file_is_task_residue(self) -> None:
        """Changing a dirty baseline path cannot be hidden by committing another file."""
        (self.repo / "README.md").write_text("user dirt\n", encoding="utf-8")
        self.dispatch("scribe")
        (self.repo / "README.md").write_text("user dirt plus task edit\n", encoding="utf-8")
        (self.repo / "task.md").write_text("task artifact\n", encoding="utf-8")
        self.git("add", "task.md")
        self.git("commit", "-qm", "docs: add task artifact")

        result = self.stop()

        decision = json.loads(result.stdout)
        self.assertIn("README.md", decision["reason"])

    def test_not_shippable_report_may_stop_without_fake_green_evidence(self) -> None:
        """A truthful blocked report is allowed when no local residue remains."""
        self.dispatch("builder")

        result = self.stop(NOT_SHIPPABLE)

        self.assertEqual(result.stdout, "")

    def test_second_builder_dispatch_invalidates_prior_evidence(self) -> None:
        """Verification and review become stale after another Builder pass."""
        self.dispatch("builder")
        (self.repo / "feature.py").write_text("VALUE = 1\n", encoding="utf-8")
        self.git("add", "feature.py")
        self.git("commit", "-qm", "feat: add fixture feature")
        self.subagent_stop(
            "verifier",
            "WORKFORCE_VERIFICATION: verdict=SHIPPABLE; full_suite=pass",
        )
        self.subagent_stop("reviewer", "WORKFORCE_REVIEW: verdict=approve")

        self.dispatch("builder")
        result = self.stop()

        decision = json.loads(result.stdout)
        self.assertIn("verifier", decision["reason"].lower())

    def test_subagent_stop_blocks_missing_terminal_marker(self) -> None:
        """Verifier and reviewer evidence must be machine-readable."""
        self.dispatch("builder")

        result = self.subagent_stop("verifier", "The tests looked fine.")

        decision = json.loads(result.stdout)
        self.assertEqual(decision["decision"], "block")
        self.assertIn("WORKFORCE_VERIFICATION", decision["reason"])

    def test_request_changes_does_not_unlock_shippable_stop(self) -> None:
        """A reviewer request for changes remains a completion blocker."""
        self.dispatch("builder")
        (self.repo / "feature.py").write_text("VALUE = 1\n", encoding="utf-8")
        self.git("add", "feature.py")
        self.git("commit", "-qm", "feat: add fixture feature")
        self.subagent_stop(
            "verifier",
            "WORKFORCE_VERIFICATION: verdict=SHIPPABLE; full_suite=pass",
        )
        self.subagent_stop("reviewer", "WORKFORCE_REVIEW: verdict=request-changes")

        result = self.stop()

        decision = json.loads(result.stdout)
        self.assertIn("reviewer", decision["reason"].lower())

    def test_stop_without_active_workforce_state_is_noop(self) -> None:
        """Ordinary non-workforce conversations are not intercepted."""
        result = self.stop("No repository task was started.")

        self.assertEqual(result.stdout, "")

    def test_content_signature_handles_existing_non_file_path(self) -> None:
        """Baseline hashing remains defined for a special or directory path."""
        signature = guard._content_signature(self.repo)

        self.assertRegex(signature, r"^[0-9a-f]{64}$")

    def test_shippable_stop_blocks_task_created_cleanup_candidate(self) -> None:
        """A merged clean task worktree must be removed before shippable closeout."""
        self.dispatch("scribe")
        linked = Path(self.temp.name) / "linked"
        self.git("branch", "task-cleanup")
        self.git("worktree", "add", "-q", str(linked), "task-cleanup")
        (linked / "task.md").write_text("task artifact\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(linked), "add", "task.md"], check=True)
        subprocess.run(
            ["git", "-C", str(linked), "commit", "-qm", "docs: add task artifact"],
            check=True,
        )
        self.git("merge", "--no-ff", "-qm", "merge: task cleanup fixture", "task-cleanup")

        result = self.stop()

        decision = json.loads(result.stdout)
        self.assertIn("cleanup", decision["reason"].lower())
        self.assertIn(str(linked), decision["reason"])

    def test_cli_stop_without_active_state_exits_cleanly(self) -> None:
        """The installed command-hook seam accepts valid Stop JSON."""
        payload = {
            "session_id": "no-state",
            "cwd": str(self.repo),
            "last_assistant_message": "ordinary response",
        }
        stdout = io.StringIO()
        stderr = io.StringIO()
        environment = {
            "AGENT_TEAM_CLOSEOUT_DIR": str(self.state_dir),
            "AGENT_TEAM_COMPLETION_LINTER": str(LINTER),
        }
        with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))):
            with mock.patch.dict(os.environ, environment, clear=False):
                with redirect_stdout(stdout), redirect_stderr(stderr):
                    result = guard.main(["stop"])

        self.assertEqual(result, 0)
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(stderr.getvalue(), "")

    def test_cli_rejects_bad_arguments_and_invalid_json(self) -> None:
        """Malformed hook calls fail visibly instead of disabling enforcement."""
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            missing_mode = guard.main([])
        self.assertEqual(missing_mode, 2)
        self.assertIn("usage", stderr.getvalue())

        stderr = io.StringIO()
        with mock.patch.object(sys, "stdin", io.StringIO("not-json")):
            with redirect_stderr(stderr):
                invalid_json = guard.main(["stop"])
        self.assertEqual(invalid_json, 2)
        self.assertIn("invalid closeout hook JSON", stderr.getvalue())

    def test_cli_stop_fails_closed_when_persisted_state_is_corrupt(self) -> None:
        """A damaged state file cannot silently disable terminal enforcement."""
        state_path = guard._state_path(self.state_dir, "session-1")
        state_path.parent.mkdir(parents=True)
        state_path.write_text("{not-json", encoding="utf-8")
        payload = {
            "session_id": "session-1",
            "cwd": str(self.repo),
            "last_assistant_message": SHIPPABLE,
        }
        stdout = io.StringIO()
        with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))):
            with mock.patch.dict(
                os.environ,
                {
                    "AGENT_TEAM_CLOSEOUT_DIR": str(self.state_dir),
                    "AGENT_TEAM_COMPLETION_LINTER": str(LINTER),
                },
                clear=False,
            ):
                with redirect_stdout(stdout):
                    result = guard.main(["stop"])

        self.assertEqual(result, 0)
        decision = json.loads(stdout.getvalue())
        self.assertEqual(decision["decision"], "block")
        self.assertIn("failed closed", decision["reason"].lower())

    def test_cli_reports_unknown_mode(self) -> None:
        """Unknown adapters fail closed with the mode named."""
        payload = {"session_id": "session-1", "cwd": str(self.repo)}
        stderr = io.StringIO()
        with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))):
            with redirect_stderr(stderr):
                result = guard.main(["unknown"])

        self.assertEqual(result, 2)
        self.assertIn("unknown closeout hook mode", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
