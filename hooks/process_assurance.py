#!/usr/bin/env python3
"""Persist and enforce Agent Workforce process-assurance checkpoints."""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import stat
import subprocess
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, Mapping


class AssuranceError(ValueError):
    """Report a typed process-assurance contract violation."""


@dataclass(frozen=True)
class HookDecision:
    """Return one deterministic hook allow or block decision."""

    exit_code: int = 0
    stdout: str = ""
    stderr: str = ""


def canonical_json(value: object) -> bytes:
    """Return deterministic UTF-8 JSON bytes for hashing and persistence."""
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def sha256(value: object) -> str:
    """Hash one canonical JSON value."""
    return hashlib.sha256(canonical_json(value)).hexdigest()


def utc_now() -> str:
    """Return a whole-second UTC timestamp."""
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _string(value: object, field: str) -> str:
    """Validate and return one nonempty bounded string."""
    if not isinstance(value, str) or not value.strip() or len(value) > 4096:
        raise AssuranceError(f"INVALID_WIRE_VALUE: {field}")
    return value


def _string_list(value: object, field: str, *, nonempty: bool = False) -> list[str]:
    """Validate and return one duplicate-free string list."""
    if not isinstance(value, list) or (nonempty and not value):
        raise AssuranceError(f"INVALID_WIRE_VALUE: {field}")
    result = [_string(item, field) for item in value]
    if len(result) != len(set(result)) or len(result) > 256:
        raise AssuranceError(f"INVALID_WIRE_VALUE: {field}")
    return result


def _fsync_directory(path: Path) -> None:
    """Flush a directory entry update to durable storage."""
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _write_atomic(path: Path, value: object) -> None:
    """Write canonical JSON through fsync and atomic replacement."""
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary_name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(canonical_json(value))
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(path)
        _fsync_directory(path.parent)
    finally:
        temporary.unlink(missing_ok=True)


def _git_output(repo: Path, *arguments: str, check: bool = True) -> bytes:
    """Return bounded Git output without invoking a shell."""
    with tempfile.TemporaryFile() as output:
        try:
            result = subprocess.run(
                ["git", "-C", str(repo), *arguments],
                check=False,
                stdout=output,
                stderr=subprocess.PIPE,
                timeout=10,
            )
        except subprocess.TimeoutExpired as error:
            raise AssuranceError("MANIFEST_INCOMPLETE: Git evidence timed out") from error
        except OSError as error:
            raise AssuranceError("MANIFEST_INCOMPLETE: Git executable unavailable") from error
        if check and result.returncode != 0:
            raise AssuranceError("MANIFEST_INCOMPLETE: Git evidence unavailable")
        size = output.tell()
        if size > 25 * 1024 * 1024:
            raise AssuranceError("MANIFEST_INCOMPLETE: Git evidence exceeds limit")
        output.seek(0)
        return output.read()


def workspace_manifest_sha256(cwd: str) -> str:
    """Derive a content-bound Git workspace frontier without storing artifact bytes."""
    root_output = _git_output(Path(cwd), "rev-parse", "--show-toplevel")
    repo = Path(os.fsdecode(root_output).strip()).resolve()
    try:
        head_result = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--verify", "HEAD"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
    except subprocess.TimeoutExpired as error:
        raise AssuranceError("MANIFEST_INCOMPLETE: Git HEAD timed out") from error
    except OSError as error:
        raise AssuranceError("MANIFEST_INCOMPLETE: Git executable unavailable") from error
    head = os.fsdecode(head_result.stdout).strip() if head_result.returncode == 0 else "UNBORN"
    status = _git_output(repo, "status", "--porcelain=v2", "-z", "--untracked-files=all")
    diff = _git_output(repo, "diff", "--binary", "HEAD", "--") if head != "UNBORN" else b""
    untracked = _git_output(repo, "ls-files", "--others", "--exclude-standard", "-z")
    untracked_hashes = _untracked_hashes(repo, untracked)
    return sha256(
        {
            "schema": "workspace-manifest/1",
            "head": head,
            "status_sha256": hashlib.sha256(status).hexdigest(),
            "tracked_diff_sha256": hashlib.sha256(diff).hexdigest(),
            "untracked_sha256s": untracked_hashes,
        }
    )


def _hash_regular_file(candidate: Path) -> str:
    """Hash one bounded regular file without following a last-component symlink."""
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(candidate, flags)
    except OSError as error:
        raise AssuranceError("MANIFEST_INCOMPLETE: untracked file changed during read") from error
    digest = hashlib.sha256(b"file\0")
    total = 5
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise AssuranceError("MANIFEST_INCOMPLETE: unsupported untracked file type")
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > 25 * 1024 * 1024:
                raise AssuranceError("MANIFEST_INCOMPLETE: untracked file exceeds limit")
            digest.update(chunk)
    finally:
        os.close(descriptor)
    return digest.hexdigest()


def _untracked_hashes(repo: Path, raw_paths: bytes) -> dict[str, str]:
    """Hash every untracked file or symlink while confining paths to the repository."""
    result: dict[str, str] = {}
    for raw_path in sorted(path for path in raw_paths.split(b"\0") if path):
        relative = os.fsdecode(raw_path)
        candidate = repo / relative
        if ".." in Path(relative).parts or not candidate.parent.resolve().is_relative_to(repo):
            raise AssuranceError("PATH_ESCAPE: untracked manifest path")
        try:
            metadata = candidate.lstat()
        except OSError as error:
            raise AssuranceError("MANIFEST_INCOMPLETE: untracked file unavailable") from error
        if stat.S_ISLNK(metadata.st_mode):
            try:
                target = os.fsencode(os.readlink(candidate))
            except OSError as error:
                raise AssuranceError(
                    "MANIFEST_INCOMPLETE: untracked symlink changed during read"
                ) from error
            result[relative] = hashlib.sha256(b"symlink\0" + target).hexdigest()
        elif stat.S_ISREG(metadata.st_mode):
            result[relative] = _hash_regular_file(candidate)
        else:
            raise AssuranceError("MANIFEST_INCOMPLETE: unsupported untracked file type")
    return result


