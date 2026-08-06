# Control-plane adoption

This engine adopts the shared ten-engine contract from
`C:\wamp64\www\skills-web-dev\docs\engine-control-plane.md`. Linux doctrine
remains authoritative for administration, hardening, services, networking,
observability, backup, and recovery across supported distro families.

## Local roles and commands

| Role | Responsibility | Permission boundary |
|---|---|---|
| Infrastructure planner | Define target state, dependencies, blast radius, and maintenance window. | Read-only until approved. |
| Hardening reviewer | Check controls, exposure, least privilege, and family-specific behavior. | Does not apply changes. |
| Incident commander | Coordinate evidence, containment, communication, and recovery. | One owner for operational decisions. |
| Rollback reviewer | Verify backup, restore path, rollback trigger, and rehearsal evidence. | Blocks irreversible change without recovery. |

Route thin commands `preflight`, `harden`, `incident`, and `rollback` to
existing scripts and skill workflows. Commands must state distro family,
target, and intended privilege level.

## Hook and release contract

- `preflight` checks identity, host scope, distro/version, maintenance window,
  dependencies, backup state, and a dry-run plan.
- `context` loads inventory, service state, configuration source, recent
  incidents, and prior changes without duplicating stale facts.
- `before_write` requires explicit target confirmation, least privilege,
  reversibility, backup/restore evidence, and bounded blast radius.
- `after_write` runs service, security, connectivity, log, and idempotence
  checks and records commands and outputs.
- `release` requires dry-run, backup, audit-log, and rollback-test evidence;
  destructive or production changes fail closed when any is absent.
- `stop` preserves command output, state deltas, failed checks, and a safe
  recovery handoff. Never hide a partial mutation behind success.

Native hooks are optional, but the safety contract is mandatory in scripts,
CI, or explicit skill steps.
