---
name: review-ticket
description: Use when user asks to review an Asana ticket, understand work requirements, or assess ticket validity before starting implementation
---

# Review Ticket

## Overview

Structured process for reviewing Asana tickets to understand work requirements, validate ticket status, identify blockers, and analyze actual scope before beginning implementation.

## Execution Model

This skill serves three purposes:

1. **Context gathering** - Fetch all information Claude Code needs to execute work autonomously
2. **Scope analysis** - Deep investigation to understand true complexity, identify decomposition needs, and surface hidden dependencies
3. **Supervisor visibility** - Provide user with comprehensive ticket analysis for informed oversight decisions

Claude Code works autonomously but under user supervision. This skill enables effective oversight by surfacing validity concerns, blockers, risks, scope mismatches, and execution context before work begins.

**Philosophy: Think Deeply Before Acting**

This skill is the "reconnaissance mission" - scout the terrain, identify obstacles, understand true scope, recommend approach. It prevents mid-flight course corrections by front-loading discovery before user approves work.

## Execution Environment for Claude Code

**Context availability:**
- Claude Code starts with fresh context when assigned a task
- Parent task context is NOT automatically loaded - this skill fetches it
- All necessary context must be in ticket description or fetched via MCP tools
- This skill is the entry point that gathers all required context

**Task assignment patterns:**
- **Pattern 1 (Parent-driven):** Assigned parent task → this skill reads all subtasks → execution proceeds with subagent spawning (when the Task tool is available; see Phase 2 for the non-delegating alternative)
- **Pattern 2 (Direct subtask):** Assigned specific subtask → this skill automatically fetches parent for context

**Information access:**
- Asana MCP tools available for fetching related tickets
- Search project docs and the scribe's status notes for related past decisions
- File system access for reading requirements docs
- Git access for checking commit history

**Entry point function:**
This skill acts as the mandatory entry point before any Asana ticket work begins. It ensures Claude Code has complete context regardless of whether work starts from parent or subtask.

## When to Use

Use this skill when:
- User provides Asana ticket ID, URL, or description
- User asks "what should I work on?" or "review this ticket"
- Before starting any Asana-tracked work
- Need to understand ticket context and requirements for both execution and oversight

## Process

### Phase 1: Presentation

Retrieve and present ticket details in structured format:

```markdown
# Ticket: [Title]
Link: [Asana URL]

**Status:** [Current state]
**Assignee:** [Person or unassigned]
**Due:** [Date or none]
**Parent:** [Parent ticket link and title] (if applicable)

## Summary
[Ticket description/summary]

## Subtasks
- [ ] Subtask 1
- [x] Subtask 2 (completed)
- [ ] Subtask 3

## Dependencies
**Blocked by:** [Ticket links with titles]
**Blocking:** [Ticket links with titles]

## Recent Activity
Last updated: [timestamp]
Last comment: [summary of most recent comment if relevant]
```

**Asana MCP tools to use:**
- `mcp__asana__asana_get_task` - Get full task details
- Include `opt_fields` parameter for: `subtasks, parent, dependencies, dependents, assignee, due_on, modified_at, notes, html_notes`

### Phase 2: Due Diligence Research & Scope Analysis

**Critical questions to investigate:**

0. **Is this ticket already assigned?**
   - **CRITICAL: If ticket is already assigned to another agent or person, you MUST NOT proceed with work unless user explicitly instructs you to take over this specific ticket. Respect existing assignments.**
   - Check assignee field in task details
   - If assigned to someone else, STOP and report to user
   - Only proceed if unassigned OR user explicitly authorizes takeover

1. **Is this ticket still valid?**
   - Check task status - is it already completed/closed?
   - Review recent comments - has work been done elsewhere?
   - Check git commits - search for related work by commit messages or file changes
   - Look for duplicate or superseding tickets in project

2. **Are there blockers to this work?**
   - Verify dependencies field - any incomplete blocking tickets?
   - Check subtasks - any prerequisites not yet done?
   - Review codebase state - does required infrastructure exist?
   - Check for missing requirements, specs, or design decisions

3. **What is the actual work?**
   - Parse ticket description for acceptance criteria
   - Identify deliverables (code changes, tests, docs, config)
   - Determine scope - is this well-defined or needs clarification?
   - Check for related requirements documents or design specs
   - **If code implementation task:** Verify acceptance criteria align with coding-standards skill requirements (TDD, test coverage, documentation, security)

