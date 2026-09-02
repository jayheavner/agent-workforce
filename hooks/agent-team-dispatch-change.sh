#!/usr/bin/env bash
# hooks/agent-team-dispatch-change.sh — the dispatch guard's workspace half: a
# `CHANGE: <slug>` declaration claims that change in the work register, and this hook
# creates or adopts its worktree as a side effect of the dispatch.
#
# Why it lives beside the guard rather than inside it: the guard already carries the
# specialist allowlist, the criteria floor, the lane-refusal routing and the budget
# ratchet, and this half pushed it past the project's file-size discipline. Nothing else
# moved.
#
# Sourced by agent-team-dispatch-guard.sh, which owns the marker constants this reads
# (CHANGE_MARKER_PREFIX, WORKTREE_MARKER_PREFIX, PARALLEL_SAFE_MARKER,
# CHANGE_REQUIRED_ROLES, the retired literal, OVERRIDE_MARKER) and the helpers it calls
# (guard_log, human_override_paths).
# Sourcing defines two functions and does nothing else; `dispatch_change_gate` does the
# work. It deliberately runs in the guard's own variable space rather than declaring
# everything local, so a refusal here is the guard's own `exit 2` — a workspace that
# cannot be claimed is a dispatch that must not start.
#
# Exit: returns 0 when the dispatch may proceed; exits 2 (block) on every refusal.

# Has the human, in their own turn, released this change? The lane refusals' override
# marker is extended to workspace claims, and only a human turn counts — an
# orchestrator that can clear its own refusals is not being held to anything.
change_released_by_human() { # $1 slug
  { [ -n "${TRANSCRIPT:-}" ] && [ -f "$TRANSCRIPT" ]; } || return 1
  local released
  while IFS= read -r released; do
    [ -n "$released" ] || continue
    [ "$released" = "$1" ] && return 0
  done <<EOF
$(human_override_paths)
EOF
  return 1
}

# The `<marker> <value>` line at the start of a line in the prompt, value only: everything
# after the marker to the end of the line with surrounding blanks trimmed, first such line.
# "Bad Slug" stays malformed and is refused as such rather than squeezed into a legal name.
dispatch_declared_line() { # $1 marker
  printf '%s\n' "$PROMPT" | sed -n "s/^${1}[[:space:]]*//p" | head -n1 | sed -e 's/[[:space:]]*$//'
}

# Is the marker present at the start of some line at all? Presence is decided separately
# from the value: a bare marker with nothing after it was once silently ignored, which is
# precisely the outcome the "refused, never ignored" rule forbids. A two-arm `case` matches
# the marker at the very start or immediately after a newline — no subprocess, no regular
# expression, and the literal cannot be misinterpreted.
dispatch_marker_present() { # $1 marker
  case "$PROMPT" in
    "$1"* | *$'\n'"$1"*) return 0 ;;
  esac
  return 1
}

