#!/usr/bin/env bash
# agent-team-policy-lib.sh — shared helpers and per-role policy functions for
# agent-team-policy.sh. Sourced, not executed directly. Split out of
# agent-team-policy.sh to keep both files under the 300-line ceiling; this is
# a pure code-motion refactor with zero behavior change (see task-6-report.md).

has() { printf '%s' "$CMD" | grep -qE "$1"; }
has_in() { printf '%s' "$1" | grep -qE "$2"; } # $1 string, $2 pattern

# Splits $CMD on shell control operators (&&, ||, ;, |) and feeds each
# trimmed, non-empty segment to callback $1, one call per segment.
# Uses `< <(...)` process substitution (not a trailing pipe) so the while
# loop runs in THIS shell process, not a subshell — verified under macOS
# bash 3.2: `cmd | while read ...; do exit 2; done` only exits the
# subshell and lets the script continue, silently defeating blocking.
# `while read ...; done < <(cmd)` propagates exit 2 to the real process.
each_segment() { # $1 = callback name, invoked once per chain segment of $CMD
  local cb="$1" seg
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$seg" ] && "$cb" "$seg"
  done < <(printf '%s\n' "$CMD" | sed -E 's/(&&|\|\||;|\|)/\n/g')
}

# The raw-shell-mutation primitive blocklist (_deny_raw_mutation_primitives_seg)
# lives in agent-team-policy-mutations.sh, sourced here from this file's own
# directory. It grew past what would keep this file under the 300-line ceiling
# once the final security-hardening pass added Gap 1/2/4 coverage (tee any
# form, install, archive/compression tools, process substitution, eval,
# raw-interpreter invocation, and interpreter inline-code flags), so it was
# split into its own file. This is the second level of a two-level source
# chain (entry point -> this lib -> mutations); resolving from ${BASH_SOURCE[0]}
# rather than $0 keeps it correct no matter how the entry point was invoked.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agent-team-policy-mutations.sh"

_deny_shell_mutation_seg() { # $1 = one chain segment
  local seg="$1"
  _deny_raw_mutation_primitives_seg "$seg"
  if has_in "$seg" '(^|[;&|[:space:]])git[[:space:]]+(add|commit|push|reset|checkout|restore|clean|rebase|merge|stash|tag|rm)([[:space:]]|$)'; then
    block "mutating git command not allowed for $ROLE" "$CMD"
  fi
  return 0
}

# Chain-aware: every segment is checked independently, so a mutation
# hidden after a benign/whitelisted segment (e.g. `sam deploy && rm -rf /`)
# is still caught.
deny_shell_mutation() {
  each_segment _deny_shell_mutation_seg
  return 0
}

_policy_deployer_seg() { # $1 = one chain segment; blocks on any disallowed segment
  local seg="$1"
  if has_in "$seg" '(^|[;&|[:space:]])(sam|amplify|cdk)([[:space:]]|$)'; then
    return 0
  fi
  if has_in "$seg" '(^|[;&|[:space:]])aws[[:space:]]'; then
    if has_in "$seg" 'aws[[:space:]]+cloudformation[[:space:]]' \
      || has_in "$seg" 'aws[[:space:]]+s3[[:space:]]+(sync|cp|ls)([[:space:]]|$)' \
      || has_in "$seg" 'aws[[:space:]]+sts[[:space:]]' \
      || has_in "$seg" 'aws[[:space:]]+[a-z0-9-]+[[:space:]]+(get-|list-|describe-|head-)'; then
      return 0
    fi
    block "aws command outside the deploy toolchain — surface it to the human at a gate" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]])terraform([[:space:]]|$)'; then
    block "terraform is not part of this team's deploy toolchain" "$CMD"
  fi
  _deny_shell_mutation_seg "$seg"
}

# Every segment of the chain must independently be a recognized-safe
# deploy-toolchain/aws-allowlisted call, or pass the mutation checks with
# no block. Only after ALL segments clear does the whole command allow —
# matching one segment against sam/amplify/cdk/aws no longer short-circuits
# an allow for the rest of the chain (that was the bypass).
policy_deployer() {
  each_segment _policy_deployer_seg
  allow "$CMD"
}

policy_readonly_runner() {
  if has '(^|[;&|[:space:]])(aws|az|gcloud)[[:space:]]'; then
    block "no cloud CLI for $ROLE" "$CMD"
  fi
  if has '(^|[;&|[:space:]])(sam|amplify|cdk|terraform)([[:space:]]|$)'; then
    block "deploy toolchain is reserved for the deployer" "$CMD"
  fi
  deny_shell_mutation
  allow "$CMD"
}

