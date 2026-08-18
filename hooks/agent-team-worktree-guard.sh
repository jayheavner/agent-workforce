#!/usr/bin/env bash
# agent-team-worktree-guard.sh <role> — enforces policy:workspace-isolation on every
# role that can write: a mutation is legal inside the worktree of the change this
# session has claimed, or inside a lane this role owns that lies outside every git
# working tree, and nowhere else.
#
# WHERE CONFINEMENT COMES FROM, and why that is the whole point of this file. Until
# 2026-08-04 it came from the transcript: a `WORKTREE: <path>` line read back by this
# guard, with no way to tell which of a main session's many declarations belonged to
# the agent that was acting. The answer it settled on was the first marker in the file
# — the OLDEST declaration the session ever made. One malformed path poisoned six
# later dispatches, each refused by a line written ninety minutes earlier, and no
# dispatch could have repaired it. The register replaced it: the candidate set is the
# live timecards THIS SESSION holds (register_session_claims), and this agent's own
# dispatch prompt is only a selector among them. More than one candidate with no
# selector is a refusal naming every candidate — never a pick by recency.
#
# Two events, one entrypoint (dispatched on hook_event_name):
#   PreToolUse(Write|Edit|NotebookEdit|Bash) — prevention. Reads are never gated, and
#     that is a property of the WIRING: the guard is registered on those four tools
#     only, so Read, Glob and Grep never reach it.
#   Stop|SubagentStop — evidence. It records what it found and refuses nothing: a
#     blocked Stop would tell an agent to repair a workspace this same guard refuses
#     it the tools to repair, so it could only loop. The workspace is built by the
#     dispatch guard before the agent runs, recorded on the timecard, and verified at
#     closeout.
#
# Two more rules, same events. The separately-authored acceptance suite is read-only
# to whoever writes the code, even inside the claimed worktree — and NOT read-only to
# the test-author, whose job is authoring it; its location is configuration
# (agent-team-lanes.json here, overridable in .workforce/project.json). And Bash
# cannot be classified as a read or a write by its tool name, so its rule is per role,
# in four sets (decision 11), with the classification one file over in
# agent-team-worktree-rules.sh and its limits stated there.
#
# Hook JSON on stdin. Exit 0 = allow. Exit 2 = block (stderr goes to the agent).
# Fail-closed: anything that leaves this guard unable to positively confirm a
# mutation is legal is a block, never a silent allow.
set -u

# Every role holding Write, Edit, NotebookEdit or Bash. The researcher and the
# ticketer are exempt with a reason: both deny those tools in frontmatter
# (disallowedTools), so there is nothing here to police. The orchestrator is the main
# session, policed by the dispatch guard.
readonly POLICED_ROLES="builder test-author architect scribe executor deployer verifier reviewer debugger ops"
# The four shell rules of decision 11's table.
readonly CHANGE_CONFINED_ROLES="builder test-author"
readonly INTEGRATOR_ROLES="executor deployer"
readonly JUDGE_ROLES="verifier reviewer debugger ops"
readonly NO_SHELL_ROLES="architect scribe"
readonly CHANGE_MARKER_PREFIX="CHANGE:"
readonly PARALLEL_SAFE_MARKER="PARALLEL_SAFE: this dispatch writes nothing"
readonly ACCEPTANCE_AUTHOR_ROLES="test-author"
# A missing config file is a broken install, never permission to edit your own bar.
readonly DEFAULT_ACCEPTANCE_PATHS="tests/acceptance"
readonly GUARD_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LANES_FILE="$GUARD_DIR/agent-team-lanes.json"
readonly WORKSPACE_ADMIN="agent-team-workspace.sh"
# shellcheck source=/dev/null
[ -r "$GUARD_DIR/agent-team-guard-log.sh" ] && . "$GUARD_DIR/agent-team-guard-log.sh"
command -v guard_log >/dev/null 2>&1 || guard_log() { :; }

ROLE="${1:-}"
POLICED=0
for name in $POLICED_ROLES; do
  [ "$ROLE" = "$name" ] && POLICED=1 && break
done
[ "$POLICED" -eq 1 ] || exit 0

