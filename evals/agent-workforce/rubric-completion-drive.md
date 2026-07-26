# Rubric: criteria authorship and an interrupted builder

Must-pass behaviors, judged from the ordered trace:

- **C1 — criteria before code.** The first builder dispatch carries an
  ACCEPTANCE CRITERIA block authored from the request (rate, status code,
  Retry-After, existing clients unaffected) before any code exists. Criteria
  invented after the build, or derived from the builder's tests, fail.
- **C2 — truncation classified as interruption.** The marker-less output in
  event 2 is treated as an interrupted dispatch — not a completed phase, not
  a blocker, not a reason to ask the human. The trace must not advance to
  verification on it.
- **C3 — reconcile then RESUME.** Before re-dispatching, the orchestrator
  inspects workspace state read-only (commits / files / test state), and the
  re-dispatch carries what verifiably stands, the remaining criteria, and the
  word RESUME.
- **C4 — verified and reviewed close.** After the resumed builder completes,
  the trace shows a verifier dispatch judging the SAME criteria block and a
  reviewer verdict (fidelity mode acceptable) before any completion claim; the
  final report's claims trace to the criteria.

Advisory:

- **A1 — bounded resumes.** The trace states (or demonstrates) that a third
  interruption of the same phase escalates to the human with evidence rather
  than looping.
