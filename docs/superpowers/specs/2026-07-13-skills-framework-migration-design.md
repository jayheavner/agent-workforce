# Skills Framework Migration — Design

**Date:** 2026-07-13  
**Status:** Integrated with upstream workforce changes and validated  
**Upstream:** `jayheavner/skills` at `e8f0bee8ca8aed807cf0e9d092e46cb2fa366498`

## Purpose

Replace the workforce's ten legacy organization skills with the portable skills
framework maintained in `jayheavner/skills`. The workforce remains a vendoring
consumer: its repository is still the complete machine-installable source of
truth, while generic skill authorship and evaluation live upstream.

## Dependency ownership

`SKILLS-FRAMEWORK` records the exact upstream revision. The upstream repository
had no Git tag when this migration was made, so the full commit SHA is the pin.
The source checkout is needed only on the authoring machine that performs an
upgrade. Target machines install the corresponding files from this repository
into each selected Claude profile; they do not need a separate skills checkout.
An upgrade is an explicit re-vendor, reviewed diff, pin change, installer test,
and workforce shakedown.

The framework core and all four packs are flattened into the existing
`skills/<name>/` layout. `policy/KEYS.md` is copied from upstream. The
`skills/project-policy/SKILL.md` instance is consumer-owned and may differ from
the upstream example without forking generic skill behavior.

## Role mapping

| Role | Preloaded skills | Situational skills |
|---|---|---|
| architect | `planning`, `project-policy` | `interviewing`, `ux-to-ui-design`, `convene-panel` |
| builder | `tdd`, `debugging`, `handling-secrets`, `project-policy` | none |
| verifier | built-in `verify`, `verifying` | none |
| reviewer | `reviewing`, `project-policy` | none |
| deployer | built-in `verify`, `handling-secrets` | none |
| researcher | none | none |
| ops | `handling-secrets` | `op-migration` |
| scribe | `writing-business-requirements`, `auditing-requirements`, `handing-off` | none |
| ticketer | `write-ticket`, `review-ticket`, `close-ticket`, `verifying`, `project-policy` | none |

`finishing-a-branch` and `writing-skills` are vendored because core framework
installs are complete and upgradeable, but they are not preloaded. Branch
integration remains an orchestrator gate, and generic skill authoring remains
an upstream-repository workflow.

## Consumer policy decision

The upstream organization example requires every code task to create a nested
per-task worktree. The current workforce does not have an orchestrator-owned
worktree creation and cleanup phase: all specialists intentionally operate on
the checkout chosen when the main session starts. Claiming otherwise in policy
would make every route noncompliant without changing its mechanics.

This consumer therefore resolves `workspace-isolation` as one task per explicit
checkout, with builder, verifier, reviewer, and deployer sharing that path.
Concurrent tasks require separate human-created checkouts or orchestrator
sessions. A future worktree-isolation feature must change orchestration,
handoff, verification paths, cleanup, policy tests, and shakedown together.

## Installer contract

Before touching any installed files, `install.sh` now validates:

- the intended Claude profile is unambiguous or selected explicitly;
- the pinned revision is a full commit SHA;
- Agent Skills-compatible names and descriptions;
- relative links inside each skill;
- every `requires:` dependency;
- every `policy:<key>` against `policy/KEYS.md`;
- every agent preload and every situational skill;
- the existing hook, dispatch, and cost test suites.

The manifest records the upstream revision. Reinstallation retires files that
the previous manifest managed but the new vendored tree removed, backing them
up first so partial-install rollback remains complete.

## Acceptance

1. No active agent definition references a legacy skill or `superpowers:*`.
2. All nineteen vendored skills install into a sandbox HOME.
3. Dependency and policy-registry defects fail before copying.
4. Drift, missing-file, upstream-pin, and retired-file behavior is tested.
5. Policy, dispatch, cost, and installer suites pass.
6. The migration remains compatible with the workforce decision-discipline,
   gap-loop, config-directory, and fixed-hook-location changes added upstream.
7. A machine with multiple Claude profiles fails closed until the caller selects
   a profile, and each selected profile can be installed and checked independently.
