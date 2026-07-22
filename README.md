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

```bash
git clone https://github.com/jayheavner/agent-workforce.git
cd agent-workforce
./bin/agent-workforce
```

The launcher checks the active profile (`CLAUDE_CONFIG_DIR`, default `~/.claude`) against the
current checkout and **self-installs when stale** — a stale profile can no longer run quietly,
which was the previous generation's dominant failure. Then it starts
`claude --agent orchestrator`. Give it a task; it triages in one paragraph and goes.

```bash
CLAUDE_CONFIG_DIR="$HOME/.claude-work" ./bin/agent-workforce   # another profile
./bin/agent-workforce --no-install                             # skip freshness check
./bin/agent-workforce --plugin                                 # legacy live plugin mode
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
| orchestrator | opus-4-8 | high | Triage, route, dispatch, closeout. Main session; read-only shell for facts | None (read + dispatch) |
| architect | opus-4-8 | high | Specs, plans; drafts new skills/agents for team growth | Docs + provisional skills/agents |
| builder | sonnet-5 | high | TDD implementation, direct or from a plan | Code + local git; no deploy, no push to main |
| debugger | sonnet-5 | high | Root-cause diagnosis with evidence | None (read + run) |
| verifier | sonnet-5 | — | Tests + acceptance evidence | None (read + run) |
| reviewer | opus-4-8 | high | Code/security review; plan + spec critique | None (read only) |
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
| Trivial action | ONE dispatch |
| Clear, contained build | builder → verifier (+ reviewer only for risky surfaces) |
| Real design decisions | architect (one combined spec+plan) → builder → verifier ∥ reviewer |
| Multi-system / production | researcher → architect deep → builder(s) → verifier ∥ reviewer → deployer → smoke |
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
| Dispatch guard | `hooks/agent-team-dispatch-guard.sh` | Valid `subagent_type` only; serializes git-mutating dispatches; every 10th dispatch requires a budget acknowledgment (the $51 stop-loss) |
| Cost collection | `hooks/agent-team-cost.sh` | Exact per-dispatch token/cost file per session (PostToolUse) |
| Priced closeout | `hooks/agent_team_closeout.py` | Stop hook: computes the whole-session cost report and blocks the final message until it is included; requires dirty-tree honesty; enforces the delivery ledger (verifier after last builder, claimed commits exist, claimed status notes exist, "deployed" needs a deployer) — every check verified against transcript/git/filesystem, never self-reported; bounded at 3 blocks (never wedges); writes telemetry mechanically |
| Cost report | `bin/agent-workforce-cost-report` | Prints the exact session table on demand — **including the orchestrator's own usage** |

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
from `agents/*.md` by `scripts/render_codex_agents.py` — never hand-edit `codex/`. Install with
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

After first setup: `./bin/agent-workforce`, then give it a disposable task ("Build a CLI tool
in a fresh temp project named csv2json-2 that converts CSV to JSON; skip deploy"). Expect: a
one-paragraph triage naming builder → verifier (a contained build — architect would be
over-routing), no approval questions, no permission prompts, a commit, one status note, and a
final message ending in the exact cost table with an orchestrator (main session) row. Then
check `grep role= ~/.claude/logs/agent-team-audit.log` shows the commands each agent ran.