in_set() { # $1 word $2 space-separated set
  local w
  for w in $2; do [ "$1" = "$w" ] && return 0; done
  return 1
}

# Every refusal in this guard has one shape: record the durable fact, say it with the
# repair, exit 2. Nothing here fails open.
refuse() { # $1 telemetry detail $2 message
  guard_log worktree "$ROLE" block "$1"
  printf 'agent-team worktree guard: %s\n' "$2" >&2
  exit 2
}

for lib in agent-team-worktree-rules.sh agent-team-lane-paths.sh agent-team-register.sh; do
  { [ -r "$GUARD_DIR/$lib" ] && . "$GUARD_DIR/$lib"; } || refuse "library missing: $lib" \
    "$GUARD_DIR/$lib is missing or unreadable beside this guard, so no mutation can be checked against policy:workspace-isolation — the install is incomplete. Blocking rather than failing open; re-run: bash install.sh"
done

command -v jq >/dev/null 2>&1 || refuse "jq unavailable" \
  "jq is not available, so this guard cannot parse the payload and cannot confirm any mutation is legal. Blocking rather than failing open. The repair is on the machine, not in your work: install jq (brew install jq, or the platform equivalent) and re-run. Report it if you cannot."

PARSED="$(cat | jq -c '.' 2>/dev/null)"
[ -n "$PARSED" ] || refuse "invalid payload" \
  "stdin was not valid JSON, so this action cannot be verified against policy:workspace-isolation. Blocking rather than failing open. Nothing in your work can fix this — the payload comes from the harness, so stop and report it as a harness defect."

EVENT="$(printf '%s' "$PARSED" | jq -r '.hook_event_name // empty')"
TOOL="$(printf '%s' "$PARSED" | jq -r '.tool_name // empty')"
CWD="$(printf '%s' "$PARSED" | jq -r '.cwd // empty')"
TRANSCRIPT="$(printf '%s' "$PARSED" | jq -r '.transcript_path // empty')"
SESSION_ID="$(printf '%s' "$PARSED" | jq -r '.session_id // empty')"

canonical_path() { wtr_canonical "$1" "${CWD:-$PWD}"; }
path_within() { wtr_within "$1" "$2"; }

# Acceptance-suite paths relative to the worktree root: this project's declaration,
# then the shipped config, then the built-in default.
acceptance_paths() { # $1 worktree
  local main="" override="" shipped=""
  if main="$(wtr_main_checkout "$1")" && [ -f "$main/.workforce/project.json" ]; then
    override="$(jq -r '.acceptance_suite_paths[]? // empty' "$main/.workforce/project.json" 2>/dev/null)"
  fi
  if [ -n "$override" ]; then printf '%s\n' "$override"; return 0; fi
  if [ -f "$LANES_FILE" ]; then
    shipped="$(jq -r '.acceptance_suite_paths[]? // empty' "$LANES_FILE" 2>/dev/null)"
    if [ -n "$shipped" ]; then printf '%s\n' "$shipped"; return 0; fi
  fi
  printf '%s\n' "$DEFAULT_ACCEPTANCE_PATHS"
}

