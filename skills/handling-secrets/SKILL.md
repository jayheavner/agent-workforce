---
name: handling-secrets
description: Universal secret-handling discipline — never materialize a credential in any file, log, or transcript; reference via env vars or on-demand reads. Use when any task touches credentials, keys, tokens, or .env files.
---

# Handling Secrets

Job: work with credentials without ever writing one down. A secret that
touches a transcript, log, scratch file, or commit is burned — treat exposure
as rotation, not cleanup.

## The discipline

- Reference every credential through an environment variable or an on-demand
  read from the secret store — never paste a value into code, config, output,
  or a command you echo.
- **Never materialize:** extract → use → discard in one command. Read the
  value into a shell variable and pass it in the same pipeline; send anything
  that would print it to /dev/null.
- When a human must see which secret you mean, show first/last characters
  only (`sk-t…5678`). That preview is the only form a value may take in any
  output — every time the value comes up again, even in passing commentary,
  not just on first mention.
- A verified vault entry IS the backup. Never create a plaintext backup "just
  in case."

## Scope

Scan for exposed secrets only in the project directory plus explicitly named
config files (`.env`, tool configs). Never sweep the whole home directory;
never content-scan `~/.ssh/` (check key encryption status only).

## When you find one exposed

Committed to git = compromised: flag for rotation immediately, then remove
from source. Test the stored replacement works before deleting the original
reference. Vendor-specific migration workflows (1Password) live in the
`secrets-1password` pack.
