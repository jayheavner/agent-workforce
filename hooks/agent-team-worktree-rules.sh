#!/usr/bin/env bash
# agent-team-worktree-rules.sh — what a shell command is trying to do, as far as a
# guard can tell from its text. Sourced by agent-team-worktree-guard.sh, which owns
# the per-role decision; this file owns only the classification.
#
# It lives beside the guard because the guard already carries the register
# resolution, the legality rule and every refusal message, and this half pushed it
# past the project's file-size discipline. Nothing else moved.
#
# WHAT THIS IS AND IS NOT. Bash cannot be classified as a read or a write by its tool
# name, so the guard has to read the command — and reading a command with patterns is
# best-effort by construction. An interpreter-wrapped write (`bash -c`, `python3 -c`),
# `find -delete`, `xargs rm`, a command substitution, or a directory change buried
# mid-command all reach a file no pattern here names. For the roles that hold no
# Write, Edit or NotebookEdit, the real wall is that absence in their frontmatter;
# these patterns are defence in depth on top of it, never the guarantee. For the roles
# that do write, the wall is the guard's path-confinement rule on the write tools.
#
# Sourced, not executed. Defines functions and constants only.

# Git subcommands that change a repository. The head-ref subcommand — the one word
# this project bans in prose, present because this list matches literal command tokens
# — is required: without it, `git <that subcommand> -D change/<slug>` destroys a
# change's ref and its history undetected, the loss the register exists to prevent.
WTR_GIT_MUTATING=" add am apply branch checkout cherry-pick clean clone commit config
fetch gc init merge mv notes prune pull push rebase reflog remote replace reset
restore revert rm stash submodule switch symbolic-ref tag update-ref worktree "
# Global options that carry a value as the NEXT token; skipping them is what stops
# `git -C /elsewhere commit` reading as the harmless subcommand `/elsewhere`.
WTR_GIT_VALUE_OPTS=" -C -c --git-dir --work-tree --namespace "
# The two global options that point git at another working tree, in either form.
WTR_GIT_DIR_OPTS=" -C --git-dir --work-tree "
# Options that end the command themselves: git does nothing to a repository for
# either, and refusing them as unidentifiable would refuse an honest read.
WTR_GIT_TERMINAL_OPTS=" --version --help -v -h "
# Command heads that mutate a file; `sed` and `perl` count only with -i.
WTR_MUTATION_HEADS=" tee cp mv rm mkdir touch install dd chmod chown ln truncate "
WTR_INPLACE_HEADS=" sed perl "

# One statement per line: split on the separators that start a new command. `&&` and
# `||` split; a single `&` does NOT, because `2>&1` is one token and splitting it would
# turn a stderr redirection into a file called `1`.
wtr_statements() { # $1 command
  local s="$1" nl=$'\n'
  s="${s//&&/$nl}"
  s="${s//||/$nl}"
  s="${s//|/$nl}"
  s="${s//;/$nl}"
  printf '%s\n' "$s"
}

# One token per line, surrounding quotes stripped, globbing off so a `*` is not
# expanded against the guard's own directory. A quoted path containing spaces is
# split — a known limit that can only ever yield MORE candidate tokens, never fewer.
wtr_tokens() { # $1 statement
  local t restore=0
  case "$-" in *f*) restore=1 ;; esac
  set -f
  for t in $1; do
    t="${t%\"}"; t="${t#\"}"
    t="${t%\'}"; t="${t#\'}"
    [ -n "$t" ] && printf '%s\n' "$t"
  done
  [ "$restore" -eq 1 ] || set +f
  return 0
}

# Membership by whole word. A loop rather than a padded-substring match: the sets
# above wrap across lines, and a word at a line boundary is padded by a newline, which
# a substring test silently misses.
wtr_word_in() { # $1 word $2 whitespace-separated set
  local w
  for w in $2; do
    [ "$1" = "$w" ] && return 0
  done
  return 1
}

# The first token of a statement, with a `sudo`, `env`, `command`, `time` or `nice`
# wrapper stepped over so it cannot hide the real command.
wtr_head() { # $1 statement
  local tok
  while IFS= read -r tok; do
    case "$tok" in
      sudo | env | command | time | nice | exec | builtin) continue ;;
      *=*) case "$tok" in -*) ;; *) continue ;; esac ;;
    esac
    printf '%s' "${tok##*/}"
    return 0
  done < <(wtr_tokens "$1")
  return 0
}

