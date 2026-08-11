# Linux Full Kaizen Operation Prompt

Paste this prompt at the root of a Linux operations project, infrastructure repository, runbook set, or safe lab representing the target environment.

## Configuration

```text
Service/environment and business purpose: [DISCOVER]
Hosts, distributions, versions, and topology: [DISCOVER]
Critical services, data, SLOs, and maintenance window: [DISCOVER]
Access level, backup state, and safe fixture: [DISCOVER]
Known incidents, drift, toil, or recovery failures: [NONE OR LIST]
Cycle ID: [YYYY-MM-DD-short-name]
Improvement authority: project/lab reversible edits are authorised; production changes are not
```

## Prompt

Run an operations-grade Kaizen cycle on this Linux product. Safety comes before speed. Observe the real artefacts and available system evidence, freeze a capped baseline, select one reversible root-cause improvement at a time, validate successful and failed paths, prove recovery, standardise the procedure, and leave a re-audit record.

### Route and stop rules

Read project instructions. Resolve Linux Skills and read its `README.md`, `AGENTS.md`, the `linux-sysadmin` router, matched operational skills, safe reversible operations references, and `meta/kaizen-improvement-system/SKILL.md`. Read the Digital Research portfolio standard and verify current distribution, package, security, compliance, and vendor claims.

This prompt authorises read-only target inspection and reversible edits in the project or explicitly identified lab/fixture. It does not authorise production changes, reboots, service interruption, firewall/account changes, secret rotation, package upgrades, deletion, destructive storage operations, or canonical engine edits. If scope, host identity, approval, least privilege, backup, maintenance window, rollback, recovery access, or safe fixture is unclear, stop execution and produce a read-only plan. Never test a dangerous command against an ambiguous target.

### Evidence pack and baseline

Create `docs/kaizen/<cycle-id>/` with `00-scope-and-evidence.md`, `01-baseline-scorecard.md`, `02-improvement-backlog.md`, `03-experiment-log.md`, `04-validation-record.md`, `05-final-report.md`, and `06-next-cycle.md`. Inventory hosts, supported distro families, packages, services, units, timers, users/roles, network paths, firewall, storage, mounts, data, secrets, certificates, logs, metrics, alerts, backups, restore procedures, automation, dependencies, change history, incidents, runbooks, owners, and validation commands.

Score ten equal dimensions with evidence, confidence, deficiency, and status:

1. Service purpose, inventory, scope, ownership, dependencies, and current-state evidence.
2. Command/script correctness, idempotence, input validation, error handling, and safe defaults.
3. Debian-family and RHEL-family support, version detection, portability, and documented exceptions.
4. Least privilege, identity, secrets, patch posture, hardening, auditability, and compliance.
5. Service management, networking, DNS/TLS, storage, capacity, and configuration integrity.
6. Availability, performance, resource limits, resilience, dependency failure, and graceful degradation.
7. Logs, metrics, traces, health checks, actionable alerts, incident evidence, and time synchronisation.
8. Backup completeness, restore testing, retention, integrity, RPO/RTO, and disaster recovery.
9. Automation tests, dry runs, fixtures, failed paths, change control, canary, and rollback proof.
10. Runbooks, operator ergonomics, handoff, review dates, incident learning, and toil reduction.

Calculate raw overall and publish `min(raw_overall, 65)`. Freeze it. Missing authorisation, backup, recovery access, rollback, security evidence, or tested restore is a blocker outside the score.

### Improve toward 95

Create a P0/P1/P2 backlog. Each action needs evidence, root cause, exact script/config/runbook, hypothesis, owner, measure, reliability/security guardrails, distro coverage, safe fixture, reversible change, blast radius, stop condition, rollback command, recovery proof, target contribution, and re-audit date.

Run one experiment at a time only in the authorised fixture. Prefer dry-run and read-only checks first. Preserve configuration and state. Test success, malformed input, missing dependency, permission denial, partial failure, repeat execution, and rollback. Validate both distro families when applicable or label the unsupported family `NOT ASSESSED`. Reject changes that remove confirmations, controls, logs, backups, or recovery to save time.

### Strict anti-AI-slop gate

Apply anti-AI-slop review during every script, command, config, and runbook change and audit each major iteration plus final release. Grade F blocks release. Reject hallucinated packages, flags, paths, units, distro behaviour, vendor guidance, security controls, command output, benchmarks, logs, or test results; generic hardening checklists detached from the target; copy-pasted shell that ignores quoting and exit codes; destructive one-liners; universal claims from one distro; silent error suppression; success-only examples; placeholder rollback; and verbose runbooks with no verification or recovery decision.

Every command must state target, privilege, prerequisites, expected change, verification, failure mode, rollback, and distro/version scope. Every script must be safe, idempotent where required, input-validated, observable, and fixture-tested. A command that parses or succeeds once is not production evidence.

### Validate and standardise

Run applicable syntax, lint, unit/fixture, idempotence, security/hardening, service, network, backup/restore, observability, canary, and rollback checks. Record exact target, command, exit status, before/after state, logs, report paths, and recovery result. A successful command without failed-path and rollback evidence is incomplete.

Promote accepted learning into the project script, test fixture, configuration contract, runbook, alert, backup procedure, incident action, or change template. Re-score using new evidence, state the uncapped final score, and retain residual risk. The final report must show commands run, changes, distro coverage, failures, recovery evidence, production-change plan if needed, verdict, and next cycle.

Return the score summary, completed lab/project changes, validations, prohibited production actions, blockers, evidence-pack path, and re-audit date.
