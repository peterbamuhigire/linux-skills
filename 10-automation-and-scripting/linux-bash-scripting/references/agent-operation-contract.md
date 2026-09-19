# Agent operation and scheduling contract

Author: Peter Bamuhigire | techguypeter.com | +256 784 464 178

This reference defines the plan boundary for a scheduled agent operation. It
extends the Bash scripting safety contract without granting authority to run a
host command. The examples in `tests/fixtures/kaizen/` are fictional and
read-only.

## Contract version and evidence boundary

The contract version is `linux-agent-operation-v1`. Book B33 supplies durable
questions about scripting and periodic processes; it is historical context, not
current distro or production evidence. Current runtime support, host access,
and scheduler behaviour remain `NOT_ASSESSED` until an approved lab exercises
them.

## Plan input

An operation plan must identify all of the following before execution is
considered:

| Field | Required rule |
|---|---|
| `target` | Kind, canonical name, and stable fingerprint. Missing or ambiguous identity is blocked. |
| `principal` | Actor or service identity and authority scope. Do not infer privilege. |
| `resource` | Canonical resource/path plus an allowed root. Resolve and reject path escape before opening anything. |
| `action` | One bounded operation with an explicit side-effect budget and stop condition. |
| `schedule` | Unique trigger ID, timezone, due time, and missed-run policy (`skip`, `run-once`, or `block`). |
| `preconditions` | Required state, source/version, and the independent acceptance oracle. |

The scheduler must reject duplicate trigger IDs, invalid targets, missing
timezone or missed-run semantics, and an unknown runtime. A plan is not an
execution result.

## Result and recovery output

Execution, when separately authorised, returns a machine-readable result with:

- `status`: `SUCCEEDED`, `NO_CHANGE`, `FAILED`, `PARTIAL`, `BLOCKED`, or
  `NOT_ASSESSED`;
- `native_exit_code`, when a native process actually ran;
- `before`, `after`, and `verification` evidence, kept separate from display
  formatting;
- `rollback`: trigger, last safe state, action, and verification; and
- `evidence`: source scope, observation time, redaction status, and reviewer.

Partial output retains each target/result record. A zero native exit code does
not establish the user-visible outcome. Missing target, denied authority,
unknown runtime, or failed verification stops the operation and preserves the
last safe plan.

## Scheduling and side-effect rules

Planning and validation are pure. Only the separately approved execution
boundary may contact a scheduler or host. A missed run follows the declared
policy and never silently replays a duplicate trigger. A rollback is a new
bounded operation with its own target, authority, verification, and evidence.

Validate the synthetic normal and failure paths with:

```powershell
python -X utf8 -m unittest tests/test_kaizen_contracts.py -v
```

The test proves contract shape and fixture decisions only; host scheduling,
privilege, distro execution, and recovery are `NOT_ASSESSED`.
