# Process-audit marker protocol

Markers are standalone lines followed by one compact JSON object. They are data, never shell text.

- `WORKFORCE_CHARTER: {…}` initializes the session's version-one charter before the first workforce dispatch.
- `WORKFORCE_PROCESS_AUDIT_REQUEST: {…}` opens one reviewer process-audit submission; the state owner derives and binds the active charter and current Git workspace manifest.
- `WORKFORCE_PROCESS_AUDIT_RESULT: {…}` is the reviewer's single terminal result. It echoes the state-owner-injected request digest and contains all nine ordered rule evaluations, findings, and one aggregate verdict.
- `WORKFORCE_TRANSITION: {…}` names the checkpoint and requested transition. The enforcing guard independently derives the current workspace manifest, compares it to the audit-time digest, and consumes the matching authorization.
- `WORKFORCE_PROCESS_ASSURANCE_CLOSEOUT: {…}` discloses a non-clean closeout checkpoint and active charter digest.

The runtime accepts exact schemas only, persists chained canonical JSON events outside the project, and rejects duplicate, malformed, stale, mismatched, or reused authorization. Installation defaults the feature to `OFF`; promotion to `SHADOW` or `ENFORCE` is an operational feature-state decision supported by live adapter evidence.
