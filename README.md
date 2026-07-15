# AI Agent Team

This repository is the cross-platform source of truth for a twelve-role AI workforce covering
design, specification, implementation, diagnosis, testing, code review, cloud deployment,
research, cloud/identity operations, document writing, and Asana ticket handling. Claude Code
uses native subagent definitions. Local Codex uses a two-part installation: the ChatGPT/Codex
plugin plus companion custom-agent profiles. That local integration pins specialist models and
reasoning efforts, carries the full role contracts, and runs hard-veto policy hooks after the user
trusts them. Hosted ChatGPT Work cannot load those local profiles or hooks and is explicitly a
reduced, non-parity surface. One of the twelve roles, the orchestrator, always stays in the main
session, decomposing incoming work, dispatching or running the other ten specialist phases one
at a time, and carrying clear requests through to verified completion without routine approval
stops. It pauses only for a genuinely new decision, scope expansion, missing authority, or
irreducible human action. The full design rationale — why
the orchestrator runs as the main session, why permissions are
layered the way they are, and why each model was assigned to each role — is written up in
`docs/superpowers/specs/2026-07-07-ai-agent-team-design.md`; the current skill integration is
recorded in `docs/superpowers/specs/2026-07-13-skills-framework-migration-design.md`. This README covers installation,
day-to-day use, and the one-time shakedown that should happen before trusting the team with
real work.

## Roster

The first table describes Claude Code. The second gives the default local Codex mapping; the
complete downshift and upshift matrix lives in `codex/model-policy.json`.

| Agent | Default model | Effort | Role | Mutation rights |
|---|---|---|---|---|
| orchestrator | `claude-opus-4-8` | high | Triage, decompose, dispatch, track authorization. Runs as the main session (see Orchestration) | None (read + dispatch only) |
| architect | `claude-opus-4-8` | high | Design, spec, plan | Docs only (specs/plans) |
| builder | `claude-sonnet-5` | high | Implement per reviewed plan, TDD, commit | Code + local git; no deploy, no push to main |
| debugger | `claude-sonnet-5` | high | Diagnose symptoms, return root cause with evidence | None (read + run) |
| verifier | `claude-sonnet-5` | — | Run tests and acceptance checks | None (read + run) |
| reviewer | `claude-opus-4-8` | high | Code and security review | None (read only) |
| deployer | `claude-sonnet-5` | medium | Cloud deploys (SAM, Amplify, CDK) | Deploy commands within dispatched authorization |
| researcher | `claude-sonnet-5` | — | Web, Glean, codebase investigation | None |
| ops | `claude-sonnet-5` | high | AWS/Azure/Okta investigation and admin | Cloud reads free; authorized mutations execute |
| scribe | `claude-sonnet-5` | — | Reports, briefs, requirements, postmortems, status notes | Docs only |
| ticketer | `claude-sonnet-5` | — | Asana write/review/track | Asana via MCP; writes within dispatched authorization |

| Agent | Local Codex default | Effort | Enforcement |
|---|---|---|---|
| orchestrator | `gpt-5.6-sol` | high | CLI launcher pins it; desktop composer selection is manual |
| architect | `gpt-5.6-sol` | high | Named profile + documentation-write hook |
| builder | `gpt-5.6-terra` | high | Named profile + builder command policy |
| debugger | `gpt-5.6-terra` | high | Named read-only profile + command and patch policy |
| verifier | `gpt-5.6-terra` | medium | Named read-only profile + command policy |
| reviewer | `gpt-5.6-sol` | high | Named read-only profile, distinct from builder |
| deployer | `gpt-5.6-terra` | medium | Named profile + deployment allowlist |
| researcher | `gpt-5.6-terra` | medium | Named read-only profile; live search enabled |
| ops | `gpt-5.6-terra` | high | Named profile + read-first cloud policy |
| scribe | `gpt-5.6-terra` | medium | Named profile + documentation-write hook |
| ticketer | `gpt-5.6-terra` | medium | Named read-only profile + connector-scoped outward writes |

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
then a new live session or `/reload-plugins`; snapshot mode additionally requires reinstalling.
Models are never upgraded implicitly. The reviewer
intentionally runs a different model (Opus) than the builder (Sonnet) so review is not the
builder's own model grading its own work. See the spec for the full model-assignment
policy and the skill preloads each agent carries.