class AssuranceStore:
    """Own one session's append-only audit history and current projection."""

    MAX_EVENTS = 10000
    MAX_EVENT_BYTES = 10 * 1024 * 1024
    MAX_STATE_BYTES = 100 * 1024 * 1024

    RULE_IDS = (
        "CHK-01-INTENT",
        "CHK-02-OUTCOME",
        "CHK-03-ROUTE",
        "CHK-04-GATES",
        "CHK-05-CORRELATION",
        "CHK-06-FRESHNESS",
        "CHK-07-TRANSITION",
        "CHK-08-CLOSEOUT",
        "CHK-09-PROCESS-GAP",
    )

    def __init__(self, root: Path, session_id: str, *, mode: str = "ENFORCE") -> None:
        """Bind a validated session identity to a path-confined state directory."""
        identity = _string(session_id, "session_id")
        if mode not in {"OFF", "SHADOW", "ENFORCE"}:
            raise AssuranceError("INVALID_WIRE_VALUE: assurance mode")
        self.mode = mode
        self.root = Path(root).resolve()
        self.session_digest = hashlib.sha256(identity.encode("utf-8")).hexdigest()
        self.directory = self.root / self.session_digest
        self.events_directory = self.directory / "events"
        self.state_path = self.directory / "state.json"
        self.pending_path = self.directory / "pending-commit.json"
        self.lock_path = self.directory / "lock"
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.events_directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.directory, 0o700)
        os.chmod(self.events_directory, 0o700)

    @contextmanager
    def _locked(self) -> Iterator[None]:
        """Serialize mutations for this session without trusting orchestrator state."""
        with self.lock_path.open("a+b") as lock:
            os.chmod(self.lock_path, 0o600)
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)

    def _read_unlocked(self) -> dict[str, Any]:
        """Read the current projection or return an empty session projection."""
        self._recover_pending_unlocked()
        if not self.state_path.is_file():
            return {
                "schema": "process-assurance-state/1",
                "session_digest": self.session_digest,
                "sequence": 0,
                "last_event_sha256": "0" * 64,
                "feature_mode": self.mode,
                "charter_history": [],
                "audit_requests": [],
                "assessment_history": [],
                "authorization_history": [],
                "amendment_history": [],
                "finding_lineages": {},
                "checkpoint_observations": [],
                "effectiveness_outcomes": [],
                "metrics": {
                    "audit_requests": 0,
                    "passes": 0,
                    "remediations": 0,
                    "human_decisions": 0,
                    "amendment_proposals": 0,
                    "amendment_remediations": 0,
                    "amendments": 0,
                    "retroactive_amendments": 0,
                    "false_blocks": 0,
                    "human_overrides": 0,
                    "escaped_violations": 0,
                    "missing_checkpoints": 0,
                    "audit_failures": 0,
                },
            }
        if self.state_path.stat().st_size > self.MAX_STATE_BYTES:
            raise AssuranceError("STATE_CORRUPT: snapshot exceeds capacity")
        state = json.loads(self.state_path.read_text(encoding="utf-8"))
        if state.get("schema") != "process-assurance-state/1":
            raise AssuranceError("STATE_CORRUPT: unknown state schema")
        if state.get("feature_mode") != self.mode:
            raise AssuranceError("FEATURE_STATE_MISMATCH: assurance mode changed without promotion")
        self._verify_integrity(state)
        return state

    def read_state(self) -> dict[str, Any]:
        """Return the current durable projection after basic schema validation."""
        with self._locked():
            return self._read_unlocked()

    def _commit(self, state: dict[str, Any], event_type: str, payload: object) -> None:
        """Journal, append one chained event, and atomically refresh the projection."""
        sequence = int(state["sequence"]) + 1
        if sequence > self.MAX_EVENTS:
            raise AssuranceError("STATE_CAPACITY: event capacity exhausted")
        event = {
            "schema": "process-assurance-event/1",
            "sequence": sequence,
            "event_type": event_type,
            "previous_event_sha256": state["last_event_sha256"],
            "payload": payload,
        }
        event["event_sha256"] = sha256(event)
        if len(canonical_json(event)) > self.MAX_EVENT_BYTES:
            raise AssuranceError("STATE_CAPACITY: event exceeds capacity")
        event_path = self.events_directory / f"{sequence:020d}.json"
        if event_path.exists():
            raise AssuranceError("STATE_CORRUPT: event sequence already exists")
        state["sequence"] = sequence
        state["last_event_sha256"] = event["event_sha256"]
        state.pop("state_sha256", None)
        state["state_sha256"] = sha256(state)
        if len(canonical_json(state)) > self.MAX_STATE_BYTES:
            raise AssuranceError("STATE_CAPACITY: snapshot exceeds capacity")
        pending = {
            "schema": "process-assurance-pending/1",
            "event_filename": event_path.name,
            "event_sha256": event["event_sha256"],
            "state": state,
        }
        _write_atomic(self.pending_path, pending)
        _write_atomic(event_path, event)
        _write_atomic(self.state_path, state)
        self.pending_path.unlink()
        _fsync_directory(self.directory)

    def _recover_pending_unlocked(self) -> None:
        """Finish a journaled commit when its event is durable, or discard an uncommitted journal."""
        if not self.pending_path.is_file():
            return
        if self.pending_path.stat().st_size > self.MAX_STATE_BYTES + self.MAX_EVENT_BYTES:
            raise AssuranceError("STATE_CORRUPT: pending commit exceeds capacity")
        try:
            pending = json.loads(self.pending_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise AssuranceError("STATE_CORRUPT: pending commit unreadable") from error
        if not isinstance(pending, dict) or pending.get("schema") != "process-assurance-pending/1":
            raise AssuranceError("STATE_CORRUPT: pending commit schema")
        filename = pending.get("event_filename")
        event_digest = pending.get("event_sha256")
        candidate_state = pending.get("state")
        if (
            not isinstance(filename, str)
            or not isinstance(event_digest, str)
            or not isinstance(candidate_state, dict)
        ):
            raise AssuranceError("STATE_CORRUPT: pending commit fields")
        event_path = self.events_directory / filename
        if not event_path.is_file():
            self.pending_path.unlink()
            _fsync_directory(self.directory)
            return
        try:
            event = json.loads(event_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise AssuranceError("STATE_CORRUPT: pending event unreadable") from error
        stored_event_hash = event.pop("event_sha256", None)
        snapshot = dict(candidate_state)
        stored_snapshot_hash = snapshot.pop("state_sha256", None)
        if (
            stored_event_hash != event_digest
            or stored_event_hash != sha256(event)
            or filename != f"{event.get('sequence', -1):020d}.json"
            or candidate_state.get("sequence") != event.get("sequence")
            or candidate_state.get("last_event_sha256") != event_digest
            or stored_snapshot_hash != sha256(snapshot)
        ):
            raise AssuranceError("STATE_CORRUPT: pending commit mismatch")
        if self.state_path.is_file():
            current = json.loads(self.state_path.read_text(encoding="utf-8"))
            if int(current.get("sequence", -1)) > int(candidate_state["sequence"]):
                raise AssuranceError("STATE_CORRUPT: stale pending commit")
        _write_atomic(self.state_path, candidate_state)
        self.pending_path.unlink()
        _fsync_directory(self.directory)

    def _verify_integrity(self, state: Mapping[str, Any]) -> None:
        """Verify the snapshot digest and complete append-only event hash chain."""
        snapshot = dict(state)
        stored_snapshot_hash = snapshot.pop("state_sha256", None)
        if stored_snapshot_hash != sha256(snapshot):
            raise AssuranceError("STATE_CORRUPT: snapshot digest mismatch")
        event_paths = sorted(self.events_directory.glob("*.json"))
        if len(event_paths) != state.get("sequence") or len(event_paths) > self.MAX_EVENTS:
            raise AssuranceError("STATE_CORRUPT: event count mismatch")
        previous = "0" * 64
        for expected_sequence, path in enumerate(event_paths, start=1):
            if path.stat().st_size > self.MAX_EVENT_BYTES:
                raise AssuranceError("STATE_CORRUPT: event exceeds capacity")
            event = json.loads(path.read_text(encoding="utf-8"))
            stored_event_hash = event.pop("event_sha256", None)
            if (
                path.name != f"{expected_sequence:020d}.json"
                or event.get("sequence") != expected_sequence
                or event.get("previous_event_sha256") != previous
                or stored_event_hash != sha256(event)
            ):
                raise AssuranceError("STATE_CORRUPT: event chain mismatch")
            previous = stored_event_hash
        if previous != state.get("last_event_sha256"):
            raise AssuranceError("STATE_CORRUPT: event head mismatch")

    def initialize_charter(self, value: Mapping[str, object]) -> dict[str, Any]:
        """Create the separately approved version-one task charter exactly once."""
        with self._locked():
            state = self._read_unlocked()
            if state["charter_history"]:
                existing = self._active_charter(state)
                duplicate = dict(value)
                duplicate.setdefault("approved_at", existing["approved_at"])
                if self._validate_initial_charter(duplicate)["charter_sha256"] == existing[
                    "charter_sha256"
                ]:
                    return existing
                raise AssuranceError("EVENT_CONFLICT: charter already initialized")
            charter = self._validate_initial_charter(value)
            state["charter_history"].append(charter)
            state["active_charter_sha256"] = charter["charter_sha256"]
            state["tier"] = charter["tier"]
            self._commit(state, "charter.initialized", charter)
            return charter

    def request_audit(self, value: Mapping[str, object]) -> dict[str, Any]:
        """Persist one full checkpoint request before invoking the independent auditor."""
        with self._locked():
            state = self._read_unlocked()
            charter = self._active_charter(state)
            request_value = dict(value)
            request_identity = _string(request_value.get("request_id"), "request_id")
            prior_requests = [
                item
                for item in state["audit_requests"]
                if item["request_id"] == request_identity
            ]
            if len(prior_requests) == 1:
                request_value.setdefault("requested_at", prior_requests[0]["requested_at"])
            request = self._validate_audit_request(request_value, charter)
            if request["submission_kind"] == "REMEDIATION" and any(
                target not in state["finding_lineages"]
                for target in request["target_lineage_ids"]
            ):
                raise AssuranceError("INVALID_WIRE_VALUE: unknown remediation target")
            if prior_requests:
                if (
                    len(prior_requests) == 1
                    and prior_requests[0]["status"] == "REQUESTED"
                    and prior_requests[0]["request_sha256"] == request["request_sha256"]
                ):
                    return prior_requests[0]
                raise AssuranceError("EVENT_CONFLICT: request_id")
            if any(
                item["checkpoint"] == request["checkpoint"] and item["status"] == "REQUESTED"
                for item in state["audit_requests"]
            ):
                raise AssuranceError("EVENT_CONFLICT: checkpoint already has an open request")
            self._invalidate_authorizations(
                state, request["checkpoint"], f"superseded-by-request:{request['request_id']}"
            )
            state["audit_requests"].append(request)
            state["metrics"]["audit_requests"] += 1
            self._commit(state, "audit.requested", request)
            return request

    def record_assessment(
        self, request_id: str, value: Mapping[str, object]
    ) -> dict[str, Any]:
        """Admit one strict assessment and derive authorization only from a valid PASS."""
        with self._locked():
            state = self._read_unlocked()
            request = self._open_request(state, _string(request_id, "request_id"))
            if any(
                item["assessment_id"] == value.get("assessment_id")
                for item in state["assessment_history"]
            ):
                raise AssuranceError("EVENT_CONFLICT: assessment_id")
            assessment = self._validate_assessment(value, request, state)
            request["status"] = "ASSESSED"
            request["assessment_id"] = assessment["assessment_id"]
            state["assessment_history"].append(assessment)
            self._apply_assessment(state, request, assessment, self.mode)
            self._commit(state, "audit.assessed", assessment)
            return assessment

    def authorize_transition(
        self,
        checkpoint: str,
        transition: str,
        evidence_manifest_sha256: str,
        dispatch_id: str | None = None,
    ) -> dict[str, Any]:
        """Consume the one current authorization bound to an exact transition frontier."""
        with self._locked():
            state = self._read_unlocked()
            binding = (
                _string(checkpoint, "checkpoint"),
                _string(transition, "transition"),
                self._digest(evidence_manifest_sha256, "evidence_manifest_sha256"),
                state.get("active_charter_sha256"),
            )
            available = [
                item
                for item in state["authorization_history"]
                if item["state"] == "AVAILABLE"
                and (
                    item["checkpoint"],
                    item["requested_transition"],
                    item["evidence_manifest_sha256"],
                    item["charter_sha256"],
                )
                == binding
            ]
            if not available:
                raise AssuranceError("AUTHORIZATION_REUSED: no current PASS authorization")
            authorization = available[-1]
            authorization["state"] = "CONSUMED"
            authorization["consumed_at"] = utc_now()
            if dispatch_id is not None:
                authorization["dispatch_id"] = _string(dispatch_id, "dispatch_id")
            receipt = {
                "schema": "transition-receipt/1",
                "authorization_id": authorization["authorization_id"],
                "authorization_state": "CONSUMED",
                "checkpoint": checkpoint,
                "requested_transition": transition,
                "evidence_manifest_sha256": evidence_manifest_sha256,
                "charter_sha256": binding[3],
                "consumed_at": authorization["consumed_at"],
            }
            if dispatch_id is not None:
                receipt["dispatch_id"] = authorization["dispatch_id"]
            receipt["receipt_sha256"] = sha256(receipt)
            authorization["receipt_sha256"] = receipt["receipt_sha256"]
            self._rehash_authorization(authorization)
            self._commit(state, "transition.authorized", receipt)
            return receipt

    def validate_consumed_receipt(
        self,
        value: Mapping[str, object],
        dispatch_id: str,
        transition: Mapping[str, object],
        current_manifest: str,
    ) -> dict[str, Any]:
        """Accept one duplicate hook pass only for the same platform tool invocation."""
        receipt = dict(value)
        supplied_digest = receipt.pop("receipt_sha256", None)
        if supplied_digest != sha256(receipt):
            raise AssuranceError("HASH_MISMATCH: transition receipt")
        if receipt.get("dispatch_id") != _string(dispatch_id, "dispatch_id"):
            raise AssuranceError("AUTHORIZATION_REUSED: receipt belongs to another dispatch")
        expected = {
            "checkpoint": transition.get("checkpoint"),
            "requested_transition": transition.get("requested_transition"),
            "evidence_manifest_sha256": current_manifest,
        }
        if any(
            receipt.get(field) != expected_value
            for field, expected_value in expected.items()
        ):
            raise AssuranceError("HASH_MISMATCH: transition receipt binding")
        with self._locked():
            state = self._read_unlocked()
            matches = [
                item
                for item in state["authorization_history"]
                if item["authorization_id"] == receipt.get("authorization_id")
                and item["state"] == "CONSUMED"
                and item.get("dispatch_id") == dispatch_id
                and item.get("receipt_sha256") == supplied_digest
            ]
            if len(matches) != 1:
                raise AssuranceError("AUTHORIZATION_REUSED: receipt is not current")
            if receipt.get("charter_sha256") != state.get("active_charter_sha256"):
                raise AssuranceError("HASH_MISMATCH: receipt charter is stale")
        receipt["receipt_sha256"] = supplied_digest
        return receipt

    def record_checkpoint_observation(self, checkpoint: str, status: str) -> dict[str, Any]:
        """Record one nonblocking structural checkpoint outcome in shadow mode."""
        if status not in {
            "PASS",
            "REMEDIATE",
            "HUMAN_DECISION",
            "MISSING",
            "AUDIT_FAILURE",
        }:
            raise AssuranceError("INVALID_WIRE_VALUE: shadow checkpoint observation")
        with self._locked():
            state = self._read_unlocked()
            prior = [
                item
                for item in state["checkpoint_observations"]
                if item["checkpoint"] == checkpoint
            ]
            if prior and prior[-1]["status"] == status:
                return prior[-1]
            observation = {
                "schema": "checkpoint-observation/1",
                "checkpoint": _string(checkpoint, "checkpoint"),
                "status": status,
                "effective_mode": "SHADOW",
                "observed_at": utc_now(),
            }
            observation["observation_sha256"] = sha256(observation)
            state["checkpoint_observations"].append(observation)
            if status == "MISSING":
                state["metrics"]["missing_checkpoints"] += 1
            if status == "AUDIT_FAILURE":
                state["metrics"]["audit_failures"] += 1
            self._commit(state, "checkpoint.observed", observation)
            return observation

    def record_effectiveness_outcome(self, value: Mapping[str, object]) -> dict[str, Any]:
        """Persist one independently evidenced false block, override, or escaped violation."""
        with self._locked():
            state = self._read_unlocked()
            outcome_type = value.get("outcome_type")
            if not isinstance(outcome_type, str):
                raise AssuranceError("INVALID_WIRE_VALUE: effectiveness outcome_type")
            metric = {
                "FALSE_BLOCK": "false_blocks",
                "HUMAN_OVERRIDE": "human_overrides",
                "ESCAPED_VIOLATION": "escaped_violations",
            }.get(outcome_type)
            if metric is None:
                raise AssuranceError("INVALID_WIRE_VALUE: effectiveness outcome_type")
            outcome: dict[str, Any] = {
                "schema": "effectiveness-outcome/1",
                "outcome_id": _string(value.get("outcome_id"), "outcome_id"),
                "outcome_type": outcome_type,
                "checkpoint": _string(value.get("checkpoint"), "checkpoint"),
                "evidence_refs": _string_list(
                    value.get("evidence_refs"), "effectiveness evidence_refs", nonempty=True
                ),
                "adjudicator_identity": _string(
                    value.get("adjudicator_identity"), "adjudicator_identity"
                ),
                "recorded_at": _string(value.get("recorded_at", utc_now()), "recorded_at"),
            }
            if any(
                item["outcome_id"] == outcome["outcome_id"]
                for item in state["effectiveness_outcomes"]
            ):
                raise AssuranceError("EVENT_CONFLICT: outcome_id")
            outcome["outcome_sha256"] = sha256(outcome)
            state["effectiveness_outcomes"].append(outcome)
            state["metrics"][metric] += 1
            self._commit(state, "effectiveness.recorded", outcome)
            return outcome

    def metrics_report(self) -> dict[str, Any]:
        """Return the durable compliance and effectiveness scorecard inputs."""
        state = self.read_state()
        return dict(state["metrics"]) | {
            "effectiveness_outcomes": list(state["effectiveness_outcomes"]),
            "amendment_frequency": state["metrics"]["amendment_proposals"],
            "approved_amendments": state["metrics"]["amendments"],
            "remediation_frequency": state["metrics"]["remediations"],
        }

    def propose_amendment(self, value: Mapping[str, object]) -> dict[str, Any]:
        """Persist an amendment proposal without changing the active charter."""
        with self._locked():
            state = self._read_unlocked()
            charter = self._active_charter(state)
            proposal = self._validate_amendment_proposal(value, charter)
            if any(
                item["proposal_id"] == proposal["proposal_id"]
                for item in state["amendment_history"]
            ):
                raise AssuranceError("EVENT_CONFLICT: proposal_id")
            self._invalidate_authorizations(
                state, None, f"amendment-proposed:{proposal['proposal_id']}"
            )
            state["amendment_history"].append(proposal)
            state["metrics"]["amendment_proposals"] += 1
            self._commit(state, "amendment.proposed", proposal)
            return proposal

    def assess_amendment(
        self, proposal_id: str, value: Mapping[str, object]
    ) -> dict[str, Any]:
        """Record the independent auditor's amendment assessment before human action."""
        with self._locked():
            state = self._read_unlocked()
            proposal = self._proposal(state, proposal_id, "PROPOSED")
            assessment = self._validate_amendment_assessment(value, proposal)
            proposal["status"] = (
                "REMEDIATION_REQUIRED"
                if assessment["verdict"] == "REMEDIATE"
                else "ASSESSED"
            )
            proposal["assessment"] = assessment
            if assessment["verdict"] == "REMEDIATE":
                state["metrics"]["amendment_remediations"] += 1
            self._commit(state, "amendment.assessed", assessment)
            return assessment

    def decide_amendment(
        self, proposal_id: str, value: Mapping[str, object]
    ) -> dict[str, Any]:
        """Apply or reject one separately assessed amendment using human authority."""
        with self._locked():
            state = self._read_unlocked()
            proposal = self._proposal(state, proposal_id, "ASSESSED")
            decision = self._validate_amendment_decision(value, proposal)
            proposal["status"] = "APPROVED" if decision["decision"] == "APPROVE" else "REJECTED"
            proposal["decision"] = decision
            if decision["decision"] == "REJECT":
                self._commit(state, "amendment.rejected", decision)
                return self._active_charter(state)
            charter = self._apply_amendment(state, proposal, decision)
            self._commit(
                state,
                "amendment.approved",
                {"proposal": proposal, "resulting_charter": charter},
            )
            return charter

    @staticmethod
    def _active_charter(state: Mapping[str, Any]) -> dict[str, Any]:
        """Return the active full charter from immutable history."""
        active = state.get("active_charter_sha256")
        for charter in reversed(state.get("charter_history", [])):
            if charter.get("charter_sha256") == active:
                return charter
        raise AssuranceError("STATE_CORRUPT: active charter unavailable")

    @staticmethod
    def _digest(value: object, field: str) -> str:
        """Validate one lowercase SHA-256 digest."""
        text = _string(value, field)
        if len(text) != 64 or any(character not in "0123456789abcdef" for character in text):
            raise AssuranceError(f"INVALID_WIRE_VALUE: {field}")
        return text

    def _validate_audit_request(
        self, value: Mapping[str, object], charter: Mapping[str, Any]
    ) -> dict[str, Any]:
        """Bind an audit request to the exact active charter and evidence manifest."""
        checkpoint = _string(value.get("checkpoint"), "checkpoint")
        if checkpoint not in charter["required_checkpoints"]:
            raise AssuranceError("INVALID_WIRE_VALUE: checkpoint not required by charter")
        kind = value.get("submission_kind")
        targets = _string_list(value.get("target_lineage_ids"), "target_lineage_ids")
        if kind not in {"INITIAL", "REMEDIATION"} or (kind == "INITIAL" and targets):
            raise AssuranceError("INVALID_WIRE_VALUE: submission_kind or targets")
        if kind == "REMEDIATION" and not targets:
            raise AssuranceError("INVALID_WIRE_VALUE: remediation requires targets")
        request: dict[str, Any] = {
            "schema": "audit-request/1",
            "request_id": _string(value.get("request_id"), "request_id"),
            "checkpoint": checkpoint,
            "requested_transition": _string(
                value.get("requested_transition"), "requested_transition"
            ),
            "submission_kind": kind,
            "target_lineage_ids": targets,
            "active_charter": charter,
            "charter_sha256": charter["charter_sha256"],
            "evidence_manifest_sha256": self._digest(
                value.get("evidence_manifest_sha256"), "evidence_manifest_sha256"
            ),
            "evidence_refs": _string_list(
                value.get("evidence_refs"), "evidence_refs", nonempty=True
            ),
            "requested_at": _string(value.get("requested_at", utc_now()), "requested_at"),
            "status": "REQUESTED",
        }
        request["request_sha256"] = sha256(request)
        return request

    def _validate_amendment_proposal(
        self, value: Mapping[str, object], charter: Mapping[str, Any]
    ) -> dict[str, Any]:
        """Validate a bounded proposal and bind it to the current charter version."""
        if value.get("origin") not in {
            "SPONSOR_REQUEST",
            "NEWLY_DISCOVERED_FACT",
            "ORCHESTRATOR_PROPOSAL",
        } or not isinstance(value.get("work_already_occurred"), bool):
            raise AssuranceError("INVALID_WIRE_VALUE: amendment origin or timing")
        changes = value.get("proposed_changes")
        allowed = {
            "objective",
            "delivery_target",
            "scope",
            "non_goals",
            "acceptance_criteria",
            "required_checkpoints",
        }
        if not isinstance(changes, dict) or not changes or not set(changes) <= allowed:
            raise AssuranceError("INVALID_WIRE_VALUE: proposed_changes")
        changes = self._validate_proposed_changes(changes)
        proposal: dict[str, Any] = {
            "schema": "charter-amendment-proposal/1",
            "proposal_id": _string(value.get("proposal_id"), "proposal_id"),
            "base_charter_sha256": charter["charter_sha256"],
            "origin": value["origin"],
            "work_already_occurred": value["work_already_occurred"],
            "rationale": _string(value.get("rationale"), "rationale"),
            "proposed_changes": changes,
            "proposer_identity": _string(
                value.get("proposer_identity"), "proposer_identity"
            ),
            "proposed_at": _string(value.get("proposed_at", utc_now()), "proposed_at"),
            "status": "PROPOSED",
        }
        proposal["proposal_sha256"] = sha256(proposal)
        return proposal

    @staticmethod
    def _validate_proposed_changes(changes: Mapping[str, object]) -> dict[str, Any]:
        """Normalize each permitted charter field before a proposal enters history."""
        normalized: dict[str, Any] = {}
        for field, value in changes.items():
            if field in {"objective", "delivery_target"}:
                normalized[field] = _string(value, f"proposed_changes.{field}")
            else:
                normalized[field] = _string_list(
                    value,
                    f"proposed_changes.{field}",
                    nonempty=field in {"scope", "acceptance_criteria", "required_checkpoints"},
                )
        return normalized

    @staticmethod
    def _proposal(
        state: Mapping[str, Any], proposal_id: str, expected_status: str
    ) -> dict[str, Any]:
        """Return one exact amendment proposal in its expected lifecycle state."""
        identity = _string(proposal_id, "proposal_id")
        matches = [item for item in state["amendment_history"] if item["proposal_id"] == identity]
        if len(matches) != 1 or matches[0]["status"] != expected_status:
            raise AssuranceError("EVENT_CONFLICT: amendment lifecycle")
        return matches[0]

    @staticmethod
    def _validate_amendment_assessment(
        value: Mapping[str, object], proposal: Mapping[str, Any]
    ) -> dict[str, Any]:
        """Require heightened review for work that preceded amendment approval."""
        verdict = value.get("verdict")
        if (
            verdict not in {"PASS", "REMEDIATE", "HUMAN_DECISION"}
            or (proposal["work_already_occurred"] and verdict == "PASS")
            or value.get("proposal_sha256") != proposal["proposal_sha256"]
        ):
            raise AssuranceError("INVALID_WIRE_VALUE: amendment assessment verdict or hash")
        auditor = _string(value.get("auditor_identity"), "auditor_identity")
        if auditor == proposal["proposer_identity"]:
            raise AssuranceError("ACTOR_UNAUTHORIZED: proposer cannot audit amendment")
        assessment: dict[str, Any] = {
            "schema": "amendment-assessment/1",
            "assessment_id": _string(value.get("assessment_id"), "assessment_id"),
            "proposal_id": proposal["proposal_id"],
            "proposal_sha256": proposal["proposal_sha256"],
            "verdict": verdict,
            "rationale": _string(value.get("rationale"), "rationale"),
            "evidence_refs": _string_list(
                value.get("evidence_refs"), "amendment evidence_refs", nonempty=True
            ),
            "auditor_identity": auditor,
            "assessed_at": _string(value.get("assessed_at", utc_now()), "assessed_at"),
        }
        assessment["assessment_sha256"] = sha256(assessment)
        return assessment

    @staticmethod
    def _validate_amendment_decision(
        value: Mapping[str, object], proposal: Mapping[str, Any]
    ) -> dict[str, Any]:
        """Validate a human decision that cannot retroactively erase history."""
        if value.get("decision") not in {"APPROVE", "REJECT"}:
            raise AssuranceError("INVALID_WIRE_VALUE: amendment decision")
        prospective = value.get("effective_prospectively")
        if not isinstance(prospective, bool) or (
            proposal["work_already_occurred"] and not prospective
        ):
            raise AssuranceError("INVALID_WIRE_VALUE: retroactive amendment must be prospective")
        decider = _string(value.get("decided_by"), "decided_by")
        if decider in {
            proposal["proposer_identity"],
            proposal["assessment"]["auditor_identity"],
        }:
            raise AssuranceError("ACTOR_UNAUTHORIZED: amendment roles must be separate")
        decision: dict[str, Any] = {
            "schema": "amendment-decision/1",
            "proposal_id": proposal["proposal_id"],
            "assessment_sha256": proposal["assessment"]["assessment_sha256"],
            "decision": value["decision"],
            "decided_by": decider,
            "approval_ref": _string(value.get("approval_ref"), "approval_ref"),
            "effective_prospectively": prospective,
            "decided_at": _string(value.get("decided_at", utc_now()), "decided_at"),
        }
        decision["decision_sha256"] = sha256(decision)
        return decision

    def _apply_amendment(
        self,
        state: dict[str, Any],
        proposal: Mapping[str, Any],
        decision: Mapping[str, Any],
    ) -> dict[str, Any]:
        """Create the next charter version and invalidate stale authorization."""
        prior = self._active_charter(state)
        if proposal["base_charter_sha256"] != prior["charter_sha256"]:
            raise AssuranceError("HASH_MISMATCH: amendment base charter is stale")
        charter = {key: value for key, value in prior.items() if key != "charter_sha256"}
        charter.update(proposal["proposed_changes"])
        charter.update(
            {
                "version": prior["version"] + 1,
                "prior_charter_sha256": prior["charter_sha256"],
                "approved_by": decision["decided_by"],
                "approval_ref": decision["approval_ref"],
                "approved_at": decision["decided_at"],
                "amendment_proposal_id": proposal["proposal_id"],
                "prospective_only": proposal["work_already_occurred"],
            }
        )
        charter["charter_sha256"] = sha256(charter)
        state["charter_history"].append(charter)
        state["active_charter_sha256"] = charter["charter_sha256"]
        self._invalidate_authorizations(
            state, None, f"amendment-approved:{proposal['proposal_id']}"
        )
        state["metrics"]["amendments"] += 1
        if proposal["work_already_occurred"]:
            state["metrics"]["retroactive_amendments"] += 1
        return charter

    @staticmethod
    def _invalidate_authorizations(
        state: dict[str, Any], checkpoint: str | None, reason: str
    ) -> None:
        """Invalidate every available authorization within an affected checkpoint."""
        for authorization in state["authorization_history"]:
            if authorization["state"] != "AVAILABLE":
                continue
            if checkpoint is not None and authorization["checkpoint"] != checkpoint:
                continue
            authorization["state"] = "INVALIDATED"
            authorization["invalidated_reason"] = reason
            authorization["invalidated_at"] = utc_now()
            AssuranceStore._rehash_authorization(authorization)

    @staticmethod
    def _rehash_authorization(authorization: dict[str, Any]) -> None:
        """Refresh one mutable projection record's canonical digest after a state change."""
        authorization.pop("authorization_sha256", None)
        authorization["authorization_sha256"] = sha256(authorization)

    @staticmethod
    def _open_request(state: Mapping[str, Any], request_id: str) -> dict[str, Any]:
        """Locate one outstanding request by exact identity."""
        matches = [item for item in state["audit_requests"] if item["request_id"] == request_id]
        if len(matches) != 1 or matches[0]["status"] != "REQUESTED":
            raise AssuranceError("EVENT_CONFLICT: request not open")
        return matches[0]

    def _validate_assessment(
        self,
        value: Mapping[str, object],
        request: Mapping[str, Any],
        state: Mapping[str, Any],
    ) -> dict[str, Any]:
        """Validate the closed checklist and deterministic aggregate verdict."""
        supplied_request_hash = value.get("request_sha256")
        if supplied_request_hash != request["request_sha256"]:
            raise AssuranceError("HASH_MISMATCH: request_sha256")
        evaluations = value.get("rule_evaluations")
        if not isinstance(evaluations, list) or [
            item.get("rule_id") if isinstance(item, dict) else None for item in evaluations
        ] != list(self.RULE_IDS):
            raise AssuranceError("INVALID_WIRE_VALUE: rule_evaluations")
        checked = [self._validate_rule_evaluation(item) for item in evaluations]
        findings = self._validate_findings(value.get("findings"), request, state)
        violated_rules = {
            item["rule_id"] for item in checked if item["result"] == "VIOLATED"
        }
        finding_rules = {item["rule_id"] for item in findings}
        if violated_rules != finding_rules:
            raise AssuranceError("INVALID_WIRE_VALUE: rule/finding consistency")
        aggregate = self._aggregate_verdict(findings)
        if value.get("verdict") != aggregate:
            raise AssuranceError("INVALID_WIRE_VALUE: verdict does not match findings")
        assessment: dict[str, Any] = {
            "schema": "process-audit-assessment/1",
            "assessment_id": _string(value.get("assessment_id"), "assessment_id"),
            "request_id": request["request_id"],
            "request_sha256": request["request_sha256"],
            "verdict": aggregate,
            "rule_evaluations": checked,
            "findings": findings,
            "auditor_identity": _string(value.get("auditor_identity"), "auditor_identity"),
            "assessed_at": _string(value.get("assessed_at", utc_now()), "assessed_at"),
        }
        assessment["assessment_sha256"] = sha256(assessment)
        return assessment

    def _validate_findings(
        self,
        value: object,
        request: Mapping[str, Any],
        state: Mapping[str, Any],
    ) -> list[dict[str, Any]]:
        """Validate bounded findings and preserve existing lineage identity."""
        if not isinstance(value, list) or len(value) > 64:
            raise AssuranceError("INVALID_WIRE_VALUE: findings")
        findings = [self._validate_finding(item) for item in value]
        lineage_ids = [item["lineage_id"] for item in findings]
        if len(lineage_ids) != len(set(lineage_ids)):
            raise AssuranceError("INVALID_WIRE_VALUE: duplicate finding lineage")
        lineages = state["finding_lineages"]
        for finding in findings:
            prior = lineages.get(finding["lineage_id"])
            if prior and (
                prior["rule_id"], prior["affected_element"]
            ) != (finding["rule_id"], finding["affected_element"]):
                raise AssuranceError("EVENT_CONFLICT: finding lineage identity changed")
            reset = [
                lineage_id
                for lineage_id, existing in lineages.items()
                if lineage_id != finding["lineage_id"]
                and (existing["rule_id"], existing["affected_element"])
                == (finding["rule_id"], finding["affected_element"])
            ]
            if reset:
                raise AssuranceError("EVENT_CONFLICT: finding lineage reset")
        exhausted = {
            target
            for target in request["target_lineage_ids"]
            if lineages[target]["remediation_count"] >= 2 and target in lineage_ids
        }
        if exhausted and any(
            finding["lineage_id"] in exhausted
            and finding["required_verdict"] != "HUMAN_DECISION"
            for finding in findings
        ):
            raise AssuranceError("INVALID_WIRE_VALUE: exhausted remediation requires human decision")
        return findings

    def _validate_finding(self, value: object) -> dict[str, Any]:
        """Validate one actionable process-audit finding."""
        if not isinstance(value, dict):
            raise AssuranceError("INVALID_WIRE_VALUE: finding")
        if value.get("rule_id") not in self.RULE_IDS or value.get("severity") not in {
            "LOW",
            "MEDIUM",
            "HIGH",
            "CRITICAL",
        }:
            raise AssuranceError("INVALID_WIRE_VALUE: finding rule or severity")
        if value.get("required_verdict") not in {"REMEDIATE", "HUMAN_DECISION"}:
            raise AssuranceError("INVALID_WIRE_VALUE: finding verdict")
        return {
            "finding_id": _string(value.get("finding_id"), "finding_id"),
            "lineage_id": _string(value.get("lineage_id"), "lineage_id"),
            "rule_id": value["rule_id"],
            "severity": value["severity"],
            "affected_element": _string(value.get("affected_element"), "affected_element"),
            "summary": _string(value.get("summary"), "summary"),
            "evidence_refs": _string_list(
                value.get("evidence_refs"), "finding evidence_refs", nonempty=True
            ),
            "required_correction": _string(
                value.get("required_correction"), "required_correction"
            ),
            "required_verdict": value["required_verdict"],
        }

    @staticmethod
    def _validate_rule_evaluation(value: object) -> dict[str, Any]:
        """Require direct evidence and positive reasoning for every checklist rule."""
        if not isinstance(value, dict) or value.get("result") not in {
            "SATISFIED",
            "VIOLATED",
            "NOT_APPLICABLE",
        }:
            raise AssuranceError("INVALID_WIRE_VALUE: rule evaluation result")
        return {
            "rule_id": _string(value.get("rule_id"), "rule_id"),
            "result": value["result"],
            "rationale": _string(value.get("rationale"), "rationale"),
            "evidence_refs": _string_list(
                value.get("evidence_refs"), "rule evidence_refs", nonempty=True
            ),
        }

    @staticmethod
    def _aggregate_verdict(findings: object) -> str:
        """Select the strongest closed verdict without an advisory warning state."""
        if not isinstance(findings, list):
            raise AssuranceError("INVALID_WIRE_VALUE: findings")
        verdicts = []
        for finding in findings:
            if not isinstance(finding, dict) or finding.get("required_verdict") not in {
                "REMEDIATE",
                "HUMAN_DECISION",
            }:
                raise AssuranceError("INVALID_WIRE_VALUE: finding verdict")
            verdicts.append(finding["required_verdict"])
        if "HUMAN_DECISION" in verdicts:
            return "HUMAN_DECISION"
        return "REMEDIATE" if verdicts else "PASS"

    @classmethod
    def _apply_assessment(
        cls,
        state: dict[str, Any],
        request: Mapping[str, Any],
        assessment: Mapping[str, Any],
        mode: str,
    ) -> None:
        """Update metrics and mint one available authorization for a clean PASS."""
        verdict = assessment["verdict"]
        metric = {
            "PASS": "passes",
            "REMEDIATE": "remediations",
            "HUMAN_DECISION": "human_decisions",
        }[verdict]
        state["metrics"][metric] += 1
        cls._update_lineages(state, request, assessment)
        if verdict != "PASS" or mode != "ENFORCE":
            return
        authorization = {
            "schema": "transition-authorization/1",
            "authorization_id": f"authorization-{assessment['assessment_id']}",
            "assessment_id": assessment["assessment_id"],
            "checkpoint": request["checkpoint"],
            "requested_transition": request["requested_transition"],
            "charter_sha256": request["charter_sha256"],
            "evidence_manifest_sha256": request["evidence_manifest_sha256"],
            "state": "AVAILABLE",
            "created_at": assessment["assessed_at"],
        }
        authorization["authorization_sha256"] = sha256(authorization)
        state["authorization_history"].append(authorization)

    @staticmethod
    def _update_lineages(
        state: dict[str, Any], request: Mapping[str, Any], assessment: Mapping[str, Any]
    ) -> None:
        """Advance finding remediation counts and liveness states deterministically."""
        findings = {item["lineage_id"]: item for item in assessment["findings"]}
        for lineage_id, finding in findings.items():
            lineage = state["finding_lineages"].setdefault(
                lineage_id,
                {
                    "lineage_id": lineage_id,
                    "rule_id": finding["rule_id"],
                    "affected_element": finding["affected_element"],
                    "remediation_count": 0,
                    "state": "OPEN",
                },
            )
            if (
                request["submission_kind"] == "REMEDIATION"
                and lineage_id in request["target_lineage_ids"]
            ):
                lineage["remediation_count"] += 1
            lineage["state"] = (
                "ESCALATED"
                if assessment["verdict"] == "HUMAN_DECISION"
                else "REMEDIATING"
                if request["submission_kind"] == "REMEDIATION"
                else "OPEN"
            )
            lineage["latest_finding_id"] = finding["finding_id"]
        for lineage_id in request["target_lineage_ids"]:
            if lineage_id not in findings:
                state["finding_lineages"][lineage_id]["state"] = "RESOLVED"

    @staticmethod
    def _validate_initial_charter(value: Mapping[str, object]) -> dict[str, Any]:
        """Validate the fixed initial charter and derive its canonical digest."""
        if value.get("version") != 1 or value.get("tier") not in {
            "trivial",
            "small",
            "standard",
            "large",
        }:
            raise AssuranceError("INVALID_WIRE_VALUE: charter version or tier")
        charter: dict[str, Any] = {
            "schema": "intent-charter/1",
            "task_id": _string(value.get("task_id"), "task_id"),
            "version": 1,
            "tier": value["tier"],
            "objective": _string(value.get("objective"), "objective"),
            "delivery_target": _string(value.get("delivery_target"), "delivery_target"),
            "scope": _string_list(value.get("scope"), "scope", nonempty=True),
            "non_goals": _string_list(value.get("non_goals"), "non_goals"),
            "acceptance_criteria": _string_list(
                value.get("acceptance_criteria"), "acceptance_criteria", nonempty=True
            ),
            "required_checkpoints": _string_list(
                value.get("required_checkpoints"), "required_checkpoints", nonempty=True
            ),
            "approved_by": _string(value.get("approved_by"), "approved_by"),
            "approval_ref": _string(value.get("approval_ref"), "approval_ref"),
            "approved_at": _string(value.get("approved_at", utc_now()), "approved_at"),
        }
        charter["charter_sha256"] = sha256(charter)
        return charter


def _marker(text: object, prefix: str) -> dict[str, Any] | None:
    """Parse exactly one standalone strict JSON marker from untrusted text."""
    if not isinstance(text, str):
        raise AssuranceError(f"INVALID_WIRE_VALUE: {prefix} text")
    matches = [line[len(prefix) :] for line in text.splitlines() if line.startswith(prefix)]
    if not matches:
        return None
    if len(matches) != 1:
        raise AssuranceError(f"INVALID_WIRE_VALUE: duplicate {prefix.strip()}")
    try:
        value = json.loads(matches[0])
    except json.JSONDecodeError as error:
        raise AssuranceError(f"INVALID_WIRE_VALUE: malformed {prefix.strip()}") from error
    if not isinstance(value, dict):
        raise AssuranceError(f"INVALID_WIRE_VALUE: {prefix.strip()} must be an object")
    return value


def _role(payload: Mapping[str, Any]) -> str:
    """Normalize the exact bare or plugin-qualified specialist role."""
    value = str(_tool_input(payload).get("subagent_type", ""))
    return value.split(":", 1)[-1]


def _tool_input(payload: Mapping[str, Any]) -> Mapping[str, Any]:
    """Return a validated hook tool-input object."""
    value = payload.get("tool_input", {})
    if not isinstance(value, dict):
        raise AssuranceError("INVALID_WIRE_VALUE: tool_input must be an object")
    return value


def _blocked(reason: str) -> HookDecision:
    """Build one fail-closed PreToolUse decision."""
    return HookDecision(exit_code=2, stderr=f"process assurance: {reason}\n")


def _replace_marker(text: str, prefix: str, value: Mapping[str, Any]) -> str:
    """Replace one marker line with its state-owner-canonicalized JSON object."""
    replacement = prefix + canonical_json(value).decode("utf-8")
    lines = [replacement if line.startswith(prefix) else line for line in text.splitlines()]
    return "\n".join(lines)


def _updated_input(
    payload: Mapping[str, Any], prompt: str, additional_context: str
) -> HookDecision:
    """Return a Claude PreToolUse input rewrite without changing permission policy."""
    tool_input = dict(_tool_input(payload))
    tool_input["prompt"] = prompt
    output = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "updatedInput": tool_input,
            "additionalContext": additional_context,
        }
    }
    return HookDecision(stdout=json.dumps(output, separators=(",", ":"), sort_keys=True))


