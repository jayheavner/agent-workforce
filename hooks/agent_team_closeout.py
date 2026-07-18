#!/usr/bin/env python3
"""Block Agent Workforce completion while local closeout work remains."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


MUTATING_ROLES = {"architect", "builder", "executor", "scribe"}
VERDICT = re.compile(r"^-\s+shipment-verdict:\s*(SHIPPABLE|NOT SHIPPABLE)\s*$", re.MULTILINE)
VERIFY_MARKER = re.compile(
    r"WORKFORCE_VERIFICATION:\s*verdict=(SHIPPABLE|NOT_SHIPPABLE|UNCHECKED);\s*"
    r"full_suite=(pass|fail|unchecked)"
)
REVIEW_MARKER = re.compile(
    r"WORKFORCE_REVIEW:\s*verdict=(approve|approve-with-nits|request-changes)"
)


@dataclass(frozen=True)
class EventResult:
    """Represent one hook decision and its process streams."""

    exit_code: int = 0
    stdout: str = ""
    stderr: str = ""


def _git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    """Run a non-interactive Git read against one repository."""
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def _repo_root(cwd: str) -> Path | None:
    """Return the containing Git root, or None outside a repository."""
    result = _git(Path(cwd), "rev-parse", "--show-toplevel", check=False)
    if result.returncode != 0:
        return None
    return Path(os.fsdecode(result.stdout).strip()).resolve()


def _content_signature(path: Path) -> str:
    """Hash current path content without following symlinks."""
    if path.is_symlink():
        payload = b"symlink\0" + os.fsencode(os.readlink(path))
    elif path.is_file():
        payload = b"file\0" + path.read_bytes()
    elif path.exists():
        payload = b"other\0" + str(path.stat().st_mode).encode("ascii")
    else:
        payload = b"missing\0"
    return hashlib.sha256(payload).hexdigest()


def _entry(repo: Path, path: str, record: bytes, original: str = "") -> dict[str, str]:
    """Build a stable signature for one dirty worktree path."""
    index = _git(repo, "ls-files", "-s", "--", path, check=False).stdout
    return {
        "record": hashlib.sha256(record).hexdigest(),
        "content": _content_signature(repo / path),
        "index": hashlib.sha256(index).hexdigest(),
        "original": original,
    }


def _dirty_snapshot(repo: Path) -> dict[str, dict[str, str]]:
    """Return status plus content/index fingerprints for every dirty path."""
    raw = _git(
        repo,
        "status",
        "--porcelain=v2",
        "-z",
        "--untracked-files=all",
    ).stdout
    records = raw.split(b"\0")
    snapshot: dict[str, dict[str, str]] = {}
    index = 0
    while index < len(records):
        record = records[index]
        index += 1
        if not record or record.startswith(b"!"):
            continue
        original = ""
        if record.startswith(b"1 "):
            path_bytes = record.split(b" ", 8)[8]
        elif record.startswith(b"2 "):
            path_bytes = record.split(b" ", 9)[9]
            if index < len(records):
                original = os.fsdecode(records[index])
                index += 1
        elif record.startswith((b"? ", b"u ")):
            path_bytes = record[2:] if record.startswith(b"? ") else record.split(b" ", 10)[10]
        else:
            continue
        path = os.fsdecode(path_bytes)
        snapshot[path] = _entry(repo, path, record, original)
    return snapshot


def _state_path(state_dir: Path, session_id: str) -> Path:
    """Map an untrusted session identifier to a safe state filename."""
    digest = hashlib.sha256(session_id.encode("utf-8")).hexdigest()
    return state_dir / f"{digest}.json"


def _load_state(state_dir: Path, session_id: str) -> dict[str, Any] | None:
    """Read existing state, returning None when no workforce task is active."""
    path = _state_path(state_dir, session_id)
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def _save_state(state_dir: Path, session_id: str, state: dict[str, Any]) -> None:
    """Atomically persist non-sensitive closeout state."""
    state_dir.mkdir(parents=True, exist_ok=True)
    path = _state_path(state_dir, session_id)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, sort_keys=True), encoding="utf-8")
    temporary.replace(path)


def _clear_state(state_dir: Path, session_id: str) -> None:
    """Retire one completed task so later turns are not intercepted."""
    _state_path(state_dir, session_id).unlink(missing_ok=True)


def _normalize_role(value: object) -> str:
    """Normalize bare and plugin-qualified workforce specialist names."""
    role = str(value or "")
    return role.split(":", 1)[-1]


def _current_branch(repo: Path) -> str:
    """Return the checked-out branch or HEAD for a detached checkout."""
    result = _git(repo, "symbolic-ref", "--short", "-q", "HEAD", check=False)
    return os.fsdecode(result.stdout).strip() or "HEAD"


def _branches(repo: Path) -> list[str]:
    """List local branch names deterministically."""
    output = _git(repo, "for-each-ref", "--format=%(refname:short)", "refs/heads/").stdout
    return sorted(line for line in os.fsdecode(output).splitlines() if line)


def _worktrees(repo: Path) -> dict[str, str]:
    """Map worktree paths to their local branch names."""
    output = os.fsdecode(_git(repo, "worktree", "list", "--porcelain").stdout)
    worktrees: dict[str, str] = {}
    path = ""
    branch = ""
    for line in output.splitlines() + [""]:
        if line.startswith("worktree "):
            path = line.removeprefix("worktree ")
        elif line.startswith("branch "):
            branch = line.removeprefix("branch refs/heads/")
        elif not line and path:
            worktrees[str(Path(path).resolve())] = branch
            path = ""
            branch = ""
    return worktrees


def _base_branch(repo: Path, current: str) -> str:
    """Select the task's cleanup base from conventional local branches."""
    branches = set(_branches(repo))
    for candidate in ("main", "master", current):
        if candidate in branches:
            return candidate
    return current


