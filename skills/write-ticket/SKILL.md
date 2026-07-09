---
name: write-ticket
description: Creates well-structured Asana tickets following separation of concerns and testability principles
allowed-tools: [mcp__asana__asana_create_task, mcp__asana__asana_set_task_dependencies, Read, Glob]
---

# Write Ticket Skill

## Purpose

Creates Asana tickets that enable effective execution by:
- **Clear completion criteria** - Unambiguous "done" state that can be verified
- **Proper decomposition** - Tasks sized for execution without mid-work breakdown
- **Dependency clarity** - Explicit sequencing when order matters
- **Context access** - Links to requirements, decisions, related documentation
- **Testability** - Objective acceptance criteria (tests pass, coverage met, docs updated)

**Execution model:** Tickets created by this skill are designed for execution via the **review-ticket** skill, which handles context gathering and execution environment setup. The review-ticket skill serves as the mandatory entry point before any Asana ticket work begins.

## Pre-Flight Checks

Before creating any ticket:

1. **Gather complete context:**
   - Read all `CLAUDE.md` files in directory path hierarchy
   - Read `.claude/rules/asana-workflow.md` for project/workspace config
   - Read any `.claude/rules/*.md` files for project standards
   - Search project docs and the scribe's status notes for related work, decisions, patterns
   - Read relevant requirements docs from `docs/requirements/`
   - Extract workspace ID and project ID from configuration
   - If not found: STOP and ask user for project
   - **Search available Claude Code skills** - identify skills that should be referenced in tasks/subtasks
   - **If creating code implementation tasks:** Review coding-standards skill to ensure verification steps align with organizational requirements (TDD, coverage thresholds, documentation, security)

2. **Clarify work scope with user:**
   - What needs to be done?
   - What does "done" look like? (success criteria)
   - What must happen first? (dependencies)
   - What context exists? (requirements docs, related tasks, decisions)

## Ticket Decomposition Process

**CRITICAL: You MUST apply Separation of Concerns (SoC) principle when decomposing work into subtasks.**

Each subtask addresses ONE concern. Do not mix unrelated responsibilities in a single subtask.

### Step 1: Identify Concerns

Break work into discrete concerns using separation of concerns principle:

**Each concern should:**
- Address single, well-defined responsibility
- Be independently testable
- Have clear boundaries
- Compose with other concerns to achieve objective

**Good decomposition examples:**
- "Implement feature X" → [Write requirements doc, Write tests (RED), Implement code (GREEN), Refactor, Update docs]
- "Fix bug in Y" → [Reproduce issue, Write failing test, Fix implementation, Verify fix, Document root cause]
- "Refactor Z" → [Ensure tests pass, Backup old implementation, Refactor, Verify tests still pass, Update docs]

**Bad decomposition (avoid):**
- Mixing unrelated concerns in single task
- Tasks too large (>1 week scope)
- Tasks too granular (15-minute tasks create overhead)
- Inline checklists instead of discrete subtasks

### Step 2: Create Parent Task

Parent task defines the WHAT and WHY, not the HOW.

**Parent task structure:**

```markdown
## Objective
[What business outcome are we achieving?]

## Context
[Why is this needed? What problem does it solve?]

## Success Criteria
- [ ] [Observable outcome 1 - must be verifiable]
- [ ] [Observable outcome 2 - must be verifiable]
- [ ] [Observable outcome 3 - must be verifiable]

## References
- Requirements: [reference - use links, file paths, or memory IDs as appropriate]
- Decisions: [reference]
- Related tasks: [reference]

## Notes
[Important constraints, considerations, or context]

## Execution Guidance for Claude Code

When executing this ticket, use **superpowers:subagent-driven-development** workflow:

1. Read all subtask descriptions upfront (don't make subagents read Asana)
2. Dispatch fresh implementer subagent per subtask with full context
3. After each implementation: dispatch spec reviewer, then code quality reviewer
4. Keep parent context clean - all implementation work happens in subagents
5. Dependencies are set - respect the BLOCKS/BLOCKED BY relationships
```

