---
name: onboard-project
description: Declare a project's issue tracker and tool ready-checks in .workforce/project.json so every session starts on checked facts instead of guesses. Use when the session-start probe or cost report says the tracker is UNDECLARED, when a project needs its required tooling captured, or when the user asks to onboard a project.
provenance: provisional
---

# Onboard Project

One short interview, one committed file: `.workforce/project.json`. After it
exists, the session-start hook verifies everything in it at every launch and
injects the results as context, and the cost report stops nagging.

## What the file declares

```json
{
  "tracker": "github",
  "strict": false,
  "ready_checks": [
    {
      "name": "azure cli on the right subscription",
      "command": "az account show --query id -o tsv",
      "expect": "<subscription-id>",
      "timeout": 15
    }
  ]
}
```

- `tracker` — where Tier-2 discovered work gets filed (`policy:discovered-work`).
  `"github"`, `"asana:<project-gid>"`, or an explicit `"none"` (which is a
  declaration, not a gap: findings go to the closeout REMAINING WORK floor).
- `ready_checks` — one entry per tool the project depends on. A ready check is
  a command plus expected output that proves the whole chain — installed,
  logged in, pointed at the right identity, permitted — in one shot. Not
  "needs az": "az account show must name subscription X".
- `strict` — reserved for the strict closeout mode (a declared-but-unreachable
  tracker blocks completion claims); not yet enforced.

## The interview

Facts come from the repo; decisions come from the human. Ask one at a time:

1. **Tracker.** If the repo has a GitHub remote and `gh repo view` succeeds,
   recommend `github`. If the org tracks work in Asana, ask for the project
   gid. Offer explicit `none` for scratch projects.
2. **Tools.** Ask what the project touches (cloud accounts, CLIs, APIs). For
   each, capture the CORRECT answer while the human is present to say what
   correct is: the right subscription id, the right account name, the right
   vault. Write the check that proves it.
3. **Verify before writing.** Run every drafted check now. A check that fails
   during onboarding is either a wrong expectation (fix the check) or a real
   gap (point at the recipe that repairs it — see `recipes/`).

## Rules

- Write the file, run the session-start probe once to prove it parses, and
  commit it with the project's convention.
- Never put secrets in a check: commands may READ tool state (`az account
  show`, `gh auth status`); expected values are identifiers (subscription
  ids, account names), never tokens.
- A failing ready check at any later session start is repaired by its recipe
  (agent steps) and the human (login/SSO steps) — the check itself is only
  ever edited when the project's intended state genuinely changed.