def _is_merged(repo: Path, branch: str, base: str) -> bool:
    """Return whether one local branch is contained in the cleanup base."""
    if not branch or not base or base == "HEAD":
        return False
    return _git(repo, "merge-base", "--is-ancestor", branch, base, check=False).returncode == 0


def _has_descendant_commit(repo: Path, baseline: str, current: str) -> bool:
    """Return whether HEAD advances, rather than merely differs from, the baseline."""
    if not baseline or current == baseline:
        return False
    return _git(repo, "merge-base", "--is-ancestor", baseline, current, check=False).returncode == 0


def _cleanup_candidates(repo: Path, state: dict[str, Any]) -> list[str]:
    """Find only clean merged resources created after this task's baseline."""
    base = str(state.get("base_branch", ""))
    current = _current_branch(repo)
    worktrees = _worktrees(repo)
    baseline_worktrees = set(state.get("baseline_worktrees", {}))
    candidates: list[str] = []
    for path, branch in worktrees.items():
        if path in baseline_worktrees or Path(path).resolve() == repo.resolve():
            continue
        if not _dirty_snapshot(Path(path)) and _is_merged(repo, branch, base):
            candidates.append(f"worktree {path}")
    checked_out = {branch for branch in worktrees.values() if branch}
    for branch in sorted(set(_branches(repo)) - set(state.get("baseline_branches", []))):
        if branch in {base, current} or branch in checked_out:
            continue
        if _is_merged(repo, branch, base):
            candidates.append(f"branch {branch}")
    return candidates


def _initialize(payload: dict[str, Any], state_dir: Path) -> EventResult:
    """Capture the repository baseline before the first mutating dispatch."""
    role = _normalize_role(payload.get("tool_input", {}).get("subagent_type"))
    session_id = str(payload.get("session_id", ""))
    repo = _repo_root(str(payload.get("cwd", "")))
    if not session_id or repo is None:
        return EventResult()
    state = _load_state(state_dir, session_id)
    if state is None:
        if role not in MUTATING_ROLES:
            return EventResult()
        state = {
            "active": True,
            "repo": str(repo),
            "baseline_head": os.fsdecode(_git(repo, "rev-parse", "HEAD").stdout).strip(),
            "baseline_branch": _current_branch(repo),
            "baseline_dirty": _dirty_snapshot(repo),
            "baseline_branches": _branches(repo),
            "baseline_worktrees": _worktrees(repo),
            "base_branch": _base_branch(repo, _current_branch(repo)),
            "builder_dispatched": False,
            "mutation_seq": 0,
            "review_seq": None,
            "verifier_seq": None,
        }
    if role == "builder":
        state["builder_dispatched"] = True
        state["mutation_seq"] = int(state.get("mutation_seq", 0)) + 1
        state["review_seq"] = None
        state["verifier_seq"] = None
    _save_state(state_dir, session_id, state)
    return EventResult()


