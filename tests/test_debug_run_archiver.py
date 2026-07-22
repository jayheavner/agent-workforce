#!/usr/bin/env python3
"""Tests for hooks/debug_run_archiver.py — trigger contract, dedup, fail-open.

A local bare git repo stands in for github.com/jayheavner/agent-workforce
(DEBUG_RUN_ARCHIVER_REMOTE), so no network or credentials are involved.
"""
import json
import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK = os.path.join(HERE, "..", "hooks", "debug_run_archiver.py")


def transcript_lines(cost_report=True, dispatched=True, in_flight=False):
    lines = []
    if dispatched:
        lines.append({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Agent", "id": "t1",
             "input": {"subagent_type": "builder"}}]}})
        if not in_flight:
            lines.append({"type": "user", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "t1",
                 "content": "done"}]}})
    text = "All finished.\n\n## Cost report\n| x |" if cost_report else "Working on it."
    lines.append({"type": "assistant", "message": {"content": [
        {"type": "text", "text": text}]}})
    return "\n".join(json.dumps(rec) for rec in lines) + "\n"


class ArchiverTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = self.tmp.name
        self.bare = os.path.join(root, "origin.git")
        subprocess.run(["git", "init", "--bare", "-b", "main", self.bare],
                       capture_output=True, check=True)
        seed = os.path.join(root, "seed")
        subprocess.run(["git", "clone", self.bare, seed], capture_output=True,
                       check=True)
        os.makedirs(os.path.join(seed, "debug-runs"))
        with open(os.path.join(seed, "debug-runs", "README.md"), "w") as f:
            f.write("seed\n")
        for cmd in (["add", "."],
                    ["-c", "user.email=t@t", "-c", "user.name=t",
                     "commit", "-q", "-m", "seed"],
                    ["push", "-q", "origin", "HEAD:main"]):
            subprocess.run(["git", "-C", seed] + cmd, capture_output=True,
                           check=True)
        self.state = os.path.join(root, "state")
        self.transcript = os.path.join(root, "transcript.jsonl")

    def tearDown(self):
        self.tmp.cleanup()

    def run_hook(self, event, session="sess-1", remote=None):
        payload = {"session_id": session, "transcript_path": self.transcript,
                   "hook_event_name": event}
        env = dict(os.environ,
                   DEBUG_RUN_ARCHIVER_STATE=self.state,
                   DEBUG_RUN_ARCHIVER_REMOTE=remote or self.bare)
        out = subprocess.run(["python3", HOOK], input=json.dumps(payload),
                             capture_output=True, text=True, env=env,
                             timeout=120)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout, "", "hook stdout must stay silent")
        return out

    def branch_files(self, session="sess-1"):
        """debug-runs/ listing on the session's transcript branch."""
        out = subprocess.run(
            ["git", "-C", self.bare, "ls-tree", "--name-only",
             "transcripts/%s" % session, "debug-runs/"],
            capture_output=True, text=True)
        return set(n for n in out.stdout.split() if not n.endswith("README.md"))

    def branch_tip(self, session="sess-1"):
        out = subprocess.run(["git", "-C", self.bare, "rev-parse",
                              "transcripts/%s" % session],
                             capture_output=True, text=True)
        return out.stdout.strip() if out.returncode == 0 else None

    def branch_file_content(self, relpath, session="sess-1"):
        out = subprocess.run(["git", "-C", self.bare, "show",
                              "transcripts/%s:%s" % (session, relpath)],
                             capture_output=True, text=True)
        return out.stdout

    def write_transcript(self, **kw):
        with open(self.transcript, "w") as f:
            f.write(transcript_lines(**kw))

    def test_stop_without_closeout_does_not_archive(self):
        self.write_transcript(cost_report=False)
        self.run_hook("Stop")
        self.assertIsNone(self.branch_tip())

    def test_stop_with_in_flight_dispatch_does_not_archive(self):
        self.write_transcript(in_flight=True)
        self.run_hook("Stop")
        self.assertIsNone(self.branch_tip())

    def test_stop_after_closeout_pushes_complete_transcript(self):
        self.write_transcript()
        self.run_hook("Stop")
        files = self.branch_files()
        self.assertEqual(len(files), 1)
        name = files.pop()
        self.assertIn("sess-1", name)
        self.assertTrue(name.endswith(".jsonl"))
        self.assertNotIn("-incomplete", name)
        self.assertEqual(self.branch_file_content(name), transcript_lines())

    def test_sessionend_without_closeout_pushes_incomplete(self):
        self.write_transcript(cost_report=False)
        self.run_hook("SessionEnd")
        files = self.branch_files()
        self.assertEqual(len(files), 1)
        self.assertIn("-incomplete", files.pop())

    def test_second_stop_same_size_pushes_nothing_new(self):
        self.write_transcript()
        self.run_hook("Stop")
        tip = self.branch_tip()
        self.run_hook("Stop")
        self.assertEqual(self.branch_tip(), tip)

    def test_grown_transcript_repushes_same_file_on_sessionend(self):
        self.write_transcript()
        self.run_hook("Stop")
        with open(self.transcript, "a") as f:
            f.write(json.dumps({"type": "assistant", "message": {"content": [
                {"type": "text", "text": "postscript"}]}}) + "\n")
        self.run_hook("SessionEnd")
        files = self.branch_files()
        self.assertEqual(len(files), 1)  # same filename, updated content
        name = files.pop()
        self.assertNotIn("-incomplete", name)
        self.assertIn("postscript", self.branch_file_content(name))

    def test_complete_supersedes_earlier_incomplete(self):
        self.write_transcript(cost_report=False)
        self.run_hook("SessionEnd")  # -incomplete pushed
        self.write_transcript(cost_report=True)
        self.run_hook("SessionEnd")  # session resumed, then completed
        files = self.branch_files()
        self.assertEqual(len(files), 1)
        self.assertNotIn("-incomplete", files.pop())

    def test_unreachable_remote_fails_open(self):
        self.write_transcript()
        out = self.run_hook("Stop",
                            remote=os.path.join(self.tmp.name, "nope.git"))
        self.assertIn("clone failed", out.stderr)


if __name__ == "__main__":
    unittest.main()
