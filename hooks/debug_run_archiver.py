#!/usr/bin/env python3
"""debug_run_archiver.py — archive session transcripts for the debug-runs pipeline.

Fires on Stop and SessionEnd. Goal: a tester's transcript lands in
debug-runs/ on main with zero tester effort and zero distributed secrets.

Trigger contract (decided 2026-07-21):
- Stop: archive only when the session has reached a passing closeout — the
  final message carries the cost report marker and no dispatches are in
  flight. That is the same machine-checked definition of "task complete" the
  closeout hook enforces, recomputed here so ordering between parallel Stop
  hooks never matters.
- SessionEnd: safety net. Archive whatever exists, suffixed "-incomplete"
  when the session never reached a closeout, so abandoned runs are captured
  too. Re-archives (force-push) if the transcript grew after an earlier
  Stop archive.

Transport (decided 2026-07-22, after deploy-key and AWS designs were
rejected): the tester's own GitHub identity. Each tester is a collaborator;
the hook pushes the transcript to a per-session branch
(transcripts/<session-id>) in a private shallow clone under the state dir,
using whatever git credentials the machine already has. The sync-debug-runs
Action folds ONLY the debug-runs/ paths of those branches into main and
deletes them; a ruleset keeps main itself locked. Every failure path is
fail-open: this hook must never block a stop or an exit, and never prints
to stdout (a Stop hook's stdout is a decision channel).
"""
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

DEFAULT_REMOTE = "https://github.com/jayheavner/agent-workforce.git"
GIT_TIMEOUT = 60


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


def git(clone, *args):
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")  # never hang on a prompt
    return subprocess.run(["git", "-C", clone, *args], env=env,
                          capture_output=True, text=True, timeout=GIT_TIMEOUT)


def tail(proc):
    err = (proc.stderr or "").strip()
    return err.splitlines()[-1] if err else "no error output"


def ensure_clone(remote):
    clone = os.path.join(state_root(), "repo")
    if not os.path.isdir(os.path.join(clone, ".git")):
        env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
        out = subprocess.run(
            ["git", "clone", "--depth", "1", remote, clone], env=env,
            capture_output=True, text=True, timeout=GIT_TIMEOUT * 3)
        if out.returncode != 0:
            warn("clone failed: " + tail(out))
            return None
        git(clone, "config", "user.name", "debug-run archiver")
        git(clone, "config", "user.email", "archiver@agent-workforce")
    fetch = git(clone, "fetch", "--depth", "1", "origin", "main")
    if fetch.returncode != 0:
        warn("fetch failed: " + tail(fetch))
        return None
    return clone


def archive(session_id, transcript, complete):
    marker = load_marker(session_id)
    try:
        size = os.path.getsize(transcript)
    except OSError:
        return
    if marker.get("archived") and size == marker.get("size", -1):
        return  # nothing new since the last archive of this session
    remote = os.environ.get("DEBUG_RUN_ARCHIVER_REMOTE", DEFAULT_REMOTE)
    clone = ensure_clone(remote)
    if not clone:
        return
    day = marker.get("day") or time.strftime("%Y-%m-%d")
    complete = complete or marker.get("complete", False)
    suffix = "" if complete else "-incomplete"
    relpath = "debug-runs/%s-%s%s.jsonl" % (day, session_id, suffix)

    git(clone, "checkout", "-B", "upload", "origin/main")
    # a completed archive supersedes an earlier -incomplete one
    if complete:
        git(clone, "rm", "-q", "--ignore-unmatch",
            "debug-runs/%s-%s-incomplete.jsonl" % (day, session_id))
    os.makedirs(os.path.join(clone, "debug-runs"), exist_ok=True)
    try:
        shutil.copyfile(transcript, os.path.join(clone, relpath))
    except OSError as exc:
        warn("copy failed: %s" % exc)
        return
    git(clone, "add", relpath)
    if git(clone, "diff", "--cached", "--quiet",
           "HEAD").returncode == 0 and marker.get("archived"):
        save_marker(session_id, {"archived": True, "size": size, "day": day,
                                 "complete": complete})
        return  # identical content already pushed
    commit = git(clone, "commit", "-m", "archive %s" % relpath)
    if commit.returncode != 0:
        warn("commit failed: " + tail(commit))
        return
    branch = "transcripts/%s" % session_id
    for _attempt in range(3):
        push = git(clone, "push", "--force", "origin", "HEAD:%s" % branch)
        if push.returncode == 0:
            save_marker(session_id, {"archived": True, "size": size,
                                     "day": day, "complete": complete})
            return
    warn("push failed after 3 attempts (%s) — is this machine's GitHub "
         "login a collaborator on the repo? Try: gh auth login && "
         "gh auth setup-git" % tail(push))


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
