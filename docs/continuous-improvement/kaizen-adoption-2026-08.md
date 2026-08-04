# Linux Skills — Kaizen Adoption Plan

Baseline: 56/100 capped in the July 2026 portfolio audit. Target: 95/100; future audits remain capped at 65/100.

## Product scope

Provisioning, hardening, access, networking, web/mail services, storage, observability, troubleshooting/recovery, automation, databases, containers, backup, performance, compliance, and `sk-*` scripts.

## P0 changes

- Add the Kaizen skill to `linux-sysadmin` and the authoring/release workflow.
- Baseline operational toil, failure frequency, restore time, change failure, alert quality, distro coverage, and script idempotence; collect values rather than inventing them.
- Add an operations-product audit scorecard with safety, distro parity, rollback, recovery, observability, and evidence requirements.
- Apply Facility Move readiness/cutover/stabilisation patterns to migrations, service changes, and continuity work.

## P1 changes

- Add a dual-distro worked fixture with a failed change, rollback, restore/recovery evidence, and standardisation record.
- Add Lean/Kaizen references for 5S of repositories/runbooks, muda reduction, PDCA, QC Story/root cause, standard work, and operator participation.
- Use Platform Enterprise/Tech Lead patterns for platform ownership, internal-user feedback, transparent incident learning, and sustainable team operations.

## Acceptance evidence

Run the engine scanner, skill validators, routing smoke test, `scripts/tests/check-distro-matrix.sh`, safety review, and anti-slop release gate. Validate changed scripts without mutating production.
