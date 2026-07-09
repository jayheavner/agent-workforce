# Software Engineering Standards

**Purpose**: Mandatory coding standards and engineering requirements for all code in this organization.

**Audience**: All developers, code reviewers, AI assistants

**Scope**: These standards apply to all production code. Deviations require documented justification and review.

---

## 1. DEVELOPMENT METHODOLOGY

### 1.1 Test-Driven Development (TDD)

**Requirement**: Write tests before implementation code.

**TDD Cycle:**
1. **Red**: Write a failing test that defines desired behavior
2. **Green**: Write minimal code to make the test pass
3. **Refactor**: Improve code quality while keeping tests green

**Benefits:**
- Ensures testable design
- Prevents untested code paths
- Documents expected behavior
- Reduces debugging time
- Enables safe refactoring

**Application:**
- Unit tests written before functions
- Integration tests written before API calls
- E2E tests written before deployment

**ENFORCEMENT:**
- Automated: CI/CD requires ≥90% test coverage (blocks merge if failed)
- Manual: TDD cycle (tests before implementation) requires developer discipline; not enforced by tooling

### 1.2 Specification-First Development

**Requirement**: Update specifications before changing code.

**Process:**
1. Identify requirement or problem
2. Update specification to address it
3. Review specification for completeness
4. Implement per updated specification
5. Verify implementation matches spec

**Never:**
- Hack code together then document later
- Change code without updating specs
- Assume specs will be "fixed later"

**ENFORCEMENT:**
- Manual: Specification documents must be updated in same commit as code changes; verified during development review

### 1.3 No Cowboy Coding

**Prohibition**: Never make ad-hoc changes without planning.

**Required:**
- Think through the change
- Understand architectural impact
- Update specs if needed
- Implement deliberately
- Test thoroughly

**Prohibited:**
- "Let me try this and see if it works"
- Making changes without understanding why
- Band-aids and workarounds
- Hoping problems will resolve themselves

**ENFORCEMENT:**
- Manual: Requires developer discipline and planning before making changes; not enforced by tooling

---

## 2. VERSION CONTROL

### 2.1 Git Initialization

**Requirement**: Initialize git repository at project start.

**Correct Sequence:**
```bash
# Step 1: Initialize git repository
git init

# Step 2: Create .gitignore file
# (See section 2.2 for contents)

# Step 3: Make initial commit
git add .gitignore
git commit -m "Initial commit: gitignore"

# Step 4: Create application code
# All subsequent files will be tracked
```

**Rationale:**
- Enables rollback of any changes
- Tracks implementation history
- Required for professional development
- Prevents catastrophic mistakes

**ENFORCEMENT:**
- Automated: Project setup test verifies `.git` directory exists (fails CI if missing)

### 2.2 .gitignore Standards

**Requirement**: Project must include .gitignore file with patterns for:
- Secrets and environment files (.env, *.pem, *.key)
- Language-specific build artifacts and dependencies
- Test output and coverage reports
- Cloud provider configuration files
- IDE and editor files
- OS-specific files

**Note**: Specific patterns defined in project technical specification based on technology stack.

**ENFORCEMENT:**
- Automated: Test verifies `.gitignore` exists and contains all required patterns; pre-commit hook blocks secret commits

### 2.3 Remote Repository

**Requirement**: Configure remote repository for backup and collaboration.

**Setup:**
```bash
# Add remote repository
git remote add origin <repository-url>

# Push initial commit
git push -u origin main
```

**Branch Strategy (Small Team):**
- `main` branch: Production-ready code
- Feature branches: Optional for complex changes
- Push directly to main for small fixes (small team)

**Required:**
- Remote repository for backup
- Push after each phase completion
- All team members have access

**ENFORCEMENT:**
- Automated: Test verifies git remote is configured (fails CI if missing)
- Manual: Regular pushes to remote verified through git activity logs

### 2.4 Pre-Commit Hooks

**Requirement**: Prevent secrets from being committed to git.

**Required Functionality:**
- Automated secret detection before commit
- Block commits containing credentials, API keys, or tokens
- Hook must be installed and active in repository

**Rationale**: Automated prevention of credential leaks is critical.

**Note**: Specific pre-commit framework and secret detection tools defined in project technical specification based on technology stack.

**ENFORCEMENT:**
- Automated: Secret detection pre-commit hook blocks commits containing secrets; test verifies hook is installed

### 2.5 Commit Practices