4. **Is this a valid ticket? (IMPORTANT)**
   - **CRITICAL: You MUST stop and report to user if ticket is invalid. Do not proceed with invalid work.**
   - Does work description match current codebase reality?
   - Has code already been implemented but ticket not updated?
   - Are requirements outdated or contradicted by newer decisions?
   - Is ticket description clear enough to implement?

5. **What is the execution context?**
   - **CRITICAL: You MUST fetch parent task when reviewing subtasks and MUST fetch all subtasks when reviewing parent**
   - **If reviewing a subtask:** Automatically fetch and read parent task
   - **If reviewing a parent:** Automatically fetch and read all subtasks
   - Check for "Execution Guidance for Claude Code" section in parent task
   - **Check for "Skills to Use" section in current task** - Extract complete list of skills
   - **CRITICAL: You MUST validate that all listed skills exist and are spelled correctly**
   - **Validate each skill name** against known skills if possible
   - **Capture reasoning** for why each skill is specified in the task description
   - Identify all skills referenced that should be invoked during execution
   - **Configuration lookup:** Check `.claude/rules/asana-workflow.md` for workspace/project IDs and verify task belongs to expected project

6. **What is the ACTUAL scope? (Scope Analysis)**
   - **Does ticket description match implementation reality?**
   - Is this really one concern or multiple concerns mixed together?
   - Are there hidden dependencies (infrastructure, other services, database changes)?
   - Does implementation require changes outside stated scope?
   - Would this work benefit from being split into multiple tickets?

   **Analysis approach:**
   - Investigate the codebase to understand implementation context (see "Codebase exploration and ticket work below" for how, depending on whether the Task tool is available)
   - Search for similar implementations to understand patterns
   - Identify all systems/components that will be affected
   - Check for separation of concerns violations in ticket scope
   - Look for infrastructure/configuration prerequisites

   **Decomposition triggers (when to recommend ticket splitting):**
   - Ticket mixes multiple concerns (e.g., "Fix bug AND refactor AND add feature")
   - Implementation requires infrastructure changes (e.g., database migration BEFORE code changes)
   - Work has clear sequential dependencies (e.g., requirements → tests → implementation)
   - Ticket scope is too large for a single focused work session, based on codebase exploration
   - Different parts require different skills or expertise

   **When scope analysis reveals decomposition need:**
   - Document the recommended split clearly in report
   - Create the decomposed tickets per the "Codebase exploration and ticket work" guidance below, if user approves decomposition
   - Set up proper dependencies between split tickets
   - Keep original ticket as parent to track overall objective

**Research methods:**

**Direct tools (use in main context, always available):**
- `mcp__asana__asana_get_stories_for_task` - Read task comments/history
- `mcp__asana__asana_search_tasks` - Find related/duplicate tickets
- `Grep` - Quick searches for specific patterns
- `Read` - Check requirements docs, architecture decisions
- `Bash` with git log - Search commit history for related work

**Codebase exploration and ticket work (conditional on Task tool availability):**

Whether deep codebase exploration and ticket creation happen via subagent dispatch or inline depends on whether the Task tool is available in the current execution context:

- **When the Task tool is available**, delegate the focused lookups to keep this skill's context clean:
  - Codebase exploration: dispatch an Explore-type subagent for deep codebase investigation, pattern analysis, or complexity assessment (for example, "Analyze the authentication module to understand impact of adding OAuth support"). This keeps exploration results contained rather than polluting review-ticket context.
  - Ticket creation: dispatch a subagent running the write-ticket skill if analysis reveals a need for additional tickets, so write-ticket can run its full process without consuming review-ticket context.
  - Requirements clarification: dispatch a subagent running the writing-business-requirements skill if the ticket lacks behavioral specifications; the subagent writes the requirements document and returns its location.
  - Design work: recommend the brainstorming skill for the user to invoke directly if the ticket needs design decisions before implementation — this is a user decision point, not something to dispatch.

- **When the Task tool is not available** (for example, this skill is itself running inside a dispatched agent such as the ticketer), do the focused lookups inline instead:
  - Perform codebase exploration directly with Grep/Read/Bash rather than dispatching an Explore agent.
  - Do not attempt to create decomposed tickets inline. Instead, document the recommended decomposition in the report and recommend it to the orchestrator, so the orchestrator can dispatch ticket creation or hand it back to the user.
  - Note in the report which lookups were done inline due to Task-tool unavailability, so the orchestrator understands why decomposition wasn't executed directly.

