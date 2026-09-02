# Book-driven Kaizen Wave 3: Linux application

Use this reference for Linux operations, scripts, services, networking, storage, monitoring,
security, backup, and recovery.

Owning skill: [Kaizen owner](../SKILL.md).

## Transfer controls

- Make scripts small, composable, explicit about shell dialect, inputs, outputs, exit status,
  signals, cleanup, logging, permissions, idempotence, and rollback. Prefer safe temporary
  resources, quoting, allowlists, and static analysis.
- Use UNIX internals as mental models for process identity, credentials, resource boundaries,
  concurrency, IPC, filesystems, memory, and failure propagation; validate behavior on the
  target distro and kernel rather than assuming implementation equivalence.
- Establish a read-only baseline, then one reversible change with a hypothesis, guardrail,
  stop rule, recovery proof, and re-audit. Test backups by restore, not by job completion.
- Verify HTTP, DNS, package, service, and security assumptions against current authorities and
  record observability sufficient to diagnose failed paths.

## Boundaries

The shell and UNIX books contain historical or unsafe patterns. Do not standardise unquoted
expansion, predictable temporary files, legacy HTTP scraping, broad kill commands, or copied
exploit material. Mark distro, vendor, kernel, and unavailable lab evidence `NOT_ASSESSED`.

## Measures and routing

Track failed-path coverage, shellcheck findings, idempotent rerun rate, restore success,
incident recurrence, toil, change failure, service SLOs, and time to diagnose. Route to the
relevant operational skill, security gate, recovery skill, and two-family validation.

## Currentness gate

Verify Bash and command behavior against current manuals and distro/vendor documentation;
record source/date/freshness/support/uncertainty and review triggers before execution.
