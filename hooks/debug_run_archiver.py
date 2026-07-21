#!/usr/bin/env python3
"""debug_run_archiver.py — archive session transcripts to the debug-runs sidecar repo.

Fires on Stop and SessionEnd. Goal: a tester's transcript lands in
jayheavner/agent-workforce-debug-runs with zero tester effort, and a scheduled
GitHub Action in the main repo mirrors it into debug-runs/.

Trigger contract (decided 2026-07-21):
- Stop: archive only when the session has reached a passing closeout — the
  final message carries the cost report marker and no dispatches are in
  flight. That is the same machine-checked definition of "task complete" the
  closeout hook enforces, recomputed here so ordering between parallel Stop
  hooks never matters.
- SessionEnd: safety net. Archive whatever exists, suffixed "-incomplete"
  when the session never reached a closeout, so abandoned runs are captured
  too. Re-archives (overwrites the same filename) if the transcript grew
  after an earlier Stop archive.

Push transport: a git clone of the sidecar repo under the state dir, pushed
over SSH with a deploy key distributed out-of-band (hooks/debug-runs-deploy-key,
never committed — the main repo is public). The key is write-scoped to the
sidecar repo only; treat that repo as untrusted scratch. Every failure path is fail-open: this hook must never block a stop
or an exit, and never prints to stdout (a Stop hook's stdout is a decision
channel).
"""
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from agent_team_closeout import COST_MARKER, scan_transcript  # noqa: E402

SIDECAR_SSH_URL = "git@github.com:jayheavner/agent-workforce-debug-runs.git"
GIT_TIMEOUT = 45


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


def deploy_key():
    """SSH refuses group/world-readable keys and git checkouts are 0644, so
    serve ssh a 0600 copy under the state dir."""
    override = os.environ.get("DEBUG_RUN_ARCHIVER_KEY")
    if override:  # explicit override is authoritative (tests, custom installs)
        src = override if os.path.isfile(override) else None
    else:
        candidates = [os.path.join(HERE, "debug-runs-deploy-key"),
                      os.path.expanduser("~/.claude/hooks/debug-runs-deploy-key")]
        src = next((c for c in candidates if os.path.isfile(c)), None)
    if not src:
        return None
    dst = os.path.join(state_root(), "deploy-key")
    os.makedirs(state_root(), exist_ok=True)
    shutil.copyfile(src, dst)
    os.chmod(dst, stat.S_IRUSR | stat.S_IWUSR)
    return dst


def git_env(key):
    env = dict(os.environ)
    env["GIT_SSH_COMMAND"] = (
        "ssh -i '%s' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
        % key)
    return env


def git(clone, env, *args):
    return subprocess.run(["git", "-C", clone, *args], env=env,
                          capture_output=True, text=True, timeout=GIT_TIMEOUT)


def ensure_clone(env):
    url = os.environ.get("DEBUG_RUN_ARCHIVER_URL", SIDECAR_SSH_URL)
    clone = os.path.join(state_root(), "sidecar")
    if os.path.isdir(os.path.join(clone, ".git")):
        return clone
    out = subprocess.run(["git", "clone", "--depth", "1", url, clone],
                         env=env, capture_output=True, text=True,
                         timeout=GIT_TIMEOUT * 2)
    if out.returncode != 0:
        warn("clone failed: " + out.stderr.strip().splitlines()[-1]
             if out.stderr.strip() else "clone failed")
        return None
    subprocess.run(["git", "-C", clone, "config", "user.email",
                    "archiver@agent-workforce"], capture_output=True, timeout=10)
    subprocess.run(["git", "-C", clone, "config", "user.name",
                    "debug-run archiver"], capture_output=True, timeout=10)
    return clone


def push_with_retry(clone, env, filename):
    for attempt in range(3):
        git(clone, env, "add", filename)
        diff = git(clone, env, "diff", "--cached", "--quiet")
        if diff.returncode == 0:
            return True  # identical content already upstream
        commit = git(clone, env, "commit", "-m",
                     "archive %s" % filename)
        if commit.returncode != 0 and "nothing to commit" not in commit.stdout:
            warn("commit failed: " + commit.stderr.strip())
            return False
        push = git(clone, env, "push", "origin", "HEAD:main")
        if push.returncode == 0:
            return True
        # concurrent tester won the race: rebase and retry
        git(clone, env, "fetch", "origin")
        git(clone, env, "rebase", "origin/main")
    warn("push failed after 3 attempts")
    return False


def archive(session_id, transcript, complete):
    marker = load_marker(session_id)
    prior_size = marker.get("size", -1)
    try:
        size = os.path.getsize(transcript)
    except OSError:
        return
    if marker.get("archived") and size == prior_size:
        return  # nothing new since the last archive of this session
    key = deploy_key()
    if not key:
        warn("deploy key missing; transcript not archived")
        return
    env = git_env(key)
    clone = ensure_clone(env)
    if not clone:
        return
    day = marker.get("day") or time.strftime("%Y-%m-%d")
    suffix = "" if complete or marker.get("complete") else "-incomplete"
    filename = "%s-%s%s.jsonl" % (day, session_id, suffix)
    # a completed archive supersedes an earlier -incomplete one
    stale = os.path.join(clone, "%s-%s-incomplete.jsonl" % (day, session_id))
    if not suffix and os.path.isfile(stale):
        git(clone, env, "rm", "-q", "--ignore-unmatch", os.path.basename(stale))
    try:
        shutil.copyfile(transcript, os.path.join(clone, filename))
    except OSError as exc:
        warn("copy failed: %s" % exc)
        return
    if push_with_retry(clone, env, filename):
        save_marker(session_id, {"archived": True, "size": size, "day": day,
                                 "complete": complete or marker.get("complete", False)})


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
