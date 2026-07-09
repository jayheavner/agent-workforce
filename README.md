# AI Agent Team

This repository is the source of truth for a team of ten scoped Claude Code subagents that
cover the full range of software and operations work: design, specification, implementation,
testing, code review, cloud deployment, research, cloud/identity operations, document writing,
and Asana ticket handling. Each agent has a fixed role, a pinned model, and enforced
permissions, so the same agent always behaves the same way regardless of which task it is
given. One of the ten, the orchestrator, is not dispatched like the others — it runs as the
main Claude Code session itself, decomposing incoming work, dispatching the other nine
specialists one phase at a time, and stopping at human approval gates between phases. The
full design rationale — why the orchestrator runs as the main session, why permissions are
layered the way they are, and why each model was assigned to each role — is written up in
`docs/superpowers/specs/2026-07-07-ai-agent-team-design.md`; this README covers installation,
day-to-day use, and the one-time shakedown that should happen before trusting the team with
real work.

## Roster

| Agent | Default model | Effort | Role | Mutation rights |
|---|---|---|---|---|
| orchestrator | `claude-opus-4-8` | high | Triage, decompose, dispatch, enforce gates. Runs as the main session (see Orchestration) | None (read + dispatch only) |
| architect | `claude-opus-4-8` | high | Design, spec, plan | Docs only (specs/plans) |
| builder | `claude-sonnet-5` | high | Implement per approved plan, TDD, commit | Code + local git; no deploy, no push to main |
| verifier | `claude-sonnet-5` | — | Run tests and acceptance checks | None (read + run) |
| reviewer | `claude-opus-4-8` | high | Code and security review | None (read only) |
| deployer | `claude-sonnet-5` | medium | Cloud deploys (SAM, Amplify, CDK) | Deploy commands only, each prompted |
| researcher | `claude-sonnet-5` | — | Web, Glean, codebase investigation | None |
| ops | `claude-sonnet-5` | high | AWS/Azure/Okta investigation and admin | Cloud reads free; mutations prompted |
| scribe | `claude-sonnet-5` | — | Reports, briefs, requirements, postmortems, status notes | Docs only |
| ticketer | `claude-sonnet-5` | — | Asana write/review/track | Asana via MCP; gated before filing |

These are **defaults, not fixed assignments**: the orchestrator triages every incoming task
and may downshift a dispatch to a cheaper model (an amendment goes to the architect on
Sonnet; a status note goes to the scribe on Haiku; a single-fact lookup goes to the
researcher on Haiku) or upshift a risky one (the architect on Fable when the design space
is genuinely open; the reviewer on Fable for a security-critical surface) using the Agent
tool's per-dispatch model override — no role defaults to Fable; it is always a deliberate,
named upshift. It states its picks at triage
so you see the cost/depth plan before work starts. The four agents with no effort pin are
the ones eligible for Haiku downshifts — Haiku rejects the effort parameter, so they
deliberately inherit the session's setting instead. Model IDs are pinned as full strings
deliberately: a default change is a deliberate edit to the agent definitions in this repo,
followed by re-running the installer, never an automatic upgrade. The reviewer
intentionally runs a different model (Opus) than the builder (Sonnet) so review is not the
builder's own model grading its own work. See the spec for the full model-assignment
policy and the skill preloads each agent carries.

## How to install

```bash
bash install.sh
```

Nothing is copied anywhere until every validation check below passes:

- `jq` is present on the machine (the policy hook depends on it to parse tool-call JSON).
- All three hook files — `hooks/agent-team-policy.sh` (the entry point),
  `hooks/agent-team-policy-lib.sh` (the shared helpers and per-role policy functions it
  sources), and `hooks/agent-team-policy-mutations.sh` (the raw-shell-mutation blocklist that
  the lib file in turn sources) — pass `bash -n` syntax checks.
- The full policy test suite (`tests/test_policy_hooks.sh`) passes.
- Every agent file under `agents/` has YAML frontmatter with the required keys (`name`,
  `description`, `model`), and the `model` value is one of the three pinned team models
  (`claude-fable-5`, `claude-opus-4-8`, `claude-sonnet-5`) — an unpinned or unrecognized model
  fails the install rather than installing silently.
