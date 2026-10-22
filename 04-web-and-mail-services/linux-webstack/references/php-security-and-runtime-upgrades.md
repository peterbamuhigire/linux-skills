# PHP Security Patching and Runtime Upgrades

**Parent skill:** [linux-webstack](../SKILL.md)
**Also load:** [linux-package-management](../../../01-provisioning-and-bootstrap/linux-package-management/SKILL.md)
**Scope:** Debian/Ubuntu and RHEL-family PHP hosts; keep the installed serving branch patched, then stage and migrate applications to a newer minor branch.

## Operating rules

- Treat the 2026-10-21 PHP release as an emergency event: PHP maintainers rated both CVE-2026-109618 and CVE-2026-109619 **Critical, CVSS 4.0 9.2/10**, with remote code execution impact. Do not describe it as “the biggest vulnerability ever found”: the vendor advisories establish severity and impact, not a comparative historical superlative.
- Check the current vendor advisory and the package's vendor-fixed version immediately before acting. Linux vendors backport fixes, so compare the complete package version and advisory, not only `php -v` or upstream numbering.
- Patch the branch currently serving traffic first. Do not delay an available security fix for a framework migration.
- Inventory each execution context: web handler (Apache module, FPM, CGI/FastCGI), CLI, cron, queue/worker services, containers, admin tools, and every virtual host. CLI PHP does not establish which binary serves HTTP.
- Limit the package transaction to the affected installed packages after inspecting candidates, holds, sources, and a simulation. Do not add an unknown repository or bypass signature verification to make a candidate appear.
- State the host, branch, affected sites/services, maintenance impact, backup/recovery point, and health checks before mutation. Preserve the last known patched runtime for recovery; do not roll back to a vulnerable build.
- Restart every affected long-lived PHP process after patching or cutover. Restart named worker units discovered during inventory; never guess service names. If a service list is overwhelming, collect and review it before the change, then enter only confirmed PHP workers or explicitly skip workers that do not exist.

## 1. Baseline and inventory

Record the OS release, installed packages and full versions, package holds, repository origins, active service units, enabled Apache modules/vhosts, Nginx upstreams, FPM pools/sockets, containers/images, cron definitions, and worker units. Inspect configuration locally because it can contain secrets.

Representative read-only commands (use only those for the detected family):

```bash
# Debian/Ubuntu
cat /etc/os-release
dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Status}\n' 'php*' 'libapache2-mod-php*'
apt-mark showhold
apt-cache policy php8.3-common php8.3-cli php8.3-fpm libapache2-mod-php8.3
systemctl list-units --type=service --all 'php*-fpm.service'
apache2ctl -M
apache2ctl -S
nginx -T

# RHEL family
cat /etc/os-release
rpm -qa 'php*' | sort
dnf repolist --enabled
dnf list --showduplicates 'php*'
systemctl list-units --type=service --all 'php-fpm.service'
httpd -M
httpd -S
nginx -T
```

Do not dump full Nginx/Apache configuration into tickets or chat; inspect it locally and redact secrets. For containers, inspect the image digest and PHP version inside each running container. For web sites, trace the public listener through every proxy to the PHP handler.

## 2. Apply an emergency branch patch

1. Read the official advisory for the actual OS release and identify the vendor-fixed package revisions. Confirm the candidate comes from the signed expected security/update repository. A missing or stale candidate means stop and repair repository metadata or investigate holds/pinning; it does not justify using an unverified source.
2. Capture a package/version list and back up relevant PHP, web-server, FPM-pool and vhost configuration. Confirm the database and application recovery process when the maintenance could affect business operations.
3. Preview the narrow package operation and review removals, new sources, dependency changes and held packages. On Debian/Ubuntu, for packages already installed in the target branch:

   ```bash
   sudo apt update
   apt-cache policy php8.3-common php8.3-cli php8.3-fpm libapache2-mod-php8.3
   sudo apt-get --simulate install --only-upgrade <installed-php-packages-for-this-branch>
   ```

   Replace the example branch and package list with the inventoried packages. Do not copy the example branch blindly. If the simulation removes packages or changes an unexpected runtime/repository, stop.

4. After the operator has reviewed the exact simulation, apply the scoped update and enter any confirmation phrase only at the script's own prompt. A phrase printed by a script is input to that prompt, not a shell command. Package operations and handler restarts can briefly affect all sites sharing the runtime.
5. On RHEL, use the same sequence with the supported `dnf` update channel: inspect enabled repositories and candidate versions, preview the exact installed PHP packages with `dnf upgrade --assumeno <packages>`, then apply only the reviewed transaction. Do not substitute a module stream or third-party repository without checking vendor support, stream conflicts and the complete transaction.
6. Update each container image separately, pin the intended image/tag or digest, rebuild, and roll out through the container deployment process. A host package update does not patch PHP inside a container.

## 3. Restart and verify the fixed runtime

Validate each changed configuration before restarting: `apache2ctl configtest` or `httpd -t`, `nginx -t` when its configuration changed, and the branch-appropriate `php-fpm -t`. Then restart the active serving handlers so old workers cannot remain resident. Use the family-correct unit names from the inventory; a graceful reload is only sufficient when it demonstrably replaces every old PHP worker. Restart confirmed queue/cron/worker processes as well.

