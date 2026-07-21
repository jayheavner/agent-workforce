#!/usr/bin/env python3
"""debug_run_archiver.py — archive session transcripts for the debug-runs pipeline.

Fires on Stop and SessionEnd. Goal: a tester's transcript lands in the
quarantine bucket with zero tester effort and zero tester-held secrets; the
sync-debug-runs GitHub Action then mirrors it into debug-runs/ in the main
repo via an OIDC-assumed role.

Trigger contract (decided 2026-07-21):
- Stop: archive only when the session has reached a passing closeout — the
  final message carries the cost report marker and no dispatches are in
  flight. That is the same machine-checked definition of "task complete" the
  closeout hook enforces, recomputed here so ordering between parallel Stop
  hooks never matters.
- SessionEnd: safety net. Archive whatever exists, suffixed "-incomplete"
  when the session never reached a closeout, so abandoned runs are captured
  too. Re-archives (overwrites) if the transcript grew after an earlier
  Stop archive.

Transport (zero-secret, decided 2026-07-21 after the deploy-key design was
rejected): POST session metadata to the public ingest Function URL
(hooks/debug-runs-endpoint, committed — it is not a credential; its only
capability is granting a presigned upload of one server-named object into
the private quarantine bucket), then upload the gzipped transcript with the
returned presigned POST. Every failure path is fail-open: this hook must
never block a stop or an exit, and never prints to stdout (a Stop hook's
stdout is a decision channel).
"""
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from agent_team_closeout import COST_MARKER, scan_transcript  # noqa: E402

CURL_TIMEOUT = 120


def warn(msg):
    print("debug-run archiver: " + msg, file=sys.stderr)


def state_root():
    return os.environ.get(
        "DEBUG_RUN_ARCHIVER_STATE",
        os.path.expanduser("~/.claude/state/agent-workforce-debug-runs"))


def marker_path(session_id):
    root = state_root()
    os.makedirs(root, exist_ok=True)
    digest = hashlib.sha256(session_id.encode()).hexdigest()
    return os.path.join(root, digest + ".json")


def load_marker(session_id):
    try:
        with open(marker_path(session_id)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_marker(session_id, data):
    try:
        with open(marker_path(session_id), "w") as f:
            json.dump(data, f)
    except OSError:
        pass


def closeout_reached(transcript):
    """The Stop-trigger test: cost report present, nothing in flight."""
    total, in_flight, _roles, _order, last_text = scan_transcript(transcript)
    return total > 0 and not in_flight and COST_MARKER in last_text


def endpoint():
    override = os.environ.get("DEBUG_RUN_ARCHIVER_URL")
    if override is not None:  # explicit override is authoritative (tests)
        return override or None
    for path in (os.path.join(HERE, "debug-runs-endpoint"),
                 os.path.expanduser("~/.claude/hooks/debug-runs-endpoint")):
        try:
            with open(path) as f:
                url = f.readline().strip()
            if url.startswith("http"):
                return url
        except OSError:
            continue
    return None


def curl(*args):
    return subprocess.run(["curl", "-sf", "-m", str(CURL_TIMEOUT), *args],
                          capture_output=True, text=True,
                          timeout=CURL_TIMEOUT + 10)


def upload(url, session_id, day, complete, gz_path):
    """Presign then upload. Returns True on success."""
    meta = json.dumps({"session_id": session_id, "day": day,
                       "complete": complete})
    for _attempt in range(3):
        presign = curl("-X", "POST", "-H", "content-type: application/json",
                       "-d", meta, url)
        if presign.returncode != 0:
            continue
        try:
            grant = json.loads(presign.stdout)
            post_url, fields = grant["url"], grant["fields"]
        except (ValueError, KeyError, TypeError):
            warn("presign response was not a valid grant")
            return False
        form = []
        for k, v in fields.items():  # S3 requires the file part last
            form += ["-F", "%s=%s" % (k, v)]
        form += ["-F", "file=@%s" % gz_path]
        put = curl("-o", "/dev/null", *form, post_url)
        if put.returncode == 0:
            return True
    warn("upload failed after 3 attempts")
    return False


def archive(session_id, transcript, complete):
    marker = load_marker(session_id)
    try:
        size = os.path.getsize(transcript)
    except OSError:
        return
    if marker.get("archived") and size == marker.get("size", -1):
        return  # nothing new since the last archive of this session
    url = endpoint()
    if not url:
        warn("no ingest endpoint configured; transcript not archived")
        return
    day = marker.get("day") or time.strftime("%Y-%m-%d")
    complete = complete or marker.get("complete", False)
    gz_path = os.path.join(state_root(), "upload.jsonl.gz")
    os.makedirs(state_root(), exist_ok=True)
    try:
        with open(transcript, "rb") as src, gzip.open(gz_path, "wb") as dst:
            shutil.copyfileobj(src, dst)
    except OSError as exc:
        warn("gzip failed: %s" % exc)
        return
    try:
        if upload(url, session_id, day, complete, gz_path):
            save_marker(session_id, {"archived": True, "size": size,
                                     "day": day, "complete": complete})
    finally:
        try:
            os.unlink(gz_path)
        except OSError:
            pass


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    session_id = payload.get("session_id") or ""
    transcript = payload.get("transcript_path") or ""
    event = payload.get("hook_event_name") or ""
    if not session_id or not os.path.isfile(transcript):
        return
    if event == "Stop":
        if closeout_reached(transcript):
            archive(session_id, transcript, complete=True)
    else:  # SessionEnd (or anything else): safety net
        archive(session_id, transcript, complete=closeout_reached(transcript))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # never block a stop/exit
        warn("unexpected error: %r" % exc)
    sys.exit(0)