**Decision criteria:**
- Use direct tools for quick, focused lookups regardless of context
- When the Task tool is available, prefer dispatching subagents for deep analysis, ticket creation, or work that would consume significant context
- When it is not available, do the equivalent work inline and shift decomposition/ticket-creation to a report recommendation

**Why prefer subagent dispatch when available?**
- Maintains clean context boundaries - review-ticket context stays focused on analysis
- Prevents context pollution from deep exploration or ticket creation workflows
- Allows specialized skills to run full process independently
- Better token efficiency - don't load ticket creation logic into review context
- Parallel execution when multiple investigations needed

### Phase 3: Supervisor Report

Present findings to user in decision-ready format for oversight:

```markdown
## Due Diligence Report

### Ticket Validity
PASS - Valid, work needed
WARNING - Questionable - [specific concerns]
FAIL - Invalid - [reason: already done, duplicate, outdated]

### Blockers
None found / [List of blocking issues]

### Scope Analysis

**As Written:** [Ticket title/description summary]

**Actual Scope Discovered:**
[What implementation really requires based on codebase exploration]

**Components Affected:**
- [List all systems, services, files, infrastructure that will change]

**Hidden Dependencies:**
- [Infrastructure prerequisites]
- [Service dependencies]
- [Database schema changes]
- [Configuration updates]

**Separation of Concerns Assessment:**
PASS - Single concern - ticket is well-scoped
WARNING - Multiple concerns mixed - [describe concerns that should be separated]
FAIL - Scope violation - [explain why ticket should be split]

**Decomposition Recommendation:**
[If ticket should be split:]
**Recommend splitting into [N] tickets:**
1. **[Ticket 1 name]** - [What it addresses] (BLOCKS -> 2)
2. **[Ticket 2 name]** - [What it addresses] (BLOCKED BY -> 1, BLOCKS -> 3)
3. **[Ticket 3 name]** - [What it addresses] (BLOCKED BY -> 2)

**Rationale:** [Why splitting improves execution - clear dependencies, testability, separate concerns, etc.]

[If ticket is well-scoped:]
**Scope is appropriate** - Single concern, clear boundaries, ready for execution

### Work Required
**Implementation Complexity:** [Simple/Moderate/Complex based on exploration]
**Files Affected:** [List based on codebase search]
**Related Patterns:** [Links to similar implementations or past commits]
**Prerequisites:** [What must exist before work can start]

### Execution Context
**Task Type:** Parent / Subtask
**Parent Task:** [Link and objective summary] (if reviewing subtask)
**Subtasks:** [Count and status overview] (if reviewing parent)

**Execution Guidance:** Found/Not Found
[Quote the "Execution Guidance for Claude Code" section if present in parent task]

### Required Skills (MANDATORY)

[If "Skills to Use" section found in task, list each skill with reasoning:]
- REQUIRED: **skill-name-1** - [Extract reason from task description why this skill is required]
- REQUIRED: **skill-name-2** - [Extract reason from task description why this skill is required]

**Next Action:** Invoke **[first-skill-name]** skill BEFORE proceeding with implementation.

[If no "Skills to Use" section found in task, show this warning:]
WARNING: No "Skills to Use" section found in task. This may indicate incomplete ticket structure or the task does not require skill invocation.

### Risks/Concerns
- [Any technical concerns]
- [Missing information or unclear requirements]
- [Dependencies on external decisions]

### Recommended Next Steps

[Choose appropriate recommendation based on findings:]

**Option A: Proceed with execution**
PASS - Ticket is valid, well-scoped, unblocked, and ready for work-ticket execution

**Option B: Split ticket first**
IN PROGRESS - Invoke write-ticket skill to create [N] properly decomposed tickets, then execute (or, if the Task tool is unavailable in this context, recommend the orchestrator dispatch that work)

**Option C: Clarify requirements**
BLOCKED - Ticket lacks sufficient detail - need user input on [specific questions]

**Option D: Close/update ticket**
FAIL - Ticket is invalid/stale - recommend closing or updating description

**Option E: Resolve blockers first**
BLOCKED - Work on blocking tickets [list IDs] before returning to this one

### EXECUTION REMINDERS

**CRITICAL - Do not skip these steps:**

1. **Assign ticket to yourself BEFORE starting work** - Use Asana MCP tools to assign unassigned tickets to current session/agent before implementation
2. **Invoke required skills FIRST** - Skills listed in "Skills to Use" are MANDATORY, not optional
3. **Do not rationalize skipping skills** - "I know what it will say" is not acceptable
4. **Follow skill guidance exactly** - Skills exist to prevent errors and ensure quality
5. **Invoke task-verification before completion** - Every subtask requires verification

**If you proceed without invoking required skills, you are violating organizational standards.**

---

**Awaiting your decision:**
- Proceed with implementation as described?
- Request clarification on specific items before proceeding?
- Reassign to different agent or close ticket?
- Defer work until blockers are resolved?
```