**Key principles:**
- **CRITICAL: Success criteria MUST be objective and verifiable.** No subjective criteria like "looks good" or "works well"
- Success criteria are OBSERVABLE (tests pass, docs exist, feature works)
- No step-by-step instructions (those are subtasks)
- Reference ALL relevant context (use links for URLs, file paths for local docs, memory IDs for past work)
- Explain business value, not implementation details

### Step 3: Create Subtasks

Each subtask addresses ONE concern from Step 1 decomposition.

**Subtask structure:**

```markdown
**Context:** Read parent task before starting - contains execution guidance and full objective context.

## Task
[Specific action to take - be precise]

## Acceptance Criteria
- [ ] [Verifiable outcome 1]
- [ ] [Verifiable outcome 2]

## Verification
[How will completion be verified? Tests? Manual check? Documentation exists?]
[Specify exact commands, file checks, or validation steps for task-verification skill to execute]

**CRITICAL: Unit Tests vs Integration Tests**
- **Unit tests CAN be required** for task completion (fast, isolated, no cost)
- **Integration tests CANNOT be required** for task completion (expensive, external APIs, may cost money)
- Verification steps must only include unit tests
- Integration tests are optional validation, not mandatory gates

## Context
**Parent Task:** [Will be auto-linked by Asana when subtask is created]
[References to relevant docs, code files, or related tasks - use links, paths, or memory IDs]

## Skills to Use
**MANDATORY - Invoke these skills before proceeding with implementation:**
[Search available Claude Code skills and list specific skills that MUST be invoked for this task type, with skill names explicitly referenced and brief rationale for why each is required]
- task-verification - REQUIRED before marking complete
```

**Subtask sizing:**
- Should be reasonable scope (not too granular, not too large)
- Should have 2-5 acceptance criteria
- Should be independently assignable to Claude Code agent
- Should have objective verification method
- **MUST include "Skills to Use" section** - search available Claude Code skills and list specific skills that MUST be invoked for this task type, with skill names explicitly referenced

**CRITICAL: For code implementation tasks, you MUST follow Test-Driven Development (RED-GREEN-REFACTOR). Tests are written BEFORE implementation code.**

**Common subtask patterns:**

**For feature implementation:**
1. Write behavioral requirements document
   - Skills: writing-business-requirements
   - Verification: Use Read tool to verify requirements doc exists and contains behavioral specifications; invoke task-verification
2. Write comprehensive tests (TDD RED phase)
   - Skills: superpowers:test-driven-development
   - Verification: Run test suite and verify tests fail as expected (RED); confirm test coverage includes new scenarios; invoke task-verification
3. Implement code to pass tests (TDD GREEN phase)
   - Skills: superpowers:test-driven-development, coding-standards
   - Verification: Run test suite and verify all tests pass (GREEN); check code coverage meets threshold (≥90%); invoke task-verification
4. Refactor if needed (TDD REFACTOR phase)
   - Skills: superpowers:test-driven-development
   - Verification: Run test suite and verify tests still pass after refactor; compare before/after code complexity metrics; invoke task-verification
5. Update user-facing documentation
   - Verification: Use Read tool to verify documentation updated with examples; check all links work; invoke task-verification

**For bug fixes:**
1. Write test that reproduces bug
   - Skills: superpowers:systematic-debugging, superpowers:test-driven-development
   - Verification: Run new test and verify it reproduces the bug (fails with expected error); invoke task-verification
2. Verify test fails
   - Skills: superpowers:systematic-debugging
   - Verification: Capture test failure output showing bug reproduction; invoke task-verification
3. Fix implementation
   - Skills: superpowers:systematic-debugging, coding-standards
   - Verification: Run all tests including new reproduction test and verify all pass; check no regressions introduced; invoke task-verification
4. Verify test passes
   - Skills: superpowers:systematic-debugging
   - Verification: Run full test suite multiple times to confirm fix is stable; invoke task-verification
