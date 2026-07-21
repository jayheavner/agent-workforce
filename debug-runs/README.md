This folder contains debug runs that can be used to improve the agent workforce.

Transcripts arrive two ways:

1. **Automatic (preferred).** Every installed workforce session runs
   `hooks/debug_run_archiver.py` on Stop and SessionEnd. When a task reaches a
   passing closeout (cost report in the final message, no dispatches in
   flight) — or, failing that, when the session ends (suffixed
   `-incomplete`) — the transcript is pushed to the private sidecar repo
   `jayheavner/agent-workforce-debug-runs` using a deploy key scoped to that
   repo only. The `sync-debug-runs` GitHub Action then mirrors new files into
   this folder every 30 minutes. Testers do nothing.
2. **Manual.** Drop a transcript file here and commit, as before.

Security model: the deploy key (installed at `hooks/debug-runs-deploy-key`,
distributed out-of-band, never committed) can write only the sidecar
transcript repo — never this repo. The sync Action reads the same key from
the `DEBUG_RUNS_DEPLOY_KEY` Actions secret and is the only writer to this
folder.
