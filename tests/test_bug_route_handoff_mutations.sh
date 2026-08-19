#!/usr/bin/env bash
# tests/test_bug_route_handoff_mutations.sh — proves tests/test_bug_route_handoff.sh
# is load-bearing rather than decorative: strip the newly pinned prose from a
# copy of each of the five pinned surfaces in turn (debugger.md,
# orchestrator.md, builder.md, verifier.md, and the agent-workforce skill's
# criteria-authoring sentence) and confirm the drift test fails closed, naming
# the mutated file. Copies live under a project-local scratch directory
# (temp/, gitignored) and are removed when this finishes. Runs in well under
# five seconds, so it is registered directly in install.sh's install-test
# gate rather than merely named as a manual proof.
#
# A negative control runs an unmutated copy through the same drift test and
# requires it to pass — proving the drift test isn't red by default for some
# unrelated reason, which would make every "CAUGHT" below meaningless. That
# control is itself falsifiable: set MUTATION_HARNESS_SELFTEST=1 to corrupt
# the control copy too, which must turn this harness's own exit non-zero.
#
# Each marker is extracted straight from the live repo file (never hand-
# retyped), so the mutation always matches the prose actually pinned today —
# there is nothing here for that prose to drift away from silently.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SCRATCH_ROOT="$REPO/temp/test_bug_route_handoff_mutations"

CAUGHT=0
FAIL=0

cleanup() { rm -rf "$SCRATCH_ROOT"; }
trap cleanup EXIT

rm -rf "$SCRATCH_ROOT"
mkdir -p "$SCRATCH_ROOT"

# Copy only the tracked files, so the scratch tree can't inherit stray local
# junk (worktrees, build output) that would confuse the drift test.
copy_tree() {
  local dest="$1"
  mkdir -p "$dest"
  (cd "$REPO" && git ls-files -z) | (cd "$REPO" && tar --null -T - -cf - ) | (cd "$dest" && tar -xf -)
}

# extract_marker MODE FILE ANCHOR > marker text on stdout
#   paragraph  — the whole blank-line-delimited paragraph containing ANCHOR.
#   row-suffix — inside the first line starting "| Symptom (", the text
#                between ANCHOR and the row's trailing " |", i.e. the clause
#                appended after the pre-existing sentence named by ANCHOR.
extract_marker() {
  local mode="$1" file="$2" anchor="$3"
  python3 - "$mode" "$file" "$anchor" <<'PY'
import sys
mode, path, anchor = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
if mode == "paragraph":
    paras = text.split("\n\n")
    hits = [p for p in paras if anchor in p]
    if len(hits) != 1:
        sys.exit(f"expected exactly one paragraph containing {anchor!r} in {path}, found {len(hits)}")
    sys.stdout.write(hits[0] + "\n\n")
elif mode == "row-suffix":
    lines = [l for l in text.split("\n") if l.startswith("| Symptom (")]
    if len(lines) != 1:
        sys.exit(f"expected exactly one symptom row in {path}, found {len(lines)}")
    line = lines[0]
    idx = line.find(anchor)
    if idx == -1:
        sys.exit(f"anchor {anchor!r} not found in symptom row of {path}")
    start = idx + len(anchor)
    end = line.rfind(" |")
    if end == -1 or end <= start:
        sys.exit(f"could not locate trailing ' |' after anchor in symptom row of {path}")
    sys.stdout.write(line[start:end])
else:
    sys.exit(f"unknown mode {mode!r}")
PY
}

# Removes the first occurrence of $marker from $file, failing loudly if the
# marker is not present — that would mean extraction and stripping disagree,
# not that the mutation succeeded.
strip_marker() {
  local file="$1" marker_file="$2"
  python3 - "$file" "$marker_file" <<'PY'
import sys
path, marker_path = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
marker = open(marker_path, encoding="utf-8").read()
if not marker or marker not in text:
    print(f"marker not found in {path}", file=sys.stderr)
    sys.exit(2)
text = text.replace(marker, "", 1)
open(path, "w", encoding="utf-8").write(text)
PY
}

run_mutation() {
  local rel="$1" label="$2" mode="$3" anchor="$4"
  local dest="$SCRATCH_ROOT/$label"
  local marker_file="$SCRATCH_ROOT/.marker-$label"
  if ! extract_marker "$mode" "$REPO/$rel" "$anchor" > "$marker_file"; then
    echo "NOT CAUGHT: $rel (could not extract marker: $(cat "$marker_file"))"
    FAIL=1
    return
  fi
  copy_tree "$dest"
  if ! strip_marker "$dest/$rel" "$marker_file"; then
    echo "NOT CAUGHT: $rel (marker not found in scratch copy)"
    FAIL=1
    rm -rf "$dest"
    return
  fi
  local out status
  out="$(bash "$dest/tests/test_bug_route_handoff.sh" 2>&1)"
  status=$?
  if [ "$status" -ne 0 ] && printf '%s\n' "$out" | grep -qF "$rel"; then
    echo "CAUGHT: $rel"
    CAUGHT=$((CAUGHT+1))
  else
    echo "NOT CAUGHT: $rel (exit=$status)"
    printf '%s\n' "$out"
    FAIL=1
  fi
  rm -rf "$dest"
}

# Negative control: an unmutated copy of the repo must pass the drift test.
# Without this, a structural break in the drift test itself (wrong path, a
# check that always short-circuits true) would make every mutation below
# report CAUGHT while proving nothing.
run_control() {
  local dest="$SCRATCH_ROOT/control"
  copy_tree "$dest"
  if [ "${MUTATION_HARNESS_SELFTEST:-0}" = "1" ]; then
    # Self-test: deliberately break the control copy's drift test so this
    # control is itself falsifiable — if corrupting it doesn't turn the
    # drift test red, the control was never asserting anything.
    printf '\nthis line is not valid bash(\n' >> "$dest/tests/test_bug_route_handoff.sh"
  fi
  local out status
  out="$(bash "$dest/tests/test_bug_route_handoff.sh" 2>&1)"
  status=$?
  if [ "$status" -eq 0 ]; then
    echo "CONTROL: drift test passes on an unmutated copy"
  else
    echo "CONTROL FAILED: drift test did not pass on an unmutated copy (exit=$status)"
    printf '%s\n' "$out"
    FAIL=1
  fi
  rm -rf "$dest"
}
run_control

# 1. agents/debugger.md — the whole REPRO COMMAND: report-line paragraph.
run_mutation "agents/debugger.md" "debugger" "paragraph" "REPRO COMMAND:"

# 2. agents/orchestrator.md — the symptom row's carried-forward clause only
# (the row's pre-existing "actionable first sentence" instruction is left in
# place, since that sentence is not the prose under test here).
run_mutation "agents/orchestrator.md" "orchestrator" "row-suffix" "Relay its actionable first sentence verbatim."

# 3. agents/builder.md — the whole repair-stance paragraph.
run_mutation "agents/builder.md" "builder" "paragraph" "Repairing a diagnosed bug"

# 4. agents/verifier.md — the whole reproduction-command diff-inspection
# paragraph.
run_mutation "agents/verifier.md" "verifier" "paragraph" "When an acceptance criterion's Check is a reproduction"

# 5. skills/agent-workforce/SKILL.md — the whole criteria-authoring
# paragraph, which is where the mirrored REPRO COMMAND source lives.
run_mutation "skills/agent-workforce/SKILL.md" "workforce_skill" "paragraph" "Author every builder phase's"

rm -rf "$SCRATCH_ROOT"

echo "caught=$CAUGHT"
[ "$FAIL" -eq 0 ] && [ "$CAUGHT" -eq 5 ]
