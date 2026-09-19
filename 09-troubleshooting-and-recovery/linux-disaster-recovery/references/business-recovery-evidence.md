# Business-to-recovery evidence crosswalk

Author: Peter Bamuhigire | techguypeter.com | +256 784 464 178

Use this crosswalk when a recovery plan must show how a business outcome will be
protected. It separates business objectives from technical evidence and keeps
catalogue or backup metadata from being mistaken for a completed restore.

## Crosswalk contract

| Business question | Required evidence | Failure or unknown state |
|---|---|---|
| What must be available, by when? | Named service/data owner, RPO, RTO, priority, and acceptance task | Missing owner or objective is `BLOCKED`. |
| Can the recovery point be used? | Recovery-point identity, age, integrity result, retention basis, and dependency list | Unavailable or stale point is `NOT_ASSESSED`; do not infer recoverability. |
| Can protected data be decrypted? | Key reference, custodian/authority, access path, and key validity check | Backup with unavailable key is `FAILED` for the scenario. Never put a secret in the record. |
| Can the service operate after restore? | Isolated restore record plus an application-level task and access check | Catalogue-only or file-existence checks cannot claim application recovery. |
| Can the plan be used if primary systems are down? | Offline copy of instructions, authority contacts, protected secret references, and last review | Missing offline access is a recovery release block. |
| What happens if the first attempt fails? | Stop condition, last safe state, rollback/alternate point, owner, and verification | Preserve the failed target and return `PARTIAL` or `BLOCKED`; do not overwrite it. |

## Evidence lifecycle

1. State the user-visible business outcome and recovery owner.
2. Resolve the recovery point, key reference, dependencies, and authority before
   any restore action.
3. Test in an isolated target, including an older recovery point where the
   business objective requires it.
4. Run the application task and access verification separately from storage
   integrity checks.
5. Record each target's result, failed path, recovery decision, and evidence
   scope. Keep unknown, denied, and unavailable states explicit.

This reference does not authorise restore, mount, service, identity, DNS, or
credential operations. Current backup products, distro behaviour, and live
restore results are `NOT_ASSESSED` in the local fixture.

Validate the synthetic crosswalk and failure case with:

```powershell
python -X utf8 -m unittest tests/test_kaizen_contracts.py -v
```
