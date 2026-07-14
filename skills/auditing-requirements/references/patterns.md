# Requirements content classification patterns

The one shared catalog. Used by `auditing-requirements` (the violation
catalog it applies) and linked from `writing-business-requirements` (the
prohibited-language table it must not restate). Edit here only.

## 1. Implementation details

Destination: `.claude/rules/` (coding standards).

| Category | Cues | Wrong | Right |
|---|---|---|---|
| Return values/types | `return None/True/False/error/dict/list/tuple` | "Extractor returns error response if the file is unreadable" | "The system shall provide error details when the file is unreadable" |
| Exception handling | `raise / catch / except / try: / throws` | "Validator raises an error when the format is invalid" | "System shall reject invalid formats with an error message" |
| Function/API calls | `call / invoke / execute`, `object.method(...)` syntax | "classifier.classify(path, taxonomy) returns the result" | "System provides classification results for uploaded documents" |
| Data structures | `dictionary / dict / list / array / tuple / JSON object / dataframe` | "The JSON object contains a tags array" | "Results include usage tags" |
| Control flow | `if/else/elif`, `for/while`, `iterate over`, `conditional logic` | "Loop through all documents in the batch" | "Process all documents in the batch" |
| Technical terms | `regex`, `deterministic extractor`, `model fallback`, `algorithm/heuristic`, `class/module/function/variable` | "Use a regex pattern to extract the identifier" | "Extract the identifier using pattern matching" |
| Unverified performance | `processes in N seconds`, `real-time/instantaneous` without verification | "Real-time updates as classification completes" | "Users see classification results when processing completes" |

Verified, measurable performance claims are fine. Vague terms ("fast",
"efficiently") should be made specific or removed.

## 2. Technology specifics

Destination: `docs/decisions/DECISIONS.md` (choices) or `docs/setup/`
(configuration).

| Category | Cues | Wrong | Extract to |
|---|---|---|---|
| Library/framework names | named PDF/OCR/test/HTTP libraries, named web frameworks, named model providers when describing HOW | "System uses <library> to extract text from files" | Decision: why chosen -> DECISIONS.md; setup instructions -> `docs/setup/` |
| API endpoints/URLs | any `https://`, "endpoint/API URL: <value>" | "System calls a specific model-provider completions URL" | `docs/setup/` (auth/config) |
| Configuration values | `timeout/retry/threshold/limit = N`, API key/secret/token | "Confidence threshold = 0.95" | `config/*.json` defaults; `docs/setup/` for env vars |
| File paths | absolute/relative paths, `data/ src/ tests/ config/` | "Results stored in data/output/results.json" | Project guidance file |

## 3. Architecture rationale

Destination: `docs/decisions/DECISIONS.md`.

| Category | Cues | Wrong |
|---|---|---|
| Design decisions/tradeoffs | `we chose / decision to / rationale for / tradeoff / considered` | "We chose multi-model consensus because single-model accuracy was insufficient" |
| System design patterns | `architecture / design pattern / fallback chain / multi-model / two-level` | "Triple validation strategy: deterministic then primary model then secondary model" |
| Technology comparison | `compared to / versus / better than / faster than` | "<model A> provides better accuracy than <model B>" |

Extracted rationale becomes a decision record (context, options evaluated,
decision, rationale, consequences) in `docs/decisions/DECISIONS.md`.

## 4. Test plans and procedures

Destination: `tests/` or test documentation.

| Category | Cues | Wrong | Extract to |
|---|---|---|---|
| Test cases/scenarios | `test case/scenario/suite`, `test_...()` names | "test_classify_with_invalid_input() verifies error handling" | `tests/unit/`, `tests/integration/` |
| Coverage requirements | `coverage`, `90%/100%`, `every branch/edge case` | "Module shall have 90% test coverage" | `.claude/rules/testing.md` |
| Verification methods | `verification method/approach`, `mock/stub/fixture` | "Verification method: mock the API responses" | `tests/README.md` |
| Assertions/expected results | `assert/expect/should return` in a test context | "Assert that the confidence score is at least 0.95" | `tests/` (as actual assertions) |

## False-positive rules — do NOT flag

- Implementation language inside a **fenced code block**.
- A clearly-labelled **example or illustration** ("Example: the extractor
  might use pattern matching...") — describing, not prescribing.
- An **attributed quote** ("The developer noted: 'we used try/except
  blocks here'").
- A **cross-reference** that only points elsewhere ("See
  `.claude/rules/testing.md` for exception-handling patterns").
- Content **already in its correct document** (a test file containing a
  test case is not a violation).

Flag only when the pattern appears in a requirement statement or its
rationale and describes HOW the system works, not WHAT it does.

## Severity

- **HIGH** — implementation language inside a requirement statement itself.
- **MEDIUM** — useful information sitting in the wrong document (e.g.
  architecture rationale mixed into requirements).
- **LOW** — minor clarity issue or a missing cross-reference.

## Destination mapping (quick reference)

| Content type | Destination |
|---|---|
| Exception handling patterns | `.claude/rules/python-style.md` |
| Error logging requirements | `.claude/rules/logging-security.md` |
| Module organization rules | `.claude/rules/project-standards.md` |
| Testing methodology | `.claude/rules/testing.md` |
| Technology choices, design patterns, tradeoffs | `docs/decisions/DECISIONS.md` |
| Library configuration | `docs/setup/*.md` |
| API authentication | `docs/setup/api-setup.md` |
| File organization | project guidance file |
| Configuration defaults | `config/*.json` |
| Test cases | `tests/unit/`, `tests/integration/` |
| Test strategy, coverage requirements | `tests/README.md`, `.claude/rules/testing.md` |

## Report format

```yaml
violations:
  - type: "implementation_detail"       # or technology_specific | architecture_rationale | test_procedure
    category: "exception_handling"
    location: "docs/requirements/verifier.md:45"
    content: "System shall catch all exceptions and log errors"
    destination: ".claude/rules/logging-security.md"
    suggested_replacement: "System shall handle errors and display error messages to users"
    severity: "high"  # high | medium | low
```

Report body: document audited, sections reviewed, which of the four
categories were applied, then each violation in the form above, then a
summary (total violations, by severity, by category).

## Citation conventions (shipped defaults, not policy)

No `policy:` key covers requirements-document citation format
(`policy:ticket-format` is tracker/ticket-specific and doesn't fit). These
are craft defaults `writing-business-requirements` ships with — adjust per
project convention:

- Identifier: `FR-n`, sequential.
- Priority: MoSCoW (Must/Should/Could/Won't Have).
- Standards cited: BABOK v3 (IIBA), IEEE 830-1998, ISO/IEC/IEEE 29148:2018.
