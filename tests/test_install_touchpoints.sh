#!/usr/bin/env bash
# tests/test_install_touchpoints.sh — every shipped hook file is wired through
# ALL of the installer's per-file touchpoints.
#
# Adding a hook means editing install.sh in five places: the manifest list, the
# pre-install backup, the rollback restore, the fresh-install cleanup, and the
# forward copy. Miss the copy and `install.sh --check` reports the file as
# installed-but-missing; miss the cleanup and a rolled-back install leaves debris.
# Both happened on 2026-08-03 while adding agent-team-lanes.json, which is why
# this is a test rather than a checklist in a document — a checklist is prose, and
# the whole point of that day's work was that prose does not hold.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$HERE/../install.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL [$1]"; }

HOOK_FILES="$(sed -n 's/^HOOK_FILES="\(.*\)"$/\1/p' "$INSTALL")"
[ -n "$HOOK_FILES" ] && ok || no "HOOK_FILES is readable from install.sh"

for h in $HOOK_FILES; do
  [ -f "$HERE/../hooks/$h" ] && ok || no "$h exists in hooks/"
  grep -qF "cp \"\$REPO/hooks/$h\" \"\$HOOKS_DIR/\"" "$INSTALL" \
    && ok || no "$h has a forward copy into the hooks dir"
  grep -qF "[ -f \"\$HOOKS_DIR/$h\" ]" "$INSTALL" \
    && ok || no "$h is backed up before install"
  grep -qF "$h) cp \"\$b\" \"\$HOOKS_DIR/\" ;;" "$INSTALL" \
    && ok || no "$h is restored on rollback"
  grep -qF "rm -f \"\$HOOKS_DIR/$h\"" "$INSTALL" \
    && ok || no "$h is cleaned up after a failed fresh install"
done

# Shell hooks must pass their own syntax check, and the installer must say so.
for h in $HOOK_FILES; do
  case "$h" in
    *.sh)
      bash -n "$HERE/../hooks/$h" 2>/dev/null && ok || no "$h passes bash -n"
      grep -qF "bash -n \"\$REPO/hooks/$h\"" "$INSTALL" \
        && ok || no "install.sh syntax-checks $h before installing it"
      ;;
    *.json)
      jq empty "$HERE/../hooks/$h" 2>/dev/null && ok || no "$h is valid JSON"
      # A shell hook gets `bash -n` before it is installed; a JSON hook needs the
      # same courtesy from `jq empty`, or a malformed config installs silently and
      # the guard that reads it falls back to a default nobody asked for. Found by
      # review on 2026-08-17: the register's config was validated by nothing.
      grep -qF "jq empty \"\$REPO/hooks/$h\"" "$INSTALL" \
        && ok || no "install.sh validates $h as JSON before installing it"
      ;;
  esac
done

echo "install-touchpoint tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
