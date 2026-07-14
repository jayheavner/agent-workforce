---
name: op-migration
description: Migrate credentials discovered by the handling-secrets discipline into 1Password using service-account authentication only. Use when moving exposed secrets into a 1Password vault, or when a task needs an op:// reference for a credential.
requires: [handling-secrets]
---

# Op Migration

Job: the 1Password-specific half of secrets work — how to authenticate,
where to write, and the phase sequence for moving a discovered credential
into the vault. The vendor-neutral discipline (never materialize a value,
scope of scanning, committed-secret = compromised) lives in
`handling-secrets`; this skill only adds what's specific to `op`.

## Authentication: service account only

This skill authenticates with a **service-account token only**. It never
uses 1Password desktop-app CLI integration, and it never installs software.

- `op` not on PATH → report to the user and stop. Do not install it.
- Service-account token missing, or `op vault list` fails → report the
  exact failure and stop. Never fall back to desktop-app auth — that
  fallback is not an option, under any authentication failure.
- A vault outside the service account's reach → hand that item to the
  human (name, fields, target vault) rather than switching auth modes;
  resume with the credentials you can reach.

Vault name and token-path are pack-local config, not core policy — resolve
them from this pack's `vault-config` entry in `references/workflow.md` and
state the resolved value before using it. This is deliberately outside
`policy/KEYS.md`: that registry stays vendor-free, and vault name/token
path are 1Password-specific, not framework policy.

## The only sanctioned write path

`op item create` and `op item edit` are the only tools ever handed a
secret value as an argument — that's the vault's intended write path, and
the sole exception to "never materialize a secret." No other command,
script, or file may receive a raw value. Populate the value into a shell
variable extracted from the source in the same pipeline; never type a
secret as a literal.

## Field naming

- Single-value secret → `credential`
- Key pair → `api_key` / `api_secret`
- Username + password → `username` / `password`

## Risk levels

CRITICAL (git-committed, current or in history) → flag for immediate
rotation. HIGH (other project files) → rotate promptly. MEDIUM (user/shell
config) → rotate as convenient. This severity mapping is fixed — a
git-committed secret is never downgraded because it "looks like a toy" or
is hard to rotate quickly.

## Sequencing: test before removing from source

The verified vault entry IS the backup. A credential's original location
is only touched — edited or deleted — after it has been stored in 1Password
**and** re-read back successfully. This is a hard sequencing rule, not a
recommendation: don't remove or rewrite the source line first and store
second, and don't skip the re-read because storing "should have worked."

## Phases

Full detail (discovery scope, question flow, test/verify/store steps) →
`references/workflow.md`. Compressed:

1. **Prerequisites** — service-account auth per above.
2. **Discovery** — scan project + user config per `handling-secrets` scope;
   build an inventory (location, risk level, type, service, value preview).
3. **Migration** — per credential: confirm it's real, test/identify it,
   create the 1Password entry (field naming above), re-read to verify.
4. **Source update** — only after Phase 3 verification passes, remove the
   value from its original location; leave an `op read` reference comment.
5. **Documentation** — generate the four reports (references only, never
   values): Migration Summary, Credential Rotation Plan, Testing Report,
   Quick Reference.
6. **Validation** — confirm all four reports exist, no hardcoded secret
   remains anywhere, and the user understands `op read` retrieval.

## Related skills

`handling-secrets` for the always-on discipline this skill assumes is
already in force (scope of scanning, never-materialize, committed = rotate).