**Commits must:**
- Have descriptive messages
- Represent logical units of work
- Pass all tests before committing
- Not contain secrets or credentials
- Be pushed to remote regularly

**ENFORCEMENT:**
- Automated: CI/CD fails if tests don't pass; pre-commit hooks block secret commits
- Manual: Commit message quality and logical units verified during git history review

---

## 3. CODE DOCUMENTATION

### 3.1 Docstring Requirements

**Standard**: All functions, classes, and modules must have documentation strings (docstrings).

**Required Docstrings:**
- Every module (file-level)
- Every function and method
- Every class

**Format Requirements:**
- One-line summary of purpose
- Longer description explaining WHY it exists, not just what it does
- Parameter descriptions
- Return value description
- Exception/error descriptions

**Note**: Specific docstring format (Google Style, NumPy Style, JSDoc, etc.) defined in project technical specification based on language.

**ENFORCEMENT:**
- Automated: Documentation linter verifies all functions/classes/modules have docstrings (specific linter defined in project technical spec)

### 3.2 Comment Philosophy

**Principle**: Comments explain WHY, code shows WHAT.

**Good Comments (explain WHY):**
```
// Apply HTTPS pattern first to avoid partial matches with http:// prefix
replacements = create_https_replacement(domain, proxy)

// Subdomain detection: don't replace if preceded by alphanumeric + dot
if is_subdomain(part):
    result += ORIGINAL_DOMAIN  // Keep subdomain unchanged
```

**Bad Comments (explain obvious WHAT):**
```
// Increment counter
counter += 1

// Get domain
domain = get_domain()

// Loop through items
for item in items:
```

**Rules:**
- Use complete sentences
- Capitalize first word
- Assume reader knows the programming language
- Remove obvious comments
- Update comments when code changes
- Delete stale comments immediately

**ENFORCEMENT:**
- Manual: Comment quality and appropriateness reviewed during code development; no automated tooling

### 3.3 Self-Documenting Code

**Principle**: Clear code needs fewer comments.

**Prefer:**
- Descriptive variable names: `authorization_code` not `ac`
- Small focused functions: `validatePath()` not `doStuff()`
- Type annotations (when supported by language)
- Extract complex logic to named functions

**When Comments Are Needed:**
- Non-obvious algorithms
- Business logic rationale
- Performance optimizations
- Workarounds for bugs
- Security considerations

**ENFORCEMENT:**
- Manual: Code readability and naming conventions reviewed during development; naming linter may be configured in project technical spec

---

## 4. TESTING ARCHITECTURE

### 4.1 Test Pyramid

**Structure**:
```
    /\
   /e2e\      ← Few, slow, full system
  /------\
 /integ. \    ← Some, medium, real APIs
/----------\
/   unit   \  ← Many, fast, isolated
```

**Unit Tests (Most):**
- Fast (<5s total)
- No network calls
- Mock all external dependencies
- Test one unit of code
- Run in CI/CD

**Integration Tests (Some):**
- Test interaction with real external systems
- Require network access
- Slower execution
- Skip in CI/CD (manual/scheduled)

**E2E Tests (Few):**
- Test complete deployed system
- Require infrastructure
- Slowest execution
- Manual only

**ENFORCEMENT:**
- Manual: Test organization and test type distribution reviewed during development; test pyramid is guideline not hard requirement

### 4.2 Test Coverage

**Minimum**: 90% code coverage

**Why 90%:**
- Catches most bugs
- Forces thinking about edge cases
- Documents behavior
- Not 100% because some defensive code is hard to test

**Coverage Must Include:**
- Happy paths
- Error paths
- Edge cases
- Boundary conditions

**ENFORCEMENT:**
- Automated: CI/CD test coverage check requires ≥90% coverage (blocks merge if failed); coverage tool defined in project technical spec

### 4.3 Test Isolation

**Requirements:**
- Tests must not depend on each other
- Tests can run in any order
- Tests can run in parallel
- Clean state for each test

**Use Mocks For:**
- External API calls
- File system operations
- Time-dependent code
- Random number generation
- Network operations

**ENFORCEMENT:**
- Automated: Test framework can verify tests run in parallel and random order (configuration in project technical spec)
- Manual: Test isolation and mocking practices reviewed during development

### 4.4 Test Naming

**Pattern**: `test_<what>_<condition>_<expected>`

**Examples:**
- `test_health_check_returns_200()`
- `test_oversized_request_rejected_with_413()`
- `test_validation_fails_with_invalid_input()`

