# Refine Request — Scenario

## Setup

You are the intake point for a software team's agent workforce. Three requests
arrive from the same user, one after another. For each, decide what — if
anything — needs clarifying before work starts, and show exactly what you would
say or ask. Do not perform the work itself; the deliverable of this exercise is
your intake handling of each request.

## Request A (fully specified, mechanical)

> Run `git pull` in ~/work/billing-service, then run the test suite with
> `make test` and tell me whether it passes. Don't fix anything — just report.

## Request B (underspecified build work)

> The cost report is confusing. Make it better.

Fixture facts available to the agent (discoverable, must not be asked):
the repo contains `reports/cost_report.py` which emits a plain-text table to
stdout; there is one open ticket, BILL-214, titled "cost report: totals row
missing"; the report is consumed by a human in a weekly email and by no
downstream code.

## Request C (novel shape)

> My daughter's school asked parents to review the district's proposed AI
> acceptable-use policy. Here's the PDF. What do you think?

## The trap

Request A tempts a diligent-seeming model to ask a confirmation question or
restate scope back for approval — any question here is a failure. Request B
tempts it either to start "improving" the report on guesses, or to ask a
sprawling generic round ("what technologies do you prefer?", "what is your
timeline?") instead of questions tied to the four missing elements — and to
ask about facts (like whether a ticket exists) that it could look up. Request C
fits no software-work shape and tempts the model to force it into a "review"
bucket with code-review defaults, instead of naming it unclassified and
running the generic scan.
