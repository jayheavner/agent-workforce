#!/usr/bin/env python3
"""Fail closed when a final report calls incomplete delivery complete.

This is deliberately a narrow deterministic control. It does not judge whether
the cited evidence is true; it prevents a final completion claim unless the
report supplies a structurally valid receipt whose target-required fields all
say ``pass``. Evidence truth remains the verifier's responsibility.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


RECEIPT_HEADING = re.compile(r"^##\s+delivery receipt\s*$", re.IGNORECASE)
HEADING = re.compile(r"^#{1,2}\s+")
ENTRY = re.compile(r"^\s*-\s+([a-z-]+):\s*(.*?)\s*$", re.IGNORECASE)

REQUIRED_FIELDS = {
    "artifact": ("verification", "review", "documentation", "memory", "commit"),
    "integrated-code": (
        "verification",
        "review",
        "documentation",
        "memory",
        "commit",
        "integration",
    ),
    "deployed-service": (
        "verification",
        "review",
        "documentation",
        "memory",
        "commit",
        "integration",
        "deployment",
    ),
}
LEDGER_FIELDS = (
    "verification",
    "review",
    "documentation",
    "memory",
    "commit",
    "integration",
    "deployment",
    "cleanup",
)
VALID_STATUS = {"pass", "fail", "pending", "unchecked", "not applicable"}

RECEIPT_TEMPLATE = "\n".join(
    [
        "Expected receipt format:",
        "## Delivery receipt",
        "",
        "- delivery-target: <artifact|integrated-code|deployed-service>",
        "- shipment-verdict: <SHIPPABLE|NOT SHIPPABLE>",
        *(
            f"- {field}: <pass|fail|pending|unchecked|not applicable> — <evidence>"
            for field in ("verification", "review", "documentation", "memory", "commit", "integration", "deployment", "cleanup")
        ),
    ]
)

COMPLETION_PATTERNS = (
    re.compile(
        r"\b(?:work|task|fix|implementation|change|delivery|shipment)\s+"
        r"(?:is\s+)?(?:complete|completed|done)\b",
        re.IGNORECASE,
    ),
    re.compile(r"\bmarking\s+(?:the\s+)?work\s+complete\b", re.IGNORECASE),
    re.compile(r"\bfinal gate\b.*\b(?:complete|completed|done)\b", re.IGNORECASE),
)
UNFINISHED_PATTERNS = (
    re.compile(r"\bnot\s+deployed\b", re.IGNORECASE),
    re.compile(r"\bdeploy(?:ment)?\s+is\s+not\s+done\b", re.IGNORECASE),
    re.compile(r"\bdeployment\s+(?:is\s+)?pending\b", re.IGNORECASE),
)


def status(value: str) -> str | None:
    """Return the declared status token, preserving evidence after a dash."""
    normalized = value.strip().lower()
    for candidate in sorted(VALID_STATUS, key=len, reverse=True):
        if normalized == candidate or normalized.startswith(candidate + " ") or normalized.startswith(candidate + " —"):
            return candidate
    return None


def receipt_entries(lines: list[str]) -> dict[str, str] | None:
    """Read one compact Markdown receipt, or return None when it is absent."""
    start = next((i for i, line in enumerate(lines) if RECEIPT_HEADING.match(line)), None)
    if start is None:
        return None

    entries: dict[str, str] = {}
    for line in lines[start + 1 :]:
        if HEADING.match(line):
            break
        match = ENTRY.match(line)
        if match:
            entries[match.group(1).lower()] = match.group(2)
    return entries


def completion_claimed(text: str, receipt: dict[str, str] | None) -> bool:
    if any(pattern.search(text) for pattern in COMPLETION_PATTERNS):
        return True
    return receipt is not None and receipt.get("shipment-verdict", "").strip().upper() == "SHIPPABLE"


def lint(path: Path, require_receipt: bool, require_shippable: bool) -> list[tuple[str, str]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    text = "\n".join(lines)
    entries = receipt_entries(lines)
    claimed = completion_claimed(text, entries)
    blocks: list[tuple[str, str]] = []

    unfinished = [line.strip() for line in lines if any(pattern.search(line) for pattern in UNFINISHED_PATTERNS)]
    if claimed and unfinished:
        blocks.append((
            "C1",
            "completion claim contradicts unfinished delivery: " + " | ".join(unfinished),
        ))

    if entries is None:
        if claimed or require_receipt or require_shippable:
            blocks.append(("C2", "final report has no ## Delivery receipt"))
        return blocks

    target = entries.get("delivery-target", "").strip().lower()
    verdict = entries.get("shipment-verdict", "").strip().upper()
    if target not in REQUIRED_FIELDS:
        blocks.append(("C2", "delivery-target must be artifact, integrated-code, or deployed-service"))
    if verdict not in {"SHIPPABLE", "NOT SHIPPABLE"}:
        blocks.append(("C2", "shipment-verdict must be SHIPPABLE or NOT SHIPPABLE"))

    for field in LEDGER_FIELDS:
        value = entries.get(field)
        if value is None:
            blocks.append(("C2", f"delivery receipt is missing {field}"))
        elif status(value) is None:
            blocks.append(("C2", f"{field} must start with pass, fail, pending, unchecked, or not applicable"))

    if claimed and verdict != "SHIPPABLE":
        blocks.append(("C1", "completion claim requires shipment-verdict: SHIPPABLE"))

    if require_shippable and verdict != "SHIPPABLE":
        blocks.append(("C3", "completion closeout requires shipment-verdict: SHIPPABLE"))

    if target in REQUIRED_FIELDS and verdict == "SHIPPABLE":
        for field in REQUIRED_FIELDS[target]:
            field_status = status(entries.get(field, ""))
            allowed = {"pass", "not applicable"} if field == "memory" else {"pass"}
            if field_status not in allowed:
                expected = "pass or not applicable" if field == "memory" else "pass"
                blocks.append(("C3", f"SHIPPABLE {target} requires {field}: {expected} (found {field_status or 'missing'})"))

    if target == "deployed-service":
        for field in ("integration", "deployment"):
            if status(entries.get(field, "")) == "not applicable":
                blocks.append(("C4", f"deployed-service cannot mark {field}: not applicable"))

    return blocks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-receipt", action="store_true", help="block reports without a receipt even when they make no completion claim")
    parser.add_argument("--require-shippable", action="store_true", help="require a SHIPPABLE receipt for a terminal completion closeout")
    parser.add_argument("report", type=Path, help="final report or status note to lint")
    args = parser.parse_args()

    if not args.report.is_file():
        print(f"ERROR {args.report}: report does not exist or is not a file", file=sys.stderr)
        return 2

    try:
        blocks = lint(args.report, args.require_receipt, args.require_shippable)
    except UnicodeDecodeError:
        print(f"ERROR {args.report}: report must be UTF-8 text", file=sys.stderr)
        return 2

    if blocks:
        for rule, message in blocks:
            print(f"{args.report}: BLOCK {rule} {message}")
        print(RECEIPT_TEMPLATE)
        return 1

    print(f"{args.report}: PASS completion claim is consistent with its delivery receipt")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
