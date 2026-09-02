# AI Agent Workforce

A twelve-role AI team you hand a task and get back a verified, priced result. The orchestrator
runs as the main session, routes work through the smallest set of specialists that can deliver
it, executes unattended inside standing authorization, and ends every task the same way: fresh
verification, a focused commit, one status note, and an exact whole-session cost report that a
Stop hook computes and enforces mechanically.

Design rationale: `docs/superpowers/specs/2026-07-18-autonomy-first-redesign.md` (the
autonomy-first redesign) supersedes the process-assurance era; the original team design is
`docs/superpowers/specs/2026-07-07-ai-agent-team-design.md`.

## Quick start

First time on a machine:

```bash
git clone https://github.com/jayheavner/agent-workforce.git
cd agent-workforce
./bin/agent-workforce        # installs the team into your profile, then starts it
```

Every time after that, from any directory:

```bash
agent-workforce
```

**You install once, and never again.** After the first `./bin/agent-workforce`, every later change
— merged, pulled, or edited locally — is picked up by the launcher itself, which refuses to start a
stale profile. Never tell a human to run `install.sh` to pick up a change; the only manual step a
change needs is landing it on the ref the launcher will see (`main`). `install.sh` by hand is for a new
profile, a non-default `CLAUDE_CONFIG_DIR`, or diagnosing a broken install — not for delivery.

That one command is the whole interface. The installer puts an `agent-workforce` shim at
`~/.local/bin/agent-workforce` (it warns if that directory is not on your PATH); the shim runs
the repo launcher, which fetches the latest build, checks the active profile
(`CLAUDE_CONFIG_DIR`, default `~/.claude`) against the checkout, **self-installs when stale**,
and starts the orchestrator with full autonomy. Give it a task; it triages in one paragraph
and goes.

> **Do not start the team with `claude --agent orchestrator`.** It looks identical but
> silently drops `--permission-mode bypassPermissions` and the freshness check: every mutation
> prompts, and the agents may be stale. The session-start hook flags such sessions as
> DEGRADED and the orchestrator will tell you to restart.

```bash
CLAUDE_CONFIG_DIR="$HOME/.claude-work" agent-workforce   # another profile
agent-workforce --no-install                             # skip freshness check
agent-workforce --plugin                                 # legacy live plugin mode
```

Snapshot install is the primary mode on purpose: plugin-shipped agents ignore `hooks`,
`permissionMode`, and `mcpServers` frontmatter, so live plugin mode loses per-role enforcement
and no-prompt autonomy (the plugin router in `hooks/hooks.json` restores hooks, but nothing can
restore `permissionMode`). Hooks always install into `~/.claude/hooks` regardless of profile —
agent frontmatter references them by that fixed path because `CLAUDE_CONFIG_DIR` is not reliably
visible to hook subprocesses.

## Roster

| Agent | Model | Effort | Role | Mutation rights |
|---|---|---|---|---|
| orchestrator | opus-5 | high | Triage, route, dispatch, closeout. Main session; read-only shell for facts | None (read + dispatch) |
| architect | opus-5 | high | Specs, plans; drafts new skills/agents for team growth | Docs + provisional skills/agents |
| builder | sonnet-5 | high | TDD implementation, direct or from a plan; works in the unique worktree its dispatch names, created for it before launch | Its own worktree only + local git; never another builder's tree or the parent checkout; no deploy, no push to main |
| debugger | sonnet-5 | high | Root-cause diagnosis with evidence | None (read + run) |
| verifier | sonnet-5 | — | Runs the given criteria AND independently tries to break them | None (read + run) |
| reviewer | opus-5 | high | Code/security review; fidelity (delivered vs requested), plan + spec critique | None (read only) |
| test-author | sonnet-5 | high | Acceptance suite from a reviewed plan, before the builder; red-proven | Test files + local git only |
| deployer | sonnet-5 | medium | Cloud deploys with rollback discipline | Deploys within authorization |
| executor | sonnet-5 | — | Authorized shell work; commit finalizer | Within dispatched intent |
| researcher | sonnet-5 | — | Web/Glean/codebase facts with citations | None |
| ops | sonnet-5 | high | AWS/Azure/Okta reads free, mutations authorized | Within dispatched scope |
| scribe | sonnet-5 | — | Documents; one closeout status note per task | Docs only |
| ticketer | sonnet-5 | — | Asana via MCP | Within dispatched authorization |

Defaults, not fixed assignments: the orchestrator overrides per dispatch (`haiku` for lookups
and status notes; `opus` for cross-subsystem builds; `fable` only with a stated reason). No
role defaults to Fable. The reviewer always runs a different model than the builder it reviews.
Model pins live in frontmatter and `hooks/agent-model-defaults.json` (drift-tested at install).

## Routes