# The git subcommand: the first token that survives skipping every leading global
# option. Nothing when the statement is not a git invocation; `unknown` when it is one
# whose subcommand cannot be identified, which the caller fails closed on.
wtr_git_subcommand() { # $1 statement
  [ "$(wtr_head "$1")" = git ] || return 0
  local tok skip_next=0 passed_git=0
  while IFS= read -r tok; do
    if [ "$passed_git" -eq 0 ]; then
      [ "${tok##*/}" = git ] && passed_git=1
      continue
    fi
    if [ "$skip_next" -eq 1 ]; then
      skip_next=0
      continue
    fi
    if wtr_word_in "$tok" "$WTR_GIT_TERMINAL_OPTS"; then
      printf '%s' "$tok"
      return 0
    fi
    case "$tok" in
      *=*)
        case "$tok" in -*) continue ;; esac
        ;;
    esac
    if wtr_word_in "$tok" "$WTR_GIT_VALUE_OPTS"; then
      skip_next=1
      continue
    fi
    case "$tok" in
      -*) continue ;;
      *) printf '%s' "$tok"; return 0 ;;
    esac
  done < <(wtr_tokens "$1")
  printf 'unknown'
}

wtr_git_mutates() { wtr_word_in "$1" "$WTR_GIT_MUTATING"; } # $1 subcommand

# Every directory a git invocation aims itself at: `-C`, `--git-dir` and `--work-tree`
# in either form. All three redirect git at another working tree, so a guard that
# judges only `-C` judges a third of the escapes.
wtr_git_dirs() { # $1 statement
  local tok want=0 opt
  while IFS= read -r tok; do
    if [ "$want" -eq 1 ]; then
      want=0
      printf '%s\n' "$tok"
      continue
    fi
    case "$tok" in
      *=*)
        opt="${tok%%=*}"
        if wtr_word_in "$opt" "$WTR_GIT_DIR_OPTS"; then
          printf '%s\n' "${tok#*=}"
        fi
        continue
        ;;
    esac
    wtr_word_in "$tok" "$WTR_GIT_DIR_OPTS" && want=1
  done < <(wtr_tokens "$1")
  return 0
}

# Does this statement mutate a file, judged by its command head?
wtr_mutates_files() { # $1 statement
  local head tok
  head="$(wtr_head "$1")"
  wtr_word_in "$head" "$WTR_MUTATION_HEADS" && return 0
  if wtr_word_in "$head" "$WTR_INPLACE_HEADS"; then
    while IFS= read -r tok; do
      case "$tok" in -i*) return 0 ;; esac
    done < <(wtr_tokens "$1")
  fi
  return 1
}

