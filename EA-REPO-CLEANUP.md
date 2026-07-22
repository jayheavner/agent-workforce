# EA repo cleanup — run on the work machine

**Audience:** a Claude Code session in
`~/Code/corporate/python/Lambda/email_webhook_handler` on Jay's work machine.

**Why, in plain terms:** during the July 22 session, the workforce's own
closeout hook kept dropping cost-summary files into that repo's
`docs/telemetry/` folder. The agent at the time thought they were junk from a
broken hook, so it hid them with a gitignore rule and hand-wrote its own
telemetry record. As of workforce build ccdebd7 those files are written
outside client repos entirely, so the workarounds are now dead weight. This
cleans them up.

## Steps

1. **Get current first.** In the workforce repo checkout on that machine, run
   `git pull` — or just launch `bin/agent-workforce` once; it now updates
   itself. Everything below assumes the current build, where telemetry no
   longer lands in this repo.
2. **Remove the dead gitignore rule.** In the EA repo's `.gitignore`, delete
   the line matching `docs/telemetry/-Users-*.jsonl` (and any purge-archive
   ignore line ONLY if Jay says so — that one is still doing its job; leave
   it by default). The telemetry line matches nothing anymore.
3. **Delete stray leftovers.** Any untracked `docs/telemetry/-Users-*.jsonl`
   files still on disk are old cost summaries — delete them. Their data lives
   in the workforce's own logs.
4. **Retire the old telemetry convention in place.** The committed files in
   `docs/telemetry/` (the dated, hand-written records and the README) are
   project history — keep them. Add one line at the top of that README:
   "Retired 2026-07-22: dispatch telemetry is now machine-written to
   workforce-owned storage (`~/.claude/logs/agent-team-telemetry/`); nothing
   new is written here, and no record in this folder should be hand-authored
   again."
5. **Check the landing-claim hook still earns its keep.** That machine has a
   Stop hook called `landing-claim-verifier` (it is not part of the workforce
   repo). Its false alarms came from the telemetry files this cleanup ends.
   If it fires again after this cleanup, whatever it names is a real
   uncommitted file — treat it as signal, not noise.
6. **Commit** the gitignore + README changes with the repo's usual
   convention, push per the repo's standing integration choice.

## Done when

`git status` in the EA repo stays clean through a full workforce task
closeout with no ignore rule hiding workforce files — clean because nothing
writes there anymore, not because anything is hidden.