def handle_dispatch(
    payload: Mapping[str, Any], state_root: Path, mode: str
) -> HookDecision:
    """Apply charter, audit-request, and protected-transition rules to Agent dispatch."""
    if mode == "OFF" or payload.get("tool_name") != "Agent":
        return HookDecision()
    try:
        session_id = _string(payload.get("session_id"), "session_id")
        prompt = _tool_input(payload).get("prompt", "")
        store = AssuranceStore(state_root, session_id, mode=mode)
        charter_value = _marker(prompt, "WORKFORCE_CHARTER: ")
        if charter_value is not None:
            store.initialize_charter(charter_value)
        elif not store.state_path.exists():
            return _blocked("active session has no versioned charter") if mode == "ENFORCE" else HookDecision()
        else:
            store.read_state()
        role = _role(payload)
        audit_request = _marker(prompt, "WORKFORCE_PROCESS_AUDIT_REQUEST: ")
        if audit_request is not None:
            if role != "reviewer":
                raise AssuranceError("ACTOR_UNAUTHORIZED: only reviewer process-audit port")
            audit_request = dict(audit_request)
            cwd = payload.get("cwd")
            if cwd:
                computed_manifest = workspace_manifest_sha256(_string(cwd, "cwd"))
                supplied_manifest = audit_request.get("evidence_manifest_sha256")
                if supplied_manifest is not None and supplied_manifest != computed_manifest:
                    raise AssuranceError("HASH_MISMATCH: supplied evidence manifest")
                audit_request["evidence_manifest_sha256"] = computed_manifest
            canonical_request = store.request_audit(audit_request)
            updated_prompt = _replace_marker(
                prompt, "WORKFORCE_PROCESS_AUDIT_REQUEST: ", canonical_request
            )
            return _updated_input(
                payload,
                updated_prompt,
                "Process-audit request was bound to the active charter and workspace manifest.",
            )
        if role == "builder":
            return _handle_builder_dispatch(store, payload, mode)
        return HookDecision()
    except (AssuranceError, OSError, json.JSONDecodeError) as error:
        return _blocked(str(error)) if mode == "ENFORCE" else HookDecision(stderr=f"process assurance shadow: {error}\n")


