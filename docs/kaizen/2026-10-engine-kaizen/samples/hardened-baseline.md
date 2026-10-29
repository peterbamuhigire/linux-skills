# Paired web-host hardening output

Date: 29 October 2026. Audience: experienced operator preparing a fresh Debian
or RHEL-family web host. Route: security-analysis → server-hardening with
webstack, mysql-mariadb, firewall-ssl and package-management.

## Target and execution boundary

Product: Nginx → PHP-FPM → Oracle MySQL, key-based administration, bounded
firewall, ACME TLS and automatic security updates. This is a complete change
plan, not evidence of applied production hardening. The request lacks a real
host, release, admin identity/subnet, public domain, recovery console, database
edition and maintenance window. Those missing inputs **block mutation**; do not
fill them with guessed hostnames or credentials. Lab `.example` names are only
for local fixtures and cannot demonstrate public ACME issuance.

Record `/etc/os-release`, package repository provenance and candidates,
`ss -lntp`, existing firewall, active MAC state, effective SSH settings and
application dependencies. Use the [dated currency review](../currency.md)
for release-specific channels; revalidate at change time. A Debian default
MariaDB metapackage is not evidence that Oracle MySQL is installed.

## Bounded sequence and family differences

| Step | Debian-family plan | RHEL-family plan | Acceptance / rollback |
|---|---|---|---|
| 1. Recovery | Snapshot supported VM/image and copy affected config with metadata; retain console and existing SSH session | Same; retain SELinux labels and relevant policy state | Prove console access and backup readability; stop without both |
| 2. Packages | Preview exact vendor-supported nginx, PHP-FPM and selected database packages with apt simulation | Preview selected streams/channels and packages using dnf assumeno | Reject unapproved repositories/removals; retain package/source/version manifest; compatible previous image is rollback |
| 3. SSH | Identify effective config/includes with `sshd -T`; provision operator key before disabling password paths | Same; privileged group usually wheel rather than sudo | Validate `sshd -t`, effective `-T -C` for real operator/context; new key session and sudo work before closing old access; restore saved config through console on failure |
| 4. Firewall | Preview UFW changes; allow actual admin source and actual SSH port first, then public HTTP/HTTPS; deny unsolicited inbound | Review active firewalld zone/interface and runtime/permanent difference; add scoped admin rule and HTTP/HTTPS | Verify from permitted and denied sources, including IPv6; keep timed recovery or console; restore captured rules if access fails |
| 5. Web/FPM | Discover installed FPM unit, pool socket and nginx worker identity; do not assume a PHP minor version | Common unit php-fpm, but verify actual package and pool; inspect SELinux type and denials | `nginx -t`, installed FPM config test, local body check and intended external request; restore prior vhost/pool/runtime as a unit |
| 6. Database | Confirm Oracle MySQL source and supported release explicitly; local socket/loopback listener, dedicated app user and bounded privileges | Confirm vendor stream/package and service name; same least-privilege design | Query server identity/listener and app login; deny unintended remote access; backup/restore verified separately before any version migration |
| 7. TLS/ACME | Confirm real public DNS A/AAAA and challenge path before Certbot staging validation; only then request production certificate | Same; packaging and timer/service names depend on chosen distribution | Check chain, names, expiry, HTTP redirect, renewal timer and staged renewal; preserve previous working cert/vhost, never disable validation to pass |
| 8. Security updates | Inspect actual unattended-upgrades origins/schedule and apt timers; enable approved security source policy | Inspect available dnf-automatic or dnf5 automatic implementation/timer and update policy | Verify timer, logs and selected security channel; define reboot ownership/window; disable only the introduced schedule and restore previous policy on regression |
| 9. MAC and files | Confirm AppArmor presence/enforcement rather than assuming distro defaults; least-permission app/secrets paths | Keep SELinux enforcing; fix evidenced labels/ports/booleans, never blanket permissive | Validate requests and audit denials; restore saved labels/policy, not a broad disable |
| 10. Handoff | Record package/config hashes, backups, service checks, external response, expiry/renewal monitoring and owner | Same | Separate applied/pass from NOT_ASSESSED; retain rollback and incident contacts |

## Required security decisions

Choose SSH authentication policy with the operator: disable password and
keyboard-interactive only if key-only access is intended and MFA does not depend
on keyboard-interactive. A high-numbered drop-in does not necessarily override an
earlier OpenSSH value. Confirm the effective result for each relevant Match
context, not only the default configuration.

Do not expose MySQL3306 to the internet for this topology. The actual app
connects through local socket/loopback; a remote database design requires a new
explicit source restriction and TLS plan. Do not hard-code one database vendor's
paths into the other. Verify backup encryption and restore without publishing keys.

Use current vendor fixes and the [security triage runbook](../../../security/current-vulnerability-triage.md)
for PHP/kernel/advisory findings. Updates already installed but not loaded by
the running process/kernel are not closed findings. Cached package output does
not establish current vulnerability status.

## Produced evidence and unresolved deployment

This output satisfies plan-level target, preconditions, sequence, family
branches, rollback and verification. It does not claim firewall enforcement,
SSH key login, ACME issuance/renewal, unattended-update execution or SELinux
behaviour was tested on a real host. Those require the missing target inputs
and an approved isolated VM followed by a separately controlled deployment.
The current 502 and database restore labs exercise their specific paths only.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
