# Incident learning and standardisation

Author: Peter Bamuhigire | techguypeter.com | +256 784 464 178

Use after an incident, near miss, failed change, failed restore, alert-quality problem, or repeated operator workaround.

## Learning record

| Field | Required content |
|---|---|
| Impact | User/service/data/safety scope, duration, and affected dependency |
| Timeline | Observed facts, timestamps, commands, alerts, decisions, and changes |
| Failure mechanism | Evidence-supported cause; separate contributing conditions and unknowns |
| Containment | Minimal authorised action and residual risk |
| Recovery | Rollback/restore steps, validation, and data/service gap |
| Countermeasure | Small reversible improvement, owner, guardrail, and due date |
| Standardisation | Skill/reference/script/test/runbook change and reviewer |
| Re-measure | Metric, denominator, period, and next review trigger |

## Blameless accountability

Describe system conditions, incentives, handoffs, observability, unclear ownership, and unsafe defaults. Preserve accountability for decisions and controls without using blame as a substitute for causal evidence. Share the learning with the platform/service users who depend on the path.

## Closure rule

An incident action is not closed because the symptom disappeared. Close only after the user-visible outcome, subsystem health, failed path, rollback/recovery path, and regression evidence are recorded. If evidence is missing, keep the action open or mark it unassessed.

