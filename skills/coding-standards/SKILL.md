---
name: coding-standards
description: Enforces organizational software engineering standards for all code development. Use when writing, reviewing, or setting up code projects. Applies mandatory standards for TDD, version control, documentation, testing, logging, infrastructure, security, and code quality. Triggers on code implementation, project setup, code review, or when organizational standards need to be followed.
---

# Coding Standards Enforcement

## Overview

This skill enforces mandatory organizational software engineering standards across all code development activities. It ensures code follows required practices for test-driven development, version control, documentation, testing architecture, logging, cloud infrastructure, security, and code quality.

## Core Standards Application

Apply these standards to all code development:

### Test-Driven Development (TDD)
Write tests before implementation code following the Red-Green-Refactor cycle:
1. Red: Write failing test defining desired behavior
2. Green: Write minimal code to pass test  
3. Refactor: Improve code quality while keeping tests green

Enforce ≥90% test coverage requirement.

### Specification-First Development
Update specifications before changing code:
1. Identify requirement/problem
2. Update specification to address it
3. Review specification for completeness
4. Implement per updated specification
5. Verify implementation matches spec

Never hack code together then document later.

### Version Control Initialization
For new projects, initialize in this exact sequence:
```bash
git init
# Create .gitignore (see references/coding-standards.md section 2.2)
git add .gitignore
git commit -m "Initial commit: gitignore"
# Then create application code
```

Configure remote repository and push regularly.

### Pre-Commit Hooks
Install secret detection pre-commit hooks to block commits containing:
- Credentials, API keys, tokens
- Passwords or secrets
- Authorization header values

### Documentation Requirements
All functions, classes, and modules must have docstrings with:
- One-line summary of purpose
- Longer description explaining WHY (not just what)
- Parameter descriptions
- Return value description
- Exception/error descriptions

Comments explain WHY, code shows WHAT. Remove obvious comments.

### Testing Architecture
Follow test pyramid structure:
- **Unit tests** (most): Fast (<5s total), no network, mock external dependencies
- **Integration tests** (some): Real APIs/databases, medium speed
- **E2E tests** (few): Full system, slow, production-like environment

### Logging Standards
Apply structured logging with:
- Consistent format across all services
- Request/response metadata (status, duration, size)
- No sensitive data (tokens, passwords, request bodies, auth headers)
- Every code path produces log entry (no blind spots)
- Error logging includes type, message, context, duration

### Infrastructure as Code
All infrastructure must be:
- Defined in code (never manual console changes)
- Version controlled
- Tested before deployment
- Deployed via CI/CD pipeline

### Security Practices
Enforce:
- No secrets in git (use .env files, environment variables, secrets management)
- Pre-commit hooks block secret commits
- Error messages sanitized (no stack traces or internal details to clients)
- Input validation on all external inputs
- Type annotations on function signatures (when language supports)

### CI/CD Pipeline
Required structure:
- Testing job: runs on all pushes, requires ≥90% coverage, blocks merge if failed
- Deployment job: runs on main branch after tests pass

## Pre-Deployment Checklist

Before pushing code to main branch, verify:
- [ ] All tests pass locally with ≥90% coverage
- [ ] Pre-commit hooks pass (secrets detection, linting)
- [ ] New functions/classes have docstrings
- [ ] New code paths produce log entries
- [ ] Function signatures have type annotations
- [ ] Exceptions caught with specific handlers
- [ ] No hardcoded credentials or API keys
- [ ] Deviations documented in commit message

## Bundled Resources

### References
- `references/coding-standards.md` - Complete organizational engineering standards document with detailed requirements, rationale, and enforcement mechanisms for all standards

Load this reference when:
- Detailed requirements needed for specific standard
- Understanding rationale behind requirements
- Checking enforcement mechanisms (automated vs manual)
- Reviewing language-specific requirements
- Setting up project infrastructure

## Code Review Application

When reviewing code, check for:
1. Tests written before implementation (TDD)
2. Specifications updated in same commit
3. Git initialization and .gitignore present
4. Pre-commit hooks configured
5. Docstrings on all functions/classes/modules
6. Structured logging without sensitive data
7. Infrastructure defined as code
8. Secrets not committed
9. Error messages sanitized
10. Type annotations present