def _handle_builder_dispatch(
    store: AssuranceStore, payload: Mapping[str, Any], mode: str
) -> HookDecision:
    """Observe or enforce the Standard/Large pre-builder checkpoint."""
    prompt = _tool_input(payload).get("prompt", "")
    cwd = payload.get("cwd")
    state = store.read_state()
    charter = store._active_charter(state)
    if charter["tier"] not in {"standard", "large"} or "PRE_BUILDER" not in charter[
        "required_checkpoints"
    ]:
        return HookDecision()
    transition = _marker(prompt, "WORKFORCE_TRANSITION: ")
    receipt_marker = _marker(prompt, "WORKFORCE_TRANSITION_RECEIPT: ")
    assessments = [
        item
        for item in state["assessment_history"]
        if next(
            request
            for request in state["audit_requests"]
            if request["request_id"] == item["request_id"]
        )["checkpoint"]
        == "PRE_BUILDER"
    ]
    if mode == "SHADOW":
        status = assessments[-1]["verdict"] if assessments else "MISSING"
        store.record_checkpoint_observation("PRE_BUILDER", status)
        return HookDecision()
    if transition is None:
        return _blocked("PRE_BUILDER requires WORKFORCE_TRANSITION metadata and a current PASS")
    try:
        supplied_manifest = transition.get("evidence_manifest_sha256")
        current_manifest = (
            workspace_manifest_sha256(_string(cwd, "cwd")) if cwd else supplied_manifest
        )
        current_manifest = store._digest(current_manifest, "evidence_manifest_sha256")
        if supplied_manifest is not None and supplied_manifest != current_manifest:
            raise AssuranceError("ATTEMPT_MANIFEST_CHANGED: supplied manifest is not current")
        if receipt_marker is not None:
            dispatch_id = payload.get("tool_use_id")
            if dispatch_id is None:
                raise AssuranceError("AUTHORIZATION_REUSED: duplicate receipt lacks tool_use_id")
            store.validate_consumed_receipt(
                receipt_marker,
                _string(dispatch_id, "tool_use_id"),
                transition,
                current_manifest,
            )
            return HookDecision()
        latest_pass = assessments[-1] if assessments else None
        if latest_pass is not None:
            request_by_id = {item["request_id"]: item for item in state["audit_requests"]}
            audited_manifest = request_by_id[latest_pass["request_id"]][
                "evidence_manifest_sha256"
            ]
            if audited_manifest != current_manifest:
                raise AssuranceError("ATTEMPT_MANIFEST_CHANGED: workspace changed after audit")
        receipt = store.authorize_transition(
            _string(transition.get("checkpoint"), "checkpoint"),
            _string(transition.get("requested_transition"), "requested_transition"),
            current_manifest,
            str(payload["tool_use_id"]) if payload.get("tool_use_id") is not None else None,
        )
    except (AssuranceError, OSError) as error:
        return _blocked(str(error))
    canonical_transition = dict(transition)
    canonical_transition["evidence_manifest_sha256"] = current_manifest
    updated_prompt = _replace_marker(prompt, "WORKFORCE_TRANSITION: ", canonical_transition)
    updated_prompt += (
        "\nWORKFORCE_TRANSITION_RECEIPT: " + canonical_json(receipt).decode("utf-8")
    )
    return _updated_input(
        payload,
        updated_prompt,
        "Process-assurance authorization was consumed before builder dispatch.",
    )