_policy_ops_seg() { # $1 = one chain segment; blocks on any disallowed segment
  local seg="$1"
  if has_in "$seg" 'aws[[:space:]]+[a-z0-9-]+[[:space:]]+(get-|list-|describe-|head-)' \
    || has_in "$seg" 'aws[[:space:]]+sts[[:space:]]' \
    || has_in "$seg" 'aws[[:space:]]+s3[[:space:]]+ls([[:space:]]|$)'; then
    return 0
  fi
  if has_in "$seg" 'az[[:space:]][^;&|]*[[:space:]](show|list)([[:space:]]|$)'; then
    return 0
  fi
  if has_in "$seg" '(^|[;&|[:space:]])aws[[:space:]]'; then
    block "mutating aws verb — present the exact command to the human at a gate instead" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]])az[[:space:]]'; then
    block "mutating az command — present the exact command to the human at a gate instead" "$CMD"
  fi
  _deny_raw_mutation_primitives_seg "$seg"
}

# Every segment of the chain must independently be a recognized-safe
# read-verb call, or pass the raw-mutation-primitives check with no block.
# Mirrors policy_deployer's chain-safe shape: matching one segment against
# the aws/az allowlist no longer short-circuits an allow for the rest of the
# chain (that was the chaining bypass), and any segment with no aws/az at
# all (e.g. a bare `rm -rf /important` riding after a benign aws call) still
# goes through the shared raw-mutation guard (that was the zero-coverage gap).
policy_ops() {
  each_segment _policy_ops_seg
  allow "$CMD"
}

_policy_builder_seg() { # $1 = one chain segment
  local seg="$1"
  if has_in "$seg" '(^|[;&|[:space:]])(aws|az|gcloud)[[:space:]]'; then
    block "builder has no cloud CLI access — hand cloud work to ops or deployer" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]])(amplify|cdk|terraform)([[:space:]]|$)'; then
    block "deploy toolchain belongs to the deployer" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]])sam[[:space:]]+deploy([[:space:]]|$)'; then
    block "sam deploy belongs to the deployer" "$CMD"
  fi
  _deny_raw_mutation_primitives_seg "$seg"
  # Destructive-git-verb check, narrower than _deny_shell_mutation_seg's full
  # git blocklist (which blocks commit/add — both required for builder's TDD
  # workflow). These four forms discard work irrecoverably outside git's
  # normal history, so they're blocked for builder even though commit/add/
  # checkout-to-a-branch/reset-soft are all legitimate builder operations:
  if has_in "$seg" '(^|[;&|[:space:]])git[[:space:]]+clean([[:space:]]|$)'; then
    block "git clean destroys untracked files — not allowed for $ROLE" "$CMD"
  fi
  # `git checkout --` / `git checkout <ref> --` is the discard-changes-to-a-
  # path syntax; plain `git checkout <branch>` (no `--`) switches branches and
  # must remain allowed, so this only matches when `--` appears as its own
  # token after checkout.
  if has_in "$seg" '(^|[;&|[:space:]])git[[:space:]]+checkout([[:space:]]+[^[:space:]]+)*[[:space:]]+--([[:space:]]|$)'; then
    block "git checkout -- discards uncommitted changes — not allowed for $ROLE" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]])git[[:space:]]+reset([[:space:]]+[^[:space:]]+)*[[:space:]]+--hard([[:space:]]|$)'; then
    block "git reset --hard discards commits and working-tree changes — not allowed for $ROLE" "$CMD"
  fi
  # Bare `git restore <path>` discards working-tree changes; `--staged` only
  # unstages (safe) and must remain allowed.
  if has_in "$seg" '(^|[;&|[:space:]])git[[:space:]]+restore([[:space:]]|$)' \
    && ! has_in "$seg" '(^|[;&|[:space:]])git[[:space:]]+restore([[:space:]]+[^[:space:]]+)*[[:space:]]+--staged([[:space:]]|$)'; then
    block "git restore without --staged discards working-tree changes — not allowed for $ROLE" "$CMD"
  fi
  if has_in "$seg" 'git[[:space:]]+push'; then
    # Three independent checks catch main/master as: a bare whitespace-delimited
    # token, the destination side of a ':'-separated refspec (e.g. HEAD:main),
    # or a fully-qualified refs/heads/ path — without false-positiving on a
    # feature-prefixed branch that merely contains "main" as a path segment
    # (e.g. feature/main). Segment is already chain-isolated so no [;&|] can
    # appear inside it, but the patterns are kept as-is (harmless) for parity
    # with the pre-chaining-fix behavior.
    if has_in "$seg" 'git[[:space:]]+push[^;&|]*[[:space:]](main|master)([[:space:]]|$|:)'; then
      block "builder may not push to main/master" "$CMD"
    fi
    if has_in "$seg" ':(main|master)([[:space:]]|$)'; then
      block "builder may not push to main/master" "$CMD"
    fi
    if has_in "$seg" '(^|[;&|[:space:]:])refs/heads/(main|master)([[:space:]]|$|:)'; then
      block "builder may not push to main/master" "$CMD"
    fi
    if ! has_in "$seg" 'git[[:space:]]+push[[:space:]]+(-u[[:space:]]+)?[^-[:space:]][^[:space:]]*[[:space:]]+[^[:space:]]+'; then
      block "git push must name a remote and an explicit feature branch" "$CMD"
    fi
  fi
  return 0
}

