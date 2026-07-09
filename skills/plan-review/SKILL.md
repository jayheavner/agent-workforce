---
name: plan-review
description: Pre-implementation plan validation against organizational standards. Use BEFORE starting any implementation work to catch violations early. Validates that implementation plans comply with TDD (tests before implementation), security requirements (secrets management, logging security, input validation), dependency management (current versions via web search, not memory), infrastructure as code, documentation, and git workflow. Critical for catching TDD violations, outdated library versions, hardcoded secrets, and security issues before code is written.
---

# Plan Review

Validate implementation plans BEFORE code is written. Gate between planning and implementation.

## Review Checklist

### 1. TDD (CRITICAL)

Tests FIRST.

Valid: 1. Write tests 2. Red 3. Implement 4. Green
Invalid: 1. Implement 2. Write tests

Check: Tests before implementation, Red-Green-Refactor shown

Fix: Restructure for TDD

### 2. Dependencies (CRITICAL)

NEVER use versions from memory.

Valid: 1. Research LTS via web search 2. Check security 3. Install pinned version
Invalid: express@4.18.0, ^4.0.0

Check: Web search for versions, no ranges

Fix: Add research step

### 3. Security

a. Secrets: Env vars, startup validation, .gitignore
b. Logging: Exclude bodies/headers/cookies/tokens/params, log metadata only
c. Input: Validation, size limits, sanitization
d. Errors: Generic to clients, detailed internal only

### 4. IaC

Use org-approved IaC (SAM, CDK, Amplify); no manual console changes.

### 5. Documentation

Docstrings, README updates, document WHY

### 6. Git

Commits are logical units, at least one per task; each references the task.

### 7. Current Info

Web search for best practices, check official docs

### 8. Forbidden Operations (CRITICAL)

Flag any plan step that:

a. **Installs packages** (pip, npm, brew, or otherwise) — forbidden. Default to stdlib-first
   tooling. A new dependency is allowed only if the human has explicitly pre-approved it in
   the plan; otherwise flag it as a violation and require either a stdlib alternative or an
   explicit pre-approval step added to the plan.
b. **Deletes or moves files via shell** (`rm`, `mv`, and equivalents) — forbidden. Require the
   plan to be restructured to plan around the file (exclude it by not creating it) or to
   overwrite its contents in place via Edit/Write instead of deleting or moving it.

Check: No step runs a package-install command without a recorded human pre-approval; no step
runs `rm`/`mv`/equivalent against tracked or user files.

Fix: Replace the install step with a stdlib-first approach (or add an explicit pre-approval
step); replace the delete/move step with an in-place overwrite or a plan restructured to avoid
creating the file at all.

## Output

```
# Plan Review: [PASS / NEEDS REVISION]

## Critical Issues
1. **[Category]**: [Violation]
   - Problem: [What's wrong]
   - Fix: [Required change]

## Decision
- [ ] APPROVED
- [ ] NEEDS REVISION
```

## Examples

Good: 1. Research 2. Write tests 3. Red 4. Implement 5. Green 6. Doc 7. Commit

Bad: 1. Install winston 2. Implement 3. Log request data 4. Tests -- TDD violation, security violation, no research, unapproved package install
