# UX Design Output Format

Before any UI, produce a written UX design with these ten sections. This is
the artifact the UI phase consumes — don't skip a section; if you can't
answer it confidently, name the gap instead of guessing.

```
USER & CONTEXT
- Primary user: [...]
- Context: [...]
- Mental model: [...]

JOB
- When [...], I want to [...] so that [...]

TASK FLOW
- Entry: [...]
- Steady state: [...]
- Exit / recovery: [...]

STATES
- [state]: [UX requirements for this state]
- ...

INFORMATION NEEDS (ranked)
- Must-see: [...]
- Should-see: [...]
- Could-see (on demand): [...]
- Should-not-see: [...]

INTERACTION NEEDS (ranked by frequency × risk)
- [...]

ERROR PREVENTION
- [mistake]: [prevention/recovery approach]

ACCESSIBILITY
- Keyboard path: [...]
- Screen-reader hierarchy: [...]
- Non-color signals: [...]

CONSTRAINTS
- [...]

UX DECISIONS
- [Decision]: [Reason rooted in the above]
```

Only after this exists do you move to the UI phase. Each later UI choice
should trace back to a specific line in this artifact — if it can't, the
choice was made by convention or pattern-envy, not by design.

## Section notes

- **User & Context / Job** — phrase the job from the user's felt outcome,
  not the system event ("confirm this does what I expect" not "click
  Save").
- **Task Flow** — include the boring middle and the unhappy paths; skipping
  either is the most common way this template gets filled out hollow.
- **States** — enumerate independently; a decision that's right for the
  clean state (free navigation) can be wrong for the dirty state (guarded
  navigation).
- **Interaction Needs** — use the frequency × risk matrix from SKILL.md to
  rank; each item should read as (frequency, risk) → (affordance,
  safeguard).
- **UX Decisions** — this is the row-by-row justification the UI phase
  reads first; a decision with no traceable reason back to an earlier
  section is a red flag, not a stylistic gap.
