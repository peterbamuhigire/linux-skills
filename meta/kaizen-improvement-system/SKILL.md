---
name: kaizen-improvement-system
description: Use when auditing or improving the Linux operations engine, linux-sysadmin skills, or any server, network, security, observability, automation, backup, database, or recovery product it produces.
metadata:
  portable: true
  compatible_with:
    - claude-code
    - codex
  author: Peter Bamuhigire
  author_url: https://techguypeter.com
  author_contact: +256 784 464178
---

<!-- dual-compat-start -->
<!-- This contract is intentionally portable across Codex and Claude Code. -->
<!-- dual-compat-end -->

# Kaizen Improvement System

Acknowledgement: Shared by Peter Bamuhigire, techguypeter.com.

## Use When

- Auditing this engine or an operational product, runbook, script, service change, or recovery procedure.
- Turning incidents, drift, toil, failed recovery, user feedback, or new evidence into a safe improvement.

## Do Not Use When

- Only a single skill safety audit is needed; use the narrowest applicable audit skill.
- A current distro, security, compliance, or vendor claim lacks source verification; route the claim to digital-research-skills first.

## Required Inputs

| Artefact | Source | Required | If absent |
|---|---|---|---|
| Target and scope | User brief, repository, host inventory | Yes | Stop and define the smallest safe scope. |
| Current-state evidence | Logs, tests, metrics, incident records, or artefact inspection | Yes | Mark the audit unassessed; do not infer quality. |
| Change controls | Change window, permissions, rollback, backups | Yes for execution | Produce a read-only plan only. |
| Success measures | Reliability, safety, toil, cost, or user outcome | Yes | Define a measurable hypothesis before experimenting. |

## Workflow

1. Read the local adoption plan, `AGENTS.md`, `linux-sysadmin`, and the portfolio Kaizen standard; inventory the engine or product. Stop if scope, authorization, or rollback is unclear.
2. Establish the baseline, score applicable dimensions, and publish `min(raw score, 65)` with safety and rollback blockers separate from the score.
3. Select one reversible improvement, define a 95/100 target, owner, hypothesis, command/test/fixture, acceptance evidence, and rollback; abort if risk exceeds the approved boundary.
4. Run the experiment on a safe fixture, validate Debian-family and RHEL-family paths where applicable, and recover or roll back on failure.
5. Check evidence, standardise only the verified change, teach the updated procedure, and schedule the next re-audit.

## Outputs

| Artefact | Consumer | Acceptance |
|---|---|---|
| Capped audit | Engine owner | Raw score is visible and published score never exceeds 65/100. |
| Improvement plan | Maintainer and operator | Each gap has a root cause, owner, measure, evidence, risk, rollback, and 95/100 target. |
| Experiment record | Reviewer | Fixture, command/test, result, and recovery evidence are reproducible. |
| Standardised update | Future operators | Skill, reference, test, or runbook change is linked and review-dated. |

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Baseline and scorecard | Dimension-level evidence, uncertainty, and 65/100 cap are recorded. |
| Product audit matrix | Correctness, idempotence, distro coverage, security, observability, backup/restore, rollback, documentation, and handoff are assessed. |
| Learning record | Hypothesis, change, result, failed-path result, and next action are captured. |
| Re-audit entry | The improvement is measured against its baseline and target. |

## Capability Contract

- May read/search engine files, product artefacts, tests, logs, references, and supplied evidence; may propose or author scoped documentation and skill updates when explicitly authorised.
- Must preserve least privilege, backups, explicit confirmation, rollback, and two-family support. Execution requires explicit authorization and a safe fixture; audit mode is read-only.
- May route current or uncertain claims to `digital-research-skills` and must record source status, date, and limitations.

## Degraded Mode

If evidence is incomplete, the target is unassessed, or distro execution is unavailable, stop execution and produce the narrowest qualified read-only audit. Label unassessed dimensions, do not invent scores, separate evidence gaps from defects, and defer standardisation until verification is available.

## Decision Rules

| Action | Risk avoided |
|---|---|
| Stop when authorization, backup, rollback, or scope is missing | Prevents an unsafe operational change. |
| Keep the raw score and cap the published audit at 65/100 | Prevents false confidence and preserves comparability. |
| Target 95/100 only through evidence-backed actions | Prevents cosmetic score improvement without capability improvement. |
| Preserve a failed-path fixture before closing the action | Prevents recurrence hidden by a successful-path test. |
| Re-audit after standardisation | Prevents stale improvements and regression. |

## Quality Standards

Preserve two-family support, idempotence, least privilege, explicit confirmation, backups, rollback, verification, evidence traceability, and review dates. Never turn a historical book or vendor example into a current command without verification.

## Anti-Patterns

- Measuring only successful execution. Fix: test failed paths and rollback.
- Removing safety prompts to save time. Fix: reduce toil around them, not the guardrail.
- Treating one distro as universal. Fix: validate both families or label the gap.
- Optimising a local step while increasing incident risk. Fix: inspect the full value stream.
- Closing an incident action without a regression test. Fix: add a fixture or script test.
- Treating missing evidence as a passing score. Fix: mark the dimension unassessed.

## Worked Example

For a backup script that passes on Debian but has no RHEL fixture, baseline it as partially assessed, cap the audit at 65/100, and record the missing distro evidence as a gap. Add a safe RHEL-family fixture, test restore and failure recovery, update the script/reference, and re-audit toward 95/100 only after the evidence passes.

## References

- [Local adoption plan](../../docs/continuous-improvement/kaizen-adoption-2026-08.md)
- [Safe reversible operations standard](../../docs/continuous-improvement/safe-reversible-operations-standard.md)
- [Value-stream, 5S, and QC Story](../../docs/continuous-improvement/value-stream-5s-qc-story.md)
- [Two-family validation and recovery](../../docs/continuous-improvement/two-family-validation-and-recovery.md)
- [Incident learning standard](../../docs/continuous-improvement/incident-learning-standard.md)
- [Linux product audit checklist](../../docs/continuous-improvement/linux-product-audit-checklist.md)
- [Portfolio Kaizen standard](C:/wamp64/www/digital-research-skills/docs/continuous-improvement/portfolio-kaizen-standard-2026-08.md)
- [Linux Kaizen operations loop](../../linux-sysadmin/kaizen-operations-loop.md)
- `meta/skill-safety-audit/`
- `15-compliance-and-auditing/`
