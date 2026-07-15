#!/usr/bin/env python3
"""Lint a plan's acceptance criteria for falsifiability.

Ported from ringer's manifest lint, adapted per
docs/superpowers/specs/2026-07-13-acceptance-check-linting-design.md.

Criterion shape (spec §1):
  - [ ] AC-N (mechanical): <claim>. Check: `<command>` -> expects <observable>.
  - [ ] AC-N (judgment):   <claim>. Judge: <who>. Bar: <what a "no" looks like>.

Findings print as:  BLOCK|WARN <class> <AC-id> — why: … good: …
Exit status: non-zero iff any BLOCK finding fired. A document with no tagged
criteria exits 0 — the lint governs the declared shape; it does not
retroactively fail legacy plans. Stdlib only (re, shlex).
"""

import re
import shlex
import sys

CRITERION_RE = re.compile(
    r"^\s*-\s*\[[ xX]?\]\s*(?P<id>AC-[\w.]+)\s*\((?P<tag>mechanical|judgment)\)\s*:\s*(?P<rest>.*)$"
)
CHECK_RE = re.compile(r"Check:\s*`(?P<cmd>[^`]+)`")
JUDGE_RE = re.compile(r"Judge:\s*\S")
BAR_RE = re.compile(r"Bar:\s*\S")

# A1: phrasing nothing could measure (advisory; reviewer confirms).
WEASEL_RE = re.compile(
    r"\b(works correctly|handles?\b[^.]*\bgracefully|gracefully|is robust|as expected|"
    r"behaves properly|works properly|sensible|reasonable)\b",
    re.IGNORECASE,
)
# A3: observable tokens that suggest a judgment label is dodging a Check:.
OBSERVABLE_RE = re.compile(
    r"\b(exit code|exit 0|returns?\b|file exists|http \d{3}|status code|prints?\b|outputs?\b)\b",
    re.IGNORECASE,
)

TAUTOLOGY_CMDS = {"echo", "printf", "true", ":"}
OUTPUT_CMDS = {"echo", "printf", "cat"}


def split_top_level(cmd, ops=("&&", "||", ";", "|")):
    """Split a shell command on top-level operators (quote-aware via shlex)."""
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        return None  # unparseable: never guess on a blocking class
    segments, current = [], []
    for tok in tokens:
        if tok in ops or tok in ("&", ";;"):
            if current:
                segments.append(current)
                current = []
            segments.append(tok)  # keep operators for branch analysis
        else:
            current.append(tok)
    if current:
        segments.append(current)
    return segments


def command_segments(parsed):
    return [s for s in parsed if isinstance(s, list) and s]


def cannot_fail(parsed):
    """L1: every command segment is echo/printf/true/:/exit 0."""
    segs = command_segments(parsed)
    if not segs:
        return False
    for seg in segs:
        head = seg[0]
        if head in TAUTOLOGY_CMDS:
            continue
        if head == "exit" and (len(seg) == 1 or seg[1] == "0"):
            continue
        return False
    return True


def has_failure_output_branch(parsed):
    """True when an `|| <something that prints>` branch exists anywhere."""
    after_or = False
    for seg in parsed:
        if seg == "||":
            after_or = True
            continue
        if after_or and isinstance(seg, list) and seg and seg[0] in OUTPUT_CMDS:
            return True
    return False


def silent_probe(seg):
    """L2: a segment that can fail while printing nothing about why."""
    head, rest = seg[0], seg[1:]
    if head == "grep" and any(a in ("-q", "--quiet", "--silent") or
                              (a.startswith("-") and not a.startswith("--") and "q" in a[1:])
                              for a in rest):
        return "grep -q prints nothing"
    if head == "diff" and any(a in ("-q", "--brief") for a in rest):
        return "diff -q says only THAT files differ, not why"
    if head in ("test", "[", "[["):
        args = [a for a in rest if a not in ("]", "]]")]
        if len(args) == 2 and args[0] in ("-f", "-e", "-d", "-s"):
            return "a bare existence probe fails silently"
    return None


def lint(path):
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError as exc:
        print(f"ERROR cannot read {path}: {exc}")
        return 2

    # Gather criterion blocks: the AC line plus indented continuation lines.
    blocks = []
    current = None
    for line in lines:
        m = CRITERION_RE.match(line)
        if m:
            current = {"id": m.group("id"), "tag": m.group("tag"), "text": m.group("rest")}
            blocks.append(current)
        elif current is not None and line.strip() and (line.startswith("  ") or line.startswith("\t")) \
                and not line.lstrip().startswith("- ["):
            current["text"] += " " + line.strip()
        else:
            current = None

    findings = []

    def add(level, cls, ac, why, good):
        findings.append((level, f"{level} {cls} {ac} — why: {why} good: {good}"))

    for b in blocks:
        ac, tag, text = b["id"], b["tag"], b["text"]

        if WEASEL_RE.search(text):
            add("WARN", "unfalsifiable-phrasing", ac,
                "the claim leans on wording no reader could measure.",
                "name the observable — what exactly is printed, returned, or present when the claim holds.")

        if tag == "mechanical":
            cm = CHECK_RE.search(text)
            if not cm:
                add("BLOCK", "mechanical-criterion-without-check", ac,
                    "an undeclared check gets verified by improvisation and hands the verifier nothing.",
                    "add Check: `<command>` -> expects <observable>, or re-tag as (judgment) with a Judge: and Bar:.")
                continue
            parsed = split_top_level(cm.group("cmd"))
            if parsed is None:
                continue  # unparseable: never block on a guess
            if cannot_fail(parsed):
                add("BLOCK", "tautological-check", ac,
                    "this check exits 0 no matter what the code does, so it passes proving nothing.",
                    "use a command whose output changes with the code under test.")
                continue
            if not has_failure_output_branch(parsed):
                for seg in command_segments(parsed):
                    reason = silent_probe(seg)
                    if reason:
                        add("BLOCK", "silent-check", ac,
                            f"{reason}; a failure leaves the verifier's evidence column empty and tells the repair loop nothing.",
                            'drop the quiet flag, or append || echo "why: <expected vs got>" so failure prints the reason.')
                        break
        else:  # judgment
            if not JUDGE_RE.search(text) or not BAR_RE.search(text):
                add("WARN", "empty-judgment-criterion", ac,
                    "a judgment criterion with no named judge or no stated bar is unfalsifiable by anyone.",
                    'name the judge and state what a "no" looks like (e.g. Judge: reviewer. Bar: an unexplained magic number is a fail).')
            if OBSERVABLE_RE.search(text):
                add("WARN", "mislabeled-criterion", ac,
                    "this claim names a machine-observable, so a command could decide it; the judgment label dodges the Check: requirement.",
                    "re-tag as (mechanical) with a Check:, or reword the claim to the genuinely subjective part.")

    for _, line in findings:
        print(line)
    blocked = any(level == "BLOCK" for level, _ in findings)
    if not findings:
        print(f"ok: {len(blocks)} criteria, no findings" if blocks
              else "ok: no tagged acceptance criteria found (legacy plan shape — nothing linted)")
    return 1 if blocked else 0


def main():
    if len(sys.argv) != 2:
        print("usage: lint_acceptance_checks.py <plan.md>", file=sys.stderr)
        return 2
    return lint(sys.argv[1])


if __name__ == "__main__":
    sys.exit(main())
