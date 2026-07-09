---
name: task-verification
description: Verifies Asana subtask completion by validating acceptance criteria against actual state with concrete evidence. Use before marking any Asana subtask as complete to ensure all criteria are met and prevent premature closure. Executes verification steps, gathers proof, and provides pass/fail determination.
---

# Task Verification

## Purpose

Ensures Asana subtasks are genuinely complete before marking them as done by:
- **Validating acceptance criteria** - Checking each criterion against actual state
- **Gathering concrete evidence** - Collecting test output, file contents, logs, metrics
- **Executing verification steps** - Running specified commands, checks, validations
- **Preventing premature closure** - Blocking completion if any criteria fail
- **Maintaining quality standards** - Ensuring work meets defined specifications

**Critical discipline:** This skill is MANDATORY before marking any Asana subtask complete. No subtask should be marked done without running this verification process.

## When to Use

Use this skill when:
- About to mark an Asana subtask as complete
- User asks "is this task done?" or "can I mark this complete?"
- Finishing implementation work on a subtask
- Need to verify acceptance criteria are met
- Checking if work satisfies requirements before moving to next task

**Trigger phrases:**
- "verify this task is complete"
- "check acceptance criteria"
- "is this done?"
- "ready to mark complete"
- "validate task completion"

## Pre-Flight Checks

Before executing verification:

1. **Confirm task context:**
   - Have task ID or URL
   - Can access task details via Asana MCP tools
   - Know which subtask is being verified (not parent)

2. **Identify verification requirements:**
   - Task has defined acceptance criteria
   - Task has Verification section with specific steps
   - Understand what "done" means for this task

3. **Tool availability:**
   - Asana MCP tools for reading task details
   - Bash for running tests, checks, commands
   - Grep/Read for examining files and code
   - Git tools for checking commits if needed

## Verification Process

### Phase 1: Read Task Details

Fetch complete task information from Asana:

**Actions:**
1. Use `mcp__asana__asana_get_task` with task ID
2. Request `opt_fields` including: `name, notes, html_notes, parent, completed`
3. Extract from task description:
   - Acceptance Criteria section (checklist items)
   - Verification section (specific steps to execute)
   - Context section (related files, code, requirements)

**Parse task structure:**
```markdown
## Acceptance Criteria
- [ ] Criterion 1: All tests pass with ≥90% coverage
- [ ] Criterion 2: Documentation updated with examples
- [ ] Criterion 3: Code review approved

## Verification
Run: `pytest tests/ --cov=src --cov-report=term`
Check: `docs/README.md` contains usage examples
Verify: GitHub PR has approval from reviewer
```

**If missing acceptance criteria or verification steps:**
- STOP immediately
- Report to user: "Task lacks acceptance criteria or verification steps. Cannot verify completion."
- Recommend updating task with criteria before marking complete

### Phase 2: Execute Verification Steps

For each verification step specified in task:

**Execute commands/checks:**
- Run test commands and capture output
- Read specified files to verify content
- Check for existence of required artifacts
- Query systems for expected state (git status, service status, etc.)
- Use Grep to search for required code patterns
- Validate configuration files contain expected values

**Gather evidence:**
- Capture command output (stdout/stderr)
- Record file contents (relevant sections)
- Document observed state vs. expected state
- Collect test results, coverage reports
- Save error messages if checks fail

**Examples:**

**Test execution:**
```bash
pytest tests/test_feature.py -v --cov=src/feature --cov-report=term
```
Evidence: Test output showing all tests passed, coverage percentage

**File content verification:**
```bash
cat docs/api.md | grep -A 5 "## Usage Examples"
```
Evidence: Documentation section with example code

**Git verification:**
```bash
git log --oneline -n 5 | grep "implement feature"
```
Evidence: Commit exists with expected message

**Configuration check:**
Read config file and verify expected values present

### Phase 3: Validate Acceptance Criteria

For each acceptance criterion, determine pass/fail:

