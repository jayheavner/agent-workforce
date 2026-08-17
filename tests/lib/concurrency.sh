#!/usr/bin/env bash
# tests/lib/concurrency.sh — a real multi-process race harness for the work
# register (plans/2026-08-17-workspace-isolation-work-register.md, Task 1).
#
# Mutual exclusion in the register is the filesystem's atomic create, and the only
# honest way to test that is with real operating-system processes racing it. A
# sequential loop proves nothing: it would pass against a check-then-write
# implementation that loses every real race. So every claimant here is its own
# `bash` process, started with `&`, and ALL of them are started before any one of
# them is waited on.
#
# Sourced by tests/test_register_concurrency.sh (and available to the acceptance
# suite's own equivalent). Sourcing defines functions only.

CONCURRENCY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONCURRENCY_REGISTER_SH="$CONCURRENCY_LIB_DIR/../../hooks/agent-team-register.sh"

# spawn_claimants <n> <register-dir> <project-root> <slug>
#
# Starts <n> background processes, each running the register's `claim` subcommand
# against <project-root>/<slug> with AGENT_TEAM_REGISTER_DIR=<register-dir> and its
# own distinct session id, and each writing its exit status to
# <register-dir>/../out/<i>.rc (with the claim's own output beside it at
# <i>.out, so a failure can be explained rather than just counted). Waits for all
# of them, then prints the output directory.
spawn_claimants() {
  local n="$1" regdir="$2" proj="$3" slug="$4"
  local outdir i pids=() p
  outdir="$(dirname "$regdir")/out"
  mkdir -p "$outdir" || return 1
  for ((i = 1; i <= n; i++)); do
    (
      AGENT_TEAM_REGISTER_DIR="$regdir" \
        bash "$CONCURRENCY_REGISTER_SH" claim "$proj" "$slug" "sess-claimant-$i" \
        > "$outdir/$i.out" 2>&1
      printf '%s\n' "$?" > "$outdir/$i.rc"
    ) &
    pids+=("$!")
  done
  # Every claimant is already running by the time the first wait is issued.
  for p in "${pids[@]}"; do
    wait "$p" 2>/dev/null
  done
  printf '%s' "$outdir"
}

# assert_exactly_one_winner <out-dir> [expected-total]
#
# Exactly one claimant may exit 0; every other must exit 3 ("held"). Anything else
# — a missing status file, a crash, a second winner — is a failure that names what
# it saw. Prints the one report line for the case and returns 0 on pass.
assert_exactly_one_winner() {
  local outdir="$1" total="${2:-20}"
  local label="exactly one of twenty claimants wins"
  local i rc winners=0 refusals=0 others="" detail
  for ((i = 1; i <= total; i++)); do
    if [ ! -f "$outdir/$i.rc" ]; then
      others="$others [$i:no-rc-file]"
      continue
    fi
    rc="$(cat "$outdir/$i.rc")"
    case "$rc" in
      0) winners=$((winners + 1)) ;;
      3) refusals=$((refusals + 1)) ;;
      *)
        detail="$(head -c 80 "$outdir/$i.out" 2>/dev/null | tr '\n\t' '  ')"
        others="$others [$i:exit=$rc $detail]"
        ;;
    esac
  done
  if [ "$winners" -eq 1 ] && [ "$refusals" -eq $((total - 1)) ]; then
    printf 'PASS [%s]\n' "$label"
    return 0
  fi
  printf 'FAIL [%s]: winners=%s refusals=%s other=%s\n' \
    "$label" "$winners" "$refusals" "${others:-none}"
  return 1
}
