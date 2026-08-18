#!/usr/bin/env python3
"""agent_team_closeout_ledger.py — the delivery ledger the closeout enforces.

One half of the closeout Stop hook (agent_team_closeout.py), split out for the
project's file-size discipline. Every check here compares a claim in the session's
final message — or a contract duty — against reality the hook can read itself:
dispatch order in the transcript, git's object store, the filesystem, the work
register. Nothing asks the model to fill in a schema; that failure mode is
documented (2026-07-17: 67 rote receipts) and must not return.

The file READS. It runs no mutating git command, removes no worktree, and deletes
no timecard — integration is a dispatched executor command and this is the thing
that checks it happened.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from agent_team_closeout_paths import (_head_ref, _ref_is_ancestor,     # noqa: E402
                                       _short_ref, git_object_exists,
                                       in_git_repo, pending_code_paths)

MUTATING_ROLES = {"builder", "executor", "deployer", "test-author"}
# Deferral language in a closeout without a disposition is narration — the
# 2026-07-22 innovation-awards failure mode ("4/4 complete, blocked: no" while
# a known-nonfunctional alerting path lived only in prose caveats). Per the
# discovered-work policy each deferral gets exactly one disposition: fixed
# now, a tracker reference, or the line-start Remaining-work floor section.
DEFERRAL_MARKERS = ("follow-up", "follow up", "deferred", "not built",
                    "never built", "half-built", "open item", "left unfixed",
                    "future work")
# A disposition is a tracker reference (#N or an /issues/ URL) or a
# line-start "Remaining work" heading — mid-sentence mentions (e.g. the cost
# report's tracker nag quoting "REMAINING WORK floor") never count.
DISPOSITION_RE = re.compile(
    r"(?im)^#{0,6}\s*remaining work\b|(?<!\w)#\d+\b|/issues/\d+")
# The one line a closeout must carry per change this session still holds, in the
# shape the register can be checked against. Three dispositions and no others:
# integration is a verified git fact, a keep cites the tracker it is parked in,
# and an abandonment is stated outright.
DISPOSITION_LINE_RE = re.compile(
    r"(?im)^[ \t>*-]*CHANGE-DISPOSITION:\s*(?P<slug>[A-Za-z0-9][A-Za-z0-9._-]*)"
    r"\s*\|\s*(?P<how>.+?)\s*$")
INTEGRATED_RE = re.compile(r"(?i)^integrated\s+into\s+(?P<ref>\S+)")
KEPT_RE = re.compile(r"(?i)^kept\s+for\s+(?P<tracker>\S+)")
ABANDONED_RE = re.compile(r"(?i)^abandoned\b")


def held_claims(cwd, session_id):
    """The live timecards for this project that this session is a member of.

    Read by shelling out to the register's own `session-claims`, so the register
    stays the single authority on what a claim is and this hook re-derives none of
    it. Returns a list of (slug, worktree, state) triples, newest reader wins on
    format: a line the register prints with fewer fields still yields its slug.
    Read-only — nothing here claims, releases, reaps, or rewrites a card. Fails
    open (empty list) when the register is absent or cannot answer: a Stop hook
    must never wedge a session over a missing helper.
    """
    script = os.path.join(HERE, "agent-team-register.sh")
    if not session_id or not os.path.isfile(script):
        return []
    try:
        out = subprocess.run(["bash", script, "session-claims", cwd, session_id],
                             capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return []
    if out.returncode != 0:
        return []
    claims = []
    for line in out.stdout.splitlines():
        fields = (line.split("\t") + ["", ""])[:3]
        if fields[0].strip():
            claims.append(tuple(f.strip() for f in fields))
    return claims


def _integration_command(cwd, slug, ref, session_id):
    """The exact command that integrates one change — the only thing that does."""
    return (f"bash {os.path.join(HERE, 'agent-team-workspace.sh')} integrate "
            f"{cwd} {slug} {_short_ref(ref)} {session_id}")


def disposition_problems(last_text, cwd, session_id):
    """Check 6: every change this session still holds needs a stated disposition,
    and an "integrated" one is verified against git rather than believed.

    Two facts have to agree before an integration claim stands: the change's ref
    is already contained in the ref the message names, AND the timecard is gone.
    A surviving card is counter-evidence on its own — `workspace_integrate` merges,
    removes the worktree, deletes the ref and releases the card in one step, so a
    card that is still there means that command never ran to completion.

    This function reads. It runs no mutating git command, removes no worktree, and
    deletes no timecard: integration is a dispatched executor command, and the hook
    is the thing that checks it happened.
    """
    problems = []
    stated = {m.group("slug"): m.group("how")
              for m in DISPOSITION_LINE_RE.finditer(last_text)}
    for slug, worktree, _state in held_claims(cwd, session_id):
        how = stated.get(slug)
        head = _head_ref(cwd)
        if how is None:
            problems.append(
                f'The change "{slug}" is still claimed in the work register: its '
                f"timecard is live and this session holds it, and its worktree is "
                f"{worktree or 'the path derived from the slug'}. A completion has to "
                "say what happened to it. Add exactly one of these lines to your "
                f"final message:\n"
                f"  CHANGE-DISPOSITION: {slug} | integrated into {head}\n"
                f"  CHANGE-DISPOSITION: {slug} | kept for <tracker-ref>\n"
                f"  CHANGE-DISPOSITION: {slug} | abandoned\n"
                "The first line is only true once the integration has actually run — "
                "this hook never integrates anything. To integrate, dispatch the "
                "executor to run:\n  "
                + _integration_command(cwd, slug, head, session_id) +
                "\nwhich merges the change, removes its worktree, deletes "
                f"refs/heads/change/{slug} and releases the timecard.")
            continue
        integrated = INTEGRATED_RE.match(how)
        if integrated:
            ref = integrated.group("ref")
            if not _ref_is_ancestor(cwd, slug, ref):
                problems.append(
                    f'The final message reports the change "{slug}" as integrated '
                    f"into {ref}, but git says refs/heads/change/{slug} is not "
                    f"contained in {ref}, so nothing was merged. Either integrate it "
                    "— dispatch the executor to run:\n  "
                    + _integration_command(cwd, slug, ref, session_id) +
                    f"\n— or restate the disposition honestly as "
                    f'"CHANGE-DISPOSITION: {slug} | kept for <tracker-ref>".')
            else:
                problems.append(
                    f'The final message reports the change "{slug}" as integrated '
                    f"into {ref}, and the merge is real, but its timecard is still "
                    "live in the work register — so the integration never ran to "
                    "completion: the worktree and refs/heads/change/"
                    f"{slug} are still standing and the claim still blocks the next "
                    "session from that slug. Dispatch the executor to run:\n  "
                    + _integration_command(cwd, slug, ref, session_id) +
                    "\nwhich is idempotent against an already-merged change: it "
                    "removes the worktree, deletes the ref and releases the "
                    "timecard.")
        elif not (KEPT_RE.match(how) or ABANDONED_RE.match(how)):
            problems.append(
                f'The disposition stated for the change "{slug}" — "{how}" — is not '
                "one this hook can check. Use exactly one of:\n"
                f"  CHANGE-DISPOSITION: {slug} | integrated into {head}\n"
                f"  CHANGE-DISPOSITION: {slug} | kept for <tracker-ref>\n"
                f"  CHANGE-DISPOSITION: {slug} | abandoned")
    return problems


def ledger_checks(last_text, roles, order, cwd, session_id=""):
    """The resurrected delivery ledger — machine-verifiable checks ONLY.

    Every check compares a claim in the final message (or a contract duty)
    against reality the hook can read itself: dispatch order in the
    transcript, git's object store, the filesystem. Nothing here asks the
    model to fill in a schema — that failure mode is documented (2026-07-17:
    67 rote receipts) and must not return.
    """
    problems = []

    # The separation rules below fire on EITHER a builder dispatch or a code
    # change this checkout can see, whichever is present. Role alone was the
    # trigger until 2026-08-03, when a source-and-test change routed to the
    # executor sailed past all of them because none of them named that role; the
    # retired comment called that "the proportionality floor". Proportionality is
    # preserved by the path classification instead — installs, cleanups, commits
    # and documentation produce no code delta and still pull in nothing.
    code_paths = pending_code_paths(cwd)
    builder_idxs = [i for i, r in enumerate(order) if r == "builder"]
    if builder_idxs:
        # A builder ran: anchor on it, so a closeout commit by another mutating
        # role after verification does not re-demand verification of itself.
        code_anchor = max(builder_idxs)
    else:
        mutating_idxs = [i for i, r in enumerate(order) if r in MUTATING_ROLES]
        code_anchor = max(mutating_idxs) if mutating_idxs else -1
    code_authored = bool(builder_idxs) or bool(code_paths)
    changed_note = ""
    if not builder_idxs and code_paths:
        shown = ", ".join(code_paths[:4])
        more = f" (+{len(code_paths) - 4} more)" if len(code_paths) > 4 else ""
        changed_note = (f" This session's un-integrated code changes: {shown}{more}. "
                        "Naming a role other than builder does not make code "
                        "changes exempt.")

    # 1. Fresh verification after the last code edit.
    if code_authored and "WORKFORCE_PAUSE: HUMAN_DECISION" not in last_text:
        if not any(r == "verifier" for r in order[code_anchor + 1:]):
            problems.append(
                "Code changed in this session with no verifier dispatch after "
                "the last agent that could have written it (or no verifier ran "
                "at all). Fresh verification must follow the final code edit: "
                "dispatch the verifier against the delivered work before "
                "closing out." + changed_note)

    # 1a. Plan critique before build (design routes only): an architect whose
    #     plan flowed straight into a builder was never independently
    #     critiqued. Requires a reviewer dispatch between the first architect
    #     and the first subsequent builder. Design-only sessions (no builder
    #     after the architect) are exempt — the human may be the next reader.
    if ("architect" in roles and "builder" in roles
            and "WORKFORCE_PAUSE: HUMAN_DECISION" not in last_text):
        first_architect = next(
            i for i, r in enumerate(order) if r == "architect")
        builders_after = [i for i, r in enumerate(order)
                         if r == "builder" and i > first_architect]
        if builders_after:
            first_builder = builders_after[0]
            if not any(r == "reviewer"
                       for r in order[first_architect + 1:first_builder]):
                problems.append(
                    "The architect's plan went straight to a builder with no "
                    "independent critique between them. Dispatch the reviewer "
                    "in plan-critique mode against the plan before building — "
                    "or, when the build already happened, against the plan "
                    "now, and route any findings through a repair loop before "
                    "closing out.")
            # 1a2. Separate test author on design routes: the acceptance
            #      suite must be written from the plan by an agent that will
            #      never write the code, before the first builder runs.
            if not any(r == "test-author"
                       for r in order[first_architect + 1:first_builder]):
                problems.append(
                    "The plan was built without a separately-authored "
                    "acceptance suite: no test-author dispatch sits between "
                    "the architect and the first builder. Dispatch the "
                    "test-author with the reviewed plan and criteria — or, "
                    "when the build already happened, dispatch it now against "
                    "the plan and route the builder to make the suite pass "
                    "before closing out.")

    # 1b. Independent review after the last code edit, same trigger as check 1.
    #     Verification proves the stated criteria; review is the only check of
    #     judgment — spec fidelity at minimum (2026-07-26 checks-balances §2).
    if code_authored and "WORKFORCE_PAUSE: HUMAN_DECISION" not in last_text:
        if not any(r == "reviewer" for r in order[code_anchor + 1:]):
            problems.append(
                "Code changed in this session and closed without an independent "
                "review verdict: no reviewer dispatch follows it. Dispatch the "
                "reviewer against the delivered diff — fidelity mode (delivered "
                "vs the original request) at minimum, full code review for "
                "risky surfaces — before closing out.")

    # 2. Every commit hash claimed in the final message must exist in this
    #    checkout's object store.
    if in_git_repo(cwd):
        for line in last_text.splitlines():
            if not re.search(r"\bcommit(s|ted|ting)?\b", line, re.IGNORECASE):
                continue
            for sha in re.findall(r"\b[0-9a-f]{7,40}\b", line):
                if not git_object_exists(cwd, sha):
                    problems.append(
                        f"The final message cites commit {sha}, which does not "
                        "exist in this checkout. Correct the hash, or state "
                        "which repository it belongs to.")

    # 3. Every status-note path claimed in the final message must exist.
    for rel in set(re.findall(r"docs/STATUS-[\w.-]+\.md", last_text)):
        if not os.path.isfile(os.path.join(cwd, rel)):
            problems.append(
                f"The final message references {rel}, which does not exist. "
                "Dispatch the scribe to write it, or remove the claim.")

    # 4. A "deployed" claim requires that a deployer actually ran.
    lowered = last_text.lower()
    if (re.search(r"\bdeployed\b", lowered)
            and not re.search(r"\bnot\s+deployed\b", lowered)
            and "deployer" not in roles):
        problems.append(
            'The final message says "deployed" but no deployer dispatch ran '
            "this session. Route the deploy through the deployer, or restate "
            "the delivery honestly (e.g. \"implemented and locally verified; "
            "deploy not authorized\").")

    # 5. Deferred work needs a disposition, never narration (discovered-work
    #    policy). A pause is not a completion claim, so open work is expected
    #    there.
    if "WORKFORCE_PAUSE: HUMAN_DECISION" not in last_text:
        hits = sorted({m for m in DEFERRAL_MARKERS if m in lowered})
        if hits and not DISPOSITION_RE.search(last_text):
            problems.append(
                "The final message defers work (matched: "
                + ", ".join(f"'{h}'" for h in hits) +
                ") with no disposition. Per the discovered-work policy each "
                "deferral gets exactly one: fix it before closing, file it in "
                "the project tracker and cite the reference (#N or the issue "
                "URL), or list it under a line-start '## Remaining work' "
                "heading. Prose caveats are not a disposition.")

    # 6. Every change this session still holds needs a stated disposition, and an
    #    "integrated" one is verified against git. Skipped on a pause for the same
    #    reason as check 5: a pause is not a completion claim, so a change is
    #    expected to be still held — a mid-task pause demands nothing here and
    #    integrates nothing.
    if "WORKFORCE_PAUSE: HUMAN_DECISION" not in last_text:
        problems.extend(disposition_problems(last_text, cwd, session_id))

    return problems
