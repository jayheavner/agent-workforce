#!/usr/bin/env python3
"""Tests for hooks/debug_run_archiver.py — trigger contract, dedup, fail-open.

A local HTTP stub stands in for the ingest service: POST / issues a
"presigned" grant naming the server-derived key (mirroring the Lambda's key
logic), POST /upload/<key> accepts the multipart upload. No network, no AWS.
"""
import gzip
import json
import os
import re
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

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


class StubIngest(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        store = self.server.store
        if self.path == "/":
            meta = json.loads(body)
            key = "%s-%s%s.jsonl.gz" % (
                meta["day"], meta["session_id"],
                "" if meta["complete"] else "-incomplete")
            grant = {"url": "http://127.0.0.1:%d/upload/%s"
                            % (self.server.server_port, key),
                     "fields": {"key": key, "policy": "stub-policy"}}
            payload = json.dumps(grant).encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        match = re.match(r"^/upload/(.+)$", self.path)
        boundary = self.headers.get("Content-Type", "").split("boundary=")[-1]
        payload = None
        for part in body.split(b"--" + boundary.encode()):
            head, _, rest = part.partition(b"\r\n\r\n")
            if b'name="file"' in head:
                payload = rest.rstrip(b"\r\n-")
        if not (match and boundary and payload is not None):
            self.send_response(400)
            self.end_headers()
            return
        store["files"][match.group(1)] = payload
        store["uploads"] = store.get("uploads", 0) + 1
        self.send_response(204)
        self.end_headers()


class ArchiverTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.state = os.path.join(self.tmp.name, "state")
        self.transcript = os.path.join(self.tmp.name, "transcript.jsonl")
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), StubIngest)
        self.server.store = {"files": {}, "uploads": 0}
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = "http://127.0.0.1:%d/" % self.server.server_port

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.tmp.cleanup()

    def run_hook(self, event, session="sess-1", url=None):
        payload = {"session_id": session, "transcript_path": self.transcript,
                   "hook_event_name": event}
        env = dict(os.environ,
                   DEBUG_RUN_ARCHIVER_STATE=self.state,
                   DEBUG_RUN_ARCHIVER_URL=url if url is not None else self.url)
        out = subprocess.run(["python3", HOOK], input=json.dumps(payload),
                             capture_output=True, text=True, env=env, timeout=120)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout, "", "hook stdout must stay silent")
        return out

    def files(self):
        return self.server.store["files"]

    def write_transcript(self, **kw):
        with open(self.transcript, "w") as f:
            f.write(transcript_lines(**kw))

    def test_stop_without_closeout_does_not_archive(self):
        self.write_transcript(cost_report=False)
        self.run_hook("Stop")
        self.assertEqual(self.files(), {})

    def test_stop_with_in_flight_dispatch_does_not_archive(self):
        self.write_transcript(in_flight=True)
        self.run_hook("Stop")
        self.assertEqual(self.files(), {})

    def test_stop_after_closeout_uploads_complete_gzip(self):
        self.write_transcript()
        self.run_hook("Stop")
        self.assertEqual(len(self.files()), 1)
        name, blob = next(iter(self.files().items()))
        self.assertIn("sess-1", name)
        self.assertTrue(name.endswith(".jsonl.gz"))
        self.assertNotIn("-incomplete", name)
        self.assertEqual(gzip.decompress(blob).decode(), transcript_lines())

    def test_sessionend_without_closeout_uploads_incomplete(self):
        self.write_transcript(cost_report=False)
        self.run_hook("SessionEnd")
        self.assertEqual(len(self.files()), 1)
        self.assertIn("-incomplete", next(iter(self.files())))

    def test_second_stop_same_size_uploads_nothing_new(self):
        self.write_transcript()
        self.run_hook("Stop")
        self.run_hook("Stop")
        self.assertEqual(self.server.store["uploads"], 1)

    def test_grown_transcript_reuploads_same_key_on_sessionend(self):
        self.write_transcript()
        self.run_hook("Stop")
        with open(self.transcript, "a") as f:
            f.write(json.dumps({"type": "assistant", "message": {"content": [
                {"type": "text", "text": "postscript"}]}}) + "\n")
        self.run_hook("SessionEnd")
        self.assertEqual(self.server.store["uploads"], 2)
        self.assertEqual(len(self.files()), 1)  # same key, updated content
        self.assertNotIn("-incomplete", next(iter(self.files())))

    def test_no_endpoint_fails_open(self):
        self.write_transcript()
        out = self.run_hook("Stop", url="")
        self.assertIn("no ingest endpoint", out.stderr)

    def test_unreachable_endpoint_fails_open(self):
        self.write_transcript()
        out = self.run_hook("Stop", url="http://127.0.0.1:1/")
        self.assertIn("upload failed", out.stderr)


if __name__ == "__main__":
    unittest.main()