def handle_subagent_stop(
    payload: Mapping[str, Any], state_root: Path, mode: str
) -> HookDecision:
    """Capture exactly one process-audit result from the independent reviewer sidechain."""
    if mode == "OFF" or str(payload.get("agent_type", "")).split(":", 1)[-1] != "reviewer":
        return HookDecision()
    checkpoint_for_failure: str | None = None
    try:
        session_id = _string(payload.get("session_id"), "session_id")
        store = AssuranceStore(state_root, session_id, mode=mode)
        if not store.state_path.exists():
            return HookDecision()
        state = store.read_state()
        open_requests = [item for item in state["audit_requests"] if item["status"] == "REQUESTED"]
        if not open_requests:
            return HookDecision()
        result = _marker(
            payload.get("last_assistant_message", ""),
            "WORKFORCE_PROCESS_AUDIT_RESULT: ",
        )
        if result is None:
            raise AssuranceError("AUDITOR_UNAVAILABLE: result marker missing")
        request_hash = result.get("request_sha256")
        matches = [
            item for item in open_requests if item["request_sha256"] == request_hash
        ]
        if len(matches) != 1:
            raise AssuranceError("HASH_MISMATCH: result does not identify one open request")
        checkpoint_for_failure = matches[0]["checkpoint"]
        store.record_assessment(matches[0]["request_id"], result)
        return HookDecision()
    except (AssuranceError, OSError, json.JSONDecodeError) as error:
        if mode == "SHADOW":
            try:
                if checkpoint_for_failure is None and len(open_requests) == 1:
                    checkpoint_for_failure = open_requests[0]["checkpoint"]
                if checkpoint_for_failure is not None:
                    store.record_checkpoint_observation(
                        checkpoint_for_failure, "AUDIT_FAILURE"
                    )
            except (AssuranceError, OSError, UnboundLocalError):
                pass
            return HookDecision(stderr=f"process assurance shadow: {error}\n")
        return _blocked(str(error))


