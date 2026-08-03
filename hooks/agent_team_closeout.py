#!/usr/bin/env python3
"""agent_team_closeout.py — Stop hook: the priced closeout that cannot be skipped.

Fires on Stop in orchestrator sessions (wired via agent frontmatter in snapshot
mode, via hooks.json + the plugin router in live plugin mode). Everything it
enforces is mechanical — checked against the transcript, git, or the
filesystem, never self-reported:

1. Any turn that ends after dispatched work must carry the exact cost report.
   The hook COMPUTES the report itself (cost_report.py, whole session including
   the orchestrator's own usage) and hands it over in the block reason — the
   model's only job is to include it. No memory, no arithmetic, no estimate.
2. If git-mutating specialists ran and the working tree is dirty, the final
   message must acknowledge the uncommitted state (commit via the executor or
   say plainly what remains and why).
3. The delivery ledger (ledger_checks): builder work needs a verifier dispatch
   after the last builder; claimed commit hashes must exist in the checkout;
   claimed docs/STATUS-*.md files must exist; a "deployed" claim requires a
   deployer dispatch. Reality-checked descendants of the 2026-07-15 receipt
   ledger, whose self-reported fields produced rote compliance (67 receipts,
   2026-07-17) and were deleted.

Design rules learned from the previous generation (see
docs/superpowers/specs/2026-07-18-autonomy-first-redesign.md):
- Never fire while dispatches are in flight.
- Never demand facts the hook cannot verify (no ownership claims, no receipt
  schemas, no ledger fields).
- Bounded enforcement: at most MAX_BLOCKS blocks per session, then fail open
  with a visible warning — a hook must never wedge a session.
- On a passing stop, telemetry is written by machine, never by a dispatch —
  and always into the workforce-owned telemetry dir, never into the client
  repo (2026-07-22: writing into the client's docs/telemetry collided with a
  curated project dir and made one hook dirty the tree another hook polices).
- Stale-read guard: the Stop event can fire before the just-finished reply is
  flushed to the transcript (observed live 2026-07-22: three identical blocks,
  each grading the PREVIOUS message, ended only by the enforcement cap). Every
  block records a hash of the tail it graded; a re-evaluation that sees the
  same tail — or no tail at all — is a stale read, retried once after a short
  delay and then allowed without spending a block.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import time

MAX_BLOCKS = 3
COST_MARKER = "## Cost report"
MUTATING_ROLES = {"builder", "executor", "deployer", "test-author"}
# Changes under these top-level directories are documentation, so they do not
# pull the separation rules in. Everything else counts as code. Overridable per
# project via .workforce/project.json, shipped default in agent-team-lanes.json.
DEFAULT_DOC_PATHS = ("docs", "plans", "doc-inventory")
# Only phrases that actually acknowledge DIRT count. "commit"/"committed" were
# removed deliberately: they satisfied the check in exactly the failure case it
# exists to catch (claiming a commit happened while the tree is dirty).
DIRTY_ACK_WORDS = ("uncommitted", "not committed", "left dirty", "dirty tree",
                   "WORKFORCE_PAUSE: HUMAN_DECISION")
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
# A background dispatch writes an immediate stub tool_result; the real
# completion arrives later as a task-notification carrying the tool_use id.
BG_STUB_MARKER = "Async agent launched successfully"
NOTIFIED_ID = re.compile(r"<tool-use-id>([^<]+)</tool-use-id>")

HERE = os.path.dirname(os.path.abspath(__file__))


def state_path(session_id):
    root = os.environ.get("AGENT_TEAM_CLOSEOUT_STATE",
                          os.path.expanduser("~/.claude/state/agent-workforce-closeout"))
    os.makedirs(root, exist_ok=True)
    digest = hashlib.sha256(session_id.encode()).hexdigest()
    return os.path.join(root, digest + ".json")


def gc_state():
    """State files persist across a session's stops (acked_total); reap old ones."""
    root = os.environ.get("AGENT_TEAM_CLOSEOUT_STATE",
                          os.path.expanduser("~/.claude/state/agent-workforce-closeout"))
    cutoff = time.time() - 30 * 86400
    try:
        for entry in os.scandir(root):
            if entry.is_file() and entry.stat().st_mtime < cutoff:
                os.unlink(entry.path)
    except OSError:
        pass


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


def block_text(block_):
    """Flatten a tool_result/content value (string or text-block list) to text."""
    content = block_.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(b.get("text", "") for b in content
                        if isinstance(b, dict) and b.get("type") == "text")
    return ""


