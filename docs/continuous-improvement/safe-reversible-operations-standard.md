# Safe reversible operations standard

Author: Peter Bamuhigire | techguypeter.com | +256 784 464 178

Use this standard for a Linux package, configuration, service, firewall, storage, database, backup, deployment, or recovery change.

## Gate before execution

1. State the user-visible objective, scope, host role, authority, and stop condition.
2. Capture a read-only before snapshot: distro family/version, relevant config, service state, sockets, logs, disk/memory, security context, and current backup or snapshot identifier.
3. Define the smallest reversible change, expected measure, guardrail, rollback command, and recovery owner.
4. Validate the command against the correct family matrix. Prefer `common.sh` primitives and family-neutral tools; never copy an `apt`/`ufw`/`apache2` command into a RHEL path or a `dnf`/`firewalld`/`httpd` command into a Debian path without an explicit mapping.
5. Test syntax and a no-op or dry-run path before mutation. Stop if the precondition, backup, rollback, or authorization is missing.

## Idempotent change contract

An operational step is idempotent when a second authorized run leaves the intended state unchanged, does not duplicate entries, and does not destroy evidence. Scripts should detect current state, use atomic temporary files plus validated replacement, preserve permissions/labels, and return a useful status for no-change, changed, and failed outcomes.

## Execute and recover

- Apply one bounded change at a time and record the exact command, timestamp, actor, and result.
- Verify both the technical state and the user-visible outcome.
- If a guardrail regresses, stop further changes, restore the known-good state, verify rollback, and preserve before/after evidence.
- Do not call a restart, reload, repair, or restore a rollback unless its effect and scope are known.
- Standardise only after the change passes the relevant Debian-family and RHEL-family checks, idempotence check, failed-path check, and rollback/recovery check.

## Evidence bundle

| Evidence | Acceptance |
|---|---|
| Before state | Host identity, family/version, relevant service/config/backup state |
| Change record | Authority, scope, command, timestamp, operator, result |
| Verification | Technical and user-visible checks with outputs |
| Failed path | Safe refusal or controlled failure is demonstrated |
| Rollback/recovery | Known-good state is restored and verified |
| Standardisation | Skill/reference/test updated with review date and next measure |