**Clarity:**
- Test name should be self-documenting
- Failure message should be obvious from name
- No need to read test code to understand what failed

**ENFORCEMENT:**
- Manual: Test naming conventions reviewed during development

### 4.5 Mocking Standards

**Mock External Dependencies:**
- API calls
- Database queries
- File I/O
- Network requests
- Time/random number generation

**Don't Mock:**
- Code under test
- Simple data structures
- Standard library (unless I/O)

**Verify Mocks:**
- Mock behavior matches real API/system behavior
- Update mocks when external APIs change
- Integration tests validate mock assumptions

**ENFORCEMENT:**
- Manual: Mocking practices and test architecture reviewed during development

---

## 5. LOGGING ARCHITECTURE

### 5.1 Structured Logging

**Format**: JSON (machine-readable)

**Log Levels:**
- `INFO`: Normal operations, successful requests
- `WARNING`: Unexpected but recoverable conditions
- `ERROR`: Failures, exceptions, error responses
- `CRITICAL`: System-level failures

**Every Log Entry:**
```json
{
  "level": "INFO|WARNING|ERROR",
  "timestamp": "2025-11-09T12:00:00Z",
  "request_id": "correlation-id",
  "...": "context-specific fields"
}
```

**ENFORCEMENT:**
- Automated: Tests verify log output format is structured (JSON or defined format); logging library configuration in project technical spec
- Manual: Log entries reviewed during development for proper formatting and content

### 5.2 No Blind Spots Principle

**Requirement**: Every code path must produce a log entry.

**Coverage:**
- All successful requests
- All error responses (4xx, 5xx)
- All exceptions
- All timeout/connection failures
- All validation failures

**Test**: Review logs, every request should have at least one entry.

**ENFORCEMENT:**
- Automated: Tests verify each code path produces log output
- Manual: Log coverage reviewed by testing all execution paths

### 5.3 Error Logging

**When errors occur, log:**
- Error type/category
- Error message (sanitized)
- Request context
- Duration until failure
- Upstream host (if applicable)

**Enables:**
- Root cause analysis
- Differentiating timeout vs connection vs other
- Monitoring and metric filtering
- Alert correlation

**ENFORCEMENT:**
- Automated: Tests verify error conditions produce appropriate log entries with required fields
- Manual: Error log quality reviewed during development

### 5.4 Security in Logging

**Never Log:**
- Request/response bodies
- Authorization header values
- Cookie values
- Query parameters (may contain tokens/codes)
- Tokens of any kind
- Passwords or secrets
- Stack traces with sensitive data

**Safe to Log:**
- Header names (not values for auth/cookie)
- Exception types
- Sanitized error messages
- Durations and timing
- Response sizes
- Content types
- HTTP status codes

**ENFORCEMENT:**
- Automated: Tests verify sensitive data is not logged; security scanning tools can detect leaked secrets in logs
- Manual: Log content reviewed for sensitive data during security reviews

---

## 6. CLOUD INFRASTRUCTURE

### 6.1 Infrastructure as Code

**Requirement**: All infrastructure must be defined in code.

**Never:**
- Create resources manually in console
- Store configuration in spreadsheets
- Rely on "tribal knowledge"
- Deploy without version control

**Always:**
- Define in infrastructure as code tool
- Version control IaC templates
- Document deployment process
- Test IaC changes

**ENFORCEMENT:**
- Automated: IaC validation tool verifies infrastructure defined in code; manual infrastructure changes detected through drift detection
- Manual: Infrastructure reviews verify all resources defined in code

### 6.2 CI/CD Pipeline

**Requirement**: Automated test execution and code deployment on every push.

**Pipeline Structure:**

**Testing Job** (runs on all pushes and PRs):
- Checkout code
- Setup build environment
- Install dependencies
- Run unit tests with coverage requirement (≥90%)

**Deployment Job** (runs on push to main branch, after tests pass):
- Configure cloud provider authentication
- Package application code
- Deploy to target environment
- Verify deployment success

**Benefits:**
- Fast code deployment (seconds vs minutes)
- Automated quality gates
- Consistent deployment process
- Immediate rollback capability

**ENFORCEMENT:**
- Automated: CI/CD pipeline configured and running; blocks deployment if tests fail
- Manual: Pipeline configuration reviewed to ensure all quality gates are enabled

**Note**: Detailed deployment workflows, rollback procedures, and monitoring configurations are defined in project technical specifications.

---

## 7. SECURITY PRACTICES

### 7.1 Secrets Management