# The path-shaped arguments of a statement: absolute, or explicitly relative (`./`,
# `../`, `~`). A token that is neither is not a path, so a `sed` script like `s/a/b/`
# is not mistaken for a file and an honest edit is not refused for a path nobody named.
wtr_path_arguments() { # $1 statement
  local tok first=1
  while IFS= read -r tok; do
    if [ "$first" -eq 1 ]; then first=0; continue; fi
    case "$tok" in
      -*) continue ;;
      /* | ./* | ../* | '~'/*) printf '%s\n' "$tok" ;;
    esac
  done < <(wtr_tokens "$1")
  return 0
}

# The files a statement redirects into; `2>&1` and `>&2` are duplications, not targets.
wtr_redirect_targets() { # $1 statement
  local tok want=0 rest
  while IFS= read -r tok; do
    if [ "$want" -eq 1 ]; then
      want=0
      case "$tok" in
        '&'*) continue ;;
        *) printf '%s\n' "$tok"; continue ;;
      esac
    fi
    case "$tok" in
      *'>'*)
        rest="${tok#*>}"
        rest="${rest#>}"
        case "$tok" in
          *'>&'*) continue ;;
        esac
        if [ -z "$rest" ]; then
          want=1
        else
          printf '%s\n' "$rest"
        fi
        ;;
    esac
  done < <(wtr_tokens "$1")
  return 0
}

# --- paths -------------------------------------------------------------------
# Absolute, `.`- and `..`-free form of a path that may not exist yet. Traversal is
# resolved TEXTUALLY, before any ancestor is walked: walking ancestors alone cannot
# resolve `<wt>/nope/../../file` — the middle segment does not exist, so the walk gives
# up and the raw string still carries the worktree prefix, which a containment test
# would then accept. That was a real confinement bypass.
wtr_normalize_abs() { # $1 raw path $2 base directory for a relative one
  local p="$1" out="" seg old
  case "$p" in
    /*) ;;
    *) p="${2:-/}/$p" ;;
  esac
  old="$IFS"; IFS='/'
  for seg in $p; do
    IFS="$old"
    case "$seg" in
      '' | '.') ;;
      '..') out="${out%/*}" ;;
      *) out="$out/$seg" ;;
    esac
    IFS='/'
  done
  IFS="$old"
  printf '%s' "${out:-/}"
}

# The comparable form of a path: normalized, then symlink-resolved as deeply as it
# exists — a lane and a target compared in different forms make an honest write look
# like it is somewhere else.
wtr_canonical() { # $1 raw path $2 base directory
  local raw head tail_part parent
  raw="$(wtr_normalize_abs "$1" "${2:-/}")"
  head="$raw"
  tail_part=""
  while [ -n "$head" ] && [ ! -d "$head" ]; do
    tail_part="$(basename "$head")${tail_part:+/$tail_part}"
    parent="$(dirname "$head")"
    [ "$parent" = "$head" ] && break
    head="$parent"
  done
  if [ -d "$head" ]; then
    head="$(cd "$head" 2>/dev/null && pwd -P)" || head="$raw"
  fi
  printf '%s' "${head%/}${tail_part:+/$tail_part}"
}

# True when $1 is $2 or lives underneath it.
wtr_within() { # $1 candidate $2 container
  [ -n "$2" ] || return 1
  case "$1" in
    "$2" | "$2"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# A linked worktree's .git is a FILE pointing at <main>/.git/worktrees/<name>; the
# shared checkout's is a directory. That is what makes a path a workspace of its own.
wtr_is_linked_worktree() { # $1 path
  [ -f "$1/.git" ] || return 1
  head -n1 "$1/.git" 2>/dev/null \
    | grep -Eq '^gitdir: .*/\.git/worktrees/[^/]+[[:space:]]*$'
}

# The shared checkout behind a linked worktree.
wtr_main_checkout() { # $1 linked worktree
  local gitdir
  gitdir="$(head -n1 "$1/.git" 2>/dev/null | sed -e 's/^gitdir:[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$gitdir" in
    */.git/worktrees/*) printf '%s' "${gitdir%%/.git/worktrees/*}" ;;
    *) return 1 ;;
  esac
}

# The directory a command opens by stepping into it: the argument of a leading `cd` or
# `pushd`, or empty. Only the FIRST statement counts — this is not a shell simulator,
# and a directory change buried later in a command is a stated limit, not a claim.
wtr_leading_cd() { # $1 command
  local first rest target
  first="$(printf '%s\n' "$1" | sed -e 's/^[[:space:]]*//' -e '/^$/d' | head -n1)"
  case "$first" in
    cd[[:space:]]*) rest="${first#cd}" ;;
    pushd[[:space:]]*) rest="${first#pushd}" ;;
    *) return 0 ;;
  esac
  rest="${rest#"${rest%%[![:space:]]*}"}"
  case "$rest" in
    '"'*) rest="${rest#\"}"; target="${rest%%\"*}" ;;
    "'"*) rest="${rest#\'}"; target="${rest%%\'*}" ;;
    *) target="${rest%%[[:space:];&|]*}" ;;
  esac
  printf '%s' "$target"
}

# The deepest existing directory at or above a path, so a path that does not exist yet
# can still be asked which repository it would land in.
wtr_nearest_dir() { # $1 absolute path
  local head="$1" parent
  while [ -n "$head" ] && [ ! -d "$head" ]; do
    parent="$(dirname "$head")"
    [ "$parent" = "$head" ] && break
    head="$parent"
  done
  [ -d "$head" ] && printf '%s' "$head"
  return 0
}

# The git working tree a path lies in, or nothing. Decision 7's second branch rests on
# this: a lane outside every working tree — the agent memory, a machine-level
# configuration directory — is legal with no claim, because no change could own it.
wtr_working_tree() { # $1 absolute path
  local dir top
  dir="$(wtr_nearest_dir "$1")"
  [ -n "$dir" ] || return 0
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
  printf '%s' "$top"
  return 0
}
