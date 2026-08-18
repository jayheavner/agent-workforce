#!/usr/bin/env python3
"""agent_team_closeout_paths.py — what git says changed, and which of it is code.

One half of the closeout Stop hook (agent_team_closeout.py), split out for the
project's file-size discipline; it has no side effects and no CLI, and every
function here READS. Nothing in this file mutates a repository: the closeout hook
is a verifier, so its git access is limited to status, diff, rev-parse, cat-file
and worktree listing.

Keying the separation rules on what CHANGED rather than on which role ran is the
point of the file: a control keyed on the actor is switched off by choosing a
different actor (2026-08-03, a source-and-test change routed to the executor
skipped every separation rule because none of them mentioned that role).
"""
import json
import os
import subprocess

# Changes under these top-level directories are documentation, so they do not
# pull the separation rules in. Everything else counts as code. Overridable per
# project via .workforce/project.json, shipped default in agent-team-lanes.json.
DEFAULT_DOC_PATHS = ("docs", "plans", "doc-inventory")


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


def _short_ref(ref):
    """`refs/heads/main` -> `main`; anything else unchanged. The integration
    command compares its argument against the checkout's short HEAD, so a remedy
    quoting the long form would be refused by the very command it names."""
    return ref[len("refs/heads/"):] if ref.startswith("refs/heads/") else ref


def _ref_is_ancestor(cwd, slug, ref):
    """True only when git positively says the change's ref is already contained
    in `ref`. An unreadable answer is False: an unverifiable integration claim is
    exactly the claim this check exists to refuse."""
    try:
        out = subprocess.run(["git", "-C", cwd, "merge-base", "--is-ancestor",
                              f"refs/heads/change/{slug}", ref],
                             capture_output=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return out.returncode == 0


def _head_ref(cwd):
    """The short ref this checkout is on, for the remedy line; `main` when git
    cannot say, since that is the name the block has to print something for."""
    lines = _git_lines(cwd, "symbolic-ref", "--short", "--quiet", "HEAD")
    return lines[0] if lines else "main"