The reusable disciplines are vendored from
[`jayheavner/skills`](https://github.com/jayheavner/skills) at the exact commit recorded in
`SKILLS-FRAMEWORK`. A checkout of that source repository is an authoring-machine concern, not
an installation dependency: every target machine gets the pinned copies from this repository.
Upgrade by re-vendoring a reviewed upstream revision, updating the pin, and running this
repository's tests and shakedown.

The additional `agent-workforce` skill is owned by this repository. It is the orchestration
layer used by ChatGPT and Codex and is safe to load alongside the Claude integration.

## Install in ChatGPT or Codex

The repo includes a Codex plugin manifest at `.codex-plugin/plugin.json` and a marketplace at
`.claude-plugin/marketplace.json`. The marketplace uses the legacy-compatible repo location
that ChatGPT desktop explicitly supports, so the existing Claude plugin layout and the new
ChatGPT distribution can coexist.

Validate the package and the generated custom-agent profiles from a checkout:

```bash
bash tests/test_chatgpt_plugin.sh
bash tests/test_codex_profiles.sh
```

Add the GitHub repo as a marketplace and install it from Codex CLI:

```bash
codex plugin marketplace add jayheavner/agent-workforce
codex plugin add agent-workforce@agent-workforce
```

Install the local model/effort profiles and policy runtime on every machine that will run the
workforce:

```bash
bash install-codex.sh
```

In Codex CLI, start the pinned orchestrator directly:

```bash
./bin/agent-workforce-codex
```

Start a conversation directly with one pinned specialist:

```bash
./bin/agent-workforce-codex --agent agent_workforce_researcher_fast
```

Run one pinned specialist phase non-interactively (the workforce skill uses this companion route when the current collaboration API cannot select custom profiles):

```bash
./bin/agent-workforce-dispatch agent_workforce_reviewer "Review the current diff."
```

In the ChatGPT desktop Codex surface, choose **GPT-5.6 Sol** and **High** before starting a new
task, then invoke `$agent-workforce`. Open `/hooks` once and trust the Agent Workforce role-policy
hooks. In ChatGPT Work, invoke `@agent-workforce`, but expect it to stop and disclose that full
parity is unavailable unless you explicitly accept reduced hosted behavior.

For ChatGPT desktop, restart the app after adding the marketplace, open **Plugins**, choose
**AI Agent Workforce**, and install the plugin. Sharing the plugin does not share files under
`~/.codex/agents`; every local Codex machine must run `install-codex.sh` separately.

### Remaining parity boundaries

Codex plugins do not distribute user-scoped custom-agent profiles, so the explicit companion
installer is required. The desktop plugin also cannot change the parent task's composer model;
the CLI launcher pins Sol/High, while desktop users select it before the task starts. Parent task
permission overrides may tighten or replace a child profile's sandbox defaults, but the trusted
role hook still vetoes prohibited commands.

On the ChatGPT desktop/Codex v2 runtime tested on 2026-07-14, the in-thread collaboration tool
accepts a task name but no custom-profile selector. Live child transcripts showed
`agent_role: null` and parent-model inheritance even when the task name matched an installed
profile. The integration therefore uses separate top-level Codex tasks for pinned specialist
phases. This preserves model, effort, role instructions, sandbox, and hooks, but not the native
child-task bubble or shared child conversation. See `docs/chatgpt-codex-parity.md` for the evidence
and remaining platform gaps.

Codex hook payloads expose the active model and tool call, so model mismatches and role-policy
violations can fail closed. They do not expose stable per-dispatch reasoning-effort, token, or
credit totals, and Codex documents transcript files as an unstable hook interface. Therefore the
local integration provides an exact dispatch/model/effort audit from its pinned profiles, but it
does not claim Claude's exact per-dispatch dollar-cost report. Hosted ChatGPT Work additionally
lacks the local profiles and policy hooks; it is not full parity.

## Install and run (live plugin mode, recommended)

Prerequisites are Git, a current Claude Code installation with `--plugin-dir` support, and
`jq`:

```bash
git --version
claude --version
jq --version
```

On a new machine:

```bash
git clone https://github.com/jayheavner/agent-workforce.git
cd agent-workforce
bash tests/test_plugin_mode.sh
./bin/agent-workforce
```

The launcher runs `claude --plugin-dir <this-checkout>`. Claude discovers the repo's agents,
skills, and hooks directly, and `settings.json` selects the namespaced live orchestrator
(`agent-workforce:orchestrator`). Nothing is copied into a Claude profile.

To update an existing clean checkout without reinstalling:

```bash
git pull --ff-only
./bin/agent-workforce
```

New files and edits are discovered automatically at the next session start. In an open
session, run `/reload-plugins` after `git pull` to reload agents, skills, and hooks without
restarting Claude Code. The plugin deliberately does not pull Git by itself: the checkout is
updated by `git pull --ff-only` or the machine's normal checkout-sync mechanism.

### Multiple Claude profiles

Live plugin mode does not install into a profile. Point the launcher at whichever profile
should supply the session's authentication, settings, and connectors:

```bash
./bin/agent-workforce
CLAUDE_CONFIG_DIR="$HOME/.claude-work" ./bin/agent-workforce
CLAUDE_CONFIG_DIR="/another/profile/path" ./bin/agent-workforce
```

All profiles use the same live checkout, so one checkout update updates the workforce for
every profile. There is no per-profile reinstall. Profile-specific credentials and connectors
remain profile/account concerns and are not stored here.

### Snapshot installer fallback

`install.sh` remains supported when direct plugin loading is unavailable or an immutable copied
snapshot is specifically wanted. Snapshot mode is the only mode that requires reinstalling
after a repo update.

Before a snapshot install, discover the machine's profiles. If multiple profiles exist, select
each intended target explicitly:

```bash
bash install.sh --list-profiles
bash install.sh --profile "$HOME/.claude"
bash install.sh --check --profile "$HOME/.claude"

bash install.sh --profile "$HOME/.claude-work"
bash install.sh --check --profile "$HOME/.claude-work"
CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude --agent orchestrator
```

Discovery checks the default `~/.claude`, the active `CLAUDE_CONFIG_DIR`, and profile-shaped
`$HOME/.claude-*` directories. Non-conventional paths can be supplied through the
colon-separated `AGENT_TEAM_PROFILE_DIRS` variable. If multiple profiles are detected without
an explicit selection, install and check operations stop before changing anything.

The snapshot installer validates agent frontmatter and skill resolution, all vendored skill
contracts, hook syntax and JSON, policy/dispatch/cost/plugin tests, and a sandbox installation
suite before copying. It backs up every managed file it replaces, rolls back a partial failure,
and writes a checksum manifest used by `bash install.sh --check`.

## How to use

Start the orchestrator as the main Claude Code session, not as a dispatched subagent. The main
session keeps the findings and authorization ledger across specialist phases and can request the
rare human-only decision when one actually appears:

```bash
./bin/agent-workforce
```

To start a specialist directly, pass its plugin-qualified name:

```bash
./bin/agent-workforce --agent agent-workforce:researcher
```

For a snapshot installation, the legacy command remains `claude --agent orchestrator`.

Give the orchestrator a task. It first **triages** — classifying the task's ambiguity,
novelty, blast radius, and size into a tier, and telling you in one paragraph which route it
chose and which model each dispatch will run on, all of which you can override. A small,
well-understood task gets a combined spec+plan, critique, build, verification, review, and
closeout. A standard task keeps spec and plan separate; a large or high-risk task adds research
and deeper review. None of those phase boundaries is an approval stop. Research, ops, document,
and ticket work likewise performs the outward action when the original request or a later choice
already authorized it.

The original request is standing authorization for the ordinary in-scope actions needed to
deliver its stated outcome. A choice such as "Deploy main now, then redrive the DLQ" is both the
decision and the authorization; the orchestrator records it and dispatches the work without
asking again. It pauses only when evidence introduces a materially different outcome, mutation
scope, blast radius, irreversible effect, or an irreducible human action. When the per-session
cost file produced by the cost-accounting hook is present and valid, closeout reports the EXACT
per-model figures — input, output, cache-write, and cache-read tokens with cost
rounded to the cent — read straight from the session transcripts and priced at
list rates from `hooks/model-rates.json`. When that file is absent or the hook
marked it unavailable, it falls back to a blended per-dispatch ESTIMATE clearly
labeled as such. Either way the number excludes the orchestrator's own session
usage; your exact session-wide number is always `/usage`. Nonzero web-search or
web-fetch server-tool calls are counted and footnoted, not priced. You can redirect or stop at
any time, but silence and routine phase completion do not create new approval requirements.

If a verifier or reviewer dispatch comes back with findings, the orchestrator sends the work
back to the builder with those findings attached, for up to two repair loops before it
escalates to you instead of retrying indefinitely. If any specialist hits its turn limit
(`maxTurns` in its frontmatter) or encounters unexpected state — missing credentials, a broken
environment — it stops and reports rather than improvising, and the orchestrator escalates
rather than blindly re-dispatching. Because the orchestrator itself has no Write tool, the
per-task status note that lets interrupted work resume cleanly is written by the scribe, at the
orchestrator's direction, at material transitions and completion — look for it if you need to pick a
task back up later.

## Deploying to another machine

The repo is the complete source of truth — the agents carry no dependency on any session
memory, project memory, or the contents of a personal `~/.claude/CLAUDE.md`. All triage,
model, effort, and permission behavior lives in the agent files this repo loads. What a
new machine DOES need, and how each is guarded:

1. **Claude Code** signed into an account whose connectors cover the MCP-backed roles —
   the researcher's Glean access and the ticketer's Asana access ride on claude.ai
   connectors, which are account-scoped, not machine-scoped.
2. **`jq`** — the policy hook parses tool-call JSON with it. The launcher and installer both
   fail clearly without it.
3. **The Claude Code built-in skills** — the framework no longer depends on the superpowers
   plugin. Nineteen pinned skills are vendored under `skills/`: the framework core, the
   requirements, Asana ticketing, 1Password, and UX packs, plus this consumer's
   `project-policy` instance. Live mode loads them directly from the checkout; snapshot mode
   copies them into the selected profile. Validation fails loudly if an agent preload,
   situational skill, dependency edge, or policy key is missing.
4. **Role credentials in the environment** ($OKTA_TOKEN, AWS profiles, the 1Password
   service-account token) — only needed for the ops/deployer work that uses them, and
   machine-specific by nature.

So the recommended deployment procedure is: install prerequisites, clone this repo, run
`bash tests/test_plugin_mode.sh`, then start `./bin/agent-workforce`, optionally setting
`CLAUDE_CONFIG_DIR` to choose among multiple profiles. Use the snapshot installer only when
direct plugin loading is unavailable or intentionally not wanted.

## Drift detection — the anti-fog mechanism

In live plugin mode, the repo files are what actually run. The launcher passes the checkout to
Claude explicitly, and the orchestrator announces `team plugin <version>, live checkout` at
session start. `git status --short` shows local modifications, `git pull --ff-only` updates the
only workforce copy, and `/reload-plugins` refreshes an open session.

Snapshot mode retains three additional drift mechanisms:

- Every install writes a **build manifest** (`<profile>/agent-team-manifest.json`): the
  repo commit, install timestamp, and a checksum of every installed file — agents, hooks,
  the pinned skills-framework revision, and every vendored skill file, each tracked under its
  own manifest key (skill files use the key `skills/<name>/<relpath>`, so nested references are
  tracked individually).
- **`bash install.sh --check [--profile <dir>]`** verifies one profile any time, without touching
  anything: it re-runs the full validation (skill resolution and the vendored-skills
  checks above, `jq` present, hook and install-skills tests pass) and compares checksums
  the same way for agents, hooks, and skills alike — an installed file hand-edited under
  the selected profile (including a skill file edited or deleted directly under its
  `skills/` directory) reports DRIFT or MISSING, a repo file changed since the last
  install reports STALE, a repo file never installed reports NEW, and a file the manifest
  still lists but the repo no longer has reports REMOVED. Any finding exits nonzero with
  the exact file named. Run it on any machine you suspect is behind.
- The **orchestrator announces its build** ("team build `<commit>`, installed `<date>`")
  as the first line of every session, read from the manifest — so a stale install is
  visible in the first message of any task, on any machine, rather than discovered later.

## How to change the team

Edit agent definitions, hook files, the consumer `project-policy`, or tests in this repository.
Generic framework-skill edits belong in `jayheavner/skills`; re-vendor them here at a new pinned
revision rather than carrying an unexplained local fork. In live plugin mode, validate with
`bash tests/test_plugin_mode.sh`, then start a new session or run `/reload-plugins`; there is no
install step. A model change remains a deliberate, reviewed frontmatter edit and is never made
automatically.

If a machine intentionally uses snapshot mode, never hand-edit the copies under a profile's
`agents/` or `skills/` directories, or under `~/.claude/hooks/`. Make the repo edit, run
`bash install.sh`, then `bash install.sh --check`; otherwise the next snapshot install will
overwrite the hand edit.

## Audit log

The team's flight recorder lives at `~/.claude/logs/agent-team-audit.log` (overridable via
`AGENT_TEAM_AUDIT_LOG`, mainly for tests). Two hooks write it. `hooks/agent-team-audit.sh`
(PostToolUse on Bash, log-only, can never block) appends one line per command any agent runs:

