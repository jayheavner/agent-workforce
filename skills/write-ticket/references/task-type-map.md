# Task type -> discipline map

Legacy versions of this skill mapped task types to `superpowers:*` skills.
Those skills don't exist in this framework — the mappings below point at
the six core disciplines instead. **Consumers: edit this file.** It's a
lookup table, not policy; add rows for task types this project actually
creates, and repoint any row to whatever skill names your installation
uses.

| Task type | Discipline(s) | Why |
|---|---|---|
| Write tests before implementation (TDD RED) | `tdd` | tests define the contract before code exists |
| Implement code to pass tests (TDD GREEN/REFACTOR) | `tdd` | keeps the red-green-refactor loop intact |
| Reproduce and fix a bug | `debugging`, `tdd` | diagnose before patching; regression test locks the fix |
| Refactor with regression protection | `tdd` | tests must stay green through the change |
| Extend or backfill test coverage | `tdd` | coverage work is still test-writing discipline |
| Documentation-only update | `verifying` | claim "docs updated" only with evidence it's true |
| Investigation / spike | `interviewing`, `planning` | surface open decisions, then plan follow-up work |
| Setup / configuration change | `verifying` | confirm the change works before closing |
| Review a code diff | `reviewing` | standards + spec-fidelity review |
| Clarify ambiguous requirements | `interviewing` | facts from the codebase, decisions from the human |
| Architecture / design decision | `interviewing`, `planning` | decide the design, then plan its implementation |
| Dependency version update | `verifying` | confirm the upgrade doesn't regress before closing |
| Performance optimization | `debugging`, `verifying` | profile like a diagnosis; prove the improvement |
| Security remediation | `debugging`, `verifying` | root-cause the vulnerability; prove it's closed |
| Decompose a large ticket into subtasks | `planning` | bite-sized, sequenced tasks |
| Draft a new ticket or subtask structure | `planning` | this skill's own output is a plan |
| Ambiguous or fuzzy work item | `interviewing` | resolve fuzziness before ticketing it |
| Verify and close any subtask | `verifying` (via the pack's `close-ticket` skill) | evidence before completion, on every task type |