# Builder calls _deny_raw_mutation_primitives_seg (via _policy_builder_seg)
# rather than the full _deny_shell_mutation_seg/deny_shell_mutation used by
# the other roles, because that shared helper's git-verb block list includes
# `commit` and `add` — both required for builder's normal TDD workflow
# (commit after every green test cycle). Builder's own push-to-main/master
# handling above already covers `git push`; a narrower destructive-git-verb
# check (git clean / checkout -- / reset --hard / restore without --staged)
# lives inline in _policy_builder_seg above. Raw shell-mutation primitives
# (rm/redirect/tee/in-place sed/package installs/subshell syntax) are also
# still blocked. See task-5-report.md for the human decisions that resolved
# the previously-flagged gaps.
policy_builder() {
  each_segment _policy_builder_seg
  allow "$CMD"
}

# stdin command (or an arbitrary string, via stripped_cmd_of) with harmless
# /dev/null redirections and fd-to-fd redirects (2>&1, 1>&2, &>&2, ...) removed,
# so redirection checks don't false-positive on "2>/dev/null" or the extremely
# common "2>&1" stderr/stdout merge — neither writes to a file, so neither is a
# file-mutation risk. A genuine file redirect elsewhere in the same command
# (e.g. "cmd 2>&1 > out.txt") still matches after this stripping, since only
# the fd-to-fd/-to-null forms are removed, not the trailing "> out.txt".
stripped_cmd() { stripped_cmd_of "$CMD"; }
stripped_cmd_of() {
  printf '%s' "$1" \
    | sed -E 's|[0-9]*>+[[:space:]]*/dev/null||g' \
    | sed -E 's|[0-9]*>&[0-9]+||g'
}

SECRET_RE='\$\{?(OKTA_TOKEN|GODADDY_API_KEY|GODADDY_API_SECRET|OP_SERVICE_ACCOUNT_TOKEN|[A-Za-z_]*_API_KEY|[A-Za-z_]*SECRET[A-Za-z_]*|[A-Za-z_]*PASSWORD[A-Za-z_]*)'

policy_docwriter_path() {
  # Block path traversal: reject any path containing '..' as a full path segment
  # (bounded by '/' or string start/end), e.g. '/../', '/..', '../', or '..'.
  # This prevents paths like '/docs/../../../../etc/passwd' from bypassing the
  # glob checks below by containing a substring match to '*/docs/*' while
  # resolving outside the allowed tree.
  if has_in "$FILE" '(^|/)\.\.(/|$)'; then
    block "path contains a '..' segment — traversal outside the allowed write tree is not permitted" "$FILE"
  fi

  case "$FILE" in
    */docs/*|docs/*|*/plans/*|plans/*|*/doc-inventory/*|doc-inventory/*)
      allow "$FILE" ;;
    */STATUS.md|STATUS.md|*/STATUS-*.md)
      allow "$FILE" ;;
    */scratchpad/*)
      allow "$FILE" ;;
    *)
      block "writes are limited to docs/, plans/, doc-inventory/, STATUS notes, and the scratchpad" "$FILE" ;;
  esac
}

check_global_rules() {
  if has "$SECRET_RE"; then
    if printf '%s' "$(stripped_cmd)" | grep -qE '(>>?|\|[[:space:]]*tee([[:space:]]|$))'; then
      block "credential-bearing value directed at a file — forbidden for every role" "$CMD"
    fi
  fi
  case "$ROLE" in
    ops|deployer) : ;;
    *)
      if has '(^|[;&|[:space:]])op([[:space:]]|$)'; then
        block "only ops and deployer may invoke the 1Password CLI" "$CMD"
      fi
      ;;
  esac
  return 0
}

# Mirrors check_global_rules' Bash-path secret guard, but for the Write/Edit/
# NotebookEdit dispatch: applies to EVERY role (the design spec's "all roles"
# guarantee), not just builder, since architect/scribe must never be allowed
# to write a secret into a doc file either. Reuses SECRET_RE as-is against
# $CONTENT (the file content / new_string / new_source being written), so
# scope is identical to the Bash-path check: shell-variable-style references
# to a known-sensitive env var name (e.g. $OKTA_TOKEN, ${MY_API_KEY}) written
# verbatim as text. Detecting a literal high-entropy secret VALUE with no `$`
# prefix is out of scope here — that is a separate entropy-scanning feature.
# Fails open on missing content: if extraction found nothing (e.g. an Edit
# variant whose tool_input didn't populate any of the fallback-chain fields),
# this only inspects what's actually present rather than blocking blind.
check_write_content_secrets() {
  if [ -n "$CONTENT" ] && has_in "$CONTENT" "$SECRET_RE"; then
    block "file content references a credential-bearing variable name — writing secrets to any file is forbidden for every role" "$CONTENT"
  fi
  return 0
}
