---
name: code-review
description: Systematic code review against organizational engineering standards. Use when reviewing code, conducting pull request reviews, checking code quality, or validating implementations. Reviews code for TDD compliance, version control setup, documentation quality, testing architecture, logging practices, infrastructure as code, security vulnerabilities, and code quality standards.
---

# Code Review

## Overview

Conduct systematic code reviews against organizational engineering standards. Provide actionable feedback on violations with specific recommendations for fixes.

## Review Methodology

Execute reviews in this structured order for comprehensive coverage:

### 1. Development Methodology Review

**Test-Driven Development (TDD):**
- [ ] Tests exist and were written before implementation (check git history if available)
- [ ] Test coverage meets ≥90% requirement
- [ ] Tests follow Red-Green-Refactor pattern
- [ ] All code paths have corresponding tests

**Specification-First Development:**
- [ ] Specifications updated in same commit as code changes
- [ ] Implementation matches specification
- [ ] No ad-hoc changes without planning

**Anti-Pattern Detection:**
- [ ] No "try this and see" coding patterns
- [ ] No band-aids or workarounds without documentation
- [ ] Changes show deliberate planning

**Violations Report:**
- Missing tests for new functions/methods
- Test coverage below 90%
- Code changes without spec updates
- Evidence of cowboy coding

### 2. Version Control Review

**Git Initialization:**
- [ ] `.git` directory exists
- [ ] Initial commit includes `.gitignore`
- [ ] `.gitignore` before application code in commit history

**.gitignore Standards:**
- [ ] Secrets and environment files (.env, *.pem, *.key) excluded
- [ ] Language-specific build artifacts excluded
- [ ] Test output and coverage reports excluded
- [ ] Cloud provider configuration files excluded
- [ ] IDE and editor files excluded
- [ ] OS-specific files excluded

**Remote Repository:**
- [ ] Git remote configured
- [ ] Recent commits pushed to remote

**Pre-Commit Hooks:**
- [ ] Secret detection hooks installed
- [ ] Hooks are active (check `.git/hooks/` or pre-commit config)

**Commit Quality:**
- [ ] Descriptive commit messages
- [ ] Logical units of work
- [ ] No secrets in commit history

**Violations Report:**
- Missing .git initialization
- Incomplete .gitignore patterns
- No remote repository configured
- Pre-commit hooks not installed
- Poor commit messages
- Secrets in commits (CRITICAL)

### 3. Documentation Review

**Docstring Requirements:**
- [ ] Every module has file-level docstring
- [ ] Every function has docstring
- [ ] Every class has docstring
- [ ] Docstrings include one-line summary
- [ ] Docstrings explain WHY (not just what)
- [ ] Parameter descriptions present
- [ ] Return value descriptions present
- [ ] Exception descriptions present

**Comment Quality:**
- [ ] Comments explain WHY, not WHAT
- [ ] No obvious comments (e.g., "increment counter")
- [ ] Complete sentences with capitalization
- [ ] Comments updated with code changes
- [ ] No stale or outdated comments

**Self-Documenting Code:**
- [ ] Descriptive variable names (not abbreviated)
- [ ] Function names are verb phrases
- [ ] Constants use uppercase with separators
- [ ] Complex logic extracted to named functions

**Violations Report:**
- Missing docstrings on functions/classes/modules
- Docstrings missing WHY explanations
- Obvious or useless comments
- Abbreviated variable names
- Stale comments

### 4. Testing Architecture Review

**Test Pyramid Structure:**
- [ ] Majority are unit tests (fast, no network)
- [ ] Some integration tests (real APIs/databases)
- [ ] Few E2E tests (full system)

**Unit Test Quality:**
- [ ] Tests run in <5 seconds total
- [ ] No network calls
- [ ] External dependencies mocked
- [ ] Tests one unit of code each

**Integration Test Quality:**
- [ ] Uses real APIs/databases
- [ ] Acceptable speed (not slow)
- [ ] Tests component interactions

**E2E Test Quality:**
- [ ] Full system testing
- [ ] Production-like environment
- [ ] Critical user paths covered

**Test Coverage:**
- [ ] ≥90% code coverage
- [ ] All error paths tested
- [ ] Edge cases covered

**Violations Report:**
- Inverted test pyramid (too many E2E tests)
- Slow unit tests (network calls)
- Unit tests not mocking dependencies
- Test coverage below 90%
- Missing error path tests

### 5. Logging Review

**Structured Logging:**
- [ ] Consistent format across codebase
- [ ] Request/response metadata logged (status, duration, size)
- [ ] Every code path produces log entry (no blind spots)

**Security in Logging:**
- [ ] No request/response bodies logged
- [ ] No authorization header values logged
- [ ] No cookie values logged
- [ ] No query parameters logged (may contain tokens)
- [ ] No tokens of any kind logged
- [ ] No passwords or secrets logged
- [ ] Stack traces sanitized