Collect evidence for all of the following:

- Installed PHP package versions meet the vendor advisory's fixed baseline; candidates and origins are recorded.
- CLI and extension inventory match the intended runtime.
- Apache/Nginx/FPM configuration checks pass; active services and sockets/listeners are healthy.
- Web requests reach the expected runtime and application through the real proxy path. Use a protected existing diagnostic or a temporary access-restricted endpoint returning only `PHP_VERSION` and `PHP_SAPI`; remove it immediately. Do not publish `phpinfo()` or leave a version endpoint exposed.
- Representative authenticated application flows, logs, uploads, database access, scheduled jobs and queues work. Test transactions with staging/safe records.
- No old PHP worker or container image remains in service. Record any worker or site not checked as `NOT ASSESSED`.
- Check the operating system's reboot-required indicator; a PHP-only update normally does not itself require a reboot, but follow the package/vendor signal.

An installed package version plus an active unit is good evidence, but does not prove every site uses that unit. Trace the real request path and verify a web-executed response.

## If patching is temporarily impossible

First restrict public access at the edge or isolate the affected application until it can be patched. An application-level maintenance check may run too late for a runtime flaw. Do not treat WAF rules, login checks, memory limits, worker recycling or suppressed diagnostics as a complete fix.

The PHP advisories describe limited configuration mitigations for specific exploit paths: disabling `session.upload_progress.enabled` can remove a demonstrated stale-state path; on PHP 8.5, `fatal_error_backtraces=0` removes one demonstrated producer; setting `memory_limit=-1` can remove one predictable OOM trigger for CVE-2026-109618. These do not cover all paths. **Do not globally disable PHP memory limits on a shared production host**: this can create resource-exhaustion outages. Apply any interim change only after reviewing the exact advisory, site scope and resource controls, restart all affected workers, and continue to patch as the only complete mitigation. Request-size limits and reduced input complexity are additional risk-reduction measures, not substitutes for the fixed package. Absence of a suspicious log entry does not prove the system was not vulnerable or exploited.

## 4. Stage a newer PHP branch, including PHP 8.5

Keep emergency patching and application migration as separate changes. PHP 8.5 should be installed side by side in an isolated staging runtime using one of:

1. The operating-system vendor's signed repository, when that OS release provides a supported PHP 8.5 package set.
2. A vetted, signed vendor repository that explicitly supports the OS release and PHP branch, after reviewing its signing-key provenance, package origin, pinning, dependency transaction and removal path.
3. An isolated, maintained container image from a verified publisher, with a locked image digest and reviewed PHP modules/configuration.

Do not solve “package unavailable” by blindly upgrading the host OS, adding a PPA/repository, compiling arbitrary source, changing the global `php` alternative, or replacing all FPM sockets. If no trusted source supports side-by-side staging on the current OS, choose an isolated staging host/container or schedule an OS migration as its own reviewed project. Keep the current patched branch serving production until compatibility and health gates pass.

For a shared host, prefer a separate FPM pool/socket per branch and change one explicitly selected virtual host at a time. For Apache `mod_php`, plan a tested per-site switch to FPM or another isolated handler; do not switch the shared Apache module globally when that would affect unrelated sites. Keep the previous patched handler configured for rapid reversion.

## 5. Cut over one application at a time

Before staging, record PHP/framework/dependency constraints, extensions and versions, INI settings, FPM pool settings, OPcache behaviour, worker commands, cron jobs, image/build configuration, and a health/rollback owner. Under the target interpreter:

```bash
php -v
php --ini
php -m
composer validate --strict
composer prohibits php 8.5
composer check-platform-reqs
composer audit
```

`composer prohibits php 8.5` identifies dependency constraints; it does not prove runtime compatibility. Run Composer with the actual target PHP binary and environment. Keep `composer.lock` stable during initial validation; if dependency updates are necessary, resolve them in a branch, review the lockfile diff and deploy that reviewed lockfile. Never bypass platform requirements to force a cutover.

Read the PHP migration guides from the application's current version through each intervening minor release, then the target guide. Run the application's test suite, static analysis and framework checks under PHP 8.5 with production-equivalent extensions and INI settings. Exercise authentication/session renewal, database procedures and transactions, file/PDF/image handling, uploads, HTTP integrations, scheduled work, queues, and any security-sensitive flows. Confirm error reporting, logs, memory/time limits and OPcache configuration.

Promote to one low-risk site first. Validate config, switch only its vhost/socket, check an authenticated request and critical user flows, inspect logs/latency/error rates, and restart its PHP workers. If a gate fails, switch that site to the previous **patched** runtime and preserve logs; do not revert to an unpatched release. Expand site by site after the observation window passes.

## 6. Interactive operator prompt design

For reusable interactive scripts, keep each confirmation adjacent to the action it authorizes. Clearly distinguish shell commands from phrases entered at a running program's `>` prompt. Show the affected hosts/sites/services, package plan, interruption risk and recovery record before the final apply prompt. When an optional worker-service prompt is difficult to answer, allow a blank response to skip, state which automatically managed services were restarted, and report the remaining worker inventory as an operator follow-up. Never silently assume worker names or restart unrelated services.