```
<UTC timestamp> role=<role> ran=<command>
```

`hooks/agent-team-secrets.sh` (PreToolUse, the team's single blocking rule) appends a
`decision=block` line whenever it stops a credential-bearing value from being directed at a
file — the one enforced boundary that survived the approve-intent redesign (spec:
`docs/superpowers/specs/2026-07-12-approve-intent-not-commands-design.md`). Everything else
is instruction-level discipline: the request or an explicit choice supplies standing authority
for its stated goal and mutation scope, agents execute silently inside it, and only a material
scope change requires another decision. The log exists so any
agent's actions — "what did the executor run at 2am" — stay reconstructable after the fact.

## Cost accounting

The orchestrator registers a `PostToolUse` hook, `hooks/agent-team-cost.sh`, that
fires after each dispatch completes. It reads exact per-request token usage from
the session's per-dispatch transcript files and writes a per-session cost file to
`~/.claude/logs/agent-team-cost/<project-slug>--<session-id>.json` (override the
directory with `AGENT_TEAM_COST_DIR`, and the rates file with `AGENT_TEAM_RATES`,
mainly for tests). Prices come only from `hooks/model-rates.json` — all list
prices per million tokens; the script contains no numbers. To change a rate, edit that file and
reload the live plugin (or reinstall a snapshot).

The hook never emits a wrong number: if it cannot recognize a transcript's format,
or sees a model missing from the rates file, it writes a sticky "unavailable"
marker for that session and the orchestrator falls back to its blended estimate.
Cache-write is split into 5-minute and 1-hour tiers (they price differently);
server web-search/web-fetch calls are counted but not priced. Known limitation:
two orchestrator sessions running in the same directory at once share the cost-file
name pattern, and the most recently modified file wins.

### Dispatch telemetry

Every routed task also leaves dispatch outcome records — evidence for recalibrating the
orchestrator's model routing table and for catching silent model overrides (spec:
`docs/superpowers/specs/2026-07-13-dispatch-telemetry-design.md`). The cost hook stamps
each dispatch's requested model override; at final closeout the scribe joins those
mechanical facts to the orchestrator's verdicts (first-try pass/fail, repair loops) and
writes one JSONL record per dispatch to the project's `docs/telemetry/` (schema in
`docs/telemetry/README.md`). Records count for calibration only once merged to canonical
main, like gap records. Telemetry is best-effort and never blocks a dispatch, changes a
cost figure, or blocks closeout.

