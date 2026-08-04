# Linux product audit checklist

Author: Peter Bamuhigire | techguypeter.com | +256 784 464 178

Apply to a skill, script, runbook, change plan, backup procedure, recovery procedure, or produced server state.

| Dimension | Inspect | Evidence |
|---|---|---|
| Value and scope | User outcome, owner, flow, toil, waste | Baseline and decision record |
| Safety | Authority, least privilege, confirmation, security controls | Read-only evidence and authorization |
| Distro parity | Debian/Ubuntu and RHEL-family mapping | Matrix or executed fixtures |
| Idempotence | Repeat behavior and no duplicate/destructive effects | Two-run result |
| Failure path | Preconditions, bounded refusal, errors, stop conditions | Negative fixture |
| Rollback/recovery | Backup, rollback, restore, validation | Recovery evidence |
| Observability | Logs, metrics, alerts, user-visible checks | Before/after outputs |
| Documentation | Prerequisites, commands, alternatives, review date | Operator handoff |
| Learning | Incident/feedback loop and next re-measure | Standardisation record |

Publish `min(raw score, 65)` and preserve raw dimension scores. Every gap requires a plan targeting 95/100 with a root cause, owner, measure, risk, rollback, and acceptance evidence.