**Error Logging:**
- [ ] Error type/category logged
- [ ] Error messages sanitized and logged
- [ ] Request context logged
- [ ] Duration until failure logged
- [ ] Upstream host logged (if applicable)

**Violations Report:**
- Inconsistent log format
- Code paths without log entries (blind spots)
- Sensitive data in logs (CRITICAL)
- Missing error context
- Request/response bodies logged

### 6. Cloud Infrastructure Review

**Infrastructure as Code:**
- [ ] All infrastructure defined in code
- [ ] Infrastructure templates version controlled
- [ ] No manual console changes
- [ ] Deployment process documented

**CI/CD Pipeline:**
- [ ] Pipeline configuration exists
- [ ] Testing job runs on all pushes
- [ ] Testing job requires ≥90% coverage
- [ ] Testing job blocks merge on failure
- [ ] Deployment job runs after tests pass
- [ ] Deployment job targets correct environment

**Violations Report:**
- Resources created manually (not in code)
- Infrastructure not version controlled
- Missing CI/CD pipeline
- Pipeline missing quality gates
- Tests not blocking merges

### 7. Security Review

**Secrets Management:**
- [ ] No secrets committed to git
- [ ] No hardcoded credentials
- [ ] No secrets in code files
- [ ] .env files in .gitignore
- [ ] Environment variables used appropriately

**Error Message Sanitization:**
- [ ] Generic error messages to clients
- [ ] No internal implementation details exposed
- [ ] No stack traces sent to clients
- [ ] Detailed errors logged internally only

**Input Validation:**
- [ ] Request size limits enforced
- [ ] Path whitelisting implemented
- [ ] Content types validated
- [ ] Parameter formats validated

**Violations Report:**
- Secrets in git commits (CRITICAL)
- Hardcoded credentials (CRITICAL)
- Detailed errors exposed to clients
- Missing input validation
- Secrets logged

### 8. Code Quality Review

**Naming Conventions:**
- [ ] Variables are descriptive (not abbreviated)
- [ ] Functions use verb phrases
- [ ] Constants use uppercase with separators
- [ ] Classes use PascalCase (if applicable)

**Function Quality:**
- [ ] Single responsibility per function
- [ ] Functions typically <50 lines
- [ ] Complex logic extracted to sub-functions
- [ ] One level of abstraction per function

**Type Annotations:**
- [ ] Function signatures have type annotations (if language supports)
- [ ] Type annotations present for parameters
- [ ] Type annotations present for return values

**Error Handling:**
- [ ] Specific exception/error handlers (not generic catch-all)
- [ ] All errors logged with context
- [ ] No silently swallowed errors

**Violations Report:**
- Abbreviated variable names
- Functions exceeding 50 lines
- Multiple responsibilities per function
- Missing type annotations
- Generic catch-all exception handlers
- Silently swallowed errors

### 9. Dependency Management Review

**Version Pinning:**
- [ ] Specific versions pinned in dependency files
- [ ] No version ranges that auto-update

**Security:**
- [ ] No known vulnerabilities in dependencies (check advisories)
- [ ] Dependencies up-to-date with security patches

**Violations Report:**
- Unpinned dependency versions
- Known vulnerabilities in dependencies

## Review Output Format

Structure reviews as follows:

```
# Code Review Results

## Summary
- [X] items passed
- [X] items failed
- [X] critical issues found

## Critical Issues (Must Fix Before Merge)
1. [Issue]: [Specific violation]
   - Location: [file:line]
   - Fix: [Specific recommendation]

## Major Issues (Should Fix Before Merge)
1. [Issue]: [Specific violation]
   - Location: [file:line]
   - Fix: [Specific recommendation]

## Minor Issues (Address in Future)
1. [Issue]: [Specific violation]
   - Location: [file:line]
   - Fix: [Specific recommendation]

## What Went Well
- [Positive observations]

## Recommendations
- [Actionable next steps]
```

## Severity Classification

**CRITICAL (Block Merge):**
- Secrets in commits or code
- Sensitive data in logs
- Missing secret detection hooks
- Missing test coverage (<90%)
- Security vulnerabilities

**Major (Should Fix):**
- Missing docstrings
- Poor error handling
- Missing input validation
- Infrastructure not as code
- Missing CI/CD pipeline

**Minor (Future Work):**
- Abbreviated variable names
- Long functions (>50 lines)
- Minor comment improvements
- Missing type annotations (if language supports)

## Bundled Resources

### References
- `references/coding-standards.md` - Complete organizational engineering standards with detailed requirements, rationale, and enforcement mechanisms

Load this reference when:
- Detailed standard requirements needed
- Understanding enforcement mechanisms
- Clarifying language-specific requirements
- Checking specific section requirements

## Quick Reference

When user provides code for review:

1. Read the code thoroughly
2. Execute systematic review in order (sections 1-9)
3. Document violations with specific locations
4. Classify severity (CRITICAL/Major/Minor)
5. Provide actionable fixes
6. Format output per template
7. Load references/coding-standards.md for detailed requirements when needed