def _block(reason: str) -> EventResult:
    """Return the structured decision Claude Stop hooks consume."""
    return EventResult(stdout=json.dumps({"decision": "block", "reason": reason}))


def _lint_report(message: str, linter_path: Path) -> str:
    """Return the completion-lint error, or an empty string on success."""
    if not linter_path.is_file():
        return f"completion linter is unavailable at {linter_path}"
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", suffix=".md") as report:
        report.write(message)
        report.flush()
        result = subprocess.run(
            [sys.executable, str(linter_path), "--require-receipt", report.name],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
    return "" if result.returncode == 0 else result.stdout.strip()


def _shipment_verdict(message: str) -> str:
    """Return the structured delivery receipt verdict, if present."""
    match = VERDICT.search(message)
    return match.group(1) if match else ""


def _record_subagent(payload: dict[str, Any], state_dir: Path) -> EventResult:
    """Record structured verifier and reviewer terminal evidence."""
    session_id = str(payload.get("session_id", ""))
    state = _load_state(state_dir, session_id) if session_id else None
    if not state:
        return EventResult()
    role = _normalize_role(payload.get("agent_type"))
    message = str(payload.get("last_assistant_message", ""))
    sequence = int(state.get("mutation_seq", 0))
    if role == "verifier":
        marker = VERIFY_MARKER.search(message)
        if not marker:
            return _block(
                "Verifier result is missing WORKFORCE_VERIFICATION with verdict and full_suite; "
                "continue the verifier and emit the required terminal marker."
            )
        state["verifier_seq"] = sequence if marker.groups() == ("SHIPPABLE", "pass") else None
    elif role == "reviewer":
        marker = REVIEW_MARKER.search(message)
        if not marker:
            return _block(
                "Reviewer result is missing WORKFORCE_REVIEW with its verdict; continue the "
                "reviewer and emit the required terminal marker."
            )
        state["review_seq"] = sequence if marker.group(1) in {"approve", "approve-with-nits"} else None
    else:
        return EventResult()
    _save_state(state_dir, session_id, state)
    return EventResult()


def _inflight_dispatches(transcript_path: str) -> int:
    """Count Agent tool_use blocks in the transcript with no matching tool_result.

    Ground truth from the session JSONL: an unresolved dispatch is still
    running, so Stop is waiting, not claiming completion. An unreadable or
    missing transcript fails closed to 0 (today's strict behavior).
    """
    if not transcript_path:
        return 0
    path = Path(transcript_path)
    if not path.is_file():
        return 0
    pending: set[str] = set()
    try:
        with path.open("r", encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                content = entry.get("message", {}).get("content", [])
                if not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "tool_use" and block.get("name") == "Agent":
                        tool_use_id = block.get("id")
                        if tool_use_id:
                            pending.add(tool_use_id)
                    elif block.get("type") == "tool_result":
                        pending.discard(block.get("tool_use_id"))
    except OSError:
        return 0
    return len(pending)


def _stop(payload: dict[str, Any], state_dir: Path, linter_path: Path) -> EventResult:
    """Block stopping when the worktree differs from its task baseline."""
    session_id = str(payload.get("session_id", ""))
    state = _load_state(state_dir, session_id) if session_id else None
    if not state:
        return EventResult()
    inflight = _inflight_dispatches(str(payload.get("transcript_path", "")))
    message = str(payload.get("last_assistant_message", ""))
    verdict = _shipment_verdict(message)
    if inflight > 0 and verdict == "SHIPPABLE":
        return _block(
            f"{inflight} dispatch(es) in flight — a completion claim cannot be final. "
            "Wait for the outstanding dispatch(es) to resolve before reporting SHIPPABLE."
        )
    if inflight > 0:
        return EventResult()
    repo = Path(state["repo"])
    current = _dirty_snapshot(repo)
    baseline = state.get("baseline_dirty", {})
    changed = sorted(path for path in set(current) | set(baseline) if current.get(path) != baseline.get(path))
    if changed:
        paths = ", ".join(changed[:8])
        return _block(
            "Task-owned uncommitted repository changes remain: "
            f"{paths}. Continue working: dispatch the executor finalizer to stage and commit "
            "only this task's delta, preserving baseline dirt."
        )
    if "WORKFORCE_PAUSE: HUMAN_DECISION" in message:
        return EventResult()
    lint_error = _lint_report(message, linter_path)
    if lint_error:
        return _block(
            "The final response does not have a valid delivery receipt. Continue working and "
            f"repair the closeout report: {lint_error}"
        )
    current_head = os.fsdecode(_git(repo, "rev-parse", "HEAD").stdout).strip()
    current_branch = _current_branch(repo)
    switched_to_preexisting_branch = (
        current_branch != state.get("baseline_branch")
        and current_branch in state.get("baseline_branches", [])
    )
    if verdict == "SHIPPABLE" and (
        switched_to_preexisting_branch
        or not _has_descendant_commit(
            repo,
            str(state.get("baseline_head", "")),
            current_head,
        )
    ):
        return _block(
            "The repository task has no new commit descended from its baseline. Continue "
            "working: dispatch the executor finalizer to create a focused local commit for "
            "the task-owned artifacts."
        )
    if verdict == "SHIPPABLE":
        cleanup = _cleanup_candidates(repo, state)
        if cleanup:
            return _block(
                "Task-created cleanup candidates remain: "
                + ", ".join(cleanup)
                + ". Continue working: dispatch the executor finalizer to remove only these "
                "clean merged non-current resources."
            )
    if verdict == "SHIPPABLE" and state.get("builder_dispatched"):
        sequence = int(state.get("mutation_seq", 0))
        if state.get("verifier_seq") != sequence:
            return _block(
                "Builder work lacks fresh passing verifier evidence. Continue working: dispatch "
                "the verifier after the final Builder edit and record its terminal marker."
            )
        if state.get("review_seq") != sequence:
            return _block(
                "Builder work lacks fresh approving reviewer evidence. Continue working: dispatch "
                "the reviewer against the final diff and record its terminal marker."
            )
    _clear_state(state_dir, session_id)
    return EventResult()


def process_event(
    mode: str,
    payload: dict[str, Any],
    *,
    state_dir: Path,
    linter_path: Path,
) -> EventResult:
    """Process one dispatch, subagent-stop, or main Stop hook event."""
    if mode == "dispatch":
        return _initialize(payload, state_dir)
    if mode == "stop":
        return _stop(payload, state_dir, linter_path)
    if mode == "subagent-stop":
        return _record_subagent(payload, state_dir)
    return EventResult(exit_code=2, stderr=f"unknown closeout hook mode: {mode}\n")


def main(argv: Sequence[str] | None = None) -> int:
    """Read hook JSON from stdin and emit one Claude hook decision."""
    args = list(argv if argv is not None else sys.argv[1:])
    if len(args) != 1:
        print("usage: agent_team_closeout.py dispatch|subagent-stop|stop", file=sys.stderr)
        return 2
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as error:
        print(f"invalid closeout hook JSON: {error}", file=sys.stderr)
        return 2
    state_dir = Path(
        os.environ.get(
            "AGENT_TEAM_CLOSEOUT_DIR",
            str(Path.home() / ".claude" / "state" / "agent-workforce-closeout"),
        )
    )
    linter = Path(os.environ.get("AGENT_TEAM_COMPLETION_LINTER", ""))
    try:
        result = process_event(args[0], payload, state_dir=state_dir, linter_path=linter)
    except Exception as error:  # Hooks must block, not disappear, on state/Git failures.
        reason = (
            "Closeout enforcement failed closed because task state or repository evidence "
            f"could not be read ({type(error).__name__}). Continue working and repair the "
            "closeout hook state before stopping."
        )
        if args[0] in {"stop", "subagent-stop"}:
            result = _block(reason)
        else:
            print(reason, file=sys.stderr)
            return 2
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr, end="")
    return result.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