**Evaluation logic:**
- PASS - Evidence clearly shows criterion is met
- FAIL - Evidence shows criterion is NOT met
- PARTIAL - Evidence is ambiguous or incomplete

**Criterion types and validation:**

**"Tests pass" criterion:**
- Run test suite
- Check exit code is 0
- Verify no failures/errors in output
- Confirm coverage meets threshold if specified

**"Documentation updated" criterion:**
- Read specified docs file
- Verify content exists (not stub)
- Check examples/usage present if required
- Confirm accuracy against implementation

**"Code review approved" criterion:**
- Check PR status (if URL provided)
- Verify review comments addressed
- Confirm approval from reviewer

**"Feature works as expected" criterion:**
- Run manual verification steps
- Test happy path scenarios
- Verify error handling if specified

**"Configuration deployed" criterion:**
- Check config file exists
- Verify values match specification
- Test configuration loads correctly

**"Logs include required info" criterion:**
- Grep logs for expected patterns
- Verify log level appropriate
- Check no secrets in logs

### Phase 4: Generate Verification Report

Create comprehensive report with all evidence:

```markdown
## Task Verification Report

**Task:** [Task name]
**URL:** [Asana task URL]
**Date:** [Current timestamp]

### Acceptance Criteria Results

#### PASS Criterion 1: All tests pass with ≥90% coverage
**Status:** PASS
**Evidence:**
```
$ pytest tests/ --cov=src --cov-report=term
========================== test session starts ==========================
collected 24 items

tests/test_auth.py ........ [ 33%]
tests/test_api.py .............. [ 92%]
tests/test_utils.py .. [100%]

---------- coverage: platform darwin, python 3.11 -----------
Name                Stmts   Miss  Cover
---------------------------------------
src/auth.py           45      2    96%
src/api.py            67      3    95%
src/utils.py          12      0   100%
---------------------------------------
TOTAL                124      5    96%

========================== 24 passed in 2.14s ==========================
```

#### FAIL Criterion 2: Documentation includes usage examples
**Status:** FAIL
**Evidence:**
```
$ cat docs/README.md
# API Documentation

## Overview
This is the API documentation.

[No usage examples found]
```
**Issue:** Documentation file exists but does not contain usage examples as required.

#### PASS Criterion 3: Code changes committed
**Status:** PASS
**Evidence:**
```
$ git log --oneline -n 3
a1b2c3d Add authentication feature with tests
e4f5g6h Update API documentation
h7i8j9k Initial project setup
```

### Verification Steps Executed

1. PASS Ran test suite: `pytest tests/ --cov=src --cov-report=term`
   - Result: All 24 tests passed
   - Coverage: 96% (exceeds 90% requirement)

2. FAIL Checked documentation: `cat docs/README.md`
   - Result: File exists but missing usage examples
   - Required: Usage examples section with code samples

3. PASS Verified git commits: `git log --oneline -n 3`
   - Result: Found commit "Add authentication feature with tests"
   - Confirmed: Work is committed to repository

### Overall Completion Status

FAIL - Cannot mark task complete

**Failed criteria:** 1 of 3
- Criterion 2: Documentation lacks required usage examples

**Required actions before completion:**
1. Add usage examples to docs/README.md
2. Re-run verification to confirm all criteria pass

---

**Do NOT mark this task as complete until all criteria pass.**
```

### Phase 5: Present Report and Block if Needed

**If all criteria PASS:**
- Present report to user
- Confirm: "PASS - All acceptance criteria verified. Task is complete and can be marked done."
- Safe to proceed with marking task complete in Asana

**If any criteria FAIL:**
- Present report with failures highlighted
- Confirm: "FAIL - Task verification failed. Cannot mark task complete."
- List specific failures and required remediation
- DO NOT mark task complete
- BLOCK user from marking task complete until criteria pass

**If verification steps cannot be executed:**
- Report inability to verify
- Explain what is missing (tools, access, files)
- Recommend manual verification or updating task
- DO NOT mark task complete without verification

