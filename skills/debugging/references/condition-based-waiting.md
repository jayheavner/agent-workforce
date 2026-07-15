# Condition-based waiting

Never sleep an arbitrary duration and hope. Wait for the actual condition you
care about: poll it (every ~10ms) with a timeout whose error message NAMES the
condition ("timed out waiting for order to reach SHIPPED").

Mistakes: no timeout (hangs forever); polling every 1ms (CPU burn); caching
state outside the loop (always stale). An arbitrary timeout is legitimate only
when testing timed behavior itself — and even then, first wait for a
triggering condition, base the delay on known intervals, and comment why.
