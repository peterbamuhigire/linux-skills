# Recommendations

## Priority Order

Recommended order:

1. fix execution-quality issues in the current foundation
2. complete and validate the tier-1 script core
3. harden CI and validation
4. build the tier-2 workhorse scripts
5. expand into scale and platform capabilities

## Skill Improvements

## 1. Make outputs more explicit

Each skill should state more clearly:

- what evidence to collect
- what success looks like
- what rollback looks like
- when to hand off to another skill

This is especially useful for:

- `linux-troubleshooting`
- `linux-disaster-recovery`
- `linux-observability`
- `linux-config-management`

## 2. Add multi-skill worked examples

Create realistic cross-domain workflows such as:

- 502 after deployment
- disk full due to logs
- backup restore after corruption
- hardening with access verification
- drift after emergency edits

## 3. Reduce tool-path assumptions

Where skills use `~/.claude/skills`, clarify that this is one deployment path rather than a
universal requirement.

## Script Improvements

## 1. Fix current spec violations first

### `sk-update-all-repos`

Keep the new constrained post-pull command model and add tests for:

- simple single-command hooks
- `&&` command chains
- rejection of shell metacharacters
- executable script hooks

### `setup-claude-code.sh`

Bring the bootstrap path closer to the engine standards:

- reduce fragile remote-install flows
- improve explicit error handling and narration
- separate Claude bootstrap from engine install if needed

## 2. Finish the tier-1 scripts first

The highest-value near-term work remains:

- `sk-new-script`
- `sk-lint`
- `sk-system-health`
- `sk-disk-hogs`
- `sk-open-ports`
- `sk-service-health`
- `sk-cert-status`
- `sk-cron-audit`
- `sk-user-audit`
- `sk-ssh-key-audit`
- `sk-fail2ban-status`
- `sk-journal-errors`
- `sk-backup-verify`

## 3. Add rollback tests as a standard pattern

For destructive or semi-destructive scripts, prove that:

- pre-change backups are created
- failed validation triggers rollback
- restored state matches the original state

## 4. Strengthen installer and upgrade testing

Add tests for:

- changed upstream scripts
- added upstream scripts
- removed upstream scripts
- local modifications in `/usr/local/bin`
- partial install failure recovery

## 5. Add stable `--json` output where it matters

Prioritize machine-readable output for:

- audit and status scripts
- monitoring/reporting scripts
- backup verification
- service health
- drift detection

## New Skills To Add

## 1. Infrastructure as Code

Add a Terraform or broader IaC skill to cover:

- state discipline
- module layout
- environment promotion
- drift and plan review

## 2. CI/CD Operations

Add a release-operations skill for:

- deployment pipeline design
- rollback strategy
- artifact promotion
- post-deploy verification

## 3. Advanced Observability

Expand into:

- Grafana
- Loki/Promtail
- alerting
- SLI/SLO patterns

## 4. Kubernetes / Orchestration

Add only if the repo intends to move beyond single-host and VM/container-host operations.

## 5. Compliance / Audit Reporting

Add a future compliance skill for:

- CIS-style reporting
- evidence capture
- policy exceptions

## System-Level Improvements

## 1. Add stronger orchestration for multi-skill workflows

Create end-to-end flows for:

- fresh server to live deployment
- audit to hardening to re-audit
- incident to diagnosis to repair to prevention
- backup creation to restore verification

## 2. Add repo-level validation gates

Automatically check:

- every `SKILL.md` manifest parses
- every listed script source exists
- every implemented script sources `common.sh`
- every implemented script exposes standard flags
- every implemented script has tests

## 3. Introduce maturity labels

Mark scripts or domains as:

- planned
- experimental
- production-ready
- proven-on-linux

## 4. Add fleet and environment concepts gradually

To scale toward platform operations, add:

- environment naming conventions
- inventory standards
- central reporting format
- host classification
- policy bundles by host type