## Report Template

Use this structure for all verification reports:

```markdown
## Task Verification Report

**Task:** [Task name and Asana URL]
**Verified:** [ISO timestamp]
**Verifier:** Claude Code task-verification skill

### Acceptance Criteria Results

[For each criterion:]
[PASS/FAIL/PARTIAL] **Criterion [N]: [Description]**
**Status:** PASS / FAIL / PARTIAL
**Evidence:**
[Concrete proof - command output, file content, screenshot, etc.]
[If FAIL: Explain what was found vs. what was expected]

### Verification Steps Executed

[Numbered list of all verification actions taken:]
1. [PASS/FAIL] [Action description]: [command/tool used]
   - Result: [What was found]
   - Status: [Pass/Fail with brief explanation]

### Overall Completion Status

[PASS / FAIL / PARTIAL]

**Summary:** [X of Y criteria passed]

[If FAIL:]
**Failed criteria:**
- [List failed criteria]

**Required actions:**
- [Specific steps needed to pass]

[If PASS:]
**All acceptance criteria verified successfully.**
Task is complete and can be marked done in Asana.

---

[If FAIL:]
**Do NOT mark this task as complete until all criteria pass.**

[If PASS:]
**Safe to mark task complete.**
```

## Anti-Patterns (NEVER DO THIS)

### Skipping Verification

```markdown
User: "I think I'm done with this task."
Agent: "Great! I'll mark it complete."
[Marks task complete without running verification]
```

**Why wrong:** No evidence criteria are actually met. Risk of incomplete work being marked done.

**Correct approach:** ALWAYS invoke task-verification skill before marking complete.

### Subjective Assessment

```markdown
Agent: "The code looks good to me, marking complete."
[No tests run, no files checked, no evidence gathered]
```

**Why wrong:** "Looks good" is not verification. Need objective evidence.

**Correct approach:** Execute verification steps, gather concrete evidence, validate against criteria.

### Partial Verification

```markdown
Agent: "Tests pass, so I'll mark it complete."
[Ignores documentation and code review criteria]
```

**Why wrong:** All criteria must pass, not just some.

**Correct approach:** Verify EVERY acceptance criterion, report on ALL of them.

### Assuming Criteria Met

```markdown
Agent: "You wrote tests, so test coverage must be ≥90%."
[Does not actually run coverage report]
```

**Why wrong:** Assumptions are not evidence. Must verify actual coverage.

**Correct approach:** Run coverage tool, capture output, verify percentage meets threshold.

### Marking Complete Despite Failures

```markdown
Report shows: "2 of 5 criteria failed"
Agent: "Close enough, marking complete."
```

**Why wrong:** Violates completion contract. Task is not done if criteria fail.

**Correct approach:** BLOCK completion, report failures, require remediation.

### Vague Evidence

```markdown
Evidence: "Documentation exists"
[Does not show actual content or verify requirements met]
```

**Why wrong:** Cannot verify criterion from vague statement.

**Correct approach:** Show actual documentation content, verify specific requirements (examples, accuracy, completeness).

### Not Reading Verification Section

```markdown
[Task has detailed Verification section with specific commands]
Agent: "I'll just check if files exist."
[Ignores specified verification steps]
```

**Why wrong:** Task author specified how to verify for a reason. Must follow their process.

**Correct approach:** Read Verification section, execute specified steps exactly as written.

### Verification Without Evidence

```markdown
Agent: "I verified the tests pass."
[No test output shown, no evidence provided]
```

**Why wrong:** Cannot audit or review verification without evidence trail.

**Correct approach:** Always include concrete evidence (command output, file content, etc.) in report.

## Integration with Other Skills

### Works Before

**review-ticket:**
- review-ticket reads task and identifies work requirements
- task-verification reads task and validates work completion
- Use review-ticket when starting work, task-verification when finishing

### Works After

**code-review:**
- Code-review validates code quality and standards compliance
- Task-verification validates acceptance criteria met
- Both should pass before marking task complete

