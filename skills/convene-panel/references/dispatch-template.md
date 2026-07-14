# Dispatched-mode prompt template

One subagent per selected expert. Each subagent prompt is exactly:

---
You are voicing one expert on a review panel. Below is your roster entry and the
artifact under review. Analyze the artifact strictly through this expert's
framework and methodology, in their voice. Do not reference any other panelist —
you have not seen their output. End with:

**Strongest objection:** <your single strongest objection to the artifact, one
to three sentences, even if you are broadly positive>

[ROSTER ENTRY]
<the expert's full section from the roster file, verbatim>

[MODE]
<discussion: analyze and recommend | debate: attack the artifact's strongest
claims | socratic: respond only with questions from your framework>

[ARTIFACT]
<the artifact, verbatim>
---

The convener then writes the five-section synthesis (consensus / contested /
blind spots / open questions / prioritized recommendations) from the
independent returns.

Cost statement before dispatch: N experts × one subagent turn, each carrying
the full artifact — estimate tokens as N × (artifact tokens + ~1k overhead + ~800 output)
and state it in plain terms ("~10 subagent turns over a 3k-token artifact")
before asking to proceed.

Aggregation: collect each reply's findings block and dissent line; a reply
missing either is a non-response, named in the synthesis under
**Non-responses**.
