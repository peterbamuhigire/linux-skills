# World-Class Definition

## Definition

A world-class Linux operations engine is a system that lets operators manage production Linux
infrastructure safely, repeatably, and at scale with low human-error rates and strong recovery
characteristics.

For Ubuntu/Debian server management, it must be more than documentation. It must combine:

- operational guidance
- safe execution tooling
- validation
- observability
- recovery discipline
- repeatable multi-environment practice

## Core Capabilities

### Provisioning

The engine must bootstrap new hosts into a secure, standardized baseline.

### Security hardening

The engine must audit and remediate host risk without casually breaking access or service behavior.

### Service management

The engine must support safe restart, reload, diagnosis, and verification of system services.

### Monitoring and logging

The engine must expose host health, retain diagnostic value locally, and support central visibility.

### Backup and recovery

The engine must create verifiable backups and prove that restores are real, not theoretical.

### Networking and DNS

The engine must manage host networking and service-facing DNS safely, with validation and rollback
awareness.

### Package management

The engine must support safe upgrades, patch discipline, and visibility into package drift and
update risk.

## Advanced Capabilities

To exceed ordinary sysadmin quality and approach DevOps/SRE standards, it should also support:

- configuration management
- observability with alerting intent
- secrets management
- intrusion detection and prevention
- automation at scale
- disaster recovery readiness
- environment-level reproducibility

## Quality Dimensions

### Safety

Destructive actions require explicit operator control. Validation before reload is mandatory.

### Idempotency

Operations must be safe to repeat. Second runs should converge, not create new risk.

### Reliability

Failure behavior must be explicit, testable, and recoverable.

### Security

The engine itself must not introduce unsafe shell behavior, secret leakage, or hidden execution.

### Performance

Operational checks must remain usable on real hosts and real datasets.

### Usability

A senior operator should move faster with the engine, not fight it. A newer operator should be less
risky when using it.

## Evidence Needed To Claim World-Class Status

A repository should not claim world-class operational maturity without evidence of:

- broad domain coverage
- mature execution coverage
- Linux-native validation
- rollback and restore proof
- CI enforcement
- realistic multi-skill workflows
- reliable behavior across repeated runs

## Where `linux-skills` Fits

`linux-skills` already aligns strongly with the philosophy of a world-class engine:

- safety-first design
- idempotency rules
- modular domain ownership
- strong separation between audit and mutation

What it still lacks is enough validated execution mass to meet the full definition today.
