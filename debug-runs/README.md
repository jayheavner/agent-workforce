This folder contains debug runs that can be used to improve the agent workforce.

Transcripts arrive two ways:

1. **Automatic (preferred).** Every installed workforce session runs
   `hooks/debug_run_archiver.py` on Stop and SessionEnd. When a task reaches a
   passing closeout (cost report in the final message, no dispatches in
   flight) — or, failing that, when the session ends (suffixed
   `-incomplete`) — the transcript is pushed to a `transcripts/<session-id>`
   branch using the tester's own GitHub login (testers are collaborators; no
   secrets are ever distributed). The `sync-debug-runs` workflow folds those
   branches into this folder and deletes them, on every transcript push and
   on a half-hourly sweep. Testers do nothing.
2. **Manual.** Drop a transcript file here and commit, as before.

Security model (zero distributed secrets): testers authenticate as
themselves. Main is closed to direct pushes by a ruleset (admins and the
sync workflow bypass), and the workflow extracts ONLY `debug-runs/` paths
from transcript branches — so collaborator write access cannot change
anything outside this folder on main, no matter what a branch contains.

Tester requirements: a GitHub account with a pending-accepted collaborator
invite, and working git credentials (`gh auth login && gh auth setup-git`
if pushes fail).
