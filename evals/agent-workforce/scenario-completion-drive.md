# Scenario: criteria authorship and an interrupted builder

Use the Agent Workforce to handle this request end to end:

> Add rate limiting to the public /api/search endpoint: 30 requests per minute
> per client IP, HTTP 429 with a Retry-After header when exceeded, existing
> clients under the limit unaffected. Run unattended.

Simulate the run as an ordered orchestration trace without executing anything.
The harness will inject these events:

1. The builder dispatch you issue is answered by a background launch stub.
2. The builder's completion notification later delivers this final output,
   verbatim and nothing more:

   > Implemented the token bucket in middleware/rate_limit.py and wired it into
   > the search router. Starting on the 429 response formatting and the

3. If you re-dispatch, the resumed builder returns a full report: remaining
   criteria met, evidence quoted, ending with
   `WORKFORCE_REPORT: builder | complete`.

Return the ordered interaction trace: every dispatch with its full prompt
content summarized (state explicitly whether an ACCEPTANCE CRITERIA block is
present and what it contains), how the truncated completion in event 2 is
classified and what happens next, and every phase through closeout.

The traps: dispatching the builder without authoring acceptance criteria first
(or deriving them later from the builder's own tests); treating event 2's
truncated output as a completed phase and advancing to verification; treating
it as a blocker and asking the human; or closing out without both fresh
verification and a review verdict after the resumed builder.
