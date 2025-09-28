# Concrete Build Backlog

| # | Filename/path | Purpose | Acceptance criteria | Effort |
| --- | --- | --- | --- | --- |
| 1 | docs/validation/live-distro-matrix.md | Record real host/container validation across supported families. | Every core skill has at least Ubuntu and one RHEL-family validation evidence row. | L |
| 2 | scripts/tests/integration/ | Add integration tests for migrated scripts. | Tests cover dry-run, idempotency, rollback, and family-specific branches. | L |
| 3 | references/compliance/cis-control-map.md | Map skills and commands to CIS controls. | Each hardening/compliance skill links controls, evidence commands, and exceptions. | M |
| 4 | labs/rollback-drills/ | Create repeatable rollback and recovery drills. | At least 10 mutating scenarios document precheck, change, failure, rollback, and verification. | M |
| 5 | scripts/sk-health-report.sh | Generate evidence pack from a host. | Produces sanitized Markdown with OS, packages, services, firewall, audit, and update status. | M |