5. Document root cause in task comments
   - Skills: superpowers:systematic-debugging
   - Verification: Use Asana MCP tools to verify comment exists with root cause analysis; invoke task-verification

**For refactoring:**
1. Ensure existing tests pass (baseline)
   - Verification: Run full test suite and capture passing results as baseline; invoke task-verification
2. Refactor implementation
   - Verification: Run tests after each refactor step; use code-review skill for quality check; invoke task-verification
3. Verify tests still pass (no regression)
   - Verification: Run full test suite and compare with baseline results; confirm identical pass rate; invoke task-verification
4. Update documentation if behavior changed
   - Verification: Use Read tool to verify documentation reflects any behavioral changes; invoke task-verification

**For documentation-only tasks:**
1. Review existing documentation for gaps
2. Draft new documentation or updates
3. Verify accuracy against code/behavior
4. Review for clarity and completeness
5. Update related documentation cross-references

**For test-writing tasks:**
1. Review existing test coverage
2. Identify gaps in test coverage
3. Write missing tests
4. Verify tests pass
5. Verify coverage meets threshold (≥90%)

**For investigation/spike tasks:**
1. Define investigation questions
2. Research approaches/solutions
3. Document findings in spike report
4. Recommend approach with tradeoffs
5. Create follow-up implementation tasks if needed

**For setup/configuration tasks:**
1. Document current state
2. Make configuration changes
3. Test configuration works
4. Update setup documentation
5. Verify changes don't break existing functionality

**For code review tasks:**
1. Review code against standards
   - Skills: code-review, coding-standards
   - Verification: Use Grep to verify code-review skill was invoked; check that review report exists; invoke task-verification
2. Verify test coverage
   - Skills: code-review
   - Verification: Run coverage report and verify ≥90% threshold met; capture coverage metrics; invoke task-verification
3. Check for security issues
   - Skills: code-review
   - Verification: Confirm security checklist completed (secrets management, input validation, logging); invoke task-verification
4. Document findings
   - Skills: code-review
   - Verification: Use Asana MCP tools or Read tool to verify findings documented with severity and recommendations; invoke task-verification
5. Approve or request changes
   - Skills: code-review
   - Verification: Verify approval/change request recorded in Asana with clear next steps; invoke task-verification

**For requirements review tasks:**
1. Verify requirements are behavioral (WHAT not HOW)
   - Skills: writing-business-requirements
2. Check requirements are testable
   - Skills: writing-business-requirements
3. Validate completeness
   - Skills: writing-business-requirements
4. Document gaps or ambiguities
   - Skills: writing-business-requirements
5. Approve or request revision
   - Skills: writing-business-requirements

**For dependency updates:**
1. Check current versions
2. Research latest stable versions
3. Update dependency specifications
4. Run full test suite
5. Verify no regressions

**For performance optimization:**
1. Establish baseline metrics
2. Profile to identify bottlenecks
3. Implement optimization
4. Measure performance improvement
5. Verify no functional regressions

**For security remediation:**
1. Verify vulnerability exists
2. Research mitigation approaches
3. Implement fix
4. Verify vulnerability is resolved
5. Document remediation

**Note:** More patterns will be added as new task types emerge.

### Step 4: Set Dependencies

**CRITICAL: You MUST set dependencies when work order matters. For TDD tasks, tests MUST BLOCK code implementation.**

Use `mcp__asana__asana_set_task_dependencies` when:
- Work MUST be sequential (requirements before tests, tests before implementation)
- One task produces output needed by another
- Order matters for correctness