**Never:**
- Commit secrets to git
- Hardcode credentials
- Log sensitive values
- Store secrets in code

**Always:**
- Use .env files (gitignored)
- Secrets management service for production
- Environment variables
- Rotate credentials regularly

**ENFORCEMENT:**
- Automated: Pre-commit hooks block commits with secrets; security scans detect hardcoded credentials
- Manual: Security reviews verify secrets management practices

### 7.2 Error Message Sanitization

**Exposed to Clients:**
- Generic error messages only
- No internal implementation details
- No stack traces
- No sensitive data

**Logged Internally:**
- Detailed diagnostic information
- Exception types and messages
- Call stack (if sanitized)
- Context for debugging

**ENFORCEMENT:**
- Automated: Tests verify error messages don't expose sensitive data; security scans check error handling
- Manual: Security reviews verify error message sanitization

### 7.3 Input Validation

**Validate:**
- Request size limits
- Path whitelisting
- Content types
- Parameter formats

**Reject:**
- Oversized requests
- Invalid paths
- Malformed input
- Unexpected content types

**ENFORCEMENT:**
- Automated: Tests verify input validation logic rejects invalid inputs; security scans check validation coverage
- Manual: Security reviews verify all input paths have validation

---

## 8. CODE QUALITY

### 8.1 Self-Documenting Code

**Naming Conventions:**
- Variables: descriptive, not abbreviated
- Functions: verb phrases (`validatePath`, `rewriteDomain`)
- Constants: uppercase with separators
- Classes: PascalCase

**Note**: Specific naming conventions (camelCase, snake_case, etc.) defined in project technical specification based on language.

**Function Size:**
- Single responsibility
- Typically <50 lines
- Extract complex logic to sub-functions
- One level of abstraction per function

**ENFORCEMENT:**
- Automated: Linter can check naming conventions and function complexity (configuration in project technical spec)
- Manual: Code readability and naming conventions reviewed during development

### 8.2 Type Annotations

**Requirement**: Use type annotations for function signatures (when supported by language).

**Benefits:**
- Documents expected types
- Enables IDE autocomplete and tooling
- Catches type errors early at compile/build time
- Improves code maintainability

**Note**: Specific type annotation syntax and requirements defined in project technical specification based on language (TypeScript, Python type hints, Java generics, etc.).

**ENFORCEMENT:**
- Automated: Type checker verifies type hints are present and correct (tool defined in project technical spec)
- Manual: Type hint coverage reviewed during development

### 8.3 Error Handling

**Principle**: Catch specific exceptions/errors, not generic catch-all handlers.

**Good (specific error handling):**
```
catch (NetworkError, TimeoutError) as e:
    // Handle connection/timeout errors

catch (ValidationError) as e:
    // Handle invalid input
```

**Bad (generic catch-all):**
```
catch (Exception):
    // What failed? Who knows!
```

**Log All Errors:**
- Exception type
- Error message
- Request context
- Never swallow silently

**ENFORCEMENT:**
- Automated: Linter can detect broad exception catches (tool configuration in project technical spec)
- Manual: Error handling quality reviewed during development

---

## 9. PRE-DEPLOYMENT CHECKLIST

Use this checklist before pushing code to main branch:

- [ ] **Tests**: All tests pass locally with ≥90% coverage
- [ ] **Pre-commit hooks**: All hooks pass (secrets detection, linting)
- [ ] **Documentation**: New functions/classes have docstrings
- [ ] **Logging**: New code paths produce log entries
- [ ] **Type annotations**: Function signatures have type annotations (if supported)
- [ ] **Error handling**: Exceptions caught with specific handlers
- [ ] **No secrets**: No hardcoded credentials or API keys
- [ ] **Code review**: If deviation from standards, documented in commit message

**Note**: Most items verified by automated tooling in CI/CD. This checklist catches what automation misses.

---

## 10. DEPENDENCY MANAGEMENT

**Requirements:**
- Pin specific versions in dependency files
- Test upgrades in non-production environment before deploying
- Monitor security advisories for dependencies
- Plan for deprecated dependencies and runtime versions

**Rationale:**
- Prevents unexpected breakage from automatic updates
- Ensures reproducible builds
- Manages security vulnerabilities proactively

**ENFORCEMENT:**
- Automated: Dependency scanning tools check for known vulnerabilities
- Manual: Dependency versions reviewed during code review

---

**This document defines engineering standards applicable to all code in this organization. Project-specific requirements belong in functional and technical specifications.**
