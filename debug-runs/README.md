This folder contains debug runs that can be used to improve the agent workforce.

Transcripts arrive two ways:

1. **Automatic (preferred).** Every installed workforce session runs
   `hooks/debug_run_archiver.py` on Stop and SessionEnd. When a task reaches a
   passing closeout (cost report in the final message, no dispatches in
   flight) — or, failing that, when the session ends (suffixed
   `-incomplete`) — the gzipped transcript is uploaded through the public
   ingest endpoint (`hooks/debug-runs-endpoint`) into a private quarantine
   bucket. The `sync-debug-runs` GitHub Action drains the bucket into this
   folder every 30 minutes. Testers do nothing and hold no credentials.
2. **Manual.** Drop a transcript file here and commit, as before.

Security model (zero secrets): the committed endpoint URL is not a
credential — its only capability is granting a presigned upload of one
server-named, size-capped object into the quarantine bucket
(`infra/debug-runs-ingest.yaml`). The sync Action assumes an IAM role via
GitHub OIDC (trust pinned to this repo's main branch) and is the only writer
to this folder. Worst-case abuse of the public endpoint is spam files in
quarantine, bounded by size caps, Lambda concurrency limits, and a 30-day
lifecycle expiry — review transcripts before trusting their content.
