#!/usr/bin/env bash
# tools/worktree-hygiene.sh <repo> — read-only worktree hygiene report.
#
# Lists every registered worktree with evidence (branch, merged-into-main,
# tree-clean, last-commit age) and counts removal candidates: merged AND
# clean AND not the current worktree. Never deletes or mutates anything —
# a candidate is evidence for a human decision, not permission to act.
set -u

REPO="${1:-}"
if [ -z "$REPO" ]; then
  echo "usage: worktree-hygiene.sh <repo>" >&2
  exit 0
fi

git -C "$REPO" rev-parse --show-toplevel >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "worktree-hygiene: $REPO is not a Git repository" >&2
  exit 0
fi

CURRENT="$(cd "$REPO" && pwd -P)"

BASE=""
for candidate in main master; do
  if git -C "$REPO" show-ref --verify --quiet "refs/heads/$candidate"; then
    BASE="$candidate"
    break
  fi
done
if [ -z "$BASE" ]; then
  BASE="$(git -C "$REPO" symbolic-ref --short -q HEAD || echo HEAD)"
fi

echo "worktree-hygiene: base=$BASE"

CANDIDATES=0
TOTAL=0

git -C "$REPO" worktree list --porcelain | {
  path=""
  branch=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch "*) branch="${line#branch refs/heads/}" ;;
      "detached") branch="(detached)" ;;
      "")
        if [ -n "$path" ]; then
          TOTAL=$((TOTAL + 1))
          resolved="$(cd "$path" 2>/dev/null && pwd -P)"

          clean="no"
          if [ -n "$resolved" ] && [ -z "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
            clean="yes"
          fi

          merged="no"
          if [ -n "$branch" ] && [ "$branch" != "(detached)" ] && [ "$branch" != "$BASE" ]; then
            if git -C "$REPO" merge-base --is-ancestor "$branch" "$BASE" 2>/dev/null; then
              merged="yes"
            fi
          fi

          age="unknown"
          last_commit_epoch="$(git -C "$path" log -1 --format=%ct 2>/dev/null)"
          if [ -n "$last_commit_epoch" ]; then
            now_epoch="$(date +%s)"
            age_days=$(( (now_epoch - last_commit_epoch) / 86400 ))
            age="${age_days}d"
          fi

          is_current="no"
          [ -n "$resolved" ] && [ "$resolved" = "$CURRENT" ] && is_current="yes"

          if [ "$merged" = "yes" ] && [ "$clean" = "yes" ] && [ "$is_current" = "no" ]; then
            printf '%s\tbranch=%s\tmerged=%s\tclean=%s\tage=%s\tcandidate\tremove: git worktree remove %s\n' \
              "$path" "${branch:-none}" "$merged" "$clean" "$age" "$path"
            CANDIDATES=$((CANDIDATES + 1))
          elif [ "$is_current" = "yes" ]; then
            printf '%s\tbranch=%s\tmerged=%s\tclean=%s\tage=%s\tkeep: current worktree\n' \
              "$path" "${branch:-none}" "$merged" "$clean" "$age"
          elif [ "$merged" = "no" ]; then
            printf '%s\tbranch=%s\tmerged=%s\tclean=%s\tage=%s\tkeep: unique commits\n' \
              "$path" "${branch:-none}" "$merged" "$clean" "$age"
          else
            printf '%s\tbranch=%s\tmerged=%s\tclean=%s\tage=%s\tkeep: dirty tree\n' \
              "$path" "${branch:-none}" "$merged" "$clean" "$age"
          fi
        fi
        path=""
        branch=""
        ;;
    esac
  done
  echo "$CANDIDATES removal candidate(s) of $TOTAL registered worktree(s)"
}

exit 0