- Every `skills:` entry in every agent file resolves to an actually-installed skill. Namespaced
  entries (`plugin:skill`) are checked against the plugin cache; bare entries are checked
  against `~/.claude/skills/<name>/SKILL.md`, except for a short whitelist of built-in skills
  that ship inside the Claude Code client itself and have no `SKILL.md` on disk anywhere
  (currently `verify`, `run`, `init`, `review`, `security-review`, `update-config`,
  `keybindings-help`) — those are recognized by name instead of by file lookup. A renamed or
  missing skill fails the install loudly rather than degrading silently.
- The installer also warns (without failing) if the `CLAUDE_CODE_SUBAGENT_MODEL` environment
  variable is set, either in the current shell or in `~/.zshrc`, `~/.zprofile`, or
  `~/.zshenv` — that variable silently overrides every model pin in the roster table above.

Only after all of that passes does the installer touch `~/.claude/`. Any agent file already
installed under `~/.claude/agents/` that this run is about to replace is copied first into a
timestamped backup directory, `~/.claude/backups/agent-team-<timestamp>/`; the same applies to
`~/.claude/hooks/agent-team-policy.sh`, `~/.claude/hooks/agent-team-policy-lib.sh`, and
`~/.claude/hooks/agent-team-policy-mutations.sh` if they already exist. If any copy step fails
partway through — an agent file, the policy script, the policy library, or the mutations
blocklist — the installer restores every file it just backed up and removes any file
it freshly created that had no prior version to restore, so a failed install always reverts
cleanly to whatever state existed before it ran; it never leaves a partial or broken install in
place. A successful run prints where the backup was written and reminds you how to start the
team.

## How to use

Start the orchestrator as the main Claude Code session, not as a dispatched subagent — this
matters because gates require the session to stop and interact with you, and a dispatched
subagent can only return a final result, not pause mid-task:

```bash
claude --agent orchestrator
```

Give the orchestrator a task. It first **triages** — classifying the task's ambiguity,
novelty, blast radius, and size into a tier, and telling you in one paragraph which route it
chose and which model each dispatch will run on, all of which you can override. A small,
well-understood task gets a collapsed route (one combined spec+plan dispatch, one gate); a
standard task gets the full sequence — architect (design and spec) → **gate** → architect
(plan) → **gate** → builder → verifier → reviewer → **gate** → deployer → verifier again as a
smoke check; a large or high-risk task adds a researcher pre-phase and deeper review.
Research, ops, document, and ticket work follows a shorter route: a researcher or
ops dispatch gathers information, a scribe or ticketer dispatch produces the artifact, then a
gate before anything goes outward-facing (a filed ticket, a sent report, a cloud mutation).

At each gate, the orchestrator stops, presents the artifact it produced (a spec, a plan, a
diff, a deploy plan) together with a plain-language summary and its own recommendation, and
waits for you. The final gate additionally includes a per-dispatch accounting table — which
agent ran on which model with how many tokens, plus an estimated cost clearly labeled as an
estimate (it excludes the orchestrator's own session usage and cache discounts; your exact
number is always `/usage`). You have three options at any gate:

- **Approve** — tell the orchestrator to continue; it dispatches the next phase. Approving one
  gate never implies approval of the next gate; the deploy gate in particular always requires
  its own explicit approval.
- **Redirect** — tell the orchestrator what to change; it returns to the relevant specialist
  with your feedback rather than moving forward.
- **Kill** — tell the orchestrator to stop the task; nothing further is dispatched.

If a verifier or reviewer dispatch comes back with findings, the orchestrator sends the work
back to the builder with those findings attached, for up to two repair loops before it
escalates to you instead of retrying indefinitely. If any specialist hits its turn limit
(`maxTurns` in its frontmatter) or encounters unexpected state — missing credentials, a broken
environment — it stops and reports rather than improvising, and the orchestrator escalates
rather than blindly re-dispatching. Because the orchestrator itself has no Write tool, the
per-task status note that lets interrupted work resume cleanly is written by the scribe, at the
orchestrator's direction, at each gate and at completion — look for it if you need to pick a
task back up later.

## Deploying to another machine

The repo is the complete source of truth — the agents carry no dependency on any session
memory, project memory, or the contents of a personal `~/.claude/CLAUDE.md`. All triage,
model, effort, and permission behavior lives in the agent files this repo installs. What a
new machine DOES need, and how each is guarded:

1. **Claude Code** signed into an account whose connectors cover the MCP-backed roles —
   the researcher's Glean access and the ticketer's Asana access ride on claude.ai
   connectors, which are account-scoped, not machine-scoped.
