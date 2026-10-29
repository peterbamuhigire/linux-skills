# Practitioner outputs before additional experiments

Date: 29 October 2026. Source: pristine baseline skills at `2ce755a`.
These are engine-guided outputs produced by the root practitioner, not another
model evaluation. Commands were inspected rather than executed on the host.

## Task 1 — requested hardened Debian and RHEL web host

Route: hub → security-analysis → server-hardening, webstack,
mysql-mariadb, firewall-ssl, package-management.

Output: establish distro/release, SSH admin identity/source subnet, independent
console, DNS name, ACME validation access, database product and maintenance
window before mutation. Back up configuration, apply one control at a time,
validate native configuration, verify a new SSH session, then close the old one.
The hardening reference offers SSH, UFW, sysctl, Nginx, PHP-FPM, database,
permissions, unattended upgrades, AppArmor, PAM, auditd and boot controls.
The RHEL matrix directs firewall changes to firewalld and MAC to SELinux.

Readiness verdict: **plan only**. No real target, public DNS, operator key or
recovery console was provided, so a production baseline cannot be applied.
Do not infer that `.example` fixture names can obtain public ACME certificates.
The current reference calls Ubuntu22.04/24.04 an Ubuntu/Debian version scope;
the database matrix equates Debian default-mysql-server with Oracle MySQL;
the body predominantly uses UFW. The skills name the right controls but do not
produce a verified paired stack from the supplied inputs.

## Task 2 — encrypted MySQL backup and second-instance restore

Route: hub → mysql-mariadb; archive-integrity and disaster-recovery for restore.
Output: mode600 credential/passphrase files, explicit backup directory and
rclone destination, single-transaction dumps, compressed GPG-encrypted artifact,
rotation, followed by decrypt/extract and import into a separate compatible
instance. Validate data and stored objects rather than merely checking exit0.

The baseline script was executed on synthetic MySQL8.4.13 data. Successful
backup exited0; a controlled GPG failure exited1 but retained a plaintext tar
archive at mode0644. The backup skill describes logical import but does not
connect this script's encrypted archive layout to a timed second-instance
restore. The failed artifact is a critical blocker; full redacted lab evidence
is retained with the mysql-lab samples.

## Task 3 — 502 after a PHP upgrade

Route: hub → webstack; service-management and troubleshooting as neighbours.
Output from the short debug block: inspect the last Nginx errors, query
`php8.3-fpm` and `apache2`, check `/run/php/php8.3-fpm.sock`, restart
`php8.3-fpm`. The general workflow says to trace the failing hop and stop without
a validator/rollback, but this concrete block jumps to restart as the fix.

Readiness verdict: **reject the restart step until the cause is evidenced**.
The incident gives no distro, current FPM unit/socket or logs. The correct next
output must branch on socket missing/refused, permission/MAC denial, timeout,
and application failure; record the pre-upgrade runtime and restore path.
A restart of a guessed version could worsen the outage or leave the wrong
socket configured. The repaired output and controlled lab are separate evidence.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
