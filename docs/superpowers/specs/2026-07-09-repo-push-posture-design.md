# Per-Repo Push Posture — Design Spec

**Date:** 2026-07-09
**Author:** architect
**Status:** Proposed (design only — no hook, test, REPO.md, or CLAUDE.md file is touched by this spec)
**Tier:** Large (self-modifying policy config, multi-file, security-adjacent)

---

## 1. Problem

The policy hook (`hooks/agent-team-policy.sh` + `agent-team-policy-lib.sh`) applies one
hardcoded push posture to every repository: no agent may push to `main`/`master`; the
feature-branch + PR flow is forced always. That posture is correct for repos with real
GitHub governance (branch protection, rulesets, collaborators) and wrong for the owner's
solo repos. The immediate case: `jayheavner/agent-workforce` (this repo, at
`/Users/jay/claude/ai-agent-team`) has **no** branch protection and **no** rulesets
(verified via `gh api` by the owner), and the owner wants agents to push directly to
`main` there, including force-push — while protected repos keep the strict posture.

## 2. Decided constraints (set by the orchestrator — designed within, not re-opened)

1. **Three-part behavior:** INVESTIGATE (determine a repo's real GitHub governance),
   DOCUMENT (record the finding in a human-readable `REPO.md` at the repo root,
   referenced from the repo's `CLAUDE.md` so it is read every session), ADAPT + REMEMBER
   (the policy hook consults the recorded determination; no re-investigation per command).
2. `REPO.md` is prose for humans **plus exactly one machine-greppable marker line** the
   bash hook keys its decision on.
3. Marker `unrestricted` ⇒ hook allows push to `main`/`master` and force-push to main.
   No marker, or `restricted`, or anything malformed ⇒ current strict behavior.
   **Fail safe: absence or ambiguity always means strict, never permissive.**
4. INVESTIGATE uses the already-proven read-only `gh api` checks (branch protection,
   rulesets, owner type, caller permissions), with a defined decision rule and a defined
   strict fallback when GitHub is unreachable or auth is wrong.

## 3. Design overview

```
INVESTIGATE (ops, via new vendored skill) ──> DOCUMENT (REPO.md + CLAUDE.md reference)
                                                      │
                                                      ▼  one marker line
ADAPT (policy hook, per Bash call):  cwd ──walk-up──> repo root ──grep──> posture
                                                      │
                                     strict (default) ┴ unrestricted (marker match only)
```

- The hook learns the session working directory from the hook input JSON's `cwd` field,
  walks up to the repo root (`.git` entry), and greps `REPO.md` there for the marker.
  Everything is offline, deterministic, and lazy (computed only when a `git push`
  segment is actually seen, cached per invocation).
- Builder is the push seat and gains posture-gated main-push. Ops gains the **same
  posture gate** on `git push` — which is a *tightening*: today ops has no git checks at
  all and can silently push to main anywhere (§12, defect D2). Deployer, verifier,
  reviewer keep their existing total `git push` block in both postures.
- Granting `unrestricted` is a human decision: the investigation skill requires an
  explicit human gate before the permissive marker is ever written.

## 4. REPO.md — structure, template, and marker grammar

### 4.1 Marker grammar (normative)

One plain-text line, at the start of a line, nothing else on the line:

```
agent-team-push-policy: unrestricted
```

Formal grammar (POSIX ERE the hook uses, anchored both ends):

```
^agent-team-push-policy:[[:space:]]*(unrestricted|restricted)[[:space:]]*$
```

Rules, all enforced by the hook:

- **Key:** literal lowercase `agent-team-push-policy:` at column 0. No leading
  whitespace, no Markdown decoration (`**`, `-`, `>`), no backticks.
- **Value:** exactly `unrestricted` or `restricted`, lowercase. Any other value —
  including case variants (`Unrestricted`), typos, trailing words — is **malformed** and
  resolves to strict.
- **Exactly one marker line per file.** The hook first counts lines matching
  `^agent-team-push-policy:`; if the count is not exactly 1, posture is strict — even if
  one of the lines says `unrestricted`. Zero markers = strict; duplicates = strict.
  Ambiguity deactivates, never activates.
- `restricted` and "no marker" produce the identical strict outcome; `restricted` exists
  so a human can record "we investigated and this repo IS governed" explicitly rather
  than by omission.

**Why this syntax and not an HTML comment** (`<!-- agent-team:push-policy=... -->`):

1. **Visibility.** This line is a standing security grant. An HTML comment disappears in
   every rendered Markdown view (GitHub, editors' preview) — exactly where a human
   skims the file. A grant of push-to-main must be visible wherever the document is
   read, so the tradeoff stays conscious (§10).
2. **Equal determinism.** A column-0 anchored, namespaced key is exactly as greppable as
   a comment; the comment buys nothing mechanically.
3. **Accident resistance.** The 22-character namespaced key does not occur in natural
   prose. Column-0 anchoring plus the nothing-else-on-the-line rule means quoting the
   marker in a sentence, a backticked code span, an indented code block, or a fenced
   example cannot activate it. And if someone *does* paste a second copy at column 0,
   the exactly-one rule downgrades to strict rather than activating anything.
4. **Keeps REPO.md a document, not a config blob.** A comment syntax invites growth into
   hidden key=value config. One visible labeled line reads as part of the prose.

Convention for the template below: whenever the marker is *discussed* in REPO.md prose,
it is written in backticks or indented, so the real marker is the only column-0 instance.

### 4.2 REPO.md template (normative content skeleton)

```markdown
# REPO.md — what this repository is and how agents may push

## What this repository is

[2–5 sentences of plain prose: purpose of the repo, who owns it, who else
works in it, where it lives on GitHub (owner/name).]

## Push governance investigation

Investigated on [YYYY-MM-DD] by [role/human] using read-only GitHub API calls:

- Default branch: [main]
- Branch protection on the default branch: [none — API returned 404 | present: ...]
- Rulesets applying to the default branch: [none | list]
- Repository owner type: [User | Organization]
- Authenticated caller's permission: [admin | ...]

## Push posture

[Prose: which posture applies and WHY — e.g. "This is a solo, user-owned repository
with no branch protection and no rulesets; the owner approved direct pushes to main,
including force-push, on YYYY-MM-DD." For strict: "This repo has branch protection /
collaborators; agents use feature branches and PRs."]

The machine-readable marker for the agent team's policy hook is the single line below.
The hook treats any file without exactly one well-formed marker line as strict.

agent-team-push-policy: unrestricted

## Re-investigation triggers

Re-run the investigation (and update this file) if: a push is rejected by GitHub
unexpectedly; the repo gains collaborators, moves to an organization, or gains branch
protection or rulesets; or the owner asks for the posture to change.
```

(For a strict repo the marker line reads `agent-team-push-policy: restricted`.)

## 5. CLAUDE.md reference mechanism

Claude Code reads `CLAUDE.md` at the repo root every session and supports `@path`
imports that inline the referenced file. The repo's root `CLAUDE.md` gets this section
(created if the file does not exist — this repo currently has **no** root `CLAUDE.md`;
the ancestor files at `/Users/jay/claude/CLAUDE.md` and `/Users/jay/CLAUDE.md` compose
with it and are untouched):

```markdown
# Repository governance

@REPO.md

The file above records what this repository is, the GitHub-governance investigation
findings, and which push posture the agent team's policy hook applies here. If the
facts on GitHub change (protection added, collaborators added, ownership transferred),
re-run the repo-push-posture investigation before relying on the recorded posture.
```

The `@REPO.md` import guarantees the prose is in context every session (matching how
this project already handles per-project instruction files: a root-level instruction
file with pointers, e.g. the doc-inventory README pointer pattern). The hook never reads
CLAUDE.md; only REPO.md carries the marker.

## 6. INVESTIGATE + DOCUMENT workflow

### 6.1 Form: a new vendored skill, executed by ops

**Recommendation: a new skill at `skills/repo-push-posture/SKILL.md`** in this repo
(installed to `~/.claude/skills/` by the existing install.sh skills loop), listed in the
ops agent's `skills:` frontmatter so install.sh's resolver validates it.

Why a skill rather than an orchestrator procedure or a manual step:

- **Repeatable across repos** — the whole point; a skill is the team's unit of
  repeatable procedure and gets installed/validated by the existing machinery.
- **Ops is the right seat** — ops already holds `gh`/API/web access and the read-only
  discipline; the checks are exactly the read-only calls ops is allowed to run. Ops can
  also write files (the Write/Edit path policy only constrains architect/scribe), so it
  can create REPO.md and the CLAUDE.md section itself.
- **Orchestrator involvement stays at the gate** — the orchestrator dispatches ops with
  the skill when onboarding a repo or when a push block looks wrong, and hosts the human
  gate before an `unrestricted` marker is written.

### 6.2 Skill procedure (normative)

1. Identify the repo: `git remote get-url origin` from the repo root; parse owner/name.
2. Read-only GitHub facts (all `gh api`, no mutations):
   - `gh api repos/<owner>/<repo>` → `.default_branch`, `.owner.type`, `.permissions`
   - `gh api repos/<owner>/<repo>/branches/<default>/protection` → expect HTTP 404
     ("Branch not protected") when none
   - `gh api repos/<owner>/<repo>/rulesets` → the configured rulesets, and
     `gh api repos/<owner>/<repo>/rules/branches/<default>` → the **effective** rules on
     the default branch (this endpoint merges active rulesets; an empty array means no
     ruleset governs the branch)
3. **Decision rule:**
   - Eligible for `unrestricted` **only if ALL of:** protection endpoint returned 404;
     effective rules array for the default branch is empty; `.owner.type == "User"`;
     `.permissions.admin == true` for the authenticated caller.
   - **Strict if ANY of:** protection exists (HTTP 200); any effective rule on the
     default branch; owner type is Organization; caller lacks admin; **or any check
     could not be completed** (network error, 401/403, ambiguous output — anything that
     is not a clean 404/empty). On failure, record strict and report the failure to the
     orchestrator; never guess permissive.
4. **Human gate (mandatory for `unrestricted`):** eligibility is not a grant. Ops
   reports the findings; the orchestrator presents them to the human; only explicit
   human approval authorizes writing `agent-team-push-policy: unrestricted`. Writing
   `restricted` needs no gate (it changes nothing the hook enforces).
5. **Document:** write REPO.md per §4.2 with the findings and date; add/extend the root
   CLAUDE.md section per §5. (Because the builder's raw-mutation rules forbid shell
   redirection, all file creation uses the Write/Edit tools, never `>`/`tee` — this also
   satisfies the team-wide "no shell file deletion/move" constraint.)

## 7. Policy hook change

### 7.1 Current state (read from source, 2026-07-09)

- `hooks/agent-team-policy.sh` extracts `TOOL`/`CMD`/`FILE`/`CONTENT` from the hook JSON.
  It does **not** read the JSON's `cwd` field.
- `hooks/agent-team-policy-lib.sh` lines 161–181 (`_policy_builder_seg`): three
  main/master patterns (bare token, `:dest` refspec, `refs/heads/`), then the line-178
  "must name a remote and an explicit branch" shape check.
- **Force-push today:** there is no explicit force check anywhere.
  - `git push --force origin main` blocks — but only via the bare `main` token pattern.
  - `git push -f origin feature` / `git push --force origin feature` (flags before the
    remote) block — but only as a side effect of the line-178 shape regex, whose
    `(-u[[:space:]]+)?` tolerates only `-u`.
  - **Gap A (live):** `git push origin +main` — the `+`-refspec force push — is
    **allowed** today: `+main` defeats the whitespace-anchored `(main|master)` pattern
    and satisfies the shape check.
  - **Gap B (live):** `git push origin feature --force` (flag *after* the refspec) is
    **allowed** today.
  - **Gap C (live):** `git -C /path push origin main` never matches
    `git[[:space:]]+push`, so it bypasses the entire push block for builder.
- **Ops:** `_policy_ops_seg` routes git commands only through
  `_deny_raw_mutation_primitives_seg`, which deliberately excludes git verbs — so ops
  can run **any** `git push`, including to main, today (defect D2, §12).
- Deployer/verifier/reviewer: `_deny_shell_mutation_seg` blocks all `git push`.

### 7.2 Files changed

| File | Change |
|---|---|
| `hooks/agent-team-policy.sh` | Extract `CWD` from hook JSON (one added jq expression). |
| `hooks/agent-team-policy-lib.sh` | Source the new push file; replace inline push block (lines 161–181) and add the ops call site with calls to the shared seg check. Net line count shrinks. |
| `hooks/agent-team-policy-push.sh` | **New** sourced file (third file in the source chain, mirroring the mutations split): repo-root discovery, posture computation, shared push seg check. Keeps every hook file under the 300-line ceiling. |
| `install.sh` | Add the new file to `HOOK_FILES`, existence + `bash -n` validation, backup (`PREEXISTING_POLICY_PUSH`), `restore()` case, `cleanup_fresh()` line, install `cp`. No chmod (sourced, not executed). |
| `tests/test_policy_hooks.sh` | New `cwd`-aware helper, fixtures, assertions (§9). |

### 7.3 Entry-point change (`agent-team-policy.sh`)

After the existing `CMD` extraction in the `Bash` case:

```bash
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"
```

`cwd` is a standard top-level field of PreToolUse hook input. If absent or empty,
posture is strict (fail safe) — so on any harness version that omits it, the feature
degrades to exactly today's behavior. (Builder verification step: after implementation,
confirm live that `.cwd` is populated by inspecting one audit line / a manual hook run.)

### 7.4 Repo-root discovery (deterministic, offline)

Pure string walk from `$CWD` upward; the first directory containing a `.git` **entry**
(`-e` — directory for normal clones, file for worktrees/submodules) is the repo root.
No `git` subprocess (no dependence on git config, PATH, or repo health). Reference
implementation (in the new file):

```bash
repo_root_of() { # $1 absolute dir; prints repo root, or returns 1
  local d="$1"
  case "$d" in /*) : ;; *) return 1 ;; esac
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -e "$d/.git" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  return 1
}
```

No `.git` found before `/` ⇒ no root ⇒ strict.

### 7.5 Posture computation (lazy, cached, fail-safe)

Computed only when a segment containing a push is seen; cached in a global for the rest
of the invocation. Reference implementation:

```bash
_PUSH_POSTURE=""
push_posture() { # prints "strict" or "unrestricted"
  [ -n "$_PUSH_POSTURE" ] && { printf '%s' "$_PUSH_POSTURE"; return 0; }
  _PUSH_POSTURE="strict"
  # If the command chain can change directories or point git elsewhere, the
  # session cwd no longer identifies the push target repo — stay strict.
  if [ -n "${CWD:-}" ] \
     && ! has '(^|[;&|[:space:]])(cd|pushd|popd)([[:space:]]|$)' \
     && ! has 'git[[:space:]]+-C([[:space:]=]|$)'; then
    local root
    root="$(repo_root_of "$CWD")" || root=""
    if [ -n "$root" ] && [ -f "$root/REPO.md" ] \
       && [ "$(grep -c '^agent-team-push-policy:' "$root/REPO.md" 2>/dev/null)" = "1" ] \
       && grep -qE '^agent-team-push-policy:[[:space:]]*unrestricted[[:space:]]*$' "$root/REPO.md"; then
      _PUSH_POSTURE="unrestricted"
    fi
  fi
  printf '%s' "$_PUSH_POSTURE"
}
```

Every failure mode lands strict: missing `cwd`; relative `cwd`; no `.git` ancestor; no
`REPO.md`; unreadable `REPO.md` (grep error ⇒ count ≠ 1); zero markers; multiple
markers; `restricted`; malformed value; a `cd`/`pushd`/`popd`/`git -C` anywhere in the
chain (cwd can no longer be trusted to name the target repo).

### 7.6 Shared push segment check

The inline builder push block (lib lines 161–181) moves into
`_check_git_push_policy_seg` in the new file; `_policy_builder_seg` calls it, and
`_policy_ops_seg` gains the same call before its raw-mutation check. Push **detection**
widens from `git[[:space:]]+push` to also match global flags between `git` and `push`
(closing Gap C for detection):

```
git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(-[^[:space:]]+[[:space:]]+)*push([[:space:]]|$)
```

(`git commit -m "push to main"` does not match: the token after `git` is `commit`,
neither a `-` flag nor `push`. A `git -C` push, once detected, is always strict by §7.5
and then fails the strict shape check — i.e. blocked; conservative and honest.)

Behavior (reference implementation, block messages use `$ROLE`, not "builder"):

```bash
_check_git_push_policy_seg() { # $1 = segment already known to contain a git push
  local seg="$1"
  if [ "$(push_posture)" = "unrestricted" ]; then
    # Bare `git push` stays blocked in BOTH postures: every push must name an
    # explicit remote and refspec, flags tolerated anywhere.
    if ! has_in "$seg" 'git[[:space:]]+push([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^-[:space:]][^[:space:]]*([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^[:space:]]+'; then
      block "git push must name a remote and an explicit branch — required in every posture" "$CMD"
    fi
    audit allow-unrestricted-push "posture=unrestricted seg=$seg"
    return 0
  fi
  # --- strict path: existing three main/master checks, verbatim ---
  if has_in "$seg" 'git[[:space:]]+push[^;&|]*[[:space:]](main|master)([[:space:]]|$|:)'; then
    block "$ROLE may not push to main/master in this repo (strict posture)" "$CMD"
  fi
  if has_in "$seg" ':(main|master)([[:space:]]|$)'; then
    block "$ROLE may not push to main/master in this repo (strict posture)" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]:])refs/heads/(main|master)([[:space:]]|$|:)'; then
    block "$ROLE may not push to main/master in this repo (strict posture)" "$CMD"
  fi
  # --- NEW: explicit force-push block on the strict path (closes Gaps A and B) ---
  if has_in "$seg" '(^|[[:space:]])--force' \
     || has_in "$seg" '(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)'; then
    block "force push is not allowed in strict posture" "$CMD"
  fi
  if has_in "$seg" 'git[[:space:]]+push[^;&|]*[[:space:]]\+[^[:space:]]'; then
    block "'+refspec' force push is not allowed in strict posture" "$CMD"
  fi
  # --- existing line-178 shape safety, PRESERVED verbatim on the strict path ---
  if ! has_in "$seg" 'git[[:space:]]+push[[:space:]]+(-u[[:space:]]+)?[^-[:space:]][^[:space:]]*[[:space:]]+[^[:space:]]+'; then
    block "git push must name a remote and an explicit feature branch" "$CMD"
  fi
  return 0
}
```

Notes:

- `--force` is matched as a prefix so `--force-with-lease`, `--force-if-includes`, and
  `--force-with-lease=ref:sha` are all caught. The short-flag pattern catches `-f` and
  fused clusters containing `f` (git push's short flags are `-u -f -q -v -n -d -4 -6`;
  none legitimately combines with `f` in this team's workflows — accepted small
  overmatch in favor of safety, consistent with the hp2 tradeoff precedent).
- **Intentional strict-path tightenings vs today:** `git push origin +main` (Gap A) and
  `git push origin feature --force` / `+feature` (Gap B) now block. Force-pushing a
  feature branch was implicitly reachable before; under strict posture it is now
  uniformly blocked — feature-branch history rewrites on a governed repo go through a
  human, and on a solo repo the unrestricted posture allows them anyway.
- Permissive decisions are always audited: the `allow-unrestricted-push` audit line
  (via the existing `audit()`, which does not exit) records posture and segment before
  the normal terminal `allow` fires, so every main-push grant is traceable in
  `~/.claude/logs/agent-team-audit.log`.

### 7.7 Allow/block matrix (normative)

Roles: builder and ops share the gated behavior below. Deployer, verifier, reviewer:
**all `git push` blocked in both postures** (unchanged — their full git-verb blocklist
stays). Architect/scribe have no Bash git surface change.

| Command shape (builder / ops) | Strict (default) | Unrestricted |
|---|---|---|
| `git push origin feature/x` | **ALLOW** (unchanged) | **ALLOW** |
| `git push -u origin feature/x` | **ALLOW** (unchanged) | **ALLOW** |
| `git push origin main` / `master` | **BLOCK** (unchanged; **new for ops**) | **ALLOW** |
| `git push origin HEAD:main` / `main:main` / `refs/heads/main` | **BLOCK** (unchanged) | **ALLOW** |
| `git push --force origin main`, `git push -f origin main` | **BLOCK** | **ALLOW** |
| `git push origin +main` | **BLOCK** (was allowed — Gap A closed) | **ALLOW** |
| `git push origin feature --force` / `origin +feature` | **BLOCK** (was allowed — Gap B closed) | **ALLOW** |
| bare `git push` (no remote/refspec) | **BLOCK** (unchanged) | **BLOCK** (kept in both postures) |
| `cd X && git push …`, `pushd … git push`, `git -C X push …` | **BLOCK-as-strict** (posture forced strict; `-C` also fails the shape check) | same — posture never resolves unrestricted when the chain moves directories |
| `git push origin :feature` (delete remote feature branch) | ALLOW (unchanged, shape check passes) | ALLOW |
| `git push origin :main` | **BLOCK** (unchanged) | **ALLOW** |

Posture resolution (all rows fail safe):

| REPO.md state at repo root | Posture |
|---|---|
| Exactly one line `agent-team-push-policy: unrestricted` | unrestricted |
| Exactly one line `agent-team-push-policy: restricted` | strict |
| No REPO.md / no marker line | strict |
| Marker malformed (case, typo, extra text, decoration, indent) | strict |
| Two or more marker lines (any values) | strict |
| REPO.md unreadable / grep error | strict |
| No `cwd` in hook input, relative cwd, or no `.git` ancestor | strict |
| Chain contains `cd`/`pushd`/`popd`/`git -C` | strict |

## 8. Role decision

- **Builder** is the push seat: it commits and pushes as part of the TDD loop, so it
  gains the posture-gated main-push. This is the primary grant.
- **Ops** gets the same gated check — but for ops this is a **tightening**, not a grant:
  today ops has zero git governance and can push to main on any repo silently (§12 D2).
  Routing ops `git push` through the shared check means ops pushes obey the same
  recorded posture. Ops does not *need* main-push for its duties (investigation is
  read-only), but if it ever pushes, it must not be the one role that ignores posture.
  Ops's other git verbs (commit, etc.) remain ungoverned — flagged in §12, not expanded
  here.
- **Deployer, verifier, reviewer:** no change; all pushes stay blocked regardless of
  posture. The unrestricted marker widens nothing for read-only or deploy roles.

## 9. Test plan (`tests/test_policy_hooks.sh`)

### 9.1 Harness additions

A cwd-aware JSON helper (existing `bash_json` is untouched, so **every existing
assertion runs with no `cwd` ⇒ strict ⇒ current behavior preserved verbatim**):

```bash
bash_cwd_json() { # $1 command, $2 cwd
  jq -cn --arg c "$1" --arg d "$2" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'
}
```

Fixtures under the existing `$TMPDIR_T`:

```bash
R_UN="$TMPDIR_T/repo-unrestricted";  mkdir -p "$R_UN/.git" "$R_UN/sub/dir"
printf '# REPO.md\n\nagent-team-push-policy: unrestricted\n' > "$R_UN/REPO.md"
R_RE="$TMPDIR_T/repo-restricted";    mkdir -p "$R_RE/.git"
printf 'agent-team-push-policy: restricted\n' > "$R_RE/REPO.md"
R_MAL="$TMPDIR_T/repo-malformed";    mkdir -p "$R_MAL/.git"
printf 'agent-team-push-policy: Unrestricted-ish\n' > "$R_MAL/REPO.md"
R_DUP="$TMPDIR_T/repo-duplicate";    mkdir -p "$R_DUP/.git"
printf 'agent-team-push-policy: unrestricted\nagent-team-push-policy: restricted\n' > "$R_DUP/REPO.md"
R_NOMARK="$TMPDIR_T/repo-nomarker";  mkdir -p "$R_NOMARK/.git"
printf '# REPO.md with prose only\n' > "$R_NOMARK/REPO.md"
R_NOMD="$TMPDIR_T/repo-norepomd";    mkdir -p "$R_NOMD/.git"
R_NOGIT="$TMPDIR_T/not-a-repo";      mkdir -p "$R_NOGIT"
```

### 9.2 New assertions (exact)

```bash
# --- push posture: unrestricted marker ---
expect_allow builder "$(bash_cwd_json 'git push origin main' "$R_UN")"                "posture: marker=unrestricted, push origin main ALLOWS for builder"
expect_allow builder "$(bash_cwd_json 'git push origin master' "$R_UN")"              "posture: marker=unrestricted, push origin master ALLOWS for builder"
expect_allow builder "$(bash_cwd_json 'git push --force origin main' "$R_UN")"        "posture: marker=unrestricted, force-push main ALLOWS for builder"
expect_allow builder "$(bash_cwd_json 'git push -f origin main' "$R_UN")"             "posture: marker=unrestricted, -f push main ALLOWS for builder"
expect_allow builder "$(bash_cwd_json 'git push origin +main' "$R_UN")"               "posture: marker=unrestricted, +refspec force ALLOWS for builder"
expect_allow builder "$(bash_cwd_json 'git push origin HEAD:main' "$R_UN")"           "posture: marker=unrestricted, HEAD:main refspec ALLOWS for builder"
expect_allow builder "$(bash_cwd_json 'git push origin feature/x' "$R_UN")"           "posture: marker=unrestricted, feature push still ALLOWS"
expect_block builder "$(bash_cwd_json 'git push' "$R_UN")"                            "posture: marker=unrestricted, bare git push still BLOCKS (remote+branch required in every posture)"
expect_allow builder "$(bash_cwd_json 'git push origin main' "$R_UN/sub/dir")"        "posture: repo-root walk-up from subdirectory resolves the marker"
expect_allow ops     "$(bash_cwd_json 'git push origin main' "$R_UN")"                "posture: marker=unrestricted, ops push main ALLOWS"
expect_block builder "$(bash_cwd_json 'cd /elsewhere && git push origin main' "$R_UN")" "posture: cd in chain forces strict — push main BLOCKS even in unrestricted repo"
expect_block builder "$(bash_cwd_json 'git -C /elsewhere push origin main' "$R_UN")"  "posture: git -C forces strict — push main BLOCKS even in unrestricted repo"

# --- push posture: fail-safe resolutions (all strict) ---
expect_block builder "$(bash_cwd_json 'git push origin main' "$R_RE")"     "posture: marker=restricted, push main BLOCKS"
expect_allow builder "$(bash_cwd_json 'git push origin feature/x' "$R_RE")" "posture: marker=restricted, feature push still ALLOWS"
expect_block builder "$(bash_cwd_json 'git push origin main' "$R_MAL")"    "posture: malformed marker fails safe — push main BLOCKS"
expect_block builder "$(bash_cwd_json 'git push origin main' "$R_DUP")"    "posture: duplicate markers fail safe — push main BLOCKS"
expect_block builder "$(bash_cwd_json 'git push origin main' "$R_NOMARK")" "posture: REPO.md without marker — push main BLOCKS"
expect_block builder "$(bash_cwd_json 'git push origin main' "$R_NOMD")"   "posture: no REPO.md — push main BLOCKS (current behavior preserved)"
expect_block builder "$(bash_cwd_json 'git push origin main' "$R_NOGIT")"  "posture: no .git ancestor — push main BLOCKS"
expect_block builder "$(bash_json 'git push origin main')"                 "posture: no cwd in hook input — push main BLOCKS (regression of original assertion)"
expect_block ops     "$(bash_json 'git push origin main')"                 "posture: ops push main BLOCKS under strict (NEW governance — was silently allowed)"
expect_block ops     "$(bash_json 'git push --force origin main')"         "posture: ops force-push main BLOCKS under strict"

# --- strict-path force-push gaps closed (no cwd => strict) ---
expect_block builder "$(bash_json 'git push origin +main')"                "force: +main refspec BLOCKS under strict (Gap A closed — was allowed)"
expect_block builder "$(bash_json 'git push origin feature --force')"      "force: trailing --force on feature BLOCKS under strict (Gap B closed — was allowed)"
expect_block builder "$(bash_json 'git push origin +feature')"             "force: +feature refspec BLOCKS under strict"
expect_block builder "$(bash_json 'git push --force-with-lease origin feature')" "force: --force-with-lease BLOCKS under strict"

# --- regressions: existing behavior must stay identical under strict ---
expect_block builder "$(bash_json 'git push origin main')"        "regression: push main still BLOCKS with no posture context"
expect_block builder "$(bash_json 'git push')"                    "regression: bare push still BLOCKS"
expect_allow builder "$(bash_json 'git push origin feature/hooks')" "regression: feature push still ALLOWS"
expect_allow builder "$(bash_json 'git push origin feature/main')" "regression: feature/main path segment still ALLOWS"
expect_block deployer "$(bash_cwd_json 'git push origin main' "$R_UN")" "regression: deployer push blocked even in unrestricted repo (full git blocklist unchanged)"
expect_block verifier "$(bash_cwd_json 'git push origin main' "$R_UN")" "regression: verifier push blocked even in unrestricted repo"
```

All pre-existing assertions run unmodified and must stay green (they carry no `cwd`,
which is exactly the strict path).

### 9.3 install.sh validation stays green

- The new hook file joins `HOOK_FILES` and gets the same existence + `bash -n` checks as
  its siblings, so validation covers it before anything is copied.
- `install.sh` already runs `tests/test_policy_hooks.sh` during validation; the new
  assertions ride that existing call. No new test wiring.
- The new `skills/repo-push-posture/` directory must satisfy the existing vendored-skill
  validation (SKILL.md present, `name:` matching the directory, `description:` present)
  and, once listed in ops's frontmatter `skills:`, the resolver check.
- Manifest, backup/restore, and `--check` drift detection pick the new file up through
  the same lists every other hook file is in (§7.2 enumerates each list to touch).

## 10. Security tradeoff (explicit, by design)

**Anyone (or any process) that can write `REPO.md` in a repo can grant agents
push-to-main and force-push there.** In a solo, unprotected repo that is precisely the
intent — the file is the owner's recorded decision. Make the tradeoff conscious:

- The grant is a visible, greppable line in a human-readable file at the repo root,
  imported into every session's context via CLAUDE.md — not hidden config.
- Writing `unrestricted` requires a human gate (§6.2 step 4). The hook cannot verify
  who wrote the marker; the gate plus the audit line (`allow-unrestricted-push`) are the
  compensating controls.
- Fail-safe direction is asymmetric on purpose: every parsing/location/ambiguity failure
  lands strict. The only way to get permissive is the exact single well-formed line.
- Defense in depth runs one way only: if a marker wrongly says `unrestricted` on a repo
  that actually HAS GitHub protection, GitHub itself still rejects the push. The
  genuinely unguarded case is a wrong `unrestricted` marker on an unprotected repo —
  which is indistinguishable from the intended use and is why the human gate exists.

**Residual risks (accepted, documented):** posture derives from the session `cwd`, so a
command that changes directory mid-chain or uses `git -C` could target a different repo
than the one investigated — mitigated by forcing strict whenever `cd`/`pushd`/`popd`/
`git -C` appears in a chain (§7.5). The regex layer remains best-effort text scanning,
not a shell parser, consistent with the hook's existing stated scope.

## 11. Migration: this repo (`jayheavner/agent-workforce`)

Part of the rollout, so the owner's immediate goal (agents pushing to main here) is
satisfied at ship time:

1. Ops (or the builder executing the plan, since the findings are already verified)
   creates `/Users/jay/claude/ai-agent-team/REPO.md` per the §4.2 template with the
   verified findings: default branch `main`; branch protection: none (404); rulesets
   /effective branch rules: none; owner type: User; caller permission: admin; posture
   prose citing the owner's 2026-07-09 approval; marker line
   `agent-team-push-policy: unrestricted`.
2. Create `/Users/jay/claude/ai-agent-team/CLAUDE.md` (none exists today) with the §5
   governance section. Both files are written with the Write tool (no shell redirection).
3. The human gate for this repo is satisfied by the owner's explicit direction in this
   task's dispatch ("push directly to main, including force-push, on such repos" with
   the governance facts verified); record that in REPO.md's investigation section.
4. Re-run `bash install.sh` so the new hook file lands in `~/.claude/hooks/` and the
   manifest records it; `bash install.sh --check` must pass.

## 12. Known related defects — flagged for separate follow-up, NOT fixed here

- **D1 — `install` word false-match:** `_deny_raw_mutation_primitives_seg` blocks the
  literal token `install` anywhere it appears surrounded by spaces — including inside
  quoted text (commit messages, PR bodies). It caused two workarounds this session
  (e.g. `git commit -m "docs: install notes"` blocks). Same class as the fixed
  "legit commit history" false positive; deserves its own scoped fix + tests.
- **D2 — ops git governance gap:** ops has no git-verb restrictions at all today. This
  design gates ops `git push` (§8) but leaves other ops git mutations ungoverned;
  whether ops should get the fuller blocklist is a separate policy decision.
- **D3 — `git -C` bypass class:** global git flags before the verb defeat every
  `git[[:space:]]+<verb>` pattern across ALL roles' git checks (not just push — e.g.
  `git -C x commit` bypasses `_deny_shell_mutation_seg` for reviewer). This design
  closes it for push only (§7.6 detection + strict-forcing); the general class needs a
  shared fix.

## 13. Out of scope

- Any change to non-push git governance, the mutations blocklist, or other roles' policies.
- Auto-refresh/staleness detection of REPO.md against live GitHub state (re-investigation
  is trigger-driven prose guidance, §4.2).
- Markers for anything beyond push posture (no config-blob growth; one key, two values).
- Fixing D1–D3 beyond what §7.6 covers for push.

---

## Self-review (spec-completeness pass)

- Every dispatch requirement mapped: marker grammar + justification (§4.1), REPO.md
  template (§4.2), CLAUDE.md mechanism (§5), hook location/grep/matrix/fail-safe
  (§7.4–7.7), line-178 preservation (§7.6, verbatim on strict path), force-push status
  finding + new strict block (§7.1, §7.6), role decision incl. ops (§8), workflow
  recommendation (§6), test plan with exact assertions + install.sh validation (§9),
  migration (§11), security caveat (§10), install-word defect flag (§12 D1).
- Fail-safe table enumerates every discovered failure mode; no path resolves permissive
  except the single exact marker.
- No placeholders; all regexes and commands are concrete; reference implementations are
  normative for behavior, with the builder free to match style, not semantics.
