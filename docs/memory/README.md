# Project Memory Records

These are project records rather than personal Codex memory. They are durable
project context, not a hidden replacement for a human decision log. A record under this directory
does not claim to update `$HOME/.codex/memories` or any other user profile.

## When to write one

Write a record when the user explicitly requests durable project memory or when
the human approves recording a reusable decision, constraint, discovery, or
landmine during closeout. Do not create a record for ordinary implementation
detail that is already obvious from the code or commit history.

Use this path format:

```text
docs/memory/YYYY-MM-DD-<slug>.md
```

The slug names the reusable topic, not the whole conversation. If no record is
requested or the work contains nothing reusable, the closeout ledger must say
`memory: not requested` or `memory: not reusable`.

## Required record format

Every record contains these headings:

```markdown
# <Topic>

## Scope

Which project, component, or workflow this applies to.

## Reusable facts

Observed facts that a future session should verify before relying on.

## Decisions and why

Choices that could plausibly be revisited and the reasoning that settled them.

## Landmines

Misleading paths, failed approaches, or environmental traps.

## Verification

Exact commands or inspections that established the facts, with their result.

## Source paths

Repository files, external references, or ticket identifiers actually read.

## Secret handling

State that no credential values, tokens, cookies, or private key material were
copied into this record. Refer to secret stores or environment variables by
name only.
```

Facts must come from files or systems actually inspected in the task. Keep
uncertainty and stale-sensitive facts labeled. Never write a credential value,
transcript secret, access token, auth header, cookie, password, or private key.

## Closeout states

The final closeout ledger uses exactly one of these memory states:

- `not requested`
- `not reusable`
- `recorded: docs/memory/<file>.md`
- `pending human approval: docs/memory/<proposed-file>.md`

The last state means the scribe prepared a proposed record but did not treat it
as approved personal or project memory.