**superpowers:verification-before-completion:**
- Division of labor is fixed, not a hedge: task-verification is the Asana-subtask-specific
  procedure (reads the task, validates its acceptance criteria and Verification section against
  Asana); `superpowers:verification-before-completion` is the general procedure for any work unit,
  Asana or not.
- The verifier preloads both skills, so `superpowers:verification-before-completion` exists in
  context whenever this skill is invoked — there is no scenario where task-verification runs
  without it available.
- For an Asana subtask, run task-verification. For any other work unit (a plan step, a standalone
  deliverable with no Asana task), run `superpowers:verification-before-completion` instead.

### Works Alongside

**test-driven-development:**
- TDD creates tests that validate implementation
- Task-verification runs those tests to verify completion
- Both ensure quality through different mechanisms

**systematic-debugging:**
- Debugging fixes issues and verifies fix works
- Task-verification confirms fix meets acceptance criteria
- Complementary quality gates

### Referenced By

**write-ticket:**
- write-ticket creates Verification sections in subtasks
- task-verification executes those verification steps
- Tight integration - writing skill defines verification contract

## Failure Mode Prevention

### "I don't know how to verify this"

**Prevention:**
- Task MUST have Verification section with specific steps
- If missing, STOP and ask user how to verify
- Update task with verification steps before proceeding
- Never guess at verification approach

### "Tests pass but work isn't actually done"

**Prevention:**
- Verify ALL acceptance criteria, not just tests
- Check for documentation, code review, deployment, configuration
- Look for criteria about user-facing behavior
- Manual verification for UI/UX changes if specified

### "Evidence is ambiguous"

**Prevention:**
- Gather comprehensive evidence (full command output)
- Show context (file path, timestamp, environment)
- If unclear, mark as PARTIAL and explain ambiguity
- Ask user for clarification rather than assuming

### "Verification steps fail partway through"

