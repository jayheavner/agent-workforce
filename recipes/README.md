# Tool recipes

A recipe is the full path from "tool not working" to "tool provably usable,"
written once and executed by any agent on any machine. Installing is only part
of it: a tool is usable when it is installed, logged in, pointed at the right
identity, permitted on the remote side, and allowed by the harness — a recipe
covers the whole chain and ends by proving it.

Decided 2026-07-22. The agent behavior rule is one sentence: **tool not
working → run its recipe.** No recipe yet? Write one while solving it the
first time (growing-the-team pattern), save it here, disclose at closeout.

## Format

One markdown file per tool or per configured capability, named for what it
delivers (`GIT-SSH.md` delivers "git reaches GitHub as the right identity").
Structure:

- **Audience line** — which machine/context runs it.
- **Phases in execution order**, each idempotent and safe to re-run.
- **Every step tagged** as agent-work or human-work. The split is fixed:
  - *Agent can:* install binaries (brew/pipx), write config files, select
    accounts/subscriptions after a login exists, store/read secrets through
    the 1Password CLI, run every verify command.
  - *Human must:* browser logins and SSO flows, MFA, "authorize for org"
    clicks, role grants in admin consoles, 1Password app actions (sign-in,
    agent toggle), and Claude Code permission/settings changes (the
    classifier blocks agents from editing their own permissions by design).
- **A final verify phase** whose checks prove the chain end to end — ideally
  the same commands the project's `.workforce/project.json` ready-checks run
  at every session start, so "recipe done" and "probe green" are one fact.
- **Stop-and-report on failed preconditions** — a recipe never improvises.

## Recipes

- [`../GIT-SSH.md`](../GIT-SSH.md) — deterministic GitHub identity routing on
  the work machine (1Password SSH agent, directory-based identity, gh evicted
  from the transport path). Lives at the repo root because it bootstraps the
  machine that pulls this repo; future recipes live in this directory.