# The worktree the human named, validated before anything is claimed: absolute, on disk,
# canonicalised, not the shared checkout, and one git lists for this project. Sets
# DECLARED_WORKTREE to the canonical path — set in the guard's own shell, never printed
# from a subshell, because an `exit 2` inside a command substitution ends only the
# substitution and the dispatch would then proceed. The path is checked HERE, not left to
# workspace_ensure, so a bad path claims nothing and there is nothing to release.
dispatch_named_worktree_gate() { # $1 declared path -> sets DECLARED_WORKTREE
  local canon listed
  case "$1" in
    /*) ;;
    *)
      guard_log dispatch "$TYPE" block "relative WORKTREE: path: $1"
      printf 'agent-team dispatch guard: the line "%s %s" names a relative path, and a relative path means something different in the shared checkout and in a worktree, so it cannot name a workspace. Write the absolute path of the worktree.\n' \
        "$WORKTREE_MARKER_PREFIX" "$1" >&2
      exit 2
      ;;
  esac
  if [ ! -d "$1" ]; then
    guard_log dispatch "$TYPE" block "WORKTREE: path missing on disk: $1"
    printf 'agent-team dispatch guard: the line "%s %s" names a directory that does not exist, so nothing was claimed. Name a worktree that exists — git -C %s worktree list shows the ones git knows — or drop the line so the worktree is created at %s.\n' \
      "$WORKTREE_MARKER_PREFIX" "$1" "$PROJECT_ROOT" "$(register_worktree_path "$PROJECT_ROOT" "$DECLARED_CHANGE")" >&2
    exit 2
  fi
  canon="$(cd "$1" && pwd -P)"
  if [ "$canon" = "$PROJECT_ROOT" ]; then
    guard_log dispatch "$TYPE" block "WORKTREE: names the shared checkout: $1"
    printf 'agent-team dispatch guard: the line "%s %s" names the shared checkout itself, which is not a worktree and isolates nothing, so nothing was claimed. Name a linked worktree — git -C %s worktree list shows them — or drop the line so one is created at %s.\n' \
      "$WORKTREE_MARKER_PREFIX" "$1" "$PROJECT_ROOT" "$(register_worktree_path "$PROJECT_ROOT" "$DECLARED_CHANGE")" >&2
    exit 2
  fi
  if ! listed="$(workspace_lookup_worktree "$PROJECT_ROOT" "$canon")"; then
    guard_log dispatch "$TYPE" block "WORKTREE: path is not a registered worktree: $1"
    printf 'agent-team dispatch guard: the line "%s %s" names a directory that git does not list as a worktree of %s, so nothing was claimed. This guard adopts only a worktree git already knows. See them with: git -C %s worktree list. Name one of those, or drop the line so the worktree is created at %s.\n' \
      "$WORKTREE_MARKER_PREFIX" "$1" "$PROJECT_ROOT" "$PROJECT_ROOT" "$(register_worktree_path "$PROJECT_ROOT" "$DECLARED_CHANGE")" >&2
    exit 2
  fi
  guard_log dispatch "$TYPE" note "change=$DECLARED_CHANGE adopts the human-named worktree $canon at ${listed:-detached}"
  DECLARED_WORKTREE="$canon"
}

dispatch_change_gate() {
  # In order: refuse the retired declaration; read the change this dispatch declares and
  # the worktree it names, if any; require a change from every role that writes; then
  # claim it, build or adopt its worktree, mark it ready, and take the writer slot. Each
  # step's own refusal names the durable fact it rests on and the one line or command
  # that clears it.
  PROMPT="$(printf '%s' "$PARSED" | jq -r '.tool_input.prompt // empty')"
  TRANSCRIPT="$(printf '%s' "$PARSED" | jq -r '.transcript_path // empty')"

  # The retired declaration is REFUSED, never ignored. A line the runtime no longer reads
  # is worse than no line at all: on 2026-08-04 seven dispatches were spent on a
  # declaration that looked enforced and was not.
  case "$PROMPT" in
    *"$RETIRED_PARALLEL_SAFE"*)
      guard_log dispatch "$TYPE" block "retired PARALLEL_SAFE literal"
      printf 'agent-team dispatch guard: this dispatch carries the retired line "%s". Its meaning changed, so the literal changed with it: the assertion is now that the dispatch writes NOTHING AT ALL, not merely that it runs no git command, and the worktree guard verifies that rather than trusting it. Use the exact line:\n  %s\nIf this dispatch does write, declare its change instead:\n  %s <slug>\n' \
        "$RETIRED_PARALLEL_SAFE" "$PARALLEL_SAFE_MARKER" "$CHANGE_MARKER_PREFIX" >&2
      exit 2
      ;;
  esac

  # The change this dispatch declares, and the worktree it names, if any.
  DECLARED_CHANGE="$(dispatch_declared_line "$CHANGE_MARKER_PREFIX")"
  DECLARED_WORKTREE="$(dispatch_declared_line "$WORKTREE_MARKER_PREFIX")"

  # A WORKTREE: line is honoured, and so it is held to a shape: a path after it, and a
  # CHANGE: line beside it. A bare marker is refused rather than ignored — "refused, never
  # ignored" — and a place with no change is refused because there is nothing to claim,
  # and a claim is what confines the agent to the place.
  if dispatch_marker_present "$WORKTREE_MARKER_PREFIX"; then
    if [ -z "$DECLARED_WORKTREE" ]; then
      guard_log dispatch "$TYPE" block "bare WORKTREE: line with no path"
      printf 'agent-team dispatch guard: this dispatch carries a "%s" line with nothing after it. That line names the existing worktree the change works in, so it needs the absolute path — or it should be dropped, in which case the worktree is created at <project>/.claude/worktrees/<slug>. Either:\n  %s <absolute path of an existing worktree>\nbeside the %s <slug> line, or no such line at all.\n' \
        "$WORKTREE_MARKER_PREFIX" "$WORKTREE_MARKER_PREFIX" "$CHANGE_MARKER_PREFIX" >&2
      exit 2
    fi
    if [ -z "$DECLARED_CHANGE" ]; then
      guard_log dispatch "$TYPE" block "WORKTREE: line without a CHANGE: line"
      printf 'agent-team dispatch guard: this dispatch names a worktree but no change. The worktree is where a change works; the change is what is claimed in the work register, and the claim is what confines the agent to that worktree — so the path alone enforces nothing. Add the line:\n  %s <slug>\nand keep the %s line beside it; the guard then adopts that worktree for the change instead of creating one.\n' \
        "$CHANGE_MARKER_PREFIX" "$WORKTREE_MARKER_PREFIX" >&2
      exit 2
    fi
  fi

  CHANGE_REQUIRED=0
  for name in $CHANGE_REQUIRED_ROLES; do
    if [ "$TYPE" = "$name" ]; then
      CHANGE_REQUIRED=1
      break
    fi
  done

  if [ -z "$DECLARED_CHANGE" ] && [ "$CHANGE_REQUIRED" -eq 1 ]; then
    case "$PROMPT" in
      *"$PARALLEL_SAFE_MARKER"*) : ;;
      *)
        guard_log dispatch "$TYPE" block "no change declared"
        printf 'agent-team dispatch guard: a %s dispatch must say which change it works on, because policy:workspace-isolation gives every change its own worktree and admits one writer at a time — and this guard cannot claim a workspace for a dispatch that names none. Add one line:\n  %s <slug>\nThe slug is lower-case letters, digits, dot, dash and underscore; the worktree is created for you at <project>/.claude/worktrees/<slug> on refs/heads/change/<slug>, or adopted when this change already has one. When the human named an existing worktree, add a second line beside it — %s <absolute path> — and that worktree is adopted instead. If this dispatch genuinely writes nothing anywhere, say so with the exact line instead:\n  %s\n' \
          "$TYPE" "$CHANGE_MARKER_PREFIX" "$WORKTREE_MARKER_PREFIX" "$PARALLEL_SAFE_MARKER" >&2
        exit 2
        ;;
    esac
  fi

  if [ -n "$DECLARED_CHANGE" ]; then
    GUARD_DIR="$(cd "$(dirname "$0")" && pwd)"
    WORKSPACE_LIB="$GUARD_DIR/agent-team-workspace.sh"
    REGISTER_CLI="$GUARD_DIR/agent-team-register.sh"
    # Sourcing the workspace library defines the register too, and its own source STATUS
    # is the answer: a library whose sibling is missing defines nothing and returns
    # non-zero, and continuing from there fails later on a missing function with the
    # wrong message and the wrong exit code.
    # shellcheck source=hooks/agent-team-workspace.sh
    if [ ! -r "$WORKSPACE_LIB" ] || ! . "$WORKSPACE_LIB"; then
      guard_log dispatch "$TYPE" block "workspace library unusable"
      printf 'agent-team dispatch guard: this dispatch declares the change "%s", and %s could not be loaded, so no claim can be made and no worktree can be built — the install is incomplete. Blocking rather than failing open; re-run: bash install.sh\n' \
        "$DECLARED_CHANGE" "$WORKSPACE_LIB" >&2
      exit 2
    fi
    if ! register_valid_slug "$DECLARED_CHANGE"; then
      guard_log dispatch "$TYPE" block "malformed change slug: $DECLARED_CHANGE"
      printf 'agent-team dispatch guard: "%s" is not a legal change slug, so nothing was claimed and nothing was created. A slug is lower-case letters, digits, dot, dash and underscore, starts with a letter or a digit, is at most 64 characters, and can never contain a path separator or "..", because the worktree path and the ref name are derived from it. For the same reason it may not end in a dot or in ".lock" — git refuses those as ref names. Re-issue the dispatch with one line:\n  %s <slug>\n' \
        "$DECLARED_CHANGE" "$CHANGE_MARKER_PREFIX" >&2
      exit 2
    fi
    CWD="$(printf '%s' "$PARSED" | jq -r '.cwd // empty')"
    PROJECT_ROOT=""
    if [ -n "$CWD" ] && [ -d "$CWD" ]; then
      PROJECT_ROOT="$(register_project_root "$CWD" 2>/dev/null || printf '')"
    fi
    if [ -z "$PROJECT_ROOT" ]; then
      guard_log dispatch "$TYPE" block "no project root for change $DECLARED_CHANGE"
      printf 'agent-team dispatch guard: this dispatch declares the change "%s", but the directory it would run in (%s) is in no git repository, so there is no project for the claim to belong to and no checkout to build a worktree from. Issue the dispatch from inside the project, or drop the declaration if this dispatch writes nothing.\n' \
        "$DECLARED_CHANGE" "${CWD:-none supplied by the harness}" >&2
      exit 2
    fi
    # A named worktree is validated before the claim, so a bad path claims nothing.
    if [ -n "$DECLARED_WORKTREE" ]; then
      dispatch_named_worktree_gate "$DECLARED_WORKTREE"
    fi
    SESSION_ID="$(printf '%s' "$PARSED" | jq -r '.session_id // empty')"
    if [ -z "$SESSION_ID" ]; then
      # No id in the payload: identity falls back to the session PROCESS, which is unique
      # to it and cannot be shared with another session. A resumed session gets a new
      # one, so its pre-resume card is reaped by liveness instead of adopted — the safe
      # direction, and never two sessions holding one identity.
      SESSION_PROCESS="$(register_session_process 2>/dev/null || printf '')"
      if [ -z "$SESSION_PROCESS" ]; then
        guard_log dispatch "$TYPE" block "no session identity for change $DECLARED_CHANGE"
        printf 'agent-team dispatch guard: this dispatch payload carries no session_id and this hook cannot resolve the session process either, so a claim on "%s" could be attributed to nobody and released by nobody. Blocking rather than writing an unattributable claim. Re-issue the dispatch; if it recurs, the harness is not passing session_id and that is the repair.\n' \
          "$DECLARED_CHANGE" >&2
        exit 2
      fi
      SESSION_ID="process:$(printf '%s' "$SESSION_PROCESS" | tr '\t' ':')"
    fi

    # Reap first: a claim whose session process is gone is not a holder, and no dispatch
    # should ever wait on one. Then claim — the exclusive create is what decides.
    register_reap "$PROJECT_ROOT" >/dev/null 2>&1 || :
    CARD="$(register_card_path "$PROJECT_ROOT" "$DECLARED_CHANGE" 2>/dev/null || printf '')"
    # Whether the card is one THIS hook wrote decides who may release it if the tree then
    # fails to build: a card that was already here belongs to an earlier dispatch of this
    # same session, which may still be working in the tree.
    CARD_EXISTED=0
    if [ -n "$CARD" ] && [ -f "$CARD" ]; then CARD_EXISTED=1; fi
    SLOT_FILE=""
    [ -n "$CARD" ] && SLOT_FILE="$(dirname "$CARD")/writers/$(basename "$CARD")"
    CLAIM_OUT="$(register_claim "$PROJECT_ROOT" "$DECLARED_CHANGE" "$SESSION_ID" "$DECLARED_WORKTREE" 2>&1)"
    CLAIM_RC=$?

    if [ "$CLAIM_RC" -eq 3 ] && change_released_by_human "$DECLARED_CHANGE"; then
      # The human, in their own turn, released this slug. That is the only authority that
      # can take a live claim from another session, and it is recorded as the fail-open it
      # is: the card and its writer slot go, and this dispatch claims the change fresh, so
      # there is exactly one holder afterwards.
      guard_log dispatch "$TYPE" fail-open \
        "human override of the claim refusal for change $DECLARED_CHANGE, held by $(printf '%s' "$CLAIM_OUT" | jq -r '.session // "an unnamed session"' 2>/dev/null)"
      rm -f "$CARD" ${SLOT_FILE:+"$SLOT_FILE"}
      CARD_EXISTED=0
      CLAIM_OUT="$(register_claim "$PROJECT_ROOT" "$DECLARED_CHANGE" "$SESSION_ID" "$DECLARED_WORKTREE" 2>&1)"
      CLAIM_RC=$?
    fi

    if [ "$CLAIM_RC" -eq 3 ]; then
      HOLD_SESSION="$(printf '%s' "$CLAIM_OUT" | jq -r '.session // "an unnamed session"' 2>/dev/null)"
      HOLD_WORKTREE="$(printf '%s' "$CLAIM_OUT" | jq -r '.worktree // empty' 2>/dev/null)"
      HOLD_OPENED="$(printf '%s' "$CLAIM_OUT" | jq -r '.opened // empty' 2>/dev/null)"
      HOLD_HEARTBEAT="$(printf '%s' "$CLAIM_OUT" | jq -r '.heartbeat // empty' 2>/dev/null)"
      HOLD_AGE="an unknown time"
      case "$HOLD_HEARTBEAT" in
        '' | *[!0-9]*) ;;
        *) HOLD_AGE="$(( ( $(date +%s) - HOLD_HEARTBEAT ) / 60 )) minutes since its last heartbeat" ;;
      esac
      guard_log dispatch "$TYPE" block "change $DECLARED_CHANGE held by $HOLD_SESSION"
      printf 'agent-team dispatch guard: the change "%s" is held by another live session, so this %s dispatch may not claim it — one change, one owning session, and that fact is on disk rather than inferred. The holder: session %s, held since %s (%s), working in %s. Its timecard is %s.\nTwo escapes. Wait: the claim is released when that session integrates the change, and it is reaped automatically by the next dispatch once that session process exits — nothing has to be cleaned up by hand. Or, if you believe this refusal is wrong, say so and stop; only your human can release it, by writing this line in their own message:\n  %s | %s\nDo not write that line yourself; a line authored by you is not read as an override.\n' \
        "$DECLARED_CHANGE" "$TYPE" "$HOLD_SESSION" "${HOLD_OPENED:-an unrecorded time}" "$HOLD_AGE" \
        "${HOLD_WORKTREE:-a worktree it did not record}" "${CARD:-its timecard}" \
        "$OVERRIDE_MARKER" "$DECLARED_CHANGE" >&2
      exit 2
    fi
    if [ "$CLAIM_RC" -ne 0 ]; then
      guard_log dispatch "$TYPE" block "claim of $DECLARED_CHANGE failed with $CLAIM_RC"
      printf 'agent-team dispatch guard: the change "%s" could not be claimed for this %s dispatch, so it has no workspace and was not started. The register said:\n%s\nThe repair is named in that line; re-issue this dispatch once it is done.\n' \
        "$DECLARED_CHANGE" "$TYPE" "$CLAIM_OUT" >&2
      exit 2
    fi

    # Which membership branch resolved an EXISTING claim is the one question this design
    # left to evidence rather than to an unverified harness detail: a subagent's payload
    # may or may not carry its parent session's id, and both branches are meant to carry
    # the case. Recorded only on that path, so the refusal log is not filled with routine
    # allows that answer nothing.
    if [ "$CARD_EXISTED" -eq 1 ]; then
      guard_log dispatch "$TYPE" note "change=$DECLARED_CHANGE resolved an existing claim: membership=$(register_mine "$PROJECT_ROOT" "$DECLARED_CHANGE" "$SESSION_ID" 2>/dev/null | head -n1)"
    fi

    # The card is the authority on WHERE the change works. A first claim recorded the
    # named worktree, if any; a later dispatch of the same change may omit the line and
    # still lands there, and one that names a DIFFERENT worktree is refused — one change,
    # one worktree, and the claim is left exactly as it was.
    CARD_WT="$(jq -r '.worktree // empty' "$CARD" 2>/dev/null)"
    CARD_ADOPTED="$(jq -r '.adopted // false' "$CARD" 2>/dev/null)"
    if [ -n "$DECLARED_WORKTREE" ] && [ "$CARD_EXISTED" -eq 1 ] && [ "$DECLARED_WORKTREE" != "$CARD_WT" ]; then
      guard_log dispatch "$TYPE" block "change $DECLARED_CHANGE works in $CARD_WT, dispatch named $DECLARED_WORKTREE"
      printf 'agent-team dispatch guard: the change "%s" already works in %s, and this dispatch names a different worktree, %s. One change has one worktree, so this dispatch was not started and the claim is unchanged. Either drop the %s line — the dispatch then lands in %s — or declare a different change for the other worktree.\n' \
        "$DECLARED_CHANGE" "$CARD_WT" "$DECLARED_WORKTREE" "$WORKTREE_MARKER_PREFIX" "$CARD_WT" >&2
      exit 2
    fi

    # Ordering is claim first, tree second, ready third: a card without a tree is reaped
    # by liveness, a tree without a card is reported by hygiene, and a card only reaches
    # "ready" once its workspace exists. An adopted worktree is handed to ensure as the
    # card records it, so nothing is created and nothing is derived.
    BASE_REF="$(jq -r '.base_ref // empty' "$CARD" 2>/dev/null)"
    [ -n "$BASE_REF" ] || BASE_REF="$(git -C "$PROJECT_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || printf '')"
    [ -n "$BASE_REF" ] || BASE_REF=HEAD
    if [ "$CARD_ADOPTED" = true ]; then
      ENSURE_OUT="$(workspace_ensure "$PROJECT_ROOT" "$DECLARED_CHANGE" "$BASE_REF" "$CARD_WT" 2>&1)"
    else
      ENSURE_OUT="$(workspace_ensure "$PROJECT_ROOT" "$DECLARED_CHANGE" "$BASE_REF" 2>&1)"
    fi
    ENSURE_RC=$?
    if [ "$ENSURE_RC" -ne 0 ]; then
      # Window A: a claim whose tree then failed to build must not be left behind a live
      # process, or the slug is held by a dispatch that never ran. The card this hook just
      # wrote is released here, by this hook, in this run.
      if [ "$CARD_EXISTED" -eq 0 ]; then
        register_release "$PROJECT_ROOT" "$DECLARED_CHANGE" "$SESSION_ID" >/dev/null 2>&1 || :
        RELEASE_NOTE="The claim this dispatch wrote has been released, so the same declaration works again the moment that is repaired."
      else
        RELEASE_NOTE="The claim was already this session's and is left as it is, so the same declaration retries once that is repaired."
      fi
      guard_log dispatch "$TYPE" block "workspace_ensure failed for $DECLARED_CHANGE"
      printf 'agent-team dispatch guard: the workspace for the change "%s" could not be built, so this %s dispatch has nowhere to work and was not started. The workspace library said:\n%s\n%s\n' \
        "$DECLARED_CHANGE" "$TYPE" "$ENSURE_OUT" "$RELEASE_NOTE" >&2
      exit 2
    fi
    if ! register_ready "$PROJECT_ROOT" "$DECLARED_CHANGE" >/dev/null 2>&1; then
      guard_log dispatch "$TYPE" fail-open \
        "the timecard for $DECLARED_CHANGE could not be marked ready, though its worktree exists"
    fi

    # A slot nobody is behind goes here, before the next one is named. The position is
    # load-bearing: the reap at the top of this run has already swept the one obstacle a
    # correctly named release can hit, the claim has succeeded so the change is
    # established as this session's, and DISPLACED_SLOT is read AFTER the release, so a
    # slot this guard released is never then reported as a TTL displacement — a release is
    # routine, a displacement is a control that stopped enforcing. It runs for EVERY
    # declaring dispatch, judge included: "nobody is working in this change" is a
    # role-independent fact, and a judge clearing a finished builder's slot is correct.
    WRITER_ROLE=0
    for wrole in $WRITER_SLOT_ROLES; do
      if [ "$TYPE" = "$wrole" ]; then
        WRITER_ROLE=1
        break
      fi
    done
    release_resolved_writer_slot "$PROJECT_ROOT" "$DECLARED_CHANGE"

    # The writer slot is named per dispatch of a role in a change, so two builders
    # repairing one change hold distinct names and the second is refused while the first
    # is live. <n> is how many dispatches of this role for this slug the transcript
    # already holds; this dispatch is not in it yet, so the first one is #0. Only a role
    # that holds the writing turn takes one.
    if [ "$WRITER_ROLE" -eq 1 ]; then
      PRIOR_ROLE_DISPATCHES=0
      if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
        PRIOR_ROLE_DISPATCHES="$(
          jq -rs --arg role "$TYPE" --arg marker "$CHANGE_MARKER_PREFIX" --arg slug "$DECLARED_CHANGE" '
            [ .[]
              | ((.message.content // []) | if type == "array" then . else [] end)[]
              | select(.type == "tool_use" and .name == "Agent")
              | (((.input.subagent_type // "") | sub("^agent-workforce:"; "")) as $r
                 | ((.input.prompt // "")
                    | [ splits("\n") ]
                    | map(select(startswith($marker)))
                    | if length == 0 then ""
                      else (.[0] | ltrimstr($marker) | sub("^[ \t]+"; "") | sub("[ \t]+$"; "")) end) as $s
                 | select($r == $role and $s == $slug))
            ] | length
          ' "$TRANSCRIPT" 2>/dev/null
        )"
        case "$PRIOR_ROLE_DISPATCHES" in '' | *[!0-9]*) PRIOR_ROLE_DISPATCHES=0 ;; esac
      fi
      WRITER_SLOT="$TYPE#$PRIOR_ROLE_DISPATCHES"
      # The slot NAME cannot tell two dispatches apart when the count behind it is not
      # reproducible: two builders on one change, dispatched before either reached the
      # transcript, both compute `builder#0`, and the acquire then read the second one as
      # the first re-entering and granted both the writing turn. Session and the card's
      # `opened` stamp do not separate them either — one session, one claim incarnation.
      # What does is the dispatch itself, and the only per-dispatch fact this hook holds
      # is the prompt it is processing: PreToolUse carries no dispatch identifier. So the
      # slot records a digest of that prompt, and re-entry requires it to match. Two
      # byte-identical prompts remain indistinguishable — that is the residual, stated
      # rather than hidden, and it is the same one change_dispatches_in_flight lives
      # with; an unavailable digest tool degrades to the old behaviour rather than
      # refusing an honest dispatch.
      DISPATCH_ID="$(printf '%s' "$PROMPT" | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"
      DISPATCH_ID="${DISPATCH_ID:0:16}"
      # Read before acquiring: a grant that displaced somebody is a control that stopped
      # enforcing, and it must be recorded as loudly as a refusal. Existence of the FILE is
      # what makes it a displacement — a slot whose JSON cannot be read is still a slot
      # somebody was behind — and BOTH the name and the dispatch digest are kept, because
      # the name alone cannot tell two dispatches apart: that is why the digest exists, and
      # keying the record on the name alone made a displacement silent in exactly the case
      # the digest was added for. CHANGE_FLIGHT, already counted by the release above, goes
      # to the acquire so it refuses to displace a writer whose dispatch is still running.
      HELD_BEFORE=0
      DISPLACED_SLOT=""
      DISPLACED_DISPATCH=""
      if [ -n "$SLOT_FILE" ] && [ -f "$SLOT_FILE" ]; then
        HELD_BEFORE=1
        DISPLACED_SLOT="$(jq -r '.slot // empty' "$SLOT_FILE" 2>/dev/null || printf '')"
        DISPLACED_DISPATCH="$(jq -r '.dispatch // empty' "$SLOT_FILE" 2>/dev/null || printf '')"
      fi
      WRITER_OUT="$(register_writer_acquire "$PROJECT_ROOT" "$DECLARED_CHANGE" "$WRITER_SLOT" \
        "$DISPATCH_ID" "${CHANGE_FLIGHT:-unknown}" 2>&1)"
      WRITER_RC=$?
      if [ "$WRITER_RC" -ne 0 ]; then
        guard_log dispatch "$TYPE" block "writer slot $WRITER_SLOT for $DECLARED_CHANGE refused"
        printf 'agent-team dispatch guard: the change "%s" already has a live writer, and one change admits one writer at a time — the worktree is shared, the writing turn is not. The register said:\n%s\nTwo escapes. Wait for that writer to finish: its own agent frees the slot with\n  bash %s writer-release %s %s <the slot it holds>\nIts slot is also released automatically by the next dispatch for this change once that agent'"'"'s own dispatch has finished, so a sequence of dispatches on one change needs nothing done by hand. Or let it lapse: a writer that died without releasing the slot is displaced automatically once its heartbeat is older than writer_ttl_seconds in %s/agent-team-register.json AND no dispatch of this change is still in flight — a lapsed heartbeat alone never displaces a writer whose dispatch is still running, because nothing refreshes a heartbeat during work. The worktree %s is already built either way — nothing needs creating.\n' \
          "$DECLARED_CHANGE" "$WRITER_OUT" "$REGISTER_CLI" "$PROJECT_ROOT" "$DECLARED_CHANGE" \
          "$GUARD_DIR" "${CARD_WT:-$(register_worktree_path "$PROJECT_ROOT" "$DECLARED_CHANGE")}" >&2
        exit 2
      fi
      if [ "$HELD_BEFORE" -eq 1 ] && { [ "$DISPLACED_SLOT" != "$WRITER_SLOT" ] \
        || [ "$DISPLACED_DISPATCH" != "$DISPATCH_ID" ]; }; then
        guard_log dispatch "$TYPE" fail-open \
          "writer slot for $DECLARED_CHANGE displaced from ${DISPLACED_SLOT:-an unnamed slot} (dispatch ${DISPLACED_DISPATCH:-none recorded}) because its slot had lapsed — heartbeat past writer_ttl_seconds, or its session gone — with no dispatch of this change in flight; $WRITER_SLOT (dispatch ${DISPATCH_ID:-none recorded}) holds it now"
      fi
    fi
  fi
}
