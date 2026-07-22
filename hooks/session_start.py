#!/usr/bin/env python3
"""session_start.py — SessionStart hook: ground the session in verified reality.

Two duties, both fail-open and read-only toward the project tree:

1. Git sync (decision 2026-07-22): fetch origin and report ahead/behind for
   the current branch, so no agent can reason from a stale checkout without
   contradicting a fact already in its context. (The 2026-07-22 EA session
   diagnosed "Tasks 16-18 don't exist" from an un-pulled plan doc and had to
   be shouted at to pull; a feedback memory saying "always fetch first"
   demonstrably did not fire. Memory is advice; this is mechanism.)

2. Onboarding probe: read `.workforce/project.json` (tracker declaration +
   ready checks) and run every ready check. A ready check is a command plus
   an expected output that proves an entire tool chain — install, login,
   identity, permissions — in one shot ("az account show" must name the right
   subscription). The agent starts work knowing what is READY and what is
   BROKEN as checked fact, never as guesswork. No declaration file is not an
   error — the session runs — but the tracker gap is named here and nagged in
   every cost report until someone spends the two minutes declaring.

Output: {"hookSpecificOutput": {"hookEventName": "SessionStart",
"additionalContext": ...}} on stdout. Every failure path allows the session.
"""
import json
import os
import subprocess
import sys

FETCH_TIMEOUT = int(os.environ.get("WORKFORCE_FETCH_TIMEOUT", "20"))
CHECK_TIMEOUT = int(os.environ.get("WORKFORCE_READY_CHECK_TIMEOUT", "15"))
PROJECT_FILE = os.path.join(".workforce", "project.json")


def run(cmd, cwd, timeout, env=None):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                              timeout=timeout, env=env)
    except (OSError, subprocess.TimeoutExpired, subprocess.SubprocessError):
        return None


def git(cwd, *args, timeout=10, env=None):
    out = run(["git", "-C", cwd, *args], cwd, timeout, env=env)
    if out is None or out.returncode != 0:
        return None
    return out.stdout.strip()


def git_sync_lines(cwd):
    """Fetch origin (bounded, soft-fail) and report ahead/behind as fact."""
    if git(cwd, "rev-parse", "--is-inside-work-tree") != "true":
        return []
    if git(cwd, "remote", "get-url", "origin") is None:
        return ["git sync: no origin remote — local-only repository."]
    env = dict(os.environ)
    env["GIT_SSH_COMMAND"] = "ssh -o ConnectTimeout=5 -o BatchMode=yes"
    fetch = run(["git", "-C", cwd,
                 "-c", "http.lowSpeedLimit=1000", "-c", "http.lowSpeedTime=10",
                 "fetch", "--quiet", "origin"], cwd, FETCH_TIMEOUT, env=env)
    if fetch is None or fetch.returncode != 0:
        return ["git sync: could not reach origin (offline?) — sync status "
                "UNKNOWN; do not assert the checkout is current."]
    branch = git(cwd, "rev-parse", "--abbrev-ref", "HEAD") or "HEAD"
    upstream = git(cwd, "rev-parse", "--abbrev-ref", "--symbolic-full-name",
                   "@{upstream}")
    if upstream is None:
        for candidate in ("origin/main", "origin/master"):
            if git(cwd, "rev-parse", "--verify", "--quiet", candidate) is not None:
                upstream = candidate
                break
    if upstream is None:
        return [f"git sync: fetched origin; no upstream for {branch}."]
    counts = git(cwd, "rev-list", "--left-right", "--count",
                 f"{upstream}...HEAD")
    if counts is None:
        return [f"git sync: fetched origin; could not compare {branch} "
                f"to {upstream}."]
    behind, ahead = (counts.split() + ["0", "0"])[:2]
    return [f"git sync: fetched origin; {branch} is {ahead} ahead / "
            f"{behind} behind {upstream}."]


def load_project(cwd):
    try:
        with open(os.path.join(cwd, PROJECT_FILE)) as f:
            doc = json.load(f)
    except (OSError, ValueError):
        return None
    return doc if isinstance(doc, dict) else None


def probe_lines(cwd):
    """Tracker declaration + ready-check results, every one a checked fact."""
    project = load_project(cwd)
    if project is None:
        return ["project onboarding: no .workforce/project.json — tracker "
                "UNDECLARED. Discovered issues that are not fixed in-task "
                "have no tracker to land in and fall to the closeout "
                "REMAINING WORK floor. Run /onboard-project to declare."]
    lines = []
    tracker = project.get("tracker")
    if isinstance(tracker, str) and tracker and tracker != "none":
        lines.append(f"project onboarding: tracker = {tracker}.")
    elif tracker == "none":
        lines.append("project onboarding: tracker explicitly 'none' — "
                     "unfixed findings go to the closeout REMAINING WORK "
                     "section.")
    else:
        lines.append("project onboarding: .workforce/project.json present "
                     "but no tracker declared — run /onboard-project.")
    checks = project.get("ready_checks")
    if not isinstance(checks, list):
        return lines
    for check in checks:
        if not isinstance(check, dict):
            continue
        name = str(check.get("name") or "unnamed check")
        command = check.get("command")
        if not isinstance(command, str) or not command:
            lines.append(f"ready: {name} — SKIPPED (no command).")
            continue
        timeout = check.get("timeout")
        timeout = timeout if isinstance(timeout, (int, float)) and timeout > 0 \
            else CHECK_TIMEOUT
        out = run(["bash", "-c", command], cwd, timeout)
        if out is None:
            lines.append(f"ready: {name} — FAIL (timed out or could not run).")
            continue
        if out.returncode != 0:
            lines.append(f"ready: {name} — FAIL (exit {out.returncode}).")
            continue
        expect = check.get("expect")
        if isinstance(expect, str) and expect and expect not in out.stdout:
            lines.append(f"ready: {name} — FAIL (expected output not found: "
                         f"{expect!r}).")
            continue
        lines.append(f"ready: {name} — OK.")
    return lines


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        payload = {}
    cwd = payload.get("cwd") if isinstance(payload, dict) else None
    cwd = cwd or os.getcwd()
    lines = []
    try:
        lines.extend(git_sync_lines(cwd))
    except Exception:
        pass
    try:
        lines.extend(probe_lines(cwd))
    except Exception:
        pass
    if lines:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": "\n".join(lines),
        }}))
    sys.exit(0)


if __name__ == "__main__":
    main()
