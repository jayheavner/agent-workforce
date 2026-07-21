#!/usr/bin/env python3
"""Tests for hooks/debug_run_archiver.py — trigger contract, dedup, fail-open.

Uses a local bare git repo as the sidecar (DEBUG_RUN_ARCHIVER_URL) so no
network or SSH is involved; DEBUG_RUN_ARCHIVER_KEY points at a dummy file
because the archiver requires a key file to exist before it will push.
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
        self.bare = os.path.join(root, "sidecar.git")
        subprocess.run(["git", "init", "--bare", "-b", "main", self.bare],
                       capture_output=True, check=True)
        # bare repos need one commit so clone succeeds with a main branch
        seed = os.path.join(root, "seed")
        subprocess.run(["git", "clone", self.bare, seed], capture_output=True,
                       check=True)
        open(os.path.join(seed, "README.md"), "w").write("seed\n")
        for cmd in (["add", "."],
                    ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "seed"],
                    ["push", "origin", "HEAD:main"]):
            subprocess.run(["git", "-C", seed] + cmd, capture_output=True, check=True)
        self.state = os.path.join(root, "state")
        self.key = os.path.join(root, "key")
        open(self.key, "w").write("dummy\n")
        self.transcript = os.path.join(root, "transcript.jsonl")

    def tearDown(self):
        self.tmp.cleanup()

    def run_hook(self, event, session="sess-1", key=None):
        payload = {"session_id": session, "transcript_path": self.transcript,
                   "hook_event_name": event}
        env = dict(os.environ,
                   DEBUG_RUN_ARCHIVER_STATE=self.state,
                   DEBUG_RUN_ARCHIVER_URL=self.bare,
                   DEBUG_RUN_ARCHIVER_KEY=key or self.key)
        out = subprocess.run(["python3", HOOK], input=json.dumps(payload),
                             capture_output=True, text=True, env=env, timeout=120)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout, "", "hook stdout must stay silent")
        return out

    def sidecar_files(self):
        out = subprocess.run(["git", "-C", self.bare, "ls-tree", "--name-only",
                              "main"], capture_output=True, text=True)
        return set(out.stdout.split())

    def write_transcript(self, **kw):
        open(self.transcript, "w").write(transcript_lines(**kw))

    def test_stop_without_closeout_does_not_archive(self):
        self.write_transcript(cost_report=False)
        self.run_hook("Stop")
        self.assertEqual(self.sidecar_files(), {"README.md"})

    def test_stop_with_in_flight_dispatch_does_not_archive(self):
        self.write_transcript(in_flight=True)
        self.run_hook("Stop")
        self.assertEqual(self.sidecar_files(), {"README.md"})

    def test_stop_after_closeout_archives_complete(self):
        self.write_transcript()
        self.run_hook("Stop")
        names = self.sidecar_files() - {"README.md"}
        self.assertEqual(len(names), 1)
        name = names.pop()
        self.assertIn("sess-1", name)
        self.assertTrue(name.endswith(".jsonl"))
        self.assertNotIn("-incomplete", name)

    def test_sessionend_without_closeout_archives_incomplete(self):
        self.write_transcript(cost_report=False)
        self.run_hook("SessionEnd")
        names = self.sidecar_files() - {"README.md"}
        self.assertEqual(len(names), 1)
        self.assertIn("-incomplete", names.pop())

    def test_second_stop_same_size_pushes_nothing_new(self):
        self.write_transcript()
        self.run_hook("Stop")
        head = subprocess.run(["git", "-C", self.bare, "rev-parse", "main"],
                              capture_output=True, text=True).stdout
        self.run_hook("Stop")
        head2 = subprocess.run(["git", "-C", self.bare, "rev-parse", "main"],
                               capture_output=True, text=True).stdout
        self.assertEqual(head, head2)

    def test_grown_transcript_rearchives_on_sessionend(self):
        self.write_transcript()
        self.run_hook("Stop")
        with open(self.transcript, "a") as f:
            f.write(json.dumps({"type": "assistant", "message": {"content": [
                {"type": "text", "text": "postscript"}]}}) + "\n")
        self.run_hook("SessionEnd")
        names = self.sidecar_files() - {"README.md"}
        self.assertEqual(len(names), 1)  # same filename, updated content

    def test_missing_key_fails_open(self):
        self.write_transcript()
        out = self.run_hook("Stop", key=os.path.join(self.tmp.name, "nope"))
        self.assertIn("deploy key missing", out.stderr)
        self.assertEqual(self.sidecar_files(), {"README.md"})


if __name__ == "__main__":
    unittest.main()