**Prevention:**
- Execute all verification steps even if early ones fail
- Report on all criteria (don't stop at first failure)
- Provide complete picture of what passed and what failed
- Allows user to see full scope of remaining work

### "False positive - marked complete but wasn't"

**Prevention:**
- Use objective criteria only (tests pass, files exist, values match)
- Run actual verification commands, don't assume
- Show concrete evidence for every criterion
- Be strict - when in doubt, mark as FAIL not PASS

### "Task marked incomplete when actually done"

**Prevention:**
- Read task description carefully to understand criteria
- Execute verification steps exactly as specified
- Consider acceptance criteria met if evidence clearly shows it
- Don't add unstated requirements

## Success Criteria

After using this skill:

- [ ] Task details read from Asana with acceptance criteria and verification steps
- [ ] All verification steps executed with output captured
- [ ] Every acceptance criterion evaluated with concrete evidence
- [ ] Comprehensive verification report generated
- [ ] Overall pass/fail determination clear and justified
- [ ] If FAIL: specific remediation actions identified
- [ ] If PASS: user can confidently mark task complete
- [ ] Evidence trail exists for audit/review purposes

## Skill Workflow

**Typical usage flow:**

1. User finishes working on Asana subtask
2. User says "verify this task is complete" or "is this done?"
3. Claude Code invokes task-verification skill
4. Skill reads task details from Asana
5. Skill executes verification steps from task
6. Skill validates each acceptance criterion
7. Skill generates verification report with evidence
8. Skill determines PASS/FAIL and reports to user
9. If PASS: User marks task complete in Asana
10. If FAIL: User addresses failures and re-runs verification

**Integration in write-ticket workflow:**

1. write-ticket creates subtask with:
   - Acceptance Criteria section
   - Verification section with specific steps
2. User works on subtask
3. Before marking complete, task-verification is invoked
4. task-verification executes steps from Verification section
5. task-verification validates Acceptance Criteria
6. Only marks complete if all criteria pass

## Examples

### Example 1: Feature Implementation Task

**Task excerpt:**
```markdown
## Task
Implement user authentication with JWT tokens

## Acceptance Criteria
- [ ] All tests pass with ≥90% coverage
- [ ] Authentication middleware properly validates tokens
- [ ] Error handling for invalid/expired tokens implemented
- [ ] Documentation updated with authentication flow

## Verification
- Run: `pytest tests/test_auth.py -v --cov=src/auth --cov-report=term`
- Test: `curl -H "Authorization: Bearer invalid" http://localhost:8000/api/protected`
- Check: `docs/authentication.md` contains JWT flow diagram and examples
```

**Verification execution:**
1. Run test suite → Capture output showing all tests pass, 94% coverage
2. Test with invalid token → Capture 401 response with proper error message
3. Read documentation → Verify JWT flow diagram and usage examples present

**Report:**
- PASS Tests: All 18 tests passed, coverage 94%
- PASS Token validation: Returns 401 with clear error for invalid token
- PASS Documentation: Contains flow diagram and 3 usage examples

**Result:** PASS - All criteria met, task can be marked complete

### Example 2: Bug Fix Task

**Task excerpt:**
```markdown
## Task
Fix race condition in database connection pool

## Acceptance Criteria
- [ ] Test reproducing race condition exists and initially fails
- [ ] Fix implemented and test now passes
- [ ] No regressions (all other tests still pass)
- [ ] Root cause documented in task comments

## Verification
- Check: `tests/test_db_pool.py` contains `test_concurrent_connections()`
- Run: `pytest tests/test_db_pool.py::test_concurrent_connections -v`
- Run: `pytest tests/ -v` (full suite)
- Verify: Task comments contain root cause explanation
```

**Verification execution:**
1. Read test file → Verify test exists with concurrent access pattern
2. Run specific test → Shows PASSED
3. Run full suite → 156 tests passed, 0 failed
4. Check Asana task comments → Root cause explanation present

**Report:**
- PASS Reproduction test: Exists in test_db_pool.py
- PASS Test passes: test_concurrent_connections PASSED
- PASS No regressions: Full suite 156/156 passed
- PASS Root cause documented: Comment dated [timestamp] explains lock contention

**Result:** PASS - Bug fix verified complete

### Example 3: Documentation Task (with failure)

**Task excerpt:**
```markdown
## Task
Update API documentation for v2 endpoints

## Acceptance Criteria
- [ ] All v2 endpoints documented
- [ ] Request/response examples included
- [ ] Authentication requirements specified
- [ ] Documentation reviewed and approved

## Verification
- Check: `docs/api-v2.md` exists and contains all 8 v2 endpoints
- Verify: Each endpoint has request/response example
- Verify: Authentication section specifies token requirements
- Check: Task has approval comment from reviewer
```

**Verification execution:**
1. Read docs/api-v2.md → File exists, lists 8 endpoints with examples
2. Check examples → All endpoints have request/response samples
3. Check auth section → Present with Bearer token requirements
4. Check task comments → No approval comment found

**Report:**
- PASS Endpoints documented: All 8 v2 endpoints present
- PASS Examples included: Request/response examples for all endpoints
- PASS Auth requirements: Bearer token specification present
- FAIL Review approval: No approval comment found on task

**Result:** FAIL - Missing review approval. Cannot mark complete until reviewer approves.

## Quick Reference

**When to invoke:** Before marking any Asana subtask complete

**What it does:** Validates acceptance criteria with concrete evidence

**What it needs:**
- Task ID or URL
- Asana MCP access
- Tools to execute verification steps (Bash, Read, Grep)

**What it produces:** Verification report with pass/fail determination

**What happens next:**
- If PASS → Safe to mark task complete
- If FAIL → Address failures and re-verify

**Key principle:** No task is complete without verification evidence

## References

Based on:
- Asana task structure from write-ticket skill
- Acceptance criteria patterns in software engineering
- Test-driven development verification practices
- Code review quality gates
- Organizational standards for task completion