Read the evidence with the scoreboard (per role × actually-ran model × tier —
first-try pass rate is the routing signal):

```
bash tools/agent-team-scoreboard.sh path/to/project/docs/telemetry
```

or ad hoc with jq:

```
jq -s 'group_by([.role,.resolved_model,.tier]) | map({key:(.[0].role+"/"+.[0].resolved_model+"/"+.[0].tier),
  n:length, first_try:(map(select(.sequence=="first" and .verdict=="pass"))|length)})' docs/telemetry/*.jsonl
```

A drifted dispatch (harness ran a different model than was pinned or requested — e.g. a
stray `CLAUDE_CODE_SUBAGENT_MODEL` in the environment) is bucketed under the model that
actually ran and counted in the scoreboard's drift column, never credited to the model
that was asked for. Role pins live in the committed `hooks/agent-model-defaults.json`,
which `install.sh` verifies against `agents/*.md` frontmatter on every run.

## Shakedown checklist

Run this once, in full, after the first setup, before trusting the team with real work:

- [ ] 1. Run `bash tests/test_policy_hooks.sh`, `bash tests/test_plugin_mode.sh`, and
      `bash tests/test_chatgpt_plugin.sh` — all pass.
- [ ] 2. Start `./bin/agent-workforce`; give it a disposable task: "Build a CLI tool in a
      fresh temp project named csv2json-2 that converts CSV to JSON, through the full
      pipeline including review; skip deploy."
