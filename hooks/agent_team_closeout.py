#!/usr/bin/env python3
"""agent_team_closeout.py — Stop hook: the priced closeout that cannot be skipped.

Fires on Stop in orchestrator sessions (wired via agent frontmatter in snapshot
mode, via hooks.json + the plugin router in live plugin mode). It enforces
exactly two things, both mechanical:

1. Any turn that ends after dispatched work must carry the exact cost report.
   The hook COMPUTES the report itself (cost_report.py, whole session including
   the orchestrator's own usage) and hands it over in the block reason — the
   model's only job is to include it. No memory, no arithmetic, no estimate.
2. If git-mutating specialists ran and the working tree is dirty, the final
   message must acknowledge the uncommitted state (commit via the executor or
   say plainly what remains and why).

Design rules learned from the previous generation (see
docs/superpowers/specs/2026-07-18-autonomy-first-redesign.md):
- Never fire while dispatches are in flight.
- Never demand facts the hook cannot verify (no ownership claims, no receipt
  schemas, no ledger fields).
- Bounded enforcement: at most MAX_BLOCKS blocks per session, then fail open
  with a visible warning — a hook must never wedge a session.
- On a passing stop, telemetry is written by machine, never by a dispatch.
"""
import hashlib
import json
import os
import subprocess
import sys

MAX_BLOCKS = 3
COST_MARKER = "## Cost report"
MUTATING_ROLES = {"builder", "executor", "deployer"}
DIRTY_ACK_WORDS = ("uncommitted", "not committed", "committed", "commit", "dirty tree",
                   "working tree", "WORKFORCE_PAUSE: HUMAN_DECISION")

HERE = os.path.dirname(os.path.abspath(__file__))


def state_path(session_id):
    root = os.environ.get("AGENT_TEAM_CLOSEOUT_STATE",
                          os.path.expanduser("~/.claude/state/agent-workforce-closeout"))
    os.makedirs(root, exist_ok=True)
    digest = hashlib.sha256(session_id.encode()).hexdigest()
    return os.path.join(root, digest + ".json")


def load_state(session_id):
    try:
        with open(state_path(session_id)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(session_id, state):
    try:
        with open(state_path(session_id), "w") as f:
            json.dump(state, f)
    except OSError:
        pass


def scan_transcript(path):
    """One pass: dispatch count, in-flight set, roles seen, last assistant text."""
    total = 0
    in_flight = {}
    roles = set()
    last_text = ""
    try:
        f = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return 0, {}, set(), ""
    with f:
        for line in f:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue
            msg = rec.get("message") or {}
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            if rec.get("type") == "assistant":
                texts = [b.get("text", "") for b in content
                         if isinstance(b, dict) and b.get("type") == "text"]
                if texts:
                    last_text = "\n".join(texts)
            for block_ in content:
                if not isinstance(block_, dict):
                    continue
                if block_.get("type") == "tool_use" and block_.get("name") == "Agent":
                    total += 1
                    stype = (block_.get("input") or {}).get("subagent_type", "") or ""
                    stype = stype.split(":")[-1]
                    in_flight[block_.get("id")] = stype
                    roles.add(stype)
                elif block_.get("type") == "tool_result" and block_.get("tool_use_id") in in_flight:
                    del in_flight[block_["tool_use_id"]]
    return total, in_flight, roles, last_text


def cost_report_cmd(transcript, session_id, cwd, extra=()):
    cost_dir = os.environ.get("AGENT_TEAM_COST_DIR",
                              os.path.expanduser("~/.claude/logs/agent-team-cost"))
    slug = cwd.replace("/", "-")
    cost_file = os.path.join(cost_dir, f"{slug}--{session_id}.json")
    cmd = [sys.executable, os.path.join(HERE, "cost_report.py"),
           "--transcript", transcript, *extra]
    if os.path.isfile(cost_file):
        cmd += ["--cost-file", cost_file]
    return cmd


def compute_cost_report(transcript, session_id, cwd):
    try:
        out = subprocess.run(cost_report_cmd(transcript, session_id, cwd),
                             capture_output=True, text=True, timeout=60)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return None


def git_dirty(cwd):
    try:
        out = subprocess.run(["git", "-C", cwd, "status", "--porcelain"],
                             capture_output=True, text=True, timeout=20)
        return out.returncode == 0 and bool(out.stdout.strip())
    except (OSError, subprocess.TimeoutExpired):
        return False


def write_telemetry(transcript, session_id, cwd):
    tdir = os.path.join(cwd, "docs", "telemetry")
    if not os.path.isdir(tdir):
        return
    cmd = cost_report_cmd(transcript, session_id, cwd,
                          extra=("--telemetry-dir", tdir,
                                 "--session-id", session_id, "--cwd", cwd))
    try:
        subprocess.run(cmd, capture_output=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        pass


def allow():
    sys.exit(0)


def block(reason):
    print(json.dumps({"decision": "block", "reason": reason}))
    sys.exit(0)


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        allow()

    session_id = payload.get("session_id") or ""
    transcript = payload.get("transcript_path") or ""
    cwd = payload.get("cwd") or os.getcwd()
    if not session_id or not os.path.isfile(transcript):
        allow()

    total, in_flight, roles, last_text = scan_transcript(transcript)

    # No dispatched work this session -> nothing to enforce (plain Q&A turn).
    if total == 0:
        allow()
    # Dispatches still in flight -> the turn end is a wait, not a closeout.
    if in_flight:
        allow()

    state = load_state(session_id)
    blocks = state.get("blocks", 0)
    if blocks >= MAX_BLOCKS:
        print("agent-team closeout: enforcement cap reached; allowing stop "
              "without a verified cost report.", file=sys.stderr)
        write_telemetry(transcript, session_id, cwd)
        allow()

    missing = []
    if COST_MARKER not in last_text:
        report = compute_cost_report(transcript, session_id, cwd)
        if report:
            missing.append(
                "Your final message must include the session cost report. "
                "Append the following verbatim (already computed — do not "
                "re-derive or estimate):\n\n" + report)
        else:
            missing.append(
                "Your final message must include the session cost report. Run "
                "`bin/agent-workforce-cost-report --transcript " + transcript +
                "` (or have the executor run it) and include its output "
                "verbatim under '" + COST_MARKER + "'.")

    if roles & MUTATING_ROLES and git_dirty(cwd):
        acked = any(w.lower() in last_text.lower() for w in DIRTY_ACK_WORDS)
        if not acked:
            missing.append(
                "The working tree has uncommitted changes and your final "
                "message does not mention them. Either dispatch the executor "
                "to commit this task's delta (the original request authorizes "
                "a focused local commit unless the human opted out), or state "
                "plainly what remains uncommitted and why.")

    if missing:
        state["blocks"] = blocks + 1
        save_state(session_id, state)
        block("\n\n".join(missing))

    write_telemetry(transcript, session_id, cwd)
    try:
        os.unlink(state_path(session_id))
    except OSError:
        pass
    allow()


if __name__ == "__main__":
    main()
