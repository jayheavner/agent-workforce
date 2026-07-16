#!/usr/bin/env python3
"""Route Claude hook payloads through the process-assurance state machine."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from process_assurance import handle_dispatch, handle_stop, handle_subagent_stop


def main(arguments: list[str]) -> int:
    """Read one hook event, emit its decision streams, and return its exit code."""
    if len(arguments) != 1 or arguments[0] not in {"dispatch", "subagent-stop", "stop"}:
        print(
            "agent-team-process-assurance: expected dispatch, subagent-stop, or stop",
            file=sys.stderr,
        )
        return 2
    mode = os.environ.get("AGENT_TEAM_PROCESS_ASSURANCE_MODE", "OFF").upper()
    if mode == "OFF":
        return 0
    if mode not in {"SHADOW", "ENFORCE"}:
        print("agent-team-process-assurance: invalid feature mode", file=sys.stderr)
        return 2
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError):
        print("agent-team-process-assurance: hook input is not valid JSON", file=sys.stderr)
        return 2
    if not isinstance(payload, dict):
        print("agent-team-process-assurance: hook input must be an object", file=sys.stderr)
        return 2
    default_root = Path.home() / ".claude" / "process-assurance"
    state_root = Path(os.environ.get("AGENT_TEAM_PROCESS_ASSURANCE_STATE", default_root))
    handler = {
        "dispatch": handle_dispatch,
        "subagent-stop": handle_subagent_stop,
        "stop": handle_stop,
    }[arguments[0]]
    decision = handler(payload, state_root, mode)
    if decision.stdout:
        print(decision.stdout)
    if decision.stderr:
        print(decision.stderr, file=sys.stderr, end="")
    return decision.exit_code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