- [ ] 3. Confirm triage fired: before the first dispatch, the orchestrator declared the task
      **small**, named the collapsed route, and listed a model pick for every planned
      dispatch (architect on Opus, scribe on Haiku). Triaging this task as standard is a
      fail — it is the canonical small task.
- [ ] 4. Confirm the collapsed route ran without an approval stop: ONE combined spec+plan,
      plan critique, then builder → verifier → reviewer → closeout; builder committed
      test-first; verifier reported evidence; reviewer returned a verdict; a STATUS note
      exists and is accurate.
- [ ] 5. Confirm scaling: at the end, ask the orchestrator to list every dispatch with the
      model it ran on. Expect the architect on Opus (not Fable), the scribe on Haiku with
      roughly three status updates (not one per phase), and no dispatch whose token count
      rivals the first shakedown's 85k–114k architect runs.
- [ ] 6. Confirm the orchestrator stayed light: progress updates were concise, no routine
      approval question appeared, and the session never approached a spend-limit event.
- [ ] 7. Confirm the flight recorder from the audit log:
      `grep role= ~/.claude/logs/agent-team-audit.log` shows every command each agent ran,
      and zero permission prompts or commands were surfaced after the initial request.
- [ ] 8. Only after all of the above pass, use the team on real work.

### Gap-loop shakedown