| Shape | Route |
|---|---|
| Question / lookup | Evidence, never memory — own shell or a `haiku` researcher |
| Trivial action | ONE executor dispatch; if it needs the builder it is code and the full builder chain applies |
| Clear, contained build | orchestrator authors lint-clean acceptance criteria → builder → verifier ∥ reviewer (fidelity mode; full review for risky surfaces) |
| Real design decisions | architect (one combined spec+plan) → reviewer plan-critique → architect folds findings → test-author (red acceptance suite) → builder (makes it pass; never edits it) → verifier ∥ reviewer |
| Multi-system / production | researcher → architect deep → same critique/test-author/build chain → deployer → smoke |
| Symptom ("X broken") | debugger first, fix routed by root cause |
| Research / ops / docs / tickets | specialist → artifact → authorized outward action |

The human is interrupted only for the four gate conditions (genuine values fork, material scope
expansion, unauthorized outward/destructive mutation, irreducible human action). Everything else
is decided and disclosed at closeout.

## Enforcement — mechanism over prose

| Mechanism | File | What it does |
|---|---|---|
| Secrets guard | `hooks/agent-team-secrets.sh` | Blocks credential values being written to files (the one blocking safety rule) |
| Audit log | `hooks/agent-team-audit.sh` | One line per shell command per role → `~/.claude/logs/agent-team-audit.log` |
| Dispatch guard | `hooks/agent-team-dispatch-guard.sh` | Valid `subagent_type` only; builder/verifier/test-author dispatches must carry an ACCEPTANCE CRITERIA block that survives the falsifiability lint (`lint_acceptance_checks.py` — a vacuous line blocks); administers workspace isolation as a side effect — a dispatch declares its change with `CHANGE: <slug>` at the start of a line, and this guard claims that change in the work register, then creates or adopts its worktree at `<project>/.claude/worktrees/<slug>` on `refs/heads/change/<slug>` (both derived from the slug) before the agent runs — or, when the human named an existing worktree with a second line `WORKTREE: <absolute path>`, adopts that worktree instead and creates nothing (the path must be one `git worktree list` already shows; integrate and remove then leave it in place). Every role that writes must declare one; a dispatch that writes nothing anywhere may instead carry the exact line `PARALLEL_SAFE: this dispatch writes nothing`, which the worktree guard then verifies rather than trusts. Refused: a malformed slug, a change held by another live session (the message names the holder, its age, and the human's `WORKFORCE_OVERRIDE: lane-refusal | <slug>` escape), a workspace that cannot be built (the claim it just wrote is released in the same run), a `WORKTREE:` line with no path, no `CHANGE:` beside it, a relative path, a path git does not list, or the shared checkout, a second worktree for an already-claimed change, and the retired `PARALLEL_SAFE` literal by name. **Different changes run concurrently**; inside one change the register's writer slot admits one writing dispatch at a time (builder, test-author, architect, scribe, executor, deployer) and is released by the next dispatch for that change, so a judge never waits on a builder that has finished. Every 10th dispatch requires a budget acknowledgment (the $51 stop-loss) |
| Worktree guard | `hooks/agent-team-worktree-guard.sh` | Enforces `policy:workspace-isolation` on all ten roles that hold a writing or shell tool (the researcher and the ticketer deny those tools, so there is nothing to police). Confinement comes from the **register**, never from a transcript scan: the candidate set is the live claims this session holds, and the agent's own dispatch prompt is only a selector among them — more than one candidate with no selector is a refusal naming every candidate, never a pick by recency (the 2026-08-04 defect, where one malformed line refused six later dispatches). PreToolUse(Write\|Edit\|NotebookEdit\|Bash) only, so reads are never gated by construction. A write is legal inside the resolved change's worktree, or inside a lane the role owns that lies outside every git working tree (the scribe's agent memory) — a lane path *inside* a checkout with no change declared is refused with the one-line repair named. The separately-authored acceptance suite is read-only even inside the worktree, to everyone but the test-author. Bash cannot be classified by tool name, so its rule is per role in four sets: builder and test-author are confined to the change's worktree (a leading `cd` into it is where the command runs); executor and deployer may mutate git only inside that worktree or through `agent-team-workspace.sh integrate\|remove`; verifier, reviewer, debugger, and ops are refused every git mutation and any in-place write landing inside a working tree, and a git command whose subcommand cannot be identified is refused rather than allowed. Stop/SubagentStop records what it found and refuses nothing — a blocked Stop could only loop, since this same guard refuses the agent the tools to repair a workspace |
| Lane guard | `hooks/agent-team-lane-guard.sh` | PreToolUse(Write\|Edit\|NotebookEdit) on the scribe, architect, and test-author: each writes only the directories its role is for (`hooks/agent-team-lanes.json`, overridable per project in `.workforce/project.json`), and a refusal is typed — `WORKFORCE_REFUSAL: out-of-lane | <path>` — so the dispatch guard can block a re-route of the same path to a role whose lane does not cover it. The lane is measured from the **write target's** working tree, not the session's directory, so a legitimate write inside a linked worktree is inside its lane. All three carry the worktree guard as well, and the two answer different questions: the lane guard decides **which directories** a role owns, the worktree guard decides **which working tree** — so a plan or a status note inside the repository must satisfy both, which is what puts a document in the workspace of the change it documents. A lane may also name an absolute path with `*` matching exactly one segment — that is how the agent memory at `~/.claude/projects/*/memory` belongs to the scribe without the session transcripts beside it belonging to anyone. Reads are never restricted. A refusal that was itself wrong is released only by the human, in the human's own message: `WORKFORCE_OVERRIDE: lane-refusal | <path>` — a directory releases everything under it — recorded as a fail-open |
| Lane path rules | `hooks/agent-team-lane-paths.sh` | The single matching rule both guards read: lane → absolute pattern, does this lane cover this path, which role owns it. Shared so that a path outside every lane in the guard that **enforces** them cannot be owned by a role in the guard that **routes** by them. A path no lane claims is the builder's only inside the working tree, where unclaimed means source; outside it, no role owns it and the dispatch guard says so instead of naming one that would be refused in turn |
| Report guard | `hooks/agent-team-report-guard.sh` | Stop/SubagentStop on every specialist: blocks the specialist from finishing until its report ends with `WORKFORCE_REPORT: <role> \| complete\|partial\|blocked` — covers sync and background dispatches at the source; never blocks twice |
| Interrupt guard | `hooks/agent-team-interrupt-guard.sh` | PostToolUse(Agent) on the orchestrator: a sync result with no report marker = a killed agent → reconcile-and-RESUME protocol, never a completed phase (Codex path: dispatcher exits 3 on the same signal) |
| Guard block log | `hooks/agent-team-guard-log.sh` | Every refusal from every guard above appends one JSON line to `~/.claude/logs/agent-team-telemetry/guard-blocks.jsonl` — guard, role, verdict, reason. A refusal that reaches only the agent's stderr cannot be counted, and "the scribe was refused a source write four times this week" is the leading indicator that routing is probing for a way around a control. Fail-opens are recorded too: a control that stopped enforcing must not be quieter than one that held |
| Cost collection | `hooks/agent-team-cost.sh` | Exact per-dispatch token/cost file per session (PostToolUse) |
| Priced closeout | `hooks/agent_team_closeout.py` | Stop hook: computes the whole-session cost report and blocks the final message until it is included; requires dirty-tree honesty; enforces the delivery ledger (plan critique between architect and builder, test-author before the first builder on design routes, verifier AND reviewer after the last builder, claimed commits exist, claimed status notes exist, "deployed" needs a deployer) — every check verified against transcript/git/filesystem, never self-reported; bounded at 3 blocks (never wedges); writes telemetry mechanically |
| Cost report | `bin/agent-workforce-cost-report` | Prints the exact session table on demand — **including the orchestrator's own usage** |
| Session grounding | `hooks/session_start.py` | SessionStart: fetches origin and injects ahead/behind as fact; reads `.workforce/project.json` (tracker declaration + tool ready-checks) and injects named OK/FAIL results — no agent reasons from a stale checkout or guesses at tooling |
| Launcher self-update | `bin/agent-workforce` | Checks origin before launch, fast-forwards a clean checkout, records any remaining deficit for the cost report to stamp (a stale clone can no longer self-certify as fresh) |
| Launcher effort pin | `bin/agent-workforce` | Passes `--effort` from `agents/orchestrator.md` so the role's declared effort is what actually runs — the profile's ambient `effortLevel` no longer decides, and an effort the model rejects (`xhigh` with thinking off) can no longer kill the session on its first request. A caller's own `--effort` still wins |

Projects onboard via `/onboard-project` (writes `.workforce/project.json`); an undeclared issue
tracker nags in every cost report until declared. Discovered work follows
`policy:discovered-work` — fix what's small, ticket what's real (declared tracker → GitHub
Issues → closeout floor), stop for what's big; never narrate. Multi-step tool setup lives in
`recipes/` (one recipe per tool: install → login → identity → permissions → verify, every step
tagged agent-work or human-work).

There is no estimate path anywhere. A model with no rate in `hooks/model-rates.json` is reported
as exact unpriced token counts; add the rate and it self-heals. Update rates by editing that
file (list prices per million tokens) — the next launcher run installs it.

## Growing the team

When a task exposes a capability gap (the practitioner test fires, or a shape keeps recurring),
the team creates the missing capability instead of stalling: researcher gathers sourced
constraints, the architect drafts the skill (or agent) in this repo marked
`provenance: provisional` per the `growing-the-team` skill, the task uses it immediately, and
closeout discloses it for your review. Accepted generic drafts get upstreamed to
[`jayheavner/skills`](https://github.com/jayheavner/skills); rejected ones are deleted with the
reason recorded. The vendored skills framework is pinned in `SKILLS-FRAMEWORK`.

## Verifying an install

```bash
bash install.sh --check --profile "$HOME/.claude"   # DRIFT/STALE/MISSING/NEW/RETIRED findings
bash install.sh --list-profiles                     # discover profiles on this machine
```

`install.sh` validates what it installs (hook syntax, agent frontmatter, skill resolution, the
focused hook test suites), backs up what it replaces, rolls back on partial failure, and writes
a checksum manifest per profile. The launcher's auto-install skips the test battery for speed
(`AGENT_TEAM_SKIP_INSTALL_TEST=1`); run a bare `bash install.sh` for the full validation.

### Installing while sessions are running

Every hook is wired to one fixed path under `~/.claude/hooks`, and the harness re-reads that file
on every tool call. Until 2026-08-04 an install therefore rewrote the enforcement of every session
already working, mid-task — and a session failing against a guard defect could not tell that apart
from the guard being edited underneath it. So the wired paths are now generated shims and the real
hooks live in immutable per-build directories:

```
~/.claude/hooks/agent-team-worktree-guard.sh          generated shim, byte-identical across builds
~/.claude/hooks/agent-team-pin.sh                     the resolution rule (not itself pinned)
~/.claude/hooks/agent-team-versions/<stamp>-<commit>/  one immutable build, never edited in place
~/.claude/hooks/agent-team-versions/current            symlink, flipped atomically at end of install
~/.claude/state/agent-team-hookver/<session-id>        the build THIS session runs
```

A session records its build on its first hook call — at session start in practice — and keeps it
for its life. An install writes a new build and flips `current`, which cannot reach a session that
is already pinned; sessions started afterwards get the new build. Rolling a bad repair back is a
symlink flip, not a reinstall. Builds are pruned by age, never while a live pin names one. An
unresolvable build blocks rather than allowing an unchecked action, and `--check` reports a
hand-edited wired path as DRIFT because editing one silently un-pins every session on the machine.

## Cost accounting

`hooks/agent-team-cost.sh` (PostToolUse) writes exact per-dispatch usage to
`~/.claude/logs/agent-team-cost/<project-slug>--<session-id>.json` as dispatches complete.
`bin/agent-workforce-cost-report --transcript <session.jsonl>` prices the entire session —
main session and every subagent — from transcripts at list rates, with per-agent attribution.
The Stop hook runs it automatically at closeout and refuses to let a task end without the
table. Telemetry (one mechanical JSONL row per dispatch: role, models, tokens, cost) lands in
the workforce-owned `~/.claude/logs/agent-team-telemetry/` (`$AGENT_TEAM_TELEMETRY_DIR`
to override) — never inside the client project; read it with
`bash tools/agent-team-scoreboard.sh`.

## ChatGPT / Codex surface

The Codex integration (plugin + companion profiles) carries the same role contracts, regenerated
from `agents/*.md` by `scripts/render_codex_agents.py` — never hand-edit `codex/`. **Any change to
`agents/*.md` is incomplete until you run `python3 scripts/render_codex_agents.py`** and commit the
regenerated `codex/` files in the same change; `tests/test_codex_profiles.sh` fails on the stale
copies, and its failures read as unrelated Codex-installer breakage rather than pointing back at
the role file you edited. Install with
`bash install-codex.sh`; launch with `./bin/agent-workforce-codex`. Details and parity limits:
`docs/chatgpt-codex-parity.md` and `skills/agent-workforce/references/`. Codex cannot produce
Claude-style exact dollar reports; it reports the dispatch/model/effort audit instead.

## Changing the team

Edit agent definitions, hooks, or skills here; run `bash tests/test_*.sh`; the next
`./bin/agent-workforce` launch installs it. Generic skill edits belong upstream in
`jayheavner/skills` (re-vendor at a pinned revision; local forks are listed in
`SKILLS-FRAMEWORK`). Model changes are deliberate frontmatter edits, never automatic. Never
hand-edit installed copies under a profile — the next install overwrites them and `--check`
reports the drift.

## Shakedown

After first setup: `agent-workforce`, then give it a disposable task ("Build a CLI tool
in a fresh temp project named csv2json-2 that converts CSV to JSON; skip deploy"). Expect: a
one-paragraph triage naming builder → verifier (a contained build — architect would be
over-routing), no approval questions, no permission prompts, a commit, one status note, and a
final message ending in the exact cost table with an orchestrator (main session) row. Then
check `grep role= ~/.claude/logs/agent-team-audit.log` shows the commands each agent ran.