**Dependency examples:**
- "Write tests" BLOCKS "Implement code" (can't implement without tests in TDD)
- "Write requirements" BLOCKS "Write tests" (need spec before tests)
- "Implement code" BLOCKS "Update docs" (need working code to document)

**When NOT to use dependencies:**
- Tasks can genuinely run in parallel
- Order is preference, not requirement
- Creating artificial sequencing

### Step 5: Draft Review

Before creating tickets in Asana, show user:

```markdown
## Proposed Ticket Structure

**Parent Task:** [Name]
- Objective: [What we're achieving]
- Success criteria: [How we know it's done]

**Subtasks:**
1. [Subtask 1 name]
   - Acceptance: [Criteria]
   - BLOCKS → 2, 3

2. [Subtask 2 name]
   - Acceptance: [Criteria]
   - BLOCKED BY → 1

3. [Subtask 3 name]
   - Acceptance: [Criteria]
   - BLOCKED BY → 1

Does this decomposition make sense?
```

Wait for user confirmation before creating tickets.

## Execution

When user confirms structure:

1. **Create parent task** using `mcp__asana__asana_create_task`:
   - Set project ID from context
   - Use parent task description template
   - Capture task ID for subtask creation

2. **Create subtasks** using `mcp__asana__asana_create_task`:
   - Set `parent` parameter to parent task ID
   - Use subtask description template
   - Capture each subtask ID

3. **Set dependencies** using `mcp__asana__asana_set_task_dependencies`:
   - Link subtasks based on sequencing needs
   - Verify dependency logic is correct

4. **Confirm completion** to user:
   ```markdown
   ## Tickets Created

   **Workspace:** [Workspace Name]
   **Project:** [Project Name]

   **Parent Task:** [Task Name](URL)
   **Objective:** [Brief 1-2 sentence summary of what's being accomplished]

   **Subtasks:** 3 total (1 unblocked, 2 blocked)
   1. [Subtask 1 Name](URL)
   2. [Subtask 2 Name](URL) - BLOCKED BY → 1
   3. [Subtask 3 Name](URL) - BLOCKED BY → 1

   Tickets are ready for execution in a fresh context.
   ```

## Anti-Patterns (NEVER DO THIS)

**CRITICAL: You MUST create discrete Asana subtasks. NEVER use inline markdown checklists in task descriptions.**

### Wrong: Inline Checklists

```markdown
Task description:
- [ ] Do step 1
- [ ] Do step 2
- [ ] Do step 3
```

**Why wrong:** Prevents independent assignment, dependency tracking, granular status updates.

**Correct approach:** Create 3 discrete subtasks with dependencies.

### Wrong: Vague Objectives

```markdown
Task: "Fix stuff"
Task: "Update code"
Task: "Make it better"
```

**Why wrong:** No clear completion criteria, can't verify success.

**Correct approach:** "Fix authentication timeout bug in login flow" with specific acceptance criteria.

### Wrong: Missing Context Links

```markdown
Task: "Implement feature X"
[No links to requirements, decisions, or related work]
```

**Why wrong:** Forces context hunting mid-work, increases failure risk.

**Correct approach:** Include links to requirements docs, architecture decisions, related tasks.

### Wrong: Untestable Acceptance Criteria

```markdown
Acceptance criteria:
- [ ] Code looks good
- [ ] Everything works
- [ ] Users will like it
```

**Why wrong:** Subjective, unverifiable, leads to scope creep.

**Correct approach:** "All tests pass with ≥90% coverage", "Documentation includes examples", "Code review approved".

### Wrong: Over-Decomposition

```markdown
Parent Task
  → Subtask 1
    → Sub-subtask 1.1
      → Sub-sub-subtask 1.1.1
```

**Why wrong:** Excessive overhead, difficult to track, Asana best practice is max 1 layer deep.

**Correct approach:** Parent → Subtasks only (1 layer).

### Wrong: Missing Dependencies

```markdown
Subtask 1: Implement code
Subtask 2: Write tests
[No dependency linking them]
```

**Why wrong:** Violates TDD (tests must come first), allows wrong execution order.

**Correct approach:** Set dependency so "Write tests" BLOCKS "Implement code".

## Failure Mode Prevention

### "I don't have enough information to start"

**Prevention:**
- Parent task MUST link to all relevant documentation
- Subtask MUST specify what context is needed
- Include links to requirements, decisions, related code
- Add notes section with constraints/considerations

### "This task is too big, I need to break it down"

**Prevention:**
- Apply separation of concerns during decomposition
- Each subtask addresses ONE responsibility
- Keep subtasks at reasonable scope
- If larger, decompose further during ticket creation

### "I don't know when this is done"

**Prevention:**
- Every task MUST have verifiable acceptance criteria
- Criteria must be objective (tests pass, docs exist, feature works)
- Avoid subjective criteria ("looks good", "works well")
- Include verification method (how to check completion)

### "I don't know what order to do these in"

**Prevention:**
- Set explicit dependencies when order matters
- Use BLOCKS/BLOCKED BY relationships
- Document WHY dependency exists in subtask notes
- Only create dependencies when truly required (allow parallelism when possible)

### "I built the wrong thing"

**Prevention:**
- Parent task explains business context (WHY)
- Link to requirements documentation
- Include success criteria at parent level
- Subtasks reference parent objective for context

## Project Context Detection

When skill is invoked:

1. Check if current directory has `.claude/rules/asana-workflow.md`
2. Read file and extract:
   - Workspace ID
   - Project ID
   - Project name
3. If file exists but missing config: Read `CLAUDE.md` for Asana configuration
4. If no config found anywhere: STOP and ask user:
   ```
   Cannot detect Asana project from local documentation.

   Please provide:
   - Project name or ID
   - Workspace name or ID (if known)
   ```

## Success Criteria

After ticket creation, verify:
- [ ] Parent task has clear objective and success criteria
- [ ] Parent task includes "Execution Guidance for Claude Code" section with superpowers:subagent-driven-development workflow
- [ ] Each subtask addresses one concern
- [ ] Each subtask includes "Skills to Use" section with specific, mandatory skill references
- [ ] Dependencies are set where order matters
- [ ] All acceptance criteria are verifiable
- [ ] Context links are present and correct
- [ ] Structure confirmed before creation
- [ ] All task URLs provided

## Required Skills by Task Type

The following skills are MANDATORY for their respective task types and are automatically included in tickets' "Skills to Use" sections:

**Implementation tasks:**
- **superpowers:test-driven-development** - REQUIRED: Tests must be written before code (TDD discipline)
- **coding-standards** - REQUIRED: Quality and consistency enforcement

**Bug fixes:**
- **superpowers:systematic-debugging** - REQUIRED: Root cause analysis and structured investigation
- **superpowers:test-driven-development** - REQUIRED: Reproduction test before fix

**Architecture/Design tasks:**
- **superpowers:brainstorming** - REQUIRED: Structured ideation and option evaluation
- **superpowers:writing-plans** - REQUIRED: Implementation planning before coding

**Requirements tasks:**
- **writing-business-requirements** - REQUIRED: Behavioral specifications focus

**Code quality validation:**
- **code-review** - REQUIRED: Standards compliance verification

**All subtasks (universal requirement):**
- **task-verification** - REQUIRED: Completion validation before marking done

**Critical Note for Executors:**
When Claude Code sees these skills listed in a ticket's "Skills to Use" section, invocation is MANDATORY, not optional. Skipping required skills violates organizational standards and results in quality issues.

## Integration with Execution Workflow

Tickets created by this skill integrate with Claude Code's execution workflow:

1. **write-ticket** creates structured tickets with mandatory skill references
2. **review-ticket** validates tickets and surfaces required skills before work begins
3. **work-ticket** executes the validated work following the plan from review-ticket
4. **Required skills** (listed in subtasks) MUST be invoked during implementation
5. **task-verification** validates completion before marking done

This creates a forcing function ensuring proper process adherence throughout the development lifecycle.

## References

Based on research from:
- Asana best practices for subtask decomposition and dependencies
- Software engineering separation of concerns principle
- Testability requirements for effective verification
- Project-specific standards in `.claude/rules/asana-workflow.md`