## Currentness and examples

Version facts below are examples captured on **2026-10-22** and must be rechecked against the exact host's official vendor advisory before use:

| Claim ID / scope | Source ID; publication or version date | Access / verification date; freshness | Support status; confidence and uncertainty | Owner; review date |
|---|---|---|---|---|
| PHPSEC-001: both CVEs are Critical RCE advisories, CVSS 4.0 9.2/10; “biggest ever” is not a sourced comparative claim | PHP-GHSA-001 and PHP-GHSA-002 (Tier 1 primary); published 2026-10-21 | 2026-10-22 / 2026-10-22; incident-specific | Supported by two upstream project advisories; high confidence for severity, unsupported as superlative; affected paths differ by SAPI | Linux webstack maintainer; recheck for incident response |
| PHPSEC-002: Ubuntu 24.04 Noble fix is `8.3.6-0ubuntu0.24.04.13` | Ubuntu-USN-8948-1 (Tier 1 primary); published 2026-10-21 | 2026-10-22 / 2026-10-22; time-sensitive | Canonical identifies fixed Noble packages; high confidence; verify host source and all installed handlers | Linux package maintainer; before each patch |
| PHPSEC-003: Debian 13 Trixie fix is `8.4.27-1~deb13u1` | Debian-DSA-6574-1 (Tier 1 primary); published 2026-10-21 | 2026-10-22 / 2026-10-22; time-sensitive | Debian Security Team identifies fixed package; high confidence; verify host candidate/source | Linux package maintainer; before each patch |
| PHPSEC-004: USN-8948-1 lists PHP 8.5 for Ubuntu 26.04/26.10 and PHP 8.3 for Noble | Ubuntu-USN-8948-1 (Tier 1 primary); published 2026-10-21 | 2026-10-22 / 2026-10-22; release-bound | High confidence for advisory package matrix; does not assert future Noble repository state | Linux package maintainer; before repository/OS choice |
| PHPSEC-005: PHP 8.5.12 is upstream stable | PHP-downloads (Tier 1 primary); released 2026-10-21 | 2026-10-22 / 2026-10-22; volatile | Official upstream release; high confidence; distro package, extension and support status may differ | PHP skills maintainer; before staging |
| PHPSEC-006: migration guide lists incompatibilities; Composer platform check uses real PHP/extensions | PHP-migration-85 and Composer-CLI (Tier 1 primary); current versions accessed 2026-10-22 | 2026-10-22 / 2026-10-22; version/tool dependent | Official docs support procedure; high confidence; runtime tests still required and commands vary by Composer release | PHP skills maintainer; each migration |
| PHPSEC-007: APT supports simulation/only-upgrade and DNF supports `--assumeno` with package specs | APT-manpage-bookworm and DNF-command-reference-stable (Tier 1 primary); versions accessed 2026-10-22 | 2026-10-22 / 2026-10-22; CLI-version dependent | Official manuals support syntax; installed release and host policy determine transaction | Linux package maintainer; before using command |
| PHPSEC-008: the fixed PHP release is the complete mitigation; configuration workarounds cover only specific demonstrated paths | PHP-GHSA-001 and PHP-GHSA-002 (Tier 1 primary); published 2026-10-21 | 2026-10-22 / 2026-10-22; incident-specific | Direct upstream advisory; high confidence; specific reachability depends on SAPI and configuration | Linux security maintainer; recheck before relying on any interim measure |

**Research route:** The local Digital Research Engine checkout was unavailable, so its current `source-evaluation`, `source-verification`, and Kaizen currentness gate were retrieved from the canonical public repository on 2026-10-22. Primary sources were opened and claim text/version numbers checked. Claim/source/date/freshness/support/uncertainty evidence is recorded above; source-tier metadata-manifest replay and local-engine execution remain `NOT ASSESSED`.

## Primary references

- [PHP GHSA-w8hw-w9fx-j79w: RCE via OOM corruption](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
- [PHP GHSA-6wmf-4rv5-p3rp: RCE via stale global state](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp)
- [APT `apt-get` manual](https://manpages.debian.org/bookworm/apt/apt-get.8)
- [DNF command reference](https://dnf.readthedocs.io/en/stable/command_ref.html)
- [Ubuntu USN-8948-1: PHP vulnerabilities](https://ubuntu.com/security/notices/USN-8948-1)
- [Debian DSA-6574-1: php8.4 security update](https://lists.debian.org/debian-security-announce/2026/msg00489.html)
- [Debian PHP 8.4 security tracker](https://security-tracker.debian.org/tracker/source-package/php8.4)
- [PHP supported versions](https://www.php.net/supported-versions.php)
- [PHP downloads](https://www.php.net/downloads.php)
- [PHP 8.5 migration guide](https://www.php.net/manual/en/migration85.php)
- [Composer CLI: validate, prohibits and check-platform-reqs](https://getcomposer.org/doc/03-cli.md)
- [Composer runtime platform check](https://getcomposer.org/doc/07-runtime.md)