2. **`jq`** — the policy hook parses tool-call JSON with it. The installer fails without it.
3. **The skills the agents preload or invoke** — the superpowers plugin plus the org
   skills (coding-standards, code-review, secure-secrets, write-ticket, and the rest named
   in the agent files). The installer resolves every one, including the architect's
   situationally-invoked skills, and fails loudly on any that are missing rather than
   installing a team that degrades at runtime.
4. **Role credentials in the environment** ($OKTA_TOKEN, AWS profiles, the 1Password
   service-account token) — only needed for the ops/deployer work that uses them, and
   machine-specific by nature.

So the deployment procedure is: install prerequisites, clone this repo, run
`bash install.sh`, and treat any validation failure as the dependency list telling you
what that machine is missing.

## How to change the team

Edit the agent definitions, hook files, or tests in this repository — never edit files under
`~/.claude/agents/` or `~/.claude/hooks/` directly, since those are install targets that get
overwritten the next time `install.sh` runs, and a direct edit there will silently vanish. After
making a change, re-run `bash install.sh` to validate and reinstall. A model change for any
role is a deliberate, reviewed edit to that agent's `model:` frontmatter line in this repo,
followed by an install — models are never changed automatically or implicitly.

## Audit log

Every decision made by the shared policy hook — every allowed and every blocked tool call, for
every role — is appended as one line to `~/.claude/logs/agent-team-audit.log` (overridable by
setting the `AGENT_TEAM_AUDIT_LOG` environment variable, which is mainly useful for pointing
the tests or a dry run at a scratch location instead of the real log). Each line has the
format written by the `audit()` function in `hooks/agent-team-policy.sh`:

```
<UTC timestamp> role=<role> tool=<tool name> decision=<allow|block> detail=<up to 200 chars of context>
```

The log exists so that any agent's actions — especially the deployer's, since it is the one
role whose mutations reach real cloud infrastructure — can be reconstructed after the fact,
and so that lane enforcement can be checked directly rather than taken on faith. It also
accumulates across the three files that make up the hook: `hooks/agent-team-policy.sh` is the
thin entry point that every agent's frontmatter actually invokes, and it sources
`hooks/agent-team-policy-lib.sh` for the shared helper functions and the per-role policy logic
(builder, deployer, ops, and the shared read-only-runner policy used by verifier and reviewer),
which in turn sources `hooks/agent-team-policy-mutations.sh` for the raw-shell-mutation
blocklist shared by every mutation-checked role (file-mutation primitives, redirection, tee,
archive/compression tools, in-place sed, package management, subshell/process-substitution
syntax, and the eval/interpreter escape hatches). If you need to change what a role is allowed
to do, the per-role function you want is in the library file; if you need to change what raw
shell primitive is blocked for everyone, it is in the mutations file. Neither is the entry point.

## Shakedown checklist

Run this once, in full, after the first install, before trusting the team with real work:

- [ ] 1. Run `bash tests/test_policy_hooks.sh` — all pass.
- [ ] 2. Start `claude --agent orchestrator`; give it a disposable task: "Build a CLI tool in a
      fresh temp project named csv2json-2 that converts CSV to JSON, through the full
      pipeline including review; skip deploy."
- [ ] 3. Confirm triage fired: before the first dispatch, the orchestrator declared the task
      **small**, named the collapsed route, and listed a model pick for every planned
      dispatch (architect on Opus, scribe on Haiku). Triaging this task as standard is a
      fail — it is the canonical small task.
- [ ] 4. Confirm the collapsed route ran: ONE combined spec+plan gate (not separate spec and
      plan gates), then builder → verifier → reviewer → final gate; builder committed
      test-first; verifier reported evidence; reviewer returned a verdict; a STATUS note
      exists and is accurate.
- [ ] 5. Confirm scaling: at the end, ask the orchestrator to list every dispatch with the
      model it ran on. Expect the architect on Opus (not Fable), the scribe on Haiku with
      roughly three status updates (not one per phase), and no dispatch whose token count
      rivals the first shakedown's 85k–114k architect runs.
- [ ] 6. Confirm the orchestrator stayed light: gate summaries arrived without extended
      deliberation, and the session never approached a spend-limit event.
- [ ] 7. Confirm lane enforcement from the audit log:
      `grep decision=block ~/.claude/logs/agent-team-audit.log` shows any attempted
      out-of-lane commands, and no role bypassed its policy.
- [ ] 8. Only after all of the above pass, use the team on real work.
