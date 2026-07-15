# Defense in depth (after the root cause)

Once the root cause is fixed, make the bug structurally impossible by
validating at every layer the bad data passed through: (1) entry-point
validation, (2) business-logic validation, (3) environment guards (refuse the
dangerous operation outright in contexts where it can only be a bug),
(4) the debug instrumentation that finally caught it, kept as an assertion
where cheap. Different call paths, mocks, and platforms each bypass a
different single check — layers are what hold.

Trace bad data BACKWARD to its origin before fixing: patching the symptom
site leaves every other consumer of the bad value broken. Fix at the source.
