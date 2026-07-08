#!/usr/bin/env bash
# agent-team-policy-mutations.sh — the raw-shell-mutation primitive blocklist
# shared by every role that runs mutation checks (readonly-runner, deployer,
# builder, ops). Sourced by agent-team-policy-lib.sh, which is itself sourced
# by agent-team-policy.sh (a two-level source chain). Split out of the lib
# file to keep every hook file under the 300-line ceiling once the final
# security-hardening pass (four gap classes) pushed the combined checks over.
#
# Function bodies here call has_in()/block() and reference $ROLE/$CMD — all
# provided by the entry point and lib file at CALL time, not source time; this
# file has no top-level executable code, so sourcing it anywhere after those
# are defined is safe.

# Shared by every role that runs mutation checks. Blocks the raw-shell-mutation
# primitives — file-mutation commands, redirection, tee (any form), archive
# and compression tools, in-place sed, package management — plus the confirmed-
# exploitable subshell/command-substitution syntaxes and the interpreter/eval
# escape hatches that would otherwise smuggle an arbitrary mutating command
# past every regex as a string argument. Deliberately excludes the git-verb
# block: builder needs `git add`/`git commit` for its own TDD workflow, so that
# block lives only in `_deny_shell_mutation_seg` (in the lib file), not here.
_deny_raw_mutation_primitives_seg() { # $1 = one chain segment
  local seg="$1"
  # Command substitution / subshell bypass: a mutating command hidden inside
  # $(...) or backticks sits immediately after a `(` or a backtick, neither of
  # which the `(^|[;&|[:space:]])` anchor used below matches — so e.g.
  # `echo $(rm -rf /)` slipped past every check untouched. Rather than trying
  # to parse nested subshell contents with POSIX ERE (impractical in bash
  # 3.2), block the syntax itself unconditionally. Process substitution
  # `<(cmd)`/`>(cmd)` is a second confirmed-live subshell-execution vector
  # (`cat <(rm -rf /)` runs `rm`), so it is blocked alongside `$(`/backtick.
  # The `<(`/`>(` pattern matches ONLY a `<`/`>` immediately followed by an
  # open paren — bare `<`/`>`/`<<` redirection is untouched and stays governed
  # by the redirect-to-file check below. Bare-paren subshells `(cmd)` are
  # intentionally NOT blocked: a broad bare-`(` check risked false-positiving
  # on legitimate parenthesized constructs (arithmetic `((x++))`, grouped test
  # conditions, `grep -E` alternation), so the fix stays scoped to the
  # confirmed-exploitable vectors only.
  if has_in "$seg" '\$\(|`|[<>]\('; then
    block "command substitution / subshell / process substitution syntax not allowed for $ROLE" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]])(rm|mv|cp|mkdir|touch|chmod|chown|ln|dd|truncate)([[:space:]]|$)'; then
    block "file-mutating command not allowed for $ROLE" "$CMD"
  fi
  # install(1) creates/copies/overwrites files with specific permissions —
  # a file-creating primitive the list above missed.
  if has_in "$seg" '(^|[;&|[:space:]])install([[:space:]]|$)'; then
    block "install(1) creates/overwrites files — not allowed for $ROLE" "$CMD"
  fi
  # Archive/compression tools extract or emit files into/out of the tree.
  if has_in "$seg" '(^|[;&|[:space:]])(tar|unzip|gzip|gunzip|bunzip2|xz|zip)([[:space:]]|$)'; then
    block "archive/compression command creates or extracts files — not allowed for $ROLE" "$CMD"
  fi
  if has_in "$(stripped_cmd_of "$seg")" '>>?'; then
    block "output redirection to a file not allowed for $ROLE" "$CMD"
  fi
  # tee in ANY form — piped (`| tee f`) or bare (`tee f < src`) — writes files.
  # Anchored as a command word so a variable/substring like `mytee` or
  # `sqlite3` is never matched; the leading `|` case is covered by the pipe
  # being one of each_segment's split characters, so a piped `tee` is its own
  # segment with `tee` as its first token, matched by the `^` alternative.
  if has_in "$seg" '(^|[;&|[:space:]])tee([[:space:]]|$)'; then
    block "tee writes files — not allowed for $ROLE" "$CMD"
  fi
  if has_in "$seg" 'sed[[:space:]]+(-[A-Za-z]*i|--in-place)'; then
    block "in-place edit not allowed for $ROLE" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]])(npm|pnpm|yarn|pip3?|uv|brew)[[:space:]]+(install|add|uninstall|remove|upgrade)'; then
    block "package management not allowed for $ROLE" "$CMD"
  fi
  # Interpreter/eval escape hatches (Gap 4): each smuggles an arbitrary
  # mutating command past every regex above as a string argument the scanner
  # never inspects as a real command. eval is blocked outright — no legitimate
  # workflow in this team needs it that couldn't be done directly.
  if has_in "$seg" '(^|[;&|[:space:]])eval([[:space:]]|$)'; then
    block "eval can execute an arbitrary hidden command — not allowed for $ROLE" "$CMD"
  fi
  # Raw shell interpreter (bash/sh/zsh/dash) as a command word is an escape
  # hatch in two forms, both blocked:
  #   1. `-c "…"` inline code (`bash -c "rm -rf /"`) — hides an arbitrary
  #      command from the scanner, exactly like python/perl -c/-e below.
  #   2. no script-path positional argument at all (`curl … | bash`,
  #      `cat x.sh | sh`, bare `bash`) — the script arrives via stdin/pipe or a
  #      terminal, so there is nothing for the scanner to inspect.
  # Bash tool calls already run through a shell, so re-invoking one as a
  # sub-command is redundant or an escape attempt. A real script invocation
  # (`bash deploy.sh`) names a positional argument and, having no `-c`, is NOT
  # matched by either branch and stays allowed.
  if has_in "$seg" '(^|[;&|[:space:]])(bash|sh|zsh|dash)[[:space:]]+(-[^[:space:]]*[[:space:]]+)*-c([[:space:]]|$)'; then
    block "shell interpreter -c inline code can hide an arbitrary command — not allowed for $ROLE" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]])(bash|sh|zsh|dash)([[:space:]]+-[^[:space:]]+)*([[:space:]]|$)' \
    && ! has_in "$seg" '(^|[;&|[:space:]])(bash|sh|zsh|dash)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^-[:space:]]'; then
    block "invoking a raw shell interpreter (stdin/piped script) is an escape hatch — not allowed for $ROLE" "$CMD"
  fi
  # Interpreter one-liners: `-c`/`-e`/`--eval`/`--command` inline code hides an
  # arbitrary command from the scanner. Blocked for python/perl/node/ruby.
  # `python3 script.py` (a real script file) and `python3 -m pytest` (module
  # invocation) name no inline-code flag and stay allowed.
  if has_in "$seg" '(^|[;&|[:space:]])(python3?|perl|node|ruby)[[:space:]]+(-c|-e|--eval|--command)([[:space:]]|$)'; then
    block "interpreter inline-code flag (-c/-e) can hide an arbitrary command — not allowed for $ROLE" "$CMD"
  fi
  return 0
}
