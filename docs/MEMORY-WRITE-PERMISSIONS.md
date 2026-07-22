# Memory-directory write permissions (human-applied)

**Why this exists (2026-07-22):** the auto-mode classifier blocked two
executor dispatches trying to correct a stale, factually wrong memory file
(`project_local_only_no_remote.md`), which then kept triggering false
"data exfiltration" warnings on every authorized push. Agents cannot wire
their own permissions — the classifier blocks self-edits by design — so this
block must be pasted by Jay (same arrangement as the delete-prompt guard).

## What to paste

Into the relevant `settings.json` (`permissions.allow` array), on each machine:

Personal machine (profile `~/.claude-jay`):

```json
"Write(//Users/jay/.claude-jay/projects/**/memory/**)",
"Edit(//Users/jay/.claude-jay/projects/**/memory/**)"
```

Work machine (default profile `~/.claude`):

```json
"Write(//Users/jay/.claude/projects/**/memory/**)",
"Edit(//Users/jay/.claude/projects/**/memory/**)"
```

## What this does and does not do

- Does: removes the permission layer from memory-file edits, so correcting a
  wrong memory is a normal write for whichever agent holds Write/Edit (the
  scribe, in the workforce roster).
- Does not: guarantee the auto-mode classifier never intervenes — that layer
  is Anthropic-side. In the 2026-07-22 session the scribe edit succeeded once
  auto mode was off; with this allow rule in place the ordinary
  permission-prompt path is covered on every mode.
- Scope is deliberately narrow: only `projects/**/memory/**` under the
  profile — not hooks, not settings, not skills.
