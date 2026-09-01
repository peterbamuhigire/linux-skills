# Current DNS operations and source gate

This reference separates durable DNS operating concepts from version-sensitive implementation detail. It is an independent synthesis of the supplied DNS, systems, improvement, and orchestration material.

## Durable operating model

Model the namespace, zones, delegation, authoritative service, recursive or forwarding path, caching, TTL, SOA serial, change ownership, monitoring, and recovery path. Test the actual baseline before changing configuration. Record the expected answer, authority, propagation boundary, and rollback condition.

## Safe change loop

For each change: define the user or service aim; capture a baseline; validate syntax and semantics; test authoritative and recursive paths; inspect logs and health; roll out in a bounded scope; monitor; and keep a reversible recovery path. Include dual-stack, split-horizon, delegation, negative caching, and DNSSEC implications where applicable.

## Currentness gate

Do not infer supported BIND versions, package names, directives, defaults, commands, operating-system paths, or security posture from older books. Verify current support and release status with ISC, protocol behaviour with the relevant IETF RFC, and distribution-specific packaging with the distribution's current official documentation. The portfolio register records the current sources admitted for this wave.

## Minimum evidence

Capture configuration-test output, authoritative queries, recursive queries, delegation checks, relevant logs, DNSSEC validation state when in scope, and before/after service health. Avoid destructive changes without an explicit maintenance boundary and rollback plan.