def scan_transcript(path):
    """One pass: dispatch count, in-flight set, roles seen (ordered), last text.

    "Last text" is the FINAL MESSAGE the human sees: every assistant text
    record since the most recent user record (tool_result, human turn, or
    task-notification), concatenated. A long final message is written as
    several consecutive assistant records; reading only the last record made
    the hook re-demand a cost table the message already carried (observed
    live 2026-07-20).

    Background dispatches are handled explicitly: their immediate tool_result
    is a launch stub (BG_STUB_MARKER), NOT a completion — the dispatch stays
    in flight until a task-notification names its tool_use id. If the harness
    ever changes the stub wording, the stub reads as a real result and the
    hook degrades to the old (allow-leaning) behavior.
    """
    total = 0
    in_flight = {}
    roles = set()
    order = []
    notified = set()
    tail_texts = []
    try:
        f = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return 0, {}, set(), [], ""
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
            if rec.get("type") == "user":
                tail_texts = []
            if isinstance(content, str):
                notified.update(NOTIFIED_ID.findall(content))
                continue
            if not isinstance(content, list):
                continue
            if rec.get("type") == "assistant":
                texts = [b.get("text", "") for b in content
                         if isinstance(b, dict) and b.get("type") == "text"]
                if texts:
                    tail_texts.append("\n".join(texts))
            for block_ in content:
                if not isinstance(block_, dict):
                    continue
                if block_.get("type") == "text":
                    notified.update(NOTIFIED_ID.findall(block_.get("text", "")))
                elif block_.get("type") == "tool_use" and block_.get("name") == "Agent":
                    total += 1
                    stype = (block_.get("input") or {}).get("subagent_type", "") or ""
                    stype = stype.split(":")[-1]
                    in_flight[block_.get("id")] = stype
                    roles.add(stype)
                    order.append(stype)
                elif block_.get("type") == "tool_result" and block_.get("tool_use_id") in in_flight:
                    if BG_STUB_MARKER not in block_text(block_):
                        del in_flight[block_["tool_use_id"]]
    for tid in notified:
        in_flight.pop(tid, None)
    return total, in_flight, roles, order, "\n".join(tail_texts)


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
        out = subprocess.run(cost_report_cmd(transcript, session_id, cwd,
                                             extra=("--cwd", cwd)),
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


def git_object_exists(cwd, sha):
    """False only when git positively says the object is absent (fail-open)."""
    try:
        out = subprocess.run(["git", "-C", cwd, "cat-file", "-e", sha],
                             capture_output=True, timeout=10)
        return out.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return True


def in_git_repo(cwd):
    try:
        out = subprocess.run(["git", "-C", cwd, "rev-parse", "--is-inside-work-tree"],
                             capture_output=True, text=True, timeout=10)
        return out.returncode == 0 and out.stdout.strip() == "true"
    except (OSError, subprocess.TimeoutExpired):
        return False


def _git_lines(cwd, *args, timeout=20):
    """Stripped stdout lines, or [] when git cannot answer."""
    try:
        out = subprocess.run(["git", "-C", cwd, *args],
                             capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return []
    if out.returncode != 0:
        return []
    return [ln for ln in (l.strip() for l in out.stdout.splitlines()) if ln]


def doc_lane_paths(cwd):
    """Top-level directories whose changes are documentation, not code.

    Project declaration first, then the shipped lanes config, then the built-in
    default. A config that cannot be read falls back to the default, never to
    "everything is documentation" — the strict side is the safe side here.
    """
    for path, key in ((os.path.join(cwd, ".workforce", "project.json"), "doc_paths"),
                      (os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                    "agent-team-lanes.json"), "doc_paths")):
        try:
            with open(path, encoding="utf-8") as fh:
                declared = json.load(fh).get(key)
        except (OSError, ValueError):
            continue
        if isinstance(declared, list):
            clean = [str(p).strip("/") for p in declared
                     if isinstance(p, str) and p.strip("/")]
            if clean:
                return tuple(clean)
    return DEFAULT_DOC_PATHS


def _integrated_ref(cwd):
    """The ref standing for "already integrated" — the shared checkout's upstream.

    Resolved once and reused for every worktree: a builder's worktree line has no
    upstream of its own, so asking each tree about its own upstream would find
    nothing for exactly the trees that hold the new code.
    """
    upstream = _git_lines(cwd, "rev-parse", "--abbrev-ref",
                          "--symbolic-full-name", "@{upstream}")
    if upstream:
        return upstream[0]
    for candidate in ("origin/HEAD", "origin/main", "origin/master"):
        if _git_lines(cwd, "rev-parse", "--verify", "--quiet", candidate):
            return candidate
    return None


def _changed_paths(tree, base):
    """Paths this tree has moved away from the integrated ref: uncommitted
    modifications plus anything its commits touch that base does not have."""
    paths = set()
    for line in _git_lines(tree, "status", "--porcelain"):
        entry = line[3:] if len(line) > 3 else ""
        if " -> " in entry:                      # rename: the destination is the write
            entry = entry.split(" -> ", 1)[1]
        entry = entry.strip().strip('"')
        if entry:
            paths.add(entry)
    if base:
        paths.update(_git_lines(tree, "diff", "--name-only", f"{base}...HEAD"))
    return paths


def pending_code_paths(cwd):
    """Code paths changed and not yet integrated, across this checkout AND every
    linked worktree — builders commit inside their own worktrees, so a check that
    only looked at the shared checkout would read "nothing changed" for exactly
    the work it exists to police.

    Keying on what changed rather than on which role ran is the point: a control
    keyed on the actor is switched off by choosing a different actor (2026-08-03,
    a source-and-test change routed to the executor skipped every separation rule
    below because none of them mentioned that role).

    An empty result means "this checkout can see no un-integrated code change" —
    which is also what a repo with no upstream and a clean tree looks like, so
    this is evidence for firing a rule, never proof that nothing happened.
    """
    if not in_git_repo(cwd):
        return []
    docs = doc_lane_paths(cwd)
    trees = [cwd]
    for line in _git_lines(cwd, "worktree", "list", "--porcelain"):
        if line.startswith("worktree "):
            other = line.split(" ", 1)[1].strip()
            if other and other != cwd and os.path.isdir(other):
                trees.append(other)
    base = _integrated_ref(cwd)
    code = set()
    for tree in trees:
        for path in _changed_paths(tree, base):
            top = path.split("/", 1)[0]
            if top not in docs:
                code.add(path)
    return sorted(code)


def ledger_checks(last_text, roles, order, cwd):
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

    return problems


def write_telemetry(transcript, session_id, cwd):
    """Machine telemetry goes to workforce-owned storage, NEVER the client
    repo — a hook must not create dirt that other hooks then police."""
    tdir = os.environ.get(
        "AGENT_TEAM_TELEMETRY_DIR",
        os.path.expanduser("~/.claude/logs/agent-team-telemetry"))
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

    total, in_flight, roles, order, last_text = scan_transcript(transcript)

    # No dispatched work this session -> nothing to enforce (plain Q&A turn).
    if total == 0:
        allow()
    # Dispatches still in flight -> the turn end is a wait, not a closeout.
    if in_flight:
        allow()

    gc_state()
    state = load_state(session_id)
    # Everything up to acked_total was already priced at an earlier passing
    # stop. Conversational turns after a closeout don't re-demand the table;
    # the next NEW dispatch re-arms enforcement.
    if total <= state.get("acked_total", 0):
        allow()
    blocks = state.get("blocks", 0)
    if blocks >= MAX_BLOCKS:
        print("agent-team closeout: enforcement cap reached; allowing stop "
              "without a verified cost report.", file=sys.stderr)
        write_telemetry(transcript, session_id, cwd)
        allow()

    def build_missing(tail):
        found = []
        if COST_MARKER not in tail:
            report = compute_cost_report(transcript, session_id, cwd)
            if report:
                found.append(
                    "Your final message must include the session cost report. "
                    "Include the following verbatim anywhere in your final "
                    "message (already computed — do not re-derive or "
                    "estimate):\n\n" + report)
            else:
                found.append(
                    "Your final message must include the session cost report. "
                    "Run `bin/agent-workforce-cost-report --transcript " +
                    transcript + "` (or have the executor run it) and include "
                    "its output verbatim under '" + COST_MARKER + "'.")

        found.extend(ledger_checks(tail, roles, order, cwd))

        if roles & MUTATING_ROLES and git_dirty(cwd):
            acked = any(w.lower() in tail.lower() for w in DIRTY_ACK_WORDS)
            if not acked:
                found.append(
                    "The working tree has uncommitted changes and your final "
                    "message does not mention them. Either dispatch the "
                    "executor to commit this task's delta (the original "
                    "request authorizes a focused local commit unless the "
                    "human opted out), or state plainly what remains "
                    "uncommitted and why.")
        return found

    def tail_hash(tail):
        return hashlib.sha256(tail.encode()).hexdigest()

    def is_stale(tail):
        """After a block, a tail identical to the one already graded — or no
        tail at all — means the model's post-block reply has not reached the
        transcript yet (Stop fired before the flush)."""
        if blocks == 0:
            return False
        return tail == "" or tail_hash(tail) == state.get("blocked_hash")

    missing = build_missing(last_text)

    if missing and is_stale(last_text):
        try:
            delay = float(os.environ.get("AGENT_TEAM_CLOSEOUT_RETRY_DELAY", "2"))
        except ValueError:
            delay = 2.0
        if delay > 0:
            time.sleep(delay)
        total, in_flight, roles, order, last_text = scan_transcript(transcript)
        missing = [] if in_flight else build_missing(last_text)
        if missing and is_stale(last_text):
            print("agent-team closeout: transcript read is stale (Stop fired "
                  "before the final reply was flushed); allowing stop without "
                  "re-verification.", file=sys.stderr)
            write_telemetry(transcript, session_id, cwd)
            allow()

    if missing:
        state["blocks"] = blocks + 1
        state["blocked_hash"] = tail_hash(last_text)
        save_state(session_id, state)
        block("\n\n".join(missing))

    write_telemetry(transcript, session_id, cwd)
    save_state(session_id, {"acked_total": total})
    allow()


if __name__ == "__main__":
    main()