def _checkpoint_status(state: Mapping[str, Any], checkpoint: str) -> str:
    """Return the latest admitted verdict for one checkpoint or MISSING."""
    request_by_id = {item["request_id"]: item for item in state["audit_requests"]}
    assessments = [
        item
        for item in state["assessment_history"]
        if request_by_id[item["request_id"]]["checkpoint"] == checkpoint
    ]
    return assessments[-1]["verdict"] if assessments else "MISSING"


def _stop_block(reason: str) -> HookDecision:
    """Build the structured decision expected by Claude Stop hooks."""
    return HookDecision(
        stdout=json.dumps(
            {"decision": "block", "reason": f"process assurance: {reason}"},
            separators=(",", ":"),
            sort_keys=True,
        )
    )


def handle_stop(payload: Mapping[str, Any], state_root: Path, mode: str) -> HookDecision:
    """Reject falsely clean closeout while leaving shadow outcomes workflow-nonblocking."""
    if mode == "OFF":
        return HookDecision()
    try:
        session_id = _string(payload.get("session_id"), "session_id")
        store = AssuranceStore(state_root, session_id, mode=mode)
        if not store.state_path.exists():
            return HookDecision()
        state = store.read_state()
        charter = store._active_charter(state)
        if charter["tier"] not in {"standard", "large"} or "PRE_CLOSEOUT" not in charter[
            "required_checkpoints"
        ]:
            return HookDecision()
        status = _checkpoint_status(state, "PRE_CLOSEOUT")
        store.record_checkpoint_observation("PRE_CLOSEOUT", status)
        if status == "PASS":
            return HookDecision()
        disclosure = _marker(
            payload.get("last_assistant_message", ""),
            "WORKFORCE_PROCESS_ASSURANCE_CLOSEOUT: ",
        )
        expected = {
            "checkpoint": "PRE_CLOSEOUT",
            "status": status,
            "charter_sha256": charter["charter_sha256"],
        }
        if disclosure != expected:
            return _stop_block(
                f"PRE_CLOSEOUT is {status}; disclose the exact checkpoint status and charter"
            )
        return HookDecision()
    except (AssuranceError, OSError, json.JSONDecodeError) as error:
        return _stop_block(str(error))
