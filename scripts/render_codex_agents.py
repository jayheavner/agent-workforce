#!/usr/bin/env python3
"""Render deterministic Codex custom-agent profiles from Claude role contracts."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
POLICY = ROOT / "codex" / "model-policy.json"
OUTPUT = ROOT / "codex" / "agents"
LAUNCH_OUTPUT = ROOT / "codex" / "profiles"
ROOT_CONFIG = ROOT / "codex" / "agent-workforce.config.toml"


def role_body(role: str) -> str:
    source = (ROOT / "agents" / f"{role}.md").read_text(encoding="utf-8")
    parts = source.split("---", 2)
    if len(parts) != 3:
        raise ValueError(f"agents/{role}.md does not have one frontmatter block")
    return parts[2].strip()


def quoted(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def render(profile: dict[str, str]) -> str:
    role = profile["role"]
    command = (
        f'AGENT_TEAM_EXPECTED_MODEL={quoted(profile["model"])} '
        'AGENT_TEAM_AUDIT_LOG="${AGENT_WORKFORCE_DISPATCH_AUDIT:-${CODEX_HOME:-$HOME/.codex}/agent-workforce/logs/audit.log}" '
        'bash "${CODEX_HOME:-$HOME/.codex}/agent-workforce/hooks/agent-team-policy.sh" '
        f'{role}'
    )
    adapter = f"""Codex adapter — these instructions take precedence over legacy Claude-specific wording below.

- You are the named `{profile['name']}` custom agent, not a generic worker.
- Your pinned runtime is `{profile['model']}` at `{profile['effort']}` reasoning effort. If a policy hook reports a model mismatch, stop and report it.
- Translate Claude tool names to the equivalent Codex tools. Use `apply_patch` for permitted file edits and the shell only inside this role's policy.
- Invoke relevant installed skills explicitly with `$<skill-name>` when their trigger applies. A reference to a "preloaded" skill means the same discipline remains mandatory in Codex.
- Never spawn another agent. Return your phase report to the main-session orchestrator.
- The installed Codex policy hook enforces the role's shell and write restrictions only after the user trusts it. If hooks are disabled, skipped, or untrusted, stop and report `PARITY BLOCKED: role policy hook inactive` before any mutation.
- Parent-task permission overrides can tighten this profile. Never ask to weaken them; report a blocked required action to the orchestrator.
- End the report with `WORKFORCE_PROFILE: {profile['name']} | {profile['model']} | {profile['effort']}`.

Role contract follows.
"""
    body = role_body(role)
    if "'''" in adapter or "'''" in body:
        raise ValueError(f"role {role} contains TOML literal delimiter")
    return "\n".join(
        [
            f"name = {quoted(profile['name'])}",
            f"description = {quoted(profile['description'])}",
            f"model = {quoted(profile['model'])}",
            f"model_reasoning_effort = {quoted(profile['effort'])}",
            f"sandbox_mode = {quoted(profile['sandbox_mode'])}",
            f"approval_policy = {quoted(profile['approval_policy'])}",
            f"web_search = {quoted(profile['web_search'])}",
            "developer_instructions = '''",
            adapter.rstrip(),
            "",
            body,
            "'''",
            "",
            "[[hooks.SessionStart]]",
            'matcher = "startup|resume"',
            "",
            "[[hooks.SessionStart.hooks]]",
            'type = "command"',
            f"command = {quoted(command)}",
            "timeout = 30",
            "",
            "[[hooks.PreToolUse]]",
            'matcher = "Bash|Edit|Write|apply_patch|spawn_agent|Agent"',
            "",
            "[[hooks.PreToolUse.hooks]]",
            'type = "command"',
            f"command = {quoted(command)}",
            "timeout = 30",
            "",
        ]
    )


def render_root_config(policy: dict[str, object]) -> str:
    lines = [
        f'model = {quoted(policy["orchestrator"]["model"])}',
        f'model_reasoning_effort = {quoted(policy["orchestrator"]["effort"])}',
        "",
        "[agents]",
        "max_threads = 6",
        "max_depth = 1",
        "interrupt_message = true",
    ]
    for profile in policy["profiles"]:
        config_file = f"./agents/{profile['name']}.toml"
        lines.extend(
            [
                "",
                f'[agents.{profile["name"]}]',
                f'description = {quoted(profile["description"])}',
                f'config_file = {quoted(config_file)}',
            ]
        )
    lines.append("")
    return "\n".join(lines)


def render_launch_profile(profile: dict[str, str]) -> str:
    """Render the same role as a top-level `codex --profile` config.

    Custom-agent identity fields are valid under `agents/` but not in a normal
    config layer, so direct specialist conversations omit only those two
    discovery fields while retaining model, effort, instructions, and hooks.
    """
    lines = render(profile).splitlines()
    return "\n".join(lines[2:]) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if generated files are stale")
    args = parser.parse_args()

    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    invalid_names = [
        profile["name"]
        for profile in policy["profiles"]
        if re.fullmatch(r"[a-z0-9_]+", profile["name"]) is None
    ]
    if invalid_names:
        print(
            "Codex custom-agent names must use lowercase letters, digits, and underscores: "
            + ", ".join(invalid_names),
            file=sys.stderr,
        )
        return 1
    expected = {
        f"{profile['name']}.toml": render(profile)
        for profile in policy["profiles"]
    }
    expected_launch = {
        f"{profile['name']}.config.toml": render_launch_profile(profile)
        for profile in policy["profiles"]
    }
    root_config = render_root_config(policy)

    if args.check:
        actual_names = {path.name for path in OUTPUT.glob("*.toml")} if OUTPUT.exists() else set()
        if actual_names != set(expected):
            print("Codex profile filenames are stale", file=sys.stderr)
            return 1
        stale = [
            name
            for name, content in expected.items()
            if (OUTPUT / name).read_text(encoding="utf-8") != content
        ]
        if stale:
            print("Stale Codex profiles: " + ", ".join(stale), file=sys.stderr)
            return 1
        actual_launch_names = (
            {path.name for path in LAUNCH_OUTPUT.glob("*.config.toml")}
            if LAUNCH_OUTPUT.exists()
            else set()
        )
        if actual_launch_names != set(expected_launch):
            print("Codex direct-launch profile filenames are stale", file=sys.stderr)
            return 1
        stale_launch = [
            name
            for name, content in expected_launch.items()
            if (LAUNCH_OUTPUT / name).read_text(encoding="utf-8") != content
        ]
        if stale_launch:
            print("Stale Codex direct-launch profiles: " + ", ".join(stale_launch), file=sys.stderr)
            return 1
        if not ROOT_CONFIG.exists() or ROOT_CONFIG.read_text(encoding="utf-8") != root_config:
            print("Codex orchestrator config is stale", file=sys.stderr)
            return 1
        return 0

    OUTPUT.mkdir(parents=True, exist_ok=True)
    LAUNCH_OUTPUT.mkdir(parents=True, exist_ok=True)
    for path in OUTPUT.glob("*.toml"):
        if path.name not in expected:
            path.unlink()
    for name, content in expected.items():
        (OUTPUT / name).write_text(content, encoding="utf-8")
    for path in LAUNCH_OUTPUT.glob("*.config.toml"):
        if path.name not in expected_launch:
            path.unlink()
    for name, content in expected_launch.items():
        (LAUNCH_OUTPUT / name).write_text(content, encoding="utf-8")
    ROOT_CONFIG.write_text(root_config, encoding="utf-8")
    print(f"Rendered {len(expected)} Codex profiles in {OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