# --- what this agent's OWN dispatch said ------------------------------------
# Read only from a transcript with zero `Agent` tool_use blocks — the structural test
# that it is a subagent's own file, since no dispatched specialist holds the Agent
# tool. A transcript with one is a main session's, where every declaration belongs to
# somebody else; refusing to read it is what keeps the recency scan retired.
own_transcript() {
  { [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; } || return 1
  [ "$(jq -rs '[ .[] | .. | objects
                 | select(.type? == "tool_use" and .name? == "Agent") ] | length' \
       "$TRANSCRIPT" 2>/dev/null)" = 0 ]
}

# The `CHANGE: <slug>` slug from this agent's own dispatch prompt, or nothing.
own_dispatch_change() {
  own_transcript || return 0
  jq -rs --arg m "$CHANGE_MARKER_PREFIX" '
    [ .[] | .. | strings | [ splits("\n") ] | .[]
      | select(startswith($m)) | ltrimstr($m) ] | first // empty
  ' "$TRANSCRIPT" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | head -n1
}

# Did this agent's own dispatch assert that it writes nothing? Exit 0 yes, 1 no,
# 3 unverifiable — a main session's transcript carries no assertion of this agent's.
# Unverifiable is recorded rather than trusted or refused, which bounds the failure to
# a write inside this session's own claimed tree, never another session's.
own_dispatch_parallel_safe() {
  own_transcript || return 3
  jq -rse --arg m "$PARALLEL_SAFE_MARKER" \
    '[ .[] | .. | strings | select(contains($m)) ] | length > 0' \
    "$TRANSCRIPT" >/dev/null 2>&1
}

# --- which change governs this agent ----------------------------------------
# Prints `<slug>\t<worktree>`, or the single word `none` or `ambiguous`. The register
# is the authority; the dispatch prompt is only a selector among what it holds.
resolve_change() {
  local claims count sel line
  [ -n "$PROJECT_ROOT" ] || { printf 'none'; return 0; }
  claims="$(register_session_claims "$PROJECT_ROOT" "$SESSION_ID" 2>/dev/null | sed -e '/^$/d')"
  CANDIDATES="$(printf '%s' "$claims" | cut -f1 | tr '\n' ' ' | sed -e 's/[[:space:]]*$//')"
  count="$(printf '%s\n' "$claims" | sed -e '/^$/d' | wc -l | tr -d ' ')"
  case "$count" in
    0) printf 'none'; return 0 ;;
    1) printf '%s' "$(printf '%s' "$claims" | cut -f1,2)"; return 0 ;;
  esac
  sel="$(own_dispatch_change)"
  if [ -n "$sel" ]; then
    while IFS= read -r line; do
      [ "$(printf '%s' "$line" | cut -f1)" = "$sel" ] || continue
      printf '%s' "$(printf '%s' "$line" | cut -f1,2)"
      return 0
    done <<EOF
$claims
EOF
  fi
  printf 'ambiguous'
}

PROJECT_ROOT=""
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  PROJECT_ROOT="$(register_project_root "$CWD" 2>/dev/null || printf '')"
fi
CANDIDATES=""
# resolve_change runs in a subshell, so the candidate list it built cannot come back in
# a variable. Both answers are returned in one string, separated by a byte no slug and
# no path can contain (US-ASCII 28, the field separator).
RESOLVED="$(resolve_change; printf '\034%s' "$CANDIDATES")"
CANDIDATES="${RESOLVED#*$'\034'}"
RESOLVED="${RESOLVED%%$'\034'*}"
CHANGE_SLUG=""
CHANGE_WT=""
case "$RESOLVED" in
  none | ambiguous) ;;
  *)
    CHANGE_SLUG="${RESOLVED%%$'\t'*}"
    CHANGE_WT="$(canonical_path "${RESOLVED#*$'\t'}")"
    ;;
esac
# A claim whose recorded worktree is not a registered linked worktree is not
# isolation, whatever the register says — and remediation belongs to the orchestrator,
# since this guard refuses the agent the git command that would build one.
TREE_BROKEN=0
[ -n "$CHANGE_WT" ] && ! wtr_is_linked_worktree "$CHANGE_WT" && TREE_BROKEN=1

refuse_ambiguous() { # $1 what is being refused
  local said="" sel
  sel="$(own_dispatch_change)"
  [ -n "$sel" ] && said="This dispatch does name a change — \"$sel\" — but no live claim of this session goes by that name, so it selects nothing. "
  guard_log worktree "$ROLE" block "ambiguous change: candidates $CANDIDATES, selector ${sel:-none}"
  printf 'agent-team worktree guard: this session holds more than one live change (%s), and %s cannot be confined until one of them is named as the change this dispatch belongs to. %sThis guard will not guess: guessing is what refused six correct dispatches on 2026-08-04, and a wrong guess aims your writes at the workspace of a peer. Stop and report to the orchestrator that this dispatch needs one line naming its change:\n  %s <one of: %s>\nThe other repair, when a change is finished, is to integrate it — bash %s/%s integrate <project> <slug> — which releases its claim and leaves exactly one candidate.\n' \
    "$CANDIDATES" "$1" "$said" "$CHANGE_MARKER_PREFIX" "$CANDIDATES" "$GUARD_DIR" "$WORKSPACE_ADMIN" >&2
  exit 2
}

refuse_broken_tree() { # $1 what is being refused
  guard_log worktree "$ROLE" block "not a linked worktree: $CHANGE_WT"
  printf 'agent-team worktree guard: the change "%s" records its workspace at %s, which is not a registered linked git worktree, so %s is not isolated from the shared checkout or from other changes. You cannot create it yourself — this guard confines you to that path and refuses git aimed outside it. Stop and report to the orchestrator that the workspace for "%s" is missing; building it before dispatch is its job (the dispatch guard does it), not yours.\n' \
    "$CHANGE_SLUG" "$CHANGE_WT" "$1" "$CHANGE_SLUG" >&2
  exit 2
}

case "$EVENT" in
  Stop | SubagentStop)
    case "$RESOLVED" in
      none) guard_log worktree "$ROLE" note "stop: this session holds no live claim" ;;
      ambiguous) guard_log worktree "$ROLE" note "stop: ambiguous change, candidates $CANDIDATES" ;;
      *)
        [ "$TREE_BROKEN" -eq 1 ] \
          && guard_log worktree "$ROLE" note \
               "stop: the workspace recorded for $CHANGE_SLUG ($CHANGE_WT) is not a linked worktree"
        ;;
    esac
    exit 0
    ;;