Run after installing the gap-detection amendment (spec:
`docs/superpowers/specs/2026-07-12-gap-detection-capability-loop-design.md`). Scenarios
are ranked, not equal: **scenario 3 is load-bearing** — it tests the
hard-is-never-a-gap discriminator and should re-run after any change to the
orchestrator's Gap flags text. Scenarios 1–2 matter at first domain contact; 4–5 are
documentation-grade.

- [ ] 1. **Domain-positive:** give the team a payroll-withholding-calculator task. Expect
      the architect to declare `DOMAIN GAP: payroll` before writing a spec; researcher
      backfill runs; progress updates disclose uncertified input and recommend criteria
      review; a `GAP-*-domain-payroll.md` record appears.
- [ ] 2. **Domain-negative:** the same task with a `domain-payroll` skill installed.
      Expect no gap declared and the skill's constraints visible in the plan.
- [ ] 3. **Hard-but-in-charter negative:** a genuinely difficult refactor entirely inside
      the team's competence. Objective pass condition: every material progress summary reads
      exactly `gaps: none` and no `GAP-*.md` file exists anywhere after the run.
- [ ] 4. **Declined promotion:** decline a recorded gap. Expect the record frozen as
      `declined — <reason>`, and a later same-identity detection presented in the next update
      with that reason attached.
- [ ] 5. **Degraded logging path:** with the manifest absent, expect the record in the
      project's own `docs/gaps/` and the next update disclosing the degraded path; at the next
      session start, expect "1 gap records in this project await upstreaming."

### Telemetry shakedown

Run after installing the dispatch-telemetry amendment (spec:
`docs/superpowers/specs/2026-07-13-dispatch-telemetry-design.md`):

- [ ] 1. Run a small task end to end. At final closeout, expect a `telemetry: <n> records`
      line, and confirm `docs/telemetry/<project-slug>--<session-id>.jsonl` exists with one
      record per dispatch: the builder row shows `sequence: "first"` and its real verdict,
      support-role rows show `n/a`, and each `resolved_model` matches the model the
      orchestrator's closeout table says actually ran. This scenario is also the live
      confirmation that the hook captures `tool_input.model` on an overridden dispatch
      (`requested_override` non-null in the session cost file for any dispatch the
      orchestrator downshifted).
- [ ] 2. Run `bash tools/agent-team-scoreboard.sh docs/telemetry` in that project — expect
      one row per (role, model, tier) group and no `unattributed` line.