## Common Scenarios

### Ticket Already Completed
Found evidence work is done (code exists, tests pass, related commits). Recommend marking ticket complete.

### Stale/Outdated Ticket
Requirements contradict current codebase state. Recommend closing or updating ticket description.

### Blocked Ticket
Dependencies not met. Present blocking tickets and recommend working on those first.

### Unclear Requirements
Ticket lacks acceptance criteria or technical details. Recommend asking user for clarification before implementation.

### Valid Ticket (Well-Scoped)
All clear - work needed, no blockers, requirements understood, single concern. Recommend proceeding with implementation.

### Scope Mismatch - Ticket Too Large
**Example:** "Fix authentication bug" actually requires:
- Database migration to add session table
- Update 3 microservices to use new session store
- Infrastructure change to add Redis cache
- Monitoring dashboard updates

**Action:** Document full scope, recommend splitting into 4 tickets with dependencies. If the Task tool is available, offer to dispatch write-ticket to create them; if not, recommend the orchestrator do so.

### Scope Mismatch - Multiple Concerns Mixed
**Example:** "Implement user profile feature" ticket includes:
- UI components (frontend concern)
- API endpoints (backend concern)
- Database schema (data concern)
- Profile photo upload to S3 (infrastructure concern)

**Action:** Recommend splitting into separate concerns with clear interfaces. If the Task tool is available, offer to dispatch write-ticket; if not, recommend the orchestrator do so.

### Hidden Infrastructure Dependency
**Example:** "Add new API endpoint" but codebase exploration reveals:
- Current infrastructure doesn't support required throughput
- Need to scale database connection pool first
- New endpoint will trigger infrastructure alerts

**Action:** Document infrastructure prerequisite, recommend creating infrastructure ticket that BLOCKS the feature ticket.

### Premature Ticket - Needs Design First
**Example:** Ticket says "implement feature X" but no design decisions exist for approach.

**Action:** Recommend brainstorming skill to evaluate approaches before creating implementation tickets.

## What NOT to Do

- Don't start implementation without documenting findings for supervisor visibility
- Don't assume ticket is valid just because it's open
- Don't skip checking for existing implementations
- Don't ignore dependencies or blockers
- Don't proceed if requirements are unclear without flagging for clarification
- **Don't accept ticket scope at face value** - always verify actual implementation requirements
- **Don't defer scope analysis to work-ticket** - front-load discovery before user approval
- **Don't duplicate specialized work** - delegate to appropriate skills when the Task tool is available (Explore for codebase analysis, write-ticket for ticket creation); do the equivalent work inline and recommend decomposition in the report when it is not
- **Don't skip decomposition recommendations** - if ticket violates separation of concerns, surface it regardless of whether you can dispatch or must recommend inline
- Don't rationalize "good enough" scope - if ticket should be split, recommend splitting

## Success Criteria

User has complete visibility for informed oversight decision:
- Understands what work Claude Code will perform
- Knows if work is still valid and needed
- Aware of blockers, risks, or concerns Claude Code identified
- **Understands true scope** - sees beyond ticket description to actual implementation requirements
- **Knows if ticket should be split** - clear decomposition recommendations when scope violates SoC
- **Sees hidden dependencies** - infrastructure, service, database changes surfaced
- Can confidently direct Claude Code on next steps (proceed/clarify/defer/close/split)
- Has clear view of required skills and execution dependencies
- **Prevented mid-flight surprises** - all complexity discovered before execution starts

## Related Skills

**Skills invoked DURING review-ticket (delegation when the Task tool is available; inline lookup with a report recommendation when it is not):**
- Explore-type subagent - Deep codebase investigation for scope analysis
- `write-ticket` - Create additional tickets when decomposition is needed
- `writing-business-requirements` - Clarify behavioral specifications when missing
- Recommend `brainstorming` - When design decisions needed before implementation

**Skills invoked AFTER review-ticket (transition):**
- `work-ticket` - Execute validated ticket work (primary handoff)
- `using-git-worktrees` - If work needs isolation
