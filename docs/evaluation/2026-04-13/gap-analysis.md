# Gap Analysis

## Main Gap

The primary gap is not domain knowledge. It is **engine completion and proof**.

`linux-skills` already knows how to operate Ubuntu/Debian servers. What prevents it from being
world-class today is that too much of the execution layer is either:

- not implemented
- not validated on Linux
- not enforced through CI and policy

## Critical Gaps

## 1. Script coverage is still far below engine requirements

The repository plans 88 scripts and currently implements only a small subset. That means much of
the system's automation promise still lives in design documents rather than in trusted tools.

## 2. Linux-native validation is insufficient

The test harness design is strong, but there is still not enough proof that the current foundation
has been exercised on Linux against realistic success and failure paths.

Missing proof includes:

- end-to-end bootstrap on fresh Linux hosts
- rollback verification
- upgrade-path verification
- repeat-run idempotency for destructive workflows
- restore drills

## 3. Design and implementation are not fully synchronized

There are visible mismatches between stated policy and real code.

Examples:

- `scripts/setup-claude-code.sh` behaves more like a convenience bootstrap script than a strictly
  governed engine component
- destructive and rollback-sensitive flows are still documented more strongly than they are proven

These are exactly the sorts of inconsistencies that reduce production trust.

## Important Gaps

## 4. CI enforcement is too weak

A world-class operations engine should automatically enforce:

- `shellcheck`
- manifest integrity
- required `SKILL.md` structure
- Linux integration tests
- upgrade and rollback test patterns

The repository has strong standards, but too many are still social rather than enforced.

## 5. Fleet-scale governance is thin

The repo is strong for host-level operations but weaker for:

- environment promotion
- centralized policy reporting
- inventory governance
- fleet-wide drift visibility
- multi-host compliance views

## 6. Recovery confidence is lower than recovery documentation quality

The disaster-recovery material is good, but restore confidence requires more than documentation. It
requires evidence:

- restore drills
- timing measurements
- integrity verification
- failure handling during restore

## 7. Observability is still host-centric

The observability skill is useful for instrumentation, but a world-class engine needs more on:

- alerting
- SLI/SLO thinking
- dashboards
- retention discipline
- operational correlation across services

## 8. Higher-order platform capabilities are missing

To claim world-class DevOps/SRE breadth, the engine still needs stronger stories for:

- CI/CD operations
- Terraform or comparable IaC
- orchestration platforms
- environment-wide secrets distribution
- database failover and replication operations

## Weak Areas By Domain

## Troubleshooting

Good structure, but it needs richer signature-driven diagnosis and more implemented decision-tree
scripts.

## Config Management

Strong conceptual direction, but one of the most important scale mechanisms in the repository is
still mostly planned rather than operational.

## Observability

Good host instrumentation guidance, but not yet a full operational observability layer.

## What Most Prevents Production-Grade Scale

The largest blockers are:

1. incomplete execution surface
2. insufficient Linux-side proof
3. weak enforcement relative to the stated standards
4. limited fleet and platform-level control mechanisms
