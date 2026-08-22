# Approval enforcement adapter

Linux actions are declared in [`approval-adapter.json`](approval-adapter.json)
and use the shared contract from `skills-web-dev/docs/approval-contract.md`.

## Required change preview

Show exact host identity, distro family/version, environment, user and
privilege, command plan hash, current state, preconditions, maintenance window,
backup/restore evidence, blast radius, rollback, verification, and expected
service state. Production execution accepts allow-listed typed commands only;
arbitrary shell strings are denied.

## Gated actions

Root/sudo commands, firewall, SSH/TLS/IAM, SELinux/AppArmor, storage, backup
restore, package repositories, secrets, hardening, and production restarts are
L3. A changed host, distro family, package manager, service topology, command,
or precondition requires a new preview and approval.

## Stop conditions

Stop when target, authority, backup, audit sink, rollback, or verification is
missing, or when a command is hidden in a generated script or chain. Never put
secrets in approval text or ordinary logs. A zero exit code is not proof of the
intended state.

## Acceptance boundary

Read-only inspection and dry-run preparation may proceed automatically. A
privileged, destructive, security, recovery, or production action cannot run
without the shared gate and post-action verification.