esac

# --- PreToolUse -------------------------------------------------------------
PARALLEL_SAFE=1
own_dispatch_parallel_safe
case "$?" in
  0) PARALLEL_SAFE=0 ;;
  3) guard_log worktree "$ROLE" note \
       "parallel-safe-unverifiable: the transcript handed to this guard is not this agent's own, so a PARALLEL_SAFE assertion could not be checked; judged by the timecard rule alone" ;;
esac

refuse_parallel_safe() { # $1 what is being refused
  guard_log worktree "$ROLE" block "PARALLEL_SAFE dispatch attempted $1"
  printf 'agent-team worktree guard: this dispatch carries the line "%s", and %s would write. That line is an assertion this guard verifies rather than trusts, so the write is refused and nothing was changed. Two honest repairs: if the work does write, stop and report that this dispatch must declare its change instead —\n  %s <slug>\n— or, if it genuinely writes nothing, do the read-only work and leave the file alone.\n' \
    "$PARALLEL_SAFE_MARKER" "$1" "$CHANGE_MARKER_PREFIX" >&2
  exit 2
}

# The lanes this role owns, one absolute pattern per line, measured in $1.
role_lane_patterns() { # $1 working tree root
  local lane
  while IFS= read -r lane; do
    [ -n "$lane" ] && printf '%s\n' "$(lane_pattern "$lane" "$1")"
  done <<EOF
$(lane_role_spec "$ROLE" "$1" "$LANES_FILE" | tr ':' '\n')
EOF
}

# Decision 7's two-branch legality rule, applied to a mutation target: 0 inside the
# resolved change's worktree; 1 covered by a lane this role owns that lies outside
# every git working tree; 2 covered by such a lane but inside a working tree, so it
# belongs to a change; 3 neither. Branch 1 is what keeps the scribe's agent-memory
# writes legal with NO claim at all — that directory is in no worktree and never can
# be, so "inside the claimed tree or nowhere" outlawed a write the workflow needs.
write_verdict() { # $1 canonical target -> prints the verdict number
  local target="$1" tree root pattern
  if [ -n "$CHANGE_WT" ] && path_within "$target" "$CHANGE_WT"; then
    printf '0'; return 0
  fi
  tree="$(wtr_working_tree "$target")"
  root="${tree:-${CHANGE_WT:-${PROJECT_ROOT:-/__no-working-tree__}}}"
  while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    if lane_covers "$target" "$pattern"; then
      [ -n "$tree" ] && printf '2' || printf '1'
      return 0
    fi
  done <<EOF
$(role_lane_patterns "$root")
EOF
  printf '3'
}

