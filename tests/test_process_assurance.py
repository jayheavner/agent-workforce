"""Verify process assurance behavior through its durable store seam."""

from __future__ import annotations

import tempfile
import unittest
import subprocess
import os
from pathlib import Path
from unittest import mock

from hooks.process_assurance import (
    AssuranceError,
    AssuranceStore,
    _git_output,
    _untracked_hashes,
    handle_dispatch,
    handle_stop,
    handle_subagent_stop,
    sha256,
    workspace_manifest_sha256,
)


class ProcessAssuranceTests(unittest.TestCase):
    """Exercise the public state-store contract with isolated state roots."""

    def test_initialize_charter_persists_versioned_fixed_reference(self) -> None:
        """A new task receives one immutable, hashed version-one charter."""
        with tempfile.TemporaryDirectory() as directory:
            store = AssuranceStore(Path(directory), "session-1")
            charter = store.initialize_charter(
                {
                    "task_id": "task-1",
                    "version": 1,
                    "tier": "standard",
                    "objective": "Deliver the process assurance pilot",
                    "delivery_target": "integrated code",
                    "scope": ["hooks", "skills", "tests"],
                    "non_goals": ["production promotion"],
                    "acceptance_criteria": ["phase drift is detected"],
                    "required_checkpoints": ["PRE_BUILDER", "PRE_CLOSEOUT"],
                    "approved_by": "requester",
                    "approval_ref": "user-message-1",
                }
            )

            self.assertEqual(charter["schema"], "intent-charter/1")
            self.assertEqual(charter["version"], 1)
            self.assertRegex(charter["charter_sha256"], r"^[0-9a-f]{64}$")
            state = store.read_state()
            self.assertEqual(state["active_charter_sha256"], charter["charter_sha256"])
            self.assertEqual(state["charter_history"], [charter])

    def test_pass_assessment_creates_one_exact_transition_authorization(self) -> None:
        """A complete clean audit authorizes its bound transition exactly once."""
        with tempfile.TemporaryDirectory() as directory:
            store = self._initialized_store(directory)
            request = store.request_audit(
                {
                    "request_id": "audit-1",
                    "checkpoint": "PRE_BUILDER",
                    "requested_transition": "START_BUILDER",
                    "submission_kind": "INITIAL",
                    "target_lineage_ids": [],
                    "evidence_manifest_sha256": "a" * 64,
                    "evidence_refs": ["repo:HEAD", "plan:approved"],
                }
            )
            rules = [
                {
                    "rule_id": rule_id,
                    "result": "SATISFIED",
                    "rationale": f"{rule_id} remains satisfied by direct evidence",
                    "evidence_refs": ["repo:HEAD"],
                }
                for rule_id in AssuranceStore.RULE_IDS
            ]
            assessment = store.record_assessment(
                "audit-1",
                {
                    "assessment_id": "assessment-1",
                    "request_sha256": request["request_sha256"],
                    "verdict": "PASS",
                    "rule_evaluations": rules,
                    "findings": [],
                    "auditor_identity": "reviewer-sidechain-1",
                },
            )

            self.assertEqual(assessment["verdict"], "PASS")
            receipt = store.authorize_transition(
                "PRE_BUILDER", "START_BUILDER", "a" * 64
            )
            self.assertEqual(receipt["authorization_state"], "CONSUMED")
            consumed = store.read_state()["authorization_history"][0]
            consumed_body = dict(consumed)
            consumed_digest = consumed_body.pop("authorization_sha256")
            self.assertEqual(consumed_digest, sha256(consumed_body))
            with self.assertRaisesRegex(ValueError, "AUTHORIZATION_REUSED"):
                store.authorize_transition("PRE_BUILDER", "START_BUILDER", "a" * 64)

    def test_same_finding_escalates_after_two_failed_remediations(self) -> None:
        """Correction is bounded: the third continuing submission needs a human decision."""
        with tempfile.TemporaryDirectory() as directory:
            store = self._initialized_store(directory)
            self._submit_finding(store, "initial", "INITIAL", [], "REMEDIATE")
            self._submit_finding(store, "repair-1", "REMEDIATION", ["lineage-a"], "REMEDIATE")
            self._submit_finding(store, "repair-2", "REMEDIATION", ["lineage-a"], "REMEDIATE")

            request = store.request_audit(
                self._request("repair-3", "REMEDIATION", ["lineage-a"])
            )
            weak = self._assessment(request, "repair-3", "REMEDIATE")
            with self.assertRaisesRegex(ValueError, "exhausted remediation"):
                store.record_assessment("repair-3", weak)

            escalated = self._assessment(request, "repair-3", "HUMAN_DECISION")
            result = store.record_assessment("repair-3", escalated)
            self.assertEqual(result["verdict"], "HUMAN_DECISION")
            lineage = store.read_state()["finding_lineages"]["lineage-a"]
            self.assertEqual(lineage["remediation_count"], 3)
            self.assertEqual(lineage["state"], "ESCALATED")

    def test_finding_identity_cannot_reset_lineage_and_omitted_target_resolves(self) -> None:
        """Rewording cannot reset a finding; corrected targets resolve in mixed assessments."""
        with tempfile.TemporaryDirectory() as directory:
            store = self._initialized_store(directory)
            self._submit_finding(store, "identity-initial", "INITIAL", [], "REMEDIATE")
            reset_request = store.request_audit(
                self._request("identity-reset", "REMEDIATION", ["lineage-a"])
            )
            reset = self._assessment(reset_request, "identity-reset", "REMEDIATE")
            reset_findings = reset["findings"]
            assert isinstance(reset_findings, list)
            assert isinstance(reset_findings[0], dict)
            reset_findings[0]["lineage_id"] = "lineage-reset"
            with self.assertRaisesRegex(ValueError, "lineage reset"):
                store.record_assessment("identity-reset", reset)

            mixed = self._assessment(reset_request, "identity-mixed", "REMEDIATE")
            mixed["assessment_id"] = "assessment-identity-mixed"
            mixed_findings = mixed["findings"]
            assert isinstance(mixed_findings, list)
            assert isinstance(mixed_findings[0], dict)
            mixed_findings[0].update(
                {
                    "finding_id": "finding-route",
                    "lineage_id": "lineage-route",
                    "rule_id": "CHK-03-ROUTE",
                    "affected_element": "route-selection",
                    "summary": "The corrected outcome now exposes a route mismatch",
                    "required_correction": "Restore the approved route",
                }
            )
            mixed["rule_evaluations"] = self._rules_with_violation("CHK-03-ROUTE")
            store.record_assessment("identity-reset", mixed)
            lineages = store.read_state()["finding_lineages"]
            self.assertEqual(lineages["lineage-a"]["state"], "RESOLVED")
            self.assertEqual(lineages["lineage-route"]["state"], "REMEDIATING")

    def test_retroactive_amendment_is_separate_prospective_history(self) -> None:
        """A human-approved retroactive proposal cannot rewrite earlier compliance history."""
        with tempfile.TemporaryDirectory() as directory:
            store = self._initialized_store(directory)
            request = store.request_audit(self._request("clean", "INITIAL", []))
            clean = {
                "assessment_id": "assessment-clean",
                "request_sha256": request["request_sha256"],
                "verdict": "PASS",
                "rule_evaluations": self._rules(),
                "findings": [],
                "auditor_identity": "reviewer-sidechain-1",
            }
            store.record_assessment("clean", clean)
            proposal = store.propose_amendment(
                {
                    "proposal_id": "amendment-1",
                    "origin": "ORCHESTRATOR_PROPOSAL",
                    "work_already_occurred": True,
                    "rationale": "New evidence requires one additional scope path",
                    "proposed_changes": {"scope": ["hooks", "skills", "tests", "runbooks"]},
                    "proposer_identity": "orchestrator",
                }
            )
            store.assess_amendment(
                "amendment-1",
                {
                    "assessment_id": "amendment-assessment-1",
                    "proposal_sha256": proposal["proposal_sha256"],
                    "verdict": "HUMAN_DECISION",
                    "rationale": "Work preceded approval, so the change can only apply prospectively",
                    "evidence_refs": ["git:work-before-amendment"],
                    "auditor_identity": "reviewer-sidechain-2",
                },
            )
            charter = store.decide_amendment(
                "amendment-1",
                {
                    "decision": "APPROVE",
                    "decided_by": "requester",
                    "approval_ref": "user-message-2",
                    "effective_prospectively": True,
                },
            )

            state = store.read_state()
            self.assertEqual(charter["version"], 2)
            self.assertEqual(len(state["charter_history"]), 2)
            self.assertEqual(state["charter_history"][0]["version"], 1)
            self.assertTrue(state["amendment_history"][0]["work_already_occurred"])
            self.assertTrue(
                all(item["state"] == "INVALIDATED" for item in state["authorization_history"])
            )
            self.assertEqual(state["metrics"]["retroactive_amendments"], 1)

    def test_dispatch_hook_enforces_audited_builder_transition(self) -> None:
        """The deterministic hook blocks builder dispatch until an exact PASS is recorded."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            session = "session-hook"
            charter = self._charter()
            architect = self._dispatch_payload(
                session,
                "architect",
                f"Design the task.\nWORKFORCE_CHARTER: {self._json(charter)}",
            )
            self.assertEqual(handle_dispatch(architect, root, "ENFORCE").exit_code, 0)

            premature = self._dispatch_payload(session, "builder", "Build the approved plan.")
            denied = handle_dispatch(premature, root, "ENFORCE")
            self.assertEqual(denied.exit_code, 2)
            self.assertIn("PRE_BUILDER", denied.stderr)

            request_value = self._request("hook-audit", "INITIAL", [])
            audit_prompt = (
                "Process-audit mode.\nWORKFORCE_PROCESS_AUDIT_REQUEST: "
                + self._json(request_value)
            )
            audit_dispatch = self._dispatch_payload(session, "reviewer", audit_prompt)
            self.assertEqual(handle_dispatch(audit_dispatch, root, "ENFORCE").exit_code, 0)
            request = AssuranceStore(root, session).read_state()["audit_requests"][0]
            result = {
                "assessment_id": "hook-assessment",
                "request_sha256": request["request_sha256"],
                "verdict": "PASS",
                "rule_evaluations": self._rules(),
                "findings": [],
                "auditor_identity": "reviewer-sidechain-hook",
            }
            stop = {
                "session_id": session,
                "agent_type": "reviewer",
                "last_assistant_message": (
                    "Audit complete.\nWORKFORCE_PROCESS_AUDIT_RESULT: " + self._json(result)
                ),
            }
            self.assertEqual(handle_subagent_stop(stop, root, "ENFORCE").exit_code, 0)

            transition = {
                "checkpoint": "PRE_BUILDER",
                "requested_transition": "START_BUILDER",
                "evidence_manifest_sha256": request["evidence_manifest_sha256"],
            }
            builder = self._dispatch_payload(
                session,
                "builder",
                "Build.\nWORKFORCE_TRANSITION: " + self._json(transition),
            )
            self.assertEqual(handle_dispatch(builder, root, "ENFORCE").exit_code, 0)
            self.assertEqual(handle_dispatch(builder, root, "ENFORCE").exit_code, 2)

    def test_shadow_hook_records_missing_checkpoint_without_blocking(self) -> None:
        """Shadow mode observes a missing audit but never blocks the builder."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            session = "session-shadow"
            charter = self._charter()
            architect = self._dispatch_payload(
                session,
                "architect",
                "Design.\nWORKFORCE_CHARTER: " + self._json(charter),
            )
            self.assertEqual(handle_dispatch(architect, root, "SHADOW").exit_code, 0)
            builder = self._dispatch_payload(session, "builder", "Build without an audit.")
            self.assertEqual(handle_dispatch(builder, root, "SHADOW").exit_code, 0)
            state = AssuranceStore(root, session, mode="SHADOW").read_state()
            self.assertEqual(state["metrics"]["missing_checkpoints"], 1)
            self.assertEqual(state["checkpoint_observations"][0]["status"], "MISSING")

    def test_event_tampering_fails_closed(self) -> None:
        """A changed event breaks the durable hash chain before state can be trusted."""
        with tempfile.TemporaryDirectory() as directory:
            store = self._initialized_store(directory)
            event_path = next(store.events_directory.glob("*.json"))
            event = __import__("json").loads(event_path.read_text(encoding="utf-8"))
            event["payload"]["objective"] = "tampered objective"
            event_path.write_text(self._json(event), encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "STATE_CORRUPT"):
                store.read_state()

    def test_closeout_requires_honest_disclosure_of_shadow_gap(self) -> None:
        """A missing closeout audit cannot be presented as a clean process result."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            session = "session-closeout"
            store = AssuranceStore(root, session, mode="SHADOW")
            charter = store.initialize_charter(self._charter())
            blocked = handle_stop(
                {"session_id": session, "last_assistant_message": "Work complete."},
                root,
                "SHADOW",
            )
            self.assertIn('"decision":"block"', blocked.stdout)

            disclosure = {
                "checkpoint": "PRE_CLOSEOUT",
                "status": "MISSING",
                "charter_sha256": charter["charter_sha256"],
            }
            allowed = handle_stop(
                {
                    "session_id": session,
                    "last_assistant_message": (
                        "Work complete.\nWORKFORCE_PROCESS_ASSURANCE_CLOSEOUT: "
                        + self._json(disclosure)
                    ),
                },
                root,
                "SHADOW",
            )
            self.assertEqual(allowed.stdout, "")
            self.assertEqual(store.read_state()["metrics"]["missing_checkpoints"], 1)

    def test_invalid_contract_values_fail_before_state_change(self) -> None:
        """Malformed identities, charters, requests, and modes cannot enter history."""
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "assurance mode"):
                AssuranceStore(Path(directory), "session", mode="WARN")
            changes: tuple[dict[str, object], ...] = (
                {"tier": "unknown"},
                {"scope": []},
                {"scope": ["hooks", "hooks"]},
                {"objective": ""},
            )
            for index, change in enumerate(changes):
                value = self._charter() | change
                with self.assertRaises(ValueError):
                    AssuranceStore(Path(directory), f"bad-{index}").initialize_charter(value)
            store = AssuranceStore(Path(directory), "valid")
            original = store.initialize_charter(self._charter())
            self.assertEqual(store.initialize_charter(self._charter()), original)
            with self.assertRaisesRegex(ValueError, "already initialized"):
                store.initialize_charter(self._charter() | {"objective": "Changed objective"})
            bad = self._request("bad-digest", "INITIAL", [])
            bad["evidence_manifest_sha256"] = "not-a-digest"
            with self.assertRaisesRegex(ValueError, "evidence_manifest"):
                store.request_audit(bad)
            bad = self._request("bad-checkpoint", "INITIAL", [])
            bad["checkpoint"] = "PRE_DEPLOY"
            with self.assertRaisesRegex(ValueError, "not required"):
                store.request_audit(bad)
            with self.assertRaisesRegex(ValueError, "submission_kind"):
                store.request_audit(self._request("bad-target", "INITIAL", ["lineage-x"]))
            with self.assertRaisesRegex(ValueError, "requires targets"):
                store.request_audit(self._request("bad-remediation", "REMEDIATION", []))
            with self.assertRaisesRegex(ValueError, "proposed_changes"):
                store.propose_amendment(
                    {
                        "proposal_id": "bad-amendment",
                        "origin": "NEWLY_DISCOVERED_FACT",
                        "work_already_occurred": False,
                        "rationale": "Malformed proposed scope",
                        "proposed_changes": {"scope": "not-a-list"},
                        "proposer_identity": "orchestrator",
                    }
                )

    def test_malformed_assessment_cannot_mint_authorization(self) -> None:
        """Hash, checklist, finding, and aggregate failures all leave the request open."""
        with tempfile.TemporaryDirectory() as directory:
            store = self._initialized_store(directory)
            request = store.request_audit(self._request("strict", "INITIAL", []))
            base = {
                "assessment_id": "strict-assessment",
                "request_sha256": request["request_sha256"],
                "verdict": "PASS",
                "rule_evaluations": self._rules(),
                "findings": [],
                "auditor_identity": "reviewer-strict",
            }
            variants = (
                base | {"request_sha256": "0" * 64},
                base | {"rule_evaluations": []},
                base | {"rule_evaluations": [dict(self._rules()[0], result="UNKNOWN")] + self._rules()[1:]},
                base | {"findings": "not-a-list"},
                base | {"findings": ["not-an-object"], "verdict": "REMEDIATE"},
                base | {"verdict": "REMEDIATE"},
            )
            for variant in variants:
                with self.assertRaises(ValueError):
                    store.record_assessment("strict", variant)
            inconsistent = self._assessment(request, "inconsistent-rules", "REMEDIATE")
            inconsistent["rule_evaluations"] = self._rules()
            with self.assertRaisesRegex(ValueError, "rule/finding consistency"):
                store.record_assessment("strict", inconsistent)
            store.record_assessment("strict", base)
            with self.assertRaisesRegex(ValueError, "request not open"):
                store.record_assessment("strict", base | {"assessment_id": "second"})

    def test_amendment_rejection_preserves_charter_and_role_separation(self) -> None:
        """Proposal, audit, and decision actors remain separate on rejected changes."""
        with tempfile.TemporaryDirectory() as directory:
            store = self._initialized_store(directory)
            proposal = store.propose_amendment(
                {
                    "proposal_id": "reject-1",
                    "origin": "NEWLY_DISCOVERED_FACT",
                    "work_already_occurred": False,
                    "rationale": "A new fact suggested a change",
                    "proposed_changes": {"non_goals": ["production", "deployment"]},
                    "proposer_identity": "orchestrator",
                }
            )
            assessment = {
                "assessment_id": "reject-audit",
                "proposal_sha256": proposal["proposal_sha256"],
                "verdict": "PASS",
                "rationale": "The prospective proposal is coherent",
                "evidence_refs": ["fact:new"],
                "auditor_identity": "orchestrator",
            }
            with self.assertRaisesRegex(ValueError, "proposer cannot audit"):
                store.assess_amendment("reject-1", assessment)
            assessment["auditor_identity"] = "reviewer"
            store.assess_amendment("reject-1", assessment)
            with self.assertRaisesRegex(ValueError, "roles must be separate"):
                store.decide_amendment(
                    "reject-1",
                    {
                        "decision": "REJECT",
                        "decided_by": "reviewer",
                        "approval_ref": "reviewer-self",
                        "effective_prospectively": True,
                    },
                )
            charter = store.decide_amendment(
                "reject-1",
                {
                    "decision": "REJECT",
                    "decided_by": "requester",
                    "approval_ref": "user-rejection",
                    "effective_prospectively": True,
                },
            )
            self.assertEqual(charter["version"], 1)
            self.assertEqual(store.read_state()["amendment_history"][0]["status"], "REJECTED")

    def test_hook_failure_paths_are_fail_closed_or_visible_in_shadow(self) -> None:
        """Malformed markers block enforcement and become visible audit failures in shadow."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertEqual(handle_dispatch({"tool_name": "Read"}, root, "ENFORCE").exit_code, 0)
            no_charter = self._dispatch_payload("shadow-empty", "architect", "Design")
            self.assertEqual(handle_dispatch(no_charter, root, "SHADOW").exit_code, 0)

            session = "hook-failures"
            charter = self._dispatch_payload(
                session,
                "architect",
                "WORKFORCE_CHARTER: " + self._json(self._charter()),
            )
            self.assertEqual(handle_dispatch(charter, root, "SHADOW").exit_code, 0)
            malformed = self._dispatch_payload(
                session, "reviewer", "WORKFORCE_PROCESS_AUDIT_REQUEST: {"
            )
            self.assertIn("malformed", handle_dispatch(malformed, root, "SHADOW").stderr)
            unauthorized = self._dispatch_payload(
                session,
                "architect",
                "WORKFORCE_PROCESS_AUDIT_REQUEST: "
                + self._json(self._request("unauthorized", "INITIAL", [])),
            )
            self.assertIn("only reviewer", handle_dispatch(unauthorized, root, "SHADOW").stderr)

            request = self._dispatch_payload(
                session,
                "reviewer",
                "WORKFORCE_PROCESS_AUDIT_REQUEST: "
                + self._json(self._request("missing-result", "INITIAL", [])),
            )
            self.assertEqual(handle_dispatch(request, root, "SHADOW").exit_code, 0)
            failure = handle_subagent_stop(
                {
                    "session_id": session,
                    "agent_type": "reviewer",
                    "last_assistant_message": "No marker",
                },
                root,
                "SHADOW",
            )
            self.assertIn("AUDITOR_UNAVAILABLE", failure.stderr)
            state = AssuranceStore(root, session, mode="SHADOW").read_state()
            self.assertEqual(state["metrics"]["audit_failures"], 1)
            self.assertEqual(handle_subagent_stop({"agent_type": "builder"}, root, "SHADOW").exit_code, 0)
            self.assertEqual(handle_stop({}, root, "OFF").exit_code, 0)

            malformed_input = {
                "session_id": "malformed-tool-input",
                "tool_name": "Agent",
                "tool_input": "not-an-object",
            }
            self.assertEqual(handle_dispatch(malformed_input, root, "ENFORCE").exit_code, 2)
            self.assertIn(
                "tool_input",
                handle_dispatch(malformed_input, root, "SHADOW").stderr,
            )

            promoted_session = "unapproved-mode-change"
            AssuranceStore(root, promoted_session, mode="SHADOW").initialize_charter(
                self._charter()
            )
            changed_mode = self._dispatch_payload(
                promoted_session, "architect", "Continue the existing route."
            )
            denied_mode_change = handle_dispatch(changed_mode, root, "ENFORCE")
            self.assertEqual(denied_mode_change.exit_code, 2)
            self.assertIn("FEATURE_STATE_MISMATCH", denied_mode_change.stderr)

    def test_effectiveness_outcomes_are_independently_evidenced(self) -> None:
        """Longitudinal control outcomes are durable evidence, not self-reported counters."""
        with tempfile.TemporaryDirectory() as directory:
            store = self._initialized_store(directory)
            for index, outcome in enumerate(
                ("FALSE_BLOCK", "HUMAN_OVERRIDE", "ESCAPED_VIOLATION")
            ):
                store.record_effectiveness_outcome(
                    {
                        "outcome_id": f"outcome-{index}",
                        "outcome_type": outcome,
                        "checkpoint": "PRE_BUILDER",
                        "evidence_refs": [f"adjudication:{index}"],
                        "adjudicator_identity": "independent-verifier",
                    }
                )
            report = store.metrics_report()
            self.assertEqual(report["false_blocks"], 1)
            self.assertEqual(report["human_overrides"], 1)
            self.assertEqual(report["escaped_violations"], 1)
            self.assertEqual(len(report["effectiveness_outcomes"]), 3)

    def test_hook_owns_workspace_freshness_and_request_correlation(self) -> None:
        """The adapter derives evidence hashes and blocks work changed after audit."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            state_root = root / "state"
            repo.mkdir()
            self._git(repo, "init", "-q")
            self._git(repo, "config", "user.email", "test@example.com")
            self._git(repo, "config", "user.name", "Process Test")
            (repo / "work.txt").write_text("before\n", encoding="utf-8")
            self._git(repo, "add", "work.txt")
            self._git(repo, "commit", "-qm", "initial")

            session = "freshness-session"
            charter_payload = self._dispatch_payload(
                session,
                "architect",
                "WORKFORCE_CHARTER: " + self._json(self._charter()),
            )
            charter_payload["cwd"] = str(repo)
            self.assertEqual(handle_dispatch(charter_payload, state_root, "ENFORCE").exit_code, 0)
            request_value = self._request("freshness-audit", "INITIAL", [])
            request_value.pop("evidence_manifest_sha256")
            audit = self._dispatch_payload(
                session,
                "reviewer",
                "WORKFORCE_PROCESS_AUDIT_REQUEST: " + self._json(request_value),
            )
            audit["cwd"] = str(repo)
            audit_decision = handle_dispatch(audit, state_root, "ENFORCE")
            self.assertEqual(audit_decision.exit_code, 0)
            updated_prompt = __import__("json").loads(audit_decision.stdout)[
                "hookSpecificOutput"
            ]["updatedInput"]["prompt"]
            normalized_request = __import__("json").loads(
                next(
                    line.removeprefix("WORKFORCE_PROCESS_AUDIT_REQUEST: ")
                    for line in updated_prompt.splitlines()
                    if line.startswith("WORKFORCE_PROCESS_AUDIT_REQUEST: ")
                )
            )
            self.assertEqual(normalized_request["active_charter"]["task_id"], "task-hook")
            request = AssuranceStore(state_root, session).read_state()["audit_requests"][0]
            result = {
                "assessment_id": "freshness-assessment",
                "request_sha256": normalized_request["request_sha256"],
                "verdict": "PASS",
                "rule_evaluations": self._rules(),
                "findings": [],
                "auditor_identity": "fresh-reviewer",
            }
            stop = {
                "session_id": session,
                "agent_type": "reviewer",
                "last_assistant_message": "WORKFORCE_PROCESS_AUDIT_RESULT: " + self._json(result),
            }
            self.assertEqual(handle_subagent_stop(stop, state_root, "ENFORCE").exit_code, 0)

            (repo / "work.txt").write_text("after\n", encoding="utf-8")
            transition = {
                "checkpoint": "PRE_BUILDER",
                "requested_transition": "START_BUILDER",
            }
            builder = self._dispatch_payload(
                session,
                "builder",
                "WORKFORCE_TRANSITION: " + self._json(transition),
            )
            builder["cwd"] = str(repo)
            denied = handle_dispatch(builder, state_root, "ENFORCE")
            self.assertEqual(denied.exit_code, 2)
            self.assertIn("ATTEMPT_MANIFEST_CHANGED", denied.stderr)
            self.assertNotEqual(
                request["evidence_manifest_sha256"],
                transition.get("evidence_manifest_sha256"),
            )

    def test_new_audit_invalidates_prior_unconsumed_authorization(self) -> None:
        """A stale PASS cannot authorize work while a newer audit is pending or non-clean."""
        with tempfile.TemporaryDirectory() as directory:
            store = self._initialized_store(directory)
            first = store.request_audit(self._request("first", "INITIAL", []))
            store.record_assessment(
                "first",
                {
                    "assessment_id": "assessment-first",
                    "request_sha256": first["request_sha256"],
                    "verdict": "PASS",
                    "rule_evaluations": self._rules(),
                    "findings": [],
                    "auditor_identity": "reviewer-first",
                },
            )
            second_value = self._request("second", "INITIAL", [])
            second_value["evidence_manifest_sha256"] = first[
                "evidence_manifest_sha256"
            ]
            store.request_audit(second_value)

            with self.assertRaisesRegex(ValueError, "no current PASS authorization"):
                store.authorize_transition(
                    "PRE_BUILDER",
                    "START_BUILDER",
                    first["evidence_manifest_sha256"],
                )
            states = [item["state"] for item in store.read_state()["authorization_history"]]
            self.assertEqual(states, ["INVALIDATED"])
            invalidated = store.read_state()["authorization_history"][0]
            invalidated_body = dict(invalidated)
            invalidated_digest = invalidated_body.pop("authorization_sha256")
            self.assertEqual(invalidated_digest, sha256(invalidated_body))

    def test_interrupted_commit_recovers_after_event_is_durable(self) -> None:
        """A crash after event persistence recovers the matching pending snapshot."""
        import hooks.process_assurance as process_assurance

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = AssuranceStore(root, "recoverable")
            original_write = process_assurance._write_atomic

            def interrupted_write(path: Path, value: object) -> None:
                original_write(path, value)
                if path.parent == store.events_directory:
                    raise OSError("simulated crash after durable event")

            with mock.patch.object(
                process_assurance, "_write_atomic", side_effect=interrupted_write
            ):
                with self.assertRaisesRegex(OSError, "simulated crash"):
                    store.initialize_charter(self._charter())

            recovered = AssuranceStore(root, "recoverable").read_state()
            self.assertEqual(recovered["sequence"], 1)
            self.assertEqual(recovered["charter_history"][0]["task_id"], "task-hook")
            self.assertFalse(store.pending_path.exists())

    def test_event_capacity_fails_before_creating_an_unreadable_sequence(self) -> None:
        """The configured event ceiling rejects a write instead of corrupting the next read."""
        with tempfile.TemporaryDirectory() as directory:
            store = AssuranceStore(Path(directory), "capacity")
            state = store._read_unlocked()
            state["sequence"] = store.MAX_EVENTS
            with self.assertRaisesRegex(AssuranceError, "event capacity"):
                store._commit(state, "capacity.test", {"bounded": True})
            self.assertEqual(list(store.events_directory.glob("*.json")), [])

    def test_manifest_rejects_untracked_special_file_without_opening_it(self) -> None:
        """Manifest collection never blocks on or follows an untracked special file."""
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            self._git(repo, "init", "-q")
            self._git(repo, "config", "user.email", "test@example.com")
            self._git(repo, "config", "user.name", "Process Test")
            (repo / "tracked.txt").write_text("tracked\n", encoding="utf-8")
            self._git(repo, "add", "tracked.txt")
            self._git(repo, "commit", "-qm", "initial")
            os.mkfifo(repo / "untracked-pipe")

            with mock.patch.object(
                Path,
                "read_bytes",
                side_effect=AssertionError("special file must not be read"),
            ):
                with self.assertRaisesRegex(AssuranceError, "unsupported untracked file"):
                    _untracked_hashes(repo, b"untracked-pipe\0")
            with self.assertRaisesRegex(AssuranceError, "PATH_ESCAPE"):
                _untracked_hashes(repo, b"../outside\0")
            with self.assertRaisesRegex(AssuranceError, "untracked file unavailable"):
                _untracked_hashes(repo, b"missing\0")

            oversized = repo / "oversized"
            with oversized.open("wb") as handle:
                handle.seek(25 * 1024 * 1024)
                handle.write(b"x")
            with self.assertRaisesRegex(AssuranceError, "untracked file exceeds limit"):
                _untracked_hashes(repo, b"oversized\0")

    def test_manifest_binds_untracked_regular_files_and_symlink_targets(self) -> None:
        """Untracked content and symlink-target changes alter the protected workspace frontier."""
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            self._git(repo, "init", "-q")
            self._git(repo, "config", "user.email", "test@example.com")
            self._git(repo, "config", "user.name", "Process Test")
            (repo / "tracked.txt").write_text("tracked\n", encoding="utf-8")
            self._git(repo, "add", "tracked.txt")
            self._git(repo, "commit", "-qm", "initial")

            (repo / "untracked.txt").write_text("first\n", encoding="utf-8")
            first = workspace_manifest_sha256(str(repo))
            (repo / "untracked.txt").write_text("second\n", encoding="utf-8")
            second = workspace_manifest_sha256(str(repo))
            os.symlink("tracked.txt", repo / "untracked-link")
            third = workspace_manifest_sha256(str(repo))
            (repo / "untracked-link").unlink()
            os.symlink("untracked.txt", repo / "untracked-link")
            fourth = workspace_manifest_sha256(str(repo))

            self.assertEqual(len({first, second, third, fourth}), 4)

    def test_git_evidence_timeout_is_a_typed_manifest_failure(self) -> None:
        """A stalled Git evidence command fails closed through the assurance contract."""
        with mock.patch(
            "hooks.process_assurance.subprocess.run",
            side_effect=subprocess.TimeoutExpired(["git"], timeout=10),
        ):
            with self.assertRaisesRegex(AssuranceError, "Git evidence timed out"):
                _git_output(Path("."), "status")
        with mock.patch(
            "hooks.process_assurance.subprocess.run",
            side_effect=OSError("git missing"),
        ):
            with self.assertRaisesRegex(AssuranceError, "Git executable unavailable"):
                _git_output(Path("."), "status")
        with self.assertRaisesRegex(AssuranceError, "Git evidence unavailable"):
            _git_output(Path("."), "definitely-not-a-git-subcommand")

    def test_amendment_audit_can_require_correction_before_human_decision(self) -> None:
        """An auditor may reject an amendment package without changing the active charter."""
        with tempfile.TemporaryDirectory() as directory:
            store = self._initialized_store(directory)
            proposal = store.propose_amendment(
                {
                    "proposal_id": "needs-repair",
                    "origin": "ORCHESTRATOR_PROPOSAL",
                    "work_already_occurred": False,
                    "rationale": "The route may need broader scope",
                    "proposed_changes": {"scope": ["hooks", "skills", "tests", "ops"]},
                    "proposer_identity": "orchestrator",
                }
            )
            assessment = store.assess_amendment(
                "needs-repair",
                {
                    "assessment_id": "repair-assessment",
                    "proposal_sha256": proposal["proposal_sha256"],
                    "verdict": "REMEDIATE",
                    "rationale": "The proposal lacks evidence for the added operations scope",
                    "evidence_refs": ["charter:scope", "repo:no-ops-evidence"],
                    "auditor_identity": "reviewer",
                },
            )

            self.assertEqual(assessment["verdict"], "REMEDIATE")
            state = store.read_state()
            self.assertEqual(state["amendment_history"][0]["status"], "REMEDIATION_REQUIRED")
            self.assertEqual(state["active_charter_sha256"], state["charter_history"][0]["charter_sha256"])
            with self.assertRaisesRegex(ValueError, "amendment lifecycle"):
                store.decide_amendment(
                    "needs-repair",
                    {
                        "decision": "APPROVE",
                        "decided_by": "requester",
                        "approval_ref": "user-message",
                        "effective_prospectively": True,
                    },
                )

    def test_concurrent_checkpoint_results_correlate_by_request_hash(self) -> None:
        """Reviewer completion admits the matching request even when two checkpoints are open."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = self._initialized_store(directory)
            first = store.request_audit(self._request("parallel-builder", "INITIAL", []))
            closeout_value = self._request("parallel-closeout", "INITIAL", [])
            closeout_value["checkpoint"] = "PRE_CLOSEOUT"
            closeout_value["requested_transition"] = "START_CLOSEOUT"
            second = store.request_audit(closeout_value)
            result = {
                "assessment_id": "assessment-closeout",
                "request_sha256": second["request_sha256"],
                "verdict": "PASS",
                "rule_evaluations": self._rules(),
                "findings": [],
                "auditor_identity": "reviewer-closeout",
            }
            decision = handle_subagent_stop(
                {
                    "session_id": "session-1",
                    "agent_type": "reviewer",
                    "last_assistant_message": (
                        "WORKFORCE_PROCESS_AUDIT_RESULT: " + self._json(result)
                    ),
                },
                root,
                "ENFORCE",
            )

            self.assertEqual(decision.exit_code, 0)
            state = store.read_state()
            requests = {item["request_sha256"]: item["status"] for item in state["audit_requests"]}
            self.assertEqual(requests[first["request_sha256"]], "REQUESTED")
            self.assertEqual(requests[second["request_sha256"]], "ASSESSED")

    def test_duplicate_hook_registration_is_idempotent_but_receipt_is_not_replayable(self) -> None:
        """The same tool call may traverse two hooks; a later tool call cannot reuse its receipt."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            session = "duplicate-hooks"
            charter_call = self._dispatch_payload(
                session,
                "architect",
                "WORKFORCE_CHARTER: " + self._json(self._charter()),
            )
            charter_call["tool_use_id"] = "tool-charter"
            self.assertEqual(handle_dispatch(charter_call, root, "ENFORCE").exit_code, 0)
            self.assertEqual(handle_dispatch(charter_call, root, "ENFORCE").exit_code, 0)

            audit_call = self._dispatch_payload(
                session,
                "reviewer",
                "WORKFORCE_PROCESS_AUDIT_REQUEST: "
                + self._json(self._request("duplicate-audit", "INITIAL", [])),
            )
            audit_call["tool_use_id"] = "tool-audit"
            first_audit = handle_dispatch(audit_call, root, "ENFORCE")
            self.assertIn("updatedInput", first_audit.stdout)
            with mock.patch(
                "hooks.process_assurance.utc_now", return_value="2099-01-01T00:00:00Z"
            ):
                self.assertEqual(handle_dispatch(audit_call, root, "ENFORCE").exit_code, 0)
            store = AssuranceStore(root, session)
            request = store.read_state()["audit_requests"][0]
            result = {
                "assessment_id": "duplicate-assessment",
                "request_sha256": request["request_sha256"],
                "verdict": "PASS",
                "rule_evaluations": self._rules(),
                "findings": [],
                "auditor_identity": "reviewer-duplicate",
            }
            self.assertEqual(
                handle_subagent_stop(
                    {
                        "session_id": session,
                        "agent_type": "reviewer",
                        "last_assistant_message": (
                            "WORKFORCE_PROCESS_AUDIT_RESULT: " + self._json(result)
                        ),
                    },
                    root,
                    "ENFORCE",
                ).exit_code,
                0,
            )

            transition = {
                "checkpoint": "PRE_BUILDER",
                "requested_transition": "START_BUILDER",
                "evidence_manifest_sha256": request["evidence_manifest_sha256"],
            }
            builder_call = self._dispatch_payload(
                session,
                "builder",
                "WORKFORCE_TRANSITION: " + self._json(transition),
            )
            builder_call["tool_use_id"] = "tool-builder-1"
            first_builder = handle_dispatch(builder_call, root, "ENFORCE")
            builder_input = builder_call["tool_input"]
            self.assertIsInstance(builder_input, dict)
            assert isinstance(builder_input, dict)
            builder_input["prompt"] = __import__("json").loads(
                first_builder.stdout
            )["hookSpecificOutput"]["updatedInput"]["prompt"]
            self.assertEqual(handle_dispatch(builder_call, root, "ENFORCE").exit_code, 0)

            replay = dict(builder_call)
            replay["tool_use_id"] = "tool-builder-2"
            self.assertEqual(handle_dispatch(replay, root, "ENFORCE").exit_code, 2)

    @staticmethod
    def _git(repo: Path, *arguments: str) -> None:
        """Run one isolated Git fixture command."""
        subprocess.run(["git", "-C", str(repo), *arguments], check=True, capture_output=True)

    @staticmethod
    def _json(value: object) -> str:
        """Encode one compact marker fixture."""
        import json

        return json.dumps(value, separators=(",", ":"), sort_keys=True)

    @staticmethod
    def _dispatch_payload(session: str, role: str, prompt: str) -> dict[str, object]:
        """Build a Claude PreToolUse Agent hook payload."""
        return {
            "session_id": session,
            "tool_name": "Agent",
            "tool_input": {"subagent_type": role, "prompt": prompt},
        }

    @staticmethod
    def _charter() -> dict[str, object]:
        """Return the common hook charter without generated fields."""
        return {
            "task_id": "task-hook",
            "version": 1,
            "tier": "standard",
            "objective": "Deliver audited workflow behavior",
            "delivery_target": "integrated code",
            "scope": ["hooks", "skills", "tests"],
            "non_goals": ["automatic production promotion"],
            "acceptance_criteria": ["builder dispatch requires process PASS"],
            "required_checkpoints": ["PRE_BUILDER", "PRE_CLOSEOUT"],
            "approved_by": "requester",
            "approval_ref": "user-message-hook",
        }

    def _submit_finding(
        self,
        store: AssuranceStore,
        identity: str,
        kind: str,
        targets: list[str],
        verdict: str,
    ) -> None:
        """Submit one continuing finding assessment for remediation-loop tests."""
        request = store.request_audit(self._request(identity, kind, targets))
        store.record_assessment(identity, self._assessment(request, identity, verdict))

    @staticmethod
    def _request(identity: str, kind: str, targets: list[str]) -> dict[str, object]:
        """Build one audit request fixture with a distinct evidence frontier."""
        return {
            "request_id": identity,
            "checkpoint": "PRE_BUILDER",
            "requested_transition": "START_BUILDER",
            "submission_kind": kind,
            "target_lineage_ids": targets,
            "evidence_manifest_sha256": identity[0].encode().hex().ljust(64, "0")[:64],
            "evidence_refs": [f"evidence:{identity}"],
        }

    @classmethod
    def _assessment(
        cls, request: dict[str, object], identity: str, verdict: str
    ) -> dict[str, object]:
        """Build one assessment retaining the same logical finding lineage."""
        finding_verdict = "HUMAN_DECISION" if verdict == "HUMAN_DECISION" else "REMEDIATE"
        return {
            "assessment_id": f"assessment-{identity}",
            "request_sha256": request["request_sha256"],
            "verdict": verdict,
            "rule_evaluations": cls._rules_with_violation("CHK-02-OUTCOME"),
            "findings": [
                {
                    "finding_id": f"finding-{identity}",
                    "lineage_id": "lineage-a",
                    "rule_id": "CHK-02-OUTCOME",
                    "severity": "HIGH",
                    "affected_element": "delivery-target",
                    "summary": "The implementation no longer delivers the chartered outcome",
                    "evidence_refs": [f"evidence:{identity}"],
                    "required_correction": "Restore the approved delivery target",
                    "required_verdict": finding_verdict,
                }
            ],
            "auditor_identity": "reviewer-sidechain-1",
        }

    @staticmethod
    def _rules() -> list[dict[str, object]]:
        """Return the closed nine-rule fixture set."""
        return [
            {
                "rule_id": rule_id,
                "result": "SATISFIED",
                "rationale": f"{rule_id} evaluated against direct evidence",
                "evidence_refs": ["repo:HEAD"],
            }
            for rule_id in AssuranceStore.RULE_IDS
        ]

    @classmethod
    def _rules_with_violation(cls, violated_rule: str) -> list[dict[str, object]]:
        """Return the closed checklist with one rule explicitly violated."""
        rules = cls._rules()
        for rule in rules:
            if rule["rule_id"] == violated_rule:
                rule["result"] = "VIOLATED"
                rule["rationale"] = f"{violated_rule} is contradicted by direct evidence"
        return rules

    @staticmethod
    def _initialized_store(directory: str) -> AssuranceStore:
        """Return a store with the common Standard-route charter."""
        store = AssuranceStore(Path(directory), "session-1")
        store.initialize_charter(
            {
                "task_id": "task-1",
                "version": 1,
                "tier": "standard",
                "objective": "Deliver the process assurance pilot",
                "delivery_target": "integrated code",
                "scope": ["hooks", "skills", "tests"],
                "non_goals": ["production promotion"],
                "acceptance_criteria": ["phase drift is detected"],
                "required_checkpoints": ["PRE_BUILDER", "PRE_CLOSEOUT"],
                "approved_by": "requester",
                "approval_ref": "user-message-1",
            }
        )
        return store


if __name__ == "__main__":
    unittest.main()
