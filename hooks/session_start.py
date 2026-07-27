#!/usr/bin/env python3
"""session_start.py — SessionStart hook: ground the session in verified reality.

Three duties, all fail-open and read-only toward the project tree:

0. Launch-mode tripwire: name a session that skipped bin/agent-workforce
   (see launch_mode_lines) so a degraded start is never silent.

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
HERE = os.path.dirname(os.path.abspath(__file__))
PAUSE_MARKER = "WORKFORCE_PAUSE: HUMAN_DECISION"


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


def launch_mode_lines():
    """Tripwire (decision 2026-07-26): a session must prove it came through
    bin/agent-workforce. `claude --agent orchestrator` looks identical to a
    launcher session but silently drops --permission-mode bypassPermissions
    and the staleness/self-update pass — the operator gets a degraded session
    with no signal. The launcher exports WORKFORCE_LAUNCH_MODE; its absence
    IS the signal."""
    mode = os.environ.get("WORKFORCE_LAUNCH_MODE")
    if mode == "snapshot":
        return []
    if mode == "plugin":
        return ["launch mode: live plugin mode — per-agent permissionMode is "
                "not honored; permission prompts are expected. Snapshot mode "
                "(bin/agent-workforce without --plugin) removes them."]
    return ["launch mode: DEGRADED — this session was not started through "
            "bin/agent-workforce (no WORKFORCE_LAUNCH_MODE in the "
            "environment). Expect permission prompts on every mutation, and "
            "the profile may be stale: neither bypassPermissions nor the "
            "freshness check ran. Tell the human now, in your first reply: "
            "exit and restart with `agent-workforce` (or "
            "`./bin/agent-workforce` from the repo checkout)."]


def load_project(cwd):
    try:
        with open(os.path.join(cwd, PROJECT_FILE)) as f:
            doc = json.load(f)
    except (OSError, ValueError):
        return None
    return doc if isinstance(doc, dict) else None


def github_work_lines(cwd):
    """Open 'workforce'-labeled issues, surfaced at every session start.

    Decision 2026-07-22: downstream work the workforce cannot finish in a
    session is filed in the project tracker, never left as a paste-this or
    remember-this instruction — and the next session is TOLD about it here,
    as checked fact, instead of anyone hunting. Fail-open: an unreachable gh
    reports UNKNOWN, never blocks the session.
    """
    out = run(["gh", "issue", "list", "--state", "open",
               "--label", "workforce", "--limit", "10",
               "--json", "number,title"], cwd, CHECK_TIMEOUT)
    if out is None or out.returncode != 0:
        return ["tracker work: could not list open 'workforce' issues "
                "(gh failed or absent) — status UNKNOWN; check the tracker "
                "manually before claiming no work is pending."]
    try:
        issues = json.loads(out.stdout)
    except ValueError:
        return ["tracker work: gh returned an unparseable issue list — "
                "status UNKNOWN."]
    if not isinstance(issues, list) or not issues:
        return ["tracker work: no open 'workforce'-labeled issues."]
    lines = [f"tracker work: {len(issues)} open 'workforce' issue(s) — "
             "review before starting new work:"]
    for issue in issues:
        if isinstance(issue, dict):
            lines.append(f"  #{issue.get('number')}: {issue.get('title')}")
    return lines


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
        if tracker == "github":
            lines.extend(github_work_lines(cwd))
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


def reconcile_lines(payload):
    """Catch an orchestrator that died mid-closeout, at the NEXT start.

    Why it exists: a headless `claude -p` orchestrator that dies after
    deliverables commit but before the closeout cost table prints still
    exits 0, and a killed process fires no Stop hook — so
    agent_team_closeout never grades the truncated final message and the
    death is silent (issue #8, observed live 2026-07-26). Detection must
    live at a consumption point that survives the death: the next session's
    start.

    Discovery: the current session's transcript_path names the per-project
    transcript directory; prior sessions are its sibling *.jsonl files.
    Inspect ONLY the single most-recent prior (highest mtime, excluding the
    current transcript by absolute path) — bounded to one extra scan and
    self-clearing, so the warning never nags across unrelated later
    sessions (a later plain session masking an older dead one is the
    accepted trade).

    Predicate (all must hold to warn): the prior had specialist dispatches
    (total > 0) AND its final message carries neither COST_MARKER (a normal
    closeout) NOR PAUSE_MARKER (an intentional human-decision pause).

    :param payload: the SessionStart hook payload dict; uses
        transcript_path.
    :returns: a one-element list with the operator warning, or [] when
        there is nothing to reconcile.
    :raises: nothing — every failure path returns [] (main() also
        try/excepts this call).
    """
    if not isinstance(payload, dict):
        return []
    transcript = payload.get("transcript_path")
    if not isinstance(transcript, str) or not transcript:
        return []
    tdir = os.path.dirname(transcript)
    if not os.path.isdir(tdir):
        return []
    current = os.path.abspath(transcript)
    priors = []
    for name in os.listdir(tdir):
        if not name.endswith(".jsonl"):
            continue
        path = os.path.join(tdir, name)
        if os.path.abspath(path) == current:
            continue
        try:
            priors.append((os.path.getmtime(path), path))
        except OSError:
            continue
    if not priors:
        return []
    priors.sort()
    prior = priors[-1][1]
    sys.path.insert(0, HERE)
    from agent_team_closeout import scan_transcript, COST_MARKER
    total, _in_flight, _roles, _order, last_text = scan_transcript(prior)
    if total == 0:
        return []
    if COST_MARKER in last_text or PAUSE_MARKER in last_text:
        return []
    name = os.path.basename(prior)
    return ["reconcile: prior session " + name + " dispatched specialists "
            "but ended without a closeout cost report or a "
            "WORKFORCE_PAUSE. It may have died mid-closeout (e.g. a "
            "headless run whose connection dropped after deliverables "
            "committed but before the cost table printed), been "
            "interrupted/closed by the operator, or been allowed to stop "
            "at the enforcement cap. Committed deliverables are "
            "unaffected; the final report/telemetry for this session may "
            "be missing. Inspect " + prior + " — recover the numbers with "
            "`bin/agent-workforce-cost-report --transcript " + prior + "`."]


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        payload = {}
    cwd = payload.get("cwd") if isinstance(payload, dict) else None
    cwd = cwd or os.getcwd()
    lines = []
    try:
        lines.extend(launch_mode_lines())
    except Exception:
        pass
    try:
        lines.extend(reconcile_lines(payload))
    except Exception:
        pass
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
