# Agent event review contract

Author: Peter Bamuhigire | techguypeter.com | +256 784 464 178

This contract turns a bounded operational event into a reviewable action while
keeping capture, aggregation, and reviewer decision separate. It applies to
synthetic agent events and does not replace the log-management access and
retention rules.

## Event identity and capture

Each event has a stable `event_id`, source locator, host/target identity,
occurred-at timestamp with timezone, severity, owner, and a bounded time
window. Capture records the raw event reference and redaction result. It does
not decide cause or remediation.

## Aggregation and review

Aggregation may deduplicate the same event identity but must retain `count`,
`first_seen`, `last_seen`, and all source locators needed to reproduce the
window. Reviewer output is a separate record with a decision (`investigate`,
`contain`, `repair`, `close`, or `unassessed`), rationale, owner, and next
verification. A count of one is different from an unobserved event.

Before export, redact secrets, tokens, private keys, and personal data while
retaining enough timestamp and context to locate the event. Error and trace
paths must never echo sensitive values. Retention basis and access owner are
required; unavailable logs or rotated periods are `NOT_ASSESSED`.

The synthetic seeded, duplicate, and redaction paths are checked by:

```powershell
python -X utf8 -m unittest tests/test_kaizen_contracts.py -v
```

No live journal, retention policy, or incident review was executed.
