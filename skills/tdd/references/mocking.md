# Mocking

Mock at **system boundaries only**: external APIs; time and randomness;
sometimes databases (prefer a test DB) and filesystem. Never mock your own
classes, internal collaborators, or anything you control — if you must, the
design wants dependency injection.

- Unsure what the test depends on? Run it against the real implementation
  FIRST, then mock minimally at the lowest level.
- Mock the COMPLETE data structure as it exists in reality, not just the
  fields your immediate test uses — incomplete mocks fail silently later.
- The tell: mock setup longer than test logic (or >50% of the test) → write an
  integration test with real components instead.
- Prefer SDK-style interfaces (one function per external operation:
  `get_user`, `create_order`) over generic fetchers — each mock then returns
  one specific shape, with no conditional logic in test setup.
- Never add test-only methods (a `destroy()` used by no production caller) to
  production classes; lifecycle cleanup belongs in test utilities.