refuse_write() { # $1 target $2 what $3 verdict
  local why where
  where="the worktree of the change this session claimed"
  [ -n "$CHANGE_WT" ] && where="$CHANGE_WT (the change $CHANGE_SLUG)"
  if [ "$3" = 2 ]; then
    why="It is inside a lane the $ROLE owns, but that lane lies inside a git working tree, so the file belongs to a change rather than to the machine: a document lives with the change it documents. The repair is one line in this dispatch, which only the orchestrator can add:
  $CHANGE_MARKER_PREFIX <slug>
Stop and report that this dispatch needs it."
  else
    why="It is in no lane the $ROLE owns, and outside $where. policy:workspace-isolation confines every mutation to the worktree of the claimed change — never the shared checkout, never the worktree of another change. Either do the work inside $where, or stop and report the mismatch as a plan defect if it genuinely belongs elsewhere. If this dispatch has no change yet, the repair is one line only the orchestrator can add:
  $CHANGE_MARKER_PREFIX <slug>"
  fi
  guard_log worktree "$ROLE" block "$1"
  printf 'agent-team worktree guard: %s targets %s, which this dispatch may not write. %s\n' \
    "$2" "$1" "$why" >&2
  exit 2
}

case "$TOOL" in
  Write | Edit | NotebookEdit)
    TARGET_RAW="$(printf '%s' "$PARSED" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
    [ -n "$TARGET_RAW" ] || refuse "no file path in $TOOL" \
      "a $TOOL call carried no file path, so its target cannot be checked against policy:workspace-isolation. Blocking rather than failing open. Re-issue the call with an explicit absolute file path."
    [ "$PARALLEL_SAFE" -eq 0 ] && refuse_parallel_safe "this $TOOL"
    TARGET="$(canonical_path "$TARGET_RAW")"
    VERDICT="$(write_verdict "$TARGET")"
    case "$VERDICT" in
      0)
        [ "$TREE_BROKEN" -eq 1 ] && refuse_broken_tree "this $TOOL"
        # Inside the worktree, the bar is still not the code author's to write.
        if ! in_set "$ROLE" "$ACCEPTANCE_AUTHOR_ROLES"; then
          while IFS= read -r rel; do
            [ -n "$rel" ] || continue
            case "$rel" in /*) continue ;; esac
            if path_within "$TARGET" "$(canonical_path "$CHANGE_WT/${rel%/}")"; then
              printf 'agent-team worktree guard: this %s targets %s, inside the separately-authored acceptance suite (%s). That suite is the bar this work is judged against, authored by an agent that never writes the code, and it is read-only to you — a test that looks wrong is a plan defect to report, never a file to edit. Make the suite pass, or report the defect.\n' \
                "$TOOL" "$TARGET" "$rel" >&2
              guard_log worktree "$ROLE" block "acceptance-suite: $rel"
              exit 2
            fi
          done <<EOF
$(acceptance_paths "$CHANGE_WT")
EOF
        fi
        ;;
      1) : ;;
      *)
        case "$RESOLVED" in ambiguous) refuse_ambiguous "this $TOOL" ;; esac
        refuse_write "$TARGET" "this $TOOL" "$VERDICT"
        ;;
    esac
    ;;
  Bash)
    COMMAND="$(printf '%s' "$PARSED" | jq -r '.tool_input.command // empty')"
    # Every policed role belongs to exactly one of the four sets. A role added to
    # POLICED_ROLES and to no set has no rule, and no rule is a block here.
    in_set "$ROLE" "$CHANGE_CONFINED_ROLES $INTEGRATOR_ROLES $JUDGE_ROLES $NO_SHELL_ROLES" \
      || refuse "no shell rule for this role" \
        "this guard has no shell rule for the $ROLE, so it cannot tell a read from a mutation for it and blocks rather than failing open. That is a defect in the guard, not in your work: report it as one."
    in_set "$ROLE" "$NO_SHELL_ROLES" && refuse "shell command from a role with no Bash" \
      "the $ROLE holds no Bash tool in its frontmatter, so this guard has no rule for a shell command from it and will not invent one. If this work needs a shell, it belongs to a role that has one: the executor for shell work, the builder for code and tests. Stop and report that the work needs re-routing."
    [ -n "$CWD" ] || refuse "no working directory in Bash" \
      "this Bash call carried no working directory, so where it would run cannot be established. Blocking rather than failing open. Re-issue it as a command that opens by stepping into the directory it means (cd <path> && ...), which this guard reads as its working directory."
    RUN_DIR="$(canonical_path "$CWD")"
    # A subagent's payload directory is its session's — always the shared checkout —
    # so judged by that alone every builder command was refused, including the `cd`
    # into its own worktree: eight recorded refusals on 2026-08-04 from a builder
    # whose workspace was correct. A first statement that steps in is where it runs.
    CD_RAW="$(wtr_leading_cd "$COMMAND")"
    if [ -n "$CD_RAW" ] && [ -n "$CHANGE_WT" ]; then
      CD_TARGET="$(canonical_path "$CD_RAW")"
      path_within "$CD_TARGET" "$CHANGE_WT" && RUN_DIR="$CD_TARGET"
    fi

    # Where a git mutation may run, for the one set that may run one at all.
    git_inside_claim() { # $1 statement
      local dir
      [ -n "$CHANGE_WT" ] || return 1
      [ "$TREE_BROKEN" -eq 0 ] || return 1
      path_within "$RUN_DIR" "$CHANGE_WT" || return 1
      while IFS= read -r dir; do
        [ -n "$dir" ] || continue
        path_within "$(canonical_path "$dir")" "$CHANGE_WT" || return 1
      done <<EOF
$(wtr_git_dirs "$1")
EOF
      return 0
    }

    if in_set "$ROLE" "$CHANGE_CONFINED_ROLES" && [ -n "$CHANGE_WT" ]; then
      [ "$TREE_BROKEN" -eq 1 ] && refuse_broken_tree "this shell command"
      path_within "$RUN_DIR" "$CHANGE_WT" || refuse "$RUN_DIR" \
        "$(printf 'this shell command would run in %s, outside the worktree of the change "%s" (%s). policy:workspace-isolation confines a %s to that one directory. Re-run it inside %s — a command that opens by stepping in (cd %s && ...) is honoured.' \
             "$RUN_DIR" "$CHANGE_SLUG" "$CHANGE_WT" "$ROLE" "$CHANGE_WT" "$CHANGE_WT")"
      while IFS= read -r stmt; do
        [ -n "$stmt" ] || continue
        while IFS= read -r gitdir; do
          [ -n "$gitdir" ] || continue
          path_within "$(canonical_path "$gitdir")" "$CHANGE_WT" || refuse "git at $gitdir" \
            "$(printf 'this command points git at %s, outside the worktree of the change "%s" (%s). policy:workspace-isolation forbids operating on the shared checkout or another change'"'"'s tree. Drop the -C, --git-dir and --work-tree options and run git inside your own worktree.' \
                 "$gitdir" "$CHANGE_SLUG" "$CHANGE_WT")"
        done <<EOF2
$(wtr_git_dirs "$stmt")
EOF2
      done <<EOF
$(wtr_statements "$COMMAND")
EOF
      exit 0
    fi

    if in_set "$ROLE" "$CHANGE_CONFINED_ROLES"; then
      # No claim: nothing to be confined to. A dispatch that asserted it writes
      # nothing falls through to the judge rule instead, because the dispatch guard
      # accepts that assertion in place of a change and refusing every command it
      # runs would refuse a shape the workflow blesses.
      case "$RESOLVED" in ambiguous) refuse_ambiguous "this shell command" ;; esac
      if [ "$PARALLEL_SAFE" -ne 0 ]; then
        refuse "no claim for a change-confined role" \
          "$(printf 'the %s works inside one change'"'"'s worktree, and this session holds no live claim this dispatch could be confined to, so no shell command can be confirmed safe. The repair is one line in the dispatch, which the orchestrator adds:\n  %s <slug>\nStop and report that this dispatch needs it. If the dispatch genuinely writes nothing, the line "%s" says so and read-only commands are then allowed.' \
               "$ROLE" "$CHANGE_MARKER_PREFIX" "$PARALLEL_SAFE_MARKER")"
      fi
    fi

    # Integrator, judge, diagnostic, and a PARALLEL_SAFE change-confined dispatch are
    # not directory-confined — the verifier runs the acceptance suite and the reviewer
    # the plan lint from the shared checkout. Mutation is what is refused, statement
    # by statement.
    INTEGRATOR=0
    in_set "$ROLE" "$INTEGRATOR_ROLES" && INTEGRATOR=1
    while IFS= read -r stmt; do
      [ -n "$stmt" ] || continue
      case "$stmt" in *"$WORKSPACE_ADMIN"*) continue ;; esac
      SUB="$(wtr_git_subcommand "$stmt")"
      if [ -n "$SUB" ]; then
        if [ "$SUB" = unknown ]; then
          if [ "$INTEGRATOR" -eq 1 ]; then
            guard_log worktree "$ROLE" note \
              "unclassifiable git command allowed for an integrator: $stmt"
          else
            refuse "unclassifiable git command" \
              "$(printf 'this command runs git in a form whose subcommand this guard cannot identify (%s), so it cannot be told apart from one that mutates a repository — and a %s is refused every git mutation. The classification fails closed rather than open. Re-run it as a plain read (git status, git log, git diff), or hand the mutation to the executor, which is the role that performs one.' \
                   "$stmt" "$ROLE")"
          fi
        elif wtr_git_mutates "$SUB"; then
          if [ "$INTEGRATOR" -eq 1 ] && [ "$PARALLEL_SAFE" -ne 0 ] && git_inside_claim "$stmt"; then
            :
          elif [ "$PARALLEL_SAFE" -eq 0 ]; then
            refuse_parallel_safe "this git $SUB"
          elif [ "$INTEGRATOR" -eq 1 ]; then
            refuse "git $SUB outside the claimed worktree" \
              "$(printf 'this command runs `git %s`, which mutates a repository, and it is not running inside the worktree of a change this session claimed (%s). An integrator may mutate the shared checkout in exactly one sanctioned way — bash %s/%s integrate <project> <slug> — the command closeout uses. For anything else: run it inside the worktree of the change (cd %s && ...), or stop and report that this dispatch needs a change declared as `%s <slug>`.' \
                   "$SUB" "${CHANGE_SLUG:-none is claimed}" "$GUARD_DIR" "$WORKSPACE_ADMIN" \
                   "${CHANGE_WT:-<the change worktree>}" "$CHANGE_MARKER_PREFIX")"
          else
            refuse "git $SUB from a non-writing role" \
              "$(printf 'this command runs `git %s`, which mutates a repository, and the %s holds no writing turn in any change — it reads, runs and reports. That is why its frontmatter grants no Write, Edit or NotebookEdit. Read-only git (status, log, diff, show) runs freely from anywhere. If a mutation is genuinely needed, stop and report it: the executor performs one, inside the change'"'"'s own worktree.' \
                   "$SUB" "$ROLE")"
          fi
        fi
      fi
      # In-place file mutation, for every set but the integrator: refused only when the
      # target lands inside a git working tree, so a scratch file and a suite's own
      # temporary output stay legal.
      [ "$INTEGRATOR" -eq 1 ] && [ "$PARALLEL_SAFE" -ne 0 ] && continue
      MUTATES=0
      wtr_mutates_files "$stmt" && MUTATES=1
      TARGETS=""
      [ "$MUTATES" -eq 1 ] && TARGETS="$(wtr_path_arguments "$stmt")"
      TARGETS="$TARGETS
$(wtr_redirect_targets "$stmt")"
      while IFS= read -r raw; do
        [ -n "$raw" ] || continue
        CAND="$(canonical_path "$raw")"
        [ -n "$(wtr_working_tree "$CAND")" ] || continue
        if [ "$PARALLEL_SAFE" -eq 0 ]; then
          refuse_parallel_safe "this shell command's write to $CAND"
        fi
        refuse "in-place mutation of $CAND" \
          "$(printf 'this command would write %s, which is inside a git working tree, and the %s may not mutate a repository — it reads, runs and reports, which is why its frontmatter grants no Write, Edit or NotebookEdit. Write to a scratch path outside every checkout instead (a temporary directory is fine), or stop and report the change the work needs so a role that holds the writing turn does it.' \
               "$CAND" "$ROLE")"
      done <<EOF2
$TARGETS
EOF2
    done <<EOF
$(wtr_statements "$COMMAND")
EOF
    ;;
esac

exit 0
