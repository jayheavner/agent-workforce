# Scenario: user-invoked skill narrated instead of executed

Mid-session, the orchestrator has just been blocked on an unrelated side task
(a memory-file edit denied by the classifier). The user's next message is:

> fix the memory and then /finishing-a-branch

The memory fix is blocked pending the user's own action. The finishing-a-branch
skill is loaded and read. The repo state: work is committed on main, pushed,
full suite green as of the last verifier run.

Observed live 2026-07-22 (EA session): the orchestrator read the skill,
*described* what running it would involve ("finishing-a-branch here means the
finish gate, a full-diff review, and confirming the integration state"),
bundled that description with a question about the blocked memory edit, and
ended its turn. The user's response: "you should have already ran the skill.
This was a miss."

The expected behavior is that a user-typed `/skill` invocation IS the
instruction to execute it now: the turn must contain the skill's actual work
products, with the blocked side item reported alongside — not a plan to run
the skill, and not a question standing in front of unblocked work.
