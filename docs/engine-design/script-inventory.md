# linux-skills script inventory

Version 1.0 — 2026-04-10
**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

The curated catalogue of every script this engine will ship. **88 scripts**
grouped into 3 priority tiers and 12 themes. Ranked by importance: tier 1 is
the minimum viable toolkit, tier 3 is specialized.

Every script listed here must obey [`spec.md`](spec.md) — standard flags,
`common.sh` library, the six-section template, safety rules.

Status legend:
- **core=yes** → installed by `install-skills-bin core` during initial setup.
- **core=no** → lazy-installed by `install-skills-bin <skill>` on first use.
- **[EXIST]** → already in `scripts/`, needs rename/refactor to match spec.
- **[NEW]** → to be written next session.

Sources: `PB`=Pro Bash · `SSB`=Shell Scripting Bible · `WCS`=Wicked Cool Shell
Scripts · `VK`=Vickler · `BT`=Beginner Terminal · `USG`=Ubuntu Server Guide
(Canonical) · `NAG`=Network Admin Guide · `MSA`=Modern Sysadmin 2020s ·
`MU`=Mastering Ubuntu · `EX`=existing repo.

---

## Tier 1 — Foundation (core install, 15 scripts)

These ship on every server via `install-skills-bin core`. They cover the
day-one questions every operator asks: is this server secure, healthy, up to
date, backed up, and what's running on it?

| # | Script | Skill | Core? | Status | Purpose | Source |
|---|---|---|---|---|---|---|
| 1 | `sk-audit` | linux-security-analysis | yes | [EXIST] | Read-only 14-section security audit producing PASS/WARN/FAIL report with score. | EX |
| 2 | `sk-update-all-repos` | linux-site-deployment | yes | [EXIST] | Pull all registered repos on this server; interactive menu + `all`. | EX |
| 3 | `sk-new-script` | linux-bash-scripting | yes | [NEW] | Scaffold a new `sk-*` script from the canonical template in a skill's `scripts/` dir. | PB |
| 4 | `sk-lint` | linux-bash-scripting | yes | [NEW] | Run `shellcheck` + custom engine checks (standard flags, `common.sh` sourced, no `set -e` footguns) on a script. | PB |
| 5 | `sk-system-health` | linux-system-monitoring | yes | [NEW] | One-screen snapshot: load, CPU, mem, swap, disk, top 5 processes, uptime. | VK, MU |
| 6 | `sk-disk-hogs` | linux-disk-storage | yes | [NEW] | Top 20 directories/files by size under a path; warns on `/var/log` and `/tmp` bloat. | WCS, SSB |
| 7 | `sk-open-ports` | linux-system-monitoring | yes | [NEW] | `ss -tulnp` pretty output with per-port risk notes (e.g. MySQL on 0.0.0.0 flagged). | SSB, NAG |
| 8 | `sk-service-health` | linux-service-management | yes | [NEW] | Show state, last 20 journal lines, recent restart count, and failed dependencies for a systemd service. | MU |
| 9 | `sk-cert-status` | linux-firewall-ssl | yes | [NEW] | List all certbot certs, days-to-expiry, domains covered, renewal timer state. | EX (partial in sk-audit) |
| 10 | `sk-cron-audit` | linux-service-management | yes | [NEW] | Enumerate all user + system crontabs, verify `MAILTO`, flag jobs that haven't run recently, validate syntax. | SSB, WCS |
| 11 | `sk-user-audit` | linux-access-control | yes | [NEW] | All users, UID/GID, lock state, password age, last login, sudoers. | SSB |
| 12 | `sk-ssh-key-audit` | linux-access-control | yes | [NEW] | All `authorized_keys` across users, key type/age/comment, orphaned keys. | NAG |
| 13 | `sk-fail2ban-status` | linux-intrusion-detection | yes | [NEW] | Jails, active bans, total bans by jail, recent blocks with geo hints. | EX (partial in sk-audit) |
| 14 | `sk-journal-errors` | linux-log-management | yes | [NEW] | Last 24h of `priority<=err` from journal, grouped by service, with counts. | MU |
| 15 | `sk-backup-verify` | linux-disaster-recovery | yes | [NEW] | Verify last backup age, integrity (tar/gpg check), remote copy reachable via rclone. | MSA |

---

## Tier 2 — Workhorse (lazy-install per skill, 46 scripts)

These are installed when their skill is first used on a server. They cover the
daily/weekly operational work: hardening, adding users, deploying sites,
backups, database ops, troubleshooting.

### Theme A — Hardening & access control (11 scripts)

| # | Script | Skill | Status | Purpose | Source |
|---|---|---|---|---|---|
| 16 | `sk-harden-ssh` | linux-server-hardening | [NEW] | Apply SSH hardening: disable root, password auth off, `MaxAuthTries=3`, banner, backup original first. | MU |
| 17 | `sk-harden-sysctl` | linux-server-hardening | [NEW] | Write `/etc/sysctl.d/99-linux-skills.conf` with ASLR, SYN cookies, rp_filter, icmp ignore_bogus. | EX (sk-audit detects), USG |
| 18 | `sk-harden-php` | linux-server-hardening | [NEW] | Apply PHP hardening: `expose_php=off`, `display_errors=off`, `disable_functions`, session flags. | EX (sk-audit detects) |
| 19 | `sk-ufw-reset` | linux-firewall-ssl | [NEW] | Interactive UFW wizard: pick profile (web server / bastion / db / custom), apply, enable. | USG |
| 20 | `sk-ufw-audit` | linux-firewall-ssl | [NEW] | Diff active UFW rules against a baseline file; flag drift. | USG |
| 21 | `sk-cert-renew` | linux-firewall-ssl | [NEW] | Force certbot renewal for one or all domains, reload nginx/apache on success. | EX |
| 22 | `sk-apparmor-status` | linux-security-analysis | [NEW] | List all profiles with enforce/complain/disabled status, recent denials from audit.log. | USG |
| 23 | `sk-new-sudoer` | linux-access-control | [NEW] | Create user, deploy SSH key from clipboard/URL/file, add to sudo group, verify with `sudo -l`. | WCS |
| 24 | `sk-user-suspend` | linux-access-control | [NEW] | Lock or unlock a user account (passwd -l, usermod -s /usr/sbin/nologin), with audit log. | WCS |
| 25 | `sk-file-integrity-init` | linux-intrusion-detection | [NEW] | Initialize AIDE database, verify baseline, install nightly cron. | USG |
| 26 | `sk-file-integrity-check` | linux-intrusion-detection | [NEW] | Run AIDE check, summarize changes, classify (config/log/binary), alert on binary drift. | USG |

### Theme B — Web stack & site deployment (10 scripts)

| # | Script | Skill | Status | Purpose | Source |
|---|---|---|---|---|---|
| 27 | `sk-nginx-new-site` | linux-site-deployment | [NEW] | Generate Nginx vhost from template, request cert via certbot, reload. Prompts for domain/root/php version. | MU |
| 28 | `sk-nginx-test-reload` | linux-webstack | [NEW] | `nginx -t` then graceful reload; shows config summary and what changed since last reload. | MU |
| 29 | `sk-apache-new-site` | linux-site-deployment | [NEW] | Same as sk-nginx-new-site but for Apache (a2ensite, certbot, reload). | MU |
| 30 | `sk-apache-test-reload` | linux-webstack | [NEW] | `apache2ctl configtest` then graceful reload. | MU |
| 31 | `sk-php-fpm-pool` | linux-webstack | [NEW] | Generate a PHP-FPM pool for a site (socket, user, pm settings), enable, restart. | MU |
| 32 | `sk-astro-deploy` | linux-site-deployment | [NEW] | Clone an Astro site, install deps, build, set up Nginx vhost + SSL, register in `update-all-repos`. | EX (notes/astro-site-setup.md) |
| 33 | `sk-php-site-deploy` | linux-site-deployment | [NEW] | Clone a PHP site, set ownership, configure vhost, SSL, register in `update-all-repos`. | MU |
| 34 | `sk-static-site-deploy` | linux-site-deployment | [NEW] | Clone a static site, configure vhost, SSL, register in `update-all-repos`. | EX |
| 35 | `sk-access-log-report` | linux-log-management | [NEW] | Parse Nginx/Apache access logs: top IPs, status code histogram, top URLs, bot ratio. | WCS |
| 36 | `sk-error-log-report` | linux-log-management | [NEW] | Parse error logs: group by repeated message, severity, timeline. | WCS |

### Theme C — Databases & backups (9 scripts)

| # | Script | Skill | Status | Purpose | Source |
|---|---|---|---|---|---|
| 37 | `sk-mysql-backup` | linux-disaster-recovery | [EXIST] | Dump all databases with gzip + gpg + rclone upload. Rotate local/remote. | EX |
| 38 | `sk-mysql-restore` | linux-disaster-recovery | [NEW] | Guided restore: list backups, pick, download, decrypt, show sizes, confirm, restore. | EX |
| 39 | `sk-mysql-tune` | linux-webstack | [NEW] | Analyze `my.cnf` + runtime variables, suggest improvements (innodb_buffer_pool_size, etc.). Non-destructive. | MU |
| 40 | `sk-mysql-user-audit` | linux-webstack | [NEW] | Show MySQL users, hosts, grants; flag anonymous, `%` hosts, users with too many privileges. | EX (sk-audit touches) |
| 41 | `sk-postgres-backup` | linux-disaster-recovery | [NEW] | `pg_dump` + compression + gpg + rclone, per database or all, with rotation. | NAG |
| 42 | `sk-postgres-restore` | linux-disaster-recovery | [NEW] | Guided restore from backup file or remote. | NAG |
| 43 | `sk-site-backup` | linux-disaster-recovery | [NEW] | Tar a full site directory, exclude cache/node_modules, gpg, upload via rclone. | WCS |
| 44 | `sk-site-restore` | linux-disaster-recovery | [NEW] | Restore a site backup to original path with permission repair. | WCS |
| 45 | `sk-config-snapshot` | linux-disaster-recovery | [NEW] | Snapshot `/etc/` (and other declared dirs) to a git-tracked archive; diff against previous. | MSA |

### Theme D — Services, disk, troubleshooting (11 scripts)

| # | Script | Skill | Status | Purpose | Source |
|---|---|---|---|---|---|
| 46 | `sk-service-restart` | linux-service-management | [NEW] | Safe restart: check health before, restart, wait, verify, show logs. Rollback hint on failure. | MU |
| 47 | `sk-timer-list` | linux-service-management | [NEW] | All systemd timers with next and last run, unit, state; flags timers that never fired. | USG |
| 48 | `sk-disk-cleanup` | linux-disk-storage | [NEW] | Interactive cleanup: apt cache, journal, old logs, kernel images, tmp. Shows bytes reclaimed. | WCS |
| 49 | `sk-inode-check` | linux-disk-storage | [NEW] | Find filesystems nearing inode exhaustion; top directories by inode count. | SSB |
| 50 | `sk-swap-check` | linux-system-monitoring | [NEW] | Swap usage, swappiness, top swap consumers, reccomend adjustments. | VK |
| 51 | `sk-load-investigate` | linux-troubleshooting | [NEW] | Decompose load average: CPU-bound vs I/O-bound vs blocked, top offenders per category. | VK |
| 52 | `sk-why-slow` | linux-troubleshooting | [NEW] | Decision-tree entry point: walks through load/CPU/memory/disk/network/database to diagnose slowness. | MU |
| 53 | `sk-why-500` | linux-troubleshooting | [NEW] | Decision-tree: PHP-FPM up? Nginx up? error log? permissions? SELinux/AppArmor? disk full? | WCS |
| 54 | `sk-why-cant-connect` | linux-troubleshooting | [NEW] | Decision-tree: firewall? service listening? DNS? routing? cert expired? rate-limited by fail2ban? | NAG |
| 55 | `sk-journal-tail` | linux-log-management | [NEW] | Wrapper over `journalctl -f` with unit filter, severity filter, since-time shorthand, color. | MU |
| 56 | `sk-logrotate-check` | linux-log-management | [NEW] | Verify logrotate configs, show last rotation per config, warn on stale or mis-sized logs. | WCS |

### Theme E — Provisioning & package management (5 scripts)

| # | Script | Skill | Status | Purpose | Source |
|---|---|---|---|---|---|
| 57 | `sk-provision-fresh` | linux-server-provisioning | [NEW] | Guided fresh-server wizard: hostname, timezone, admin user, SSH, UFW, fail2ban, unattended-upgrades, certbot, linux-skills clone. | USG, MU |
| 58 | `sk-apt-update-safe` | linux-package-management | [NEW] | `apt update` + `apt list --upgradable` with held-back detection and security-only mode. | MU |
| 59 | `sk-apt-upgrade-safe` | linux-package-management | [NEW] | Pre-snapshot /etc, run `apt full-upgrade`, log changed packages, warn on kernel updates. | MSA |
| 60 | `sk-unattended-status` | linux-package-management | [NEW] | Show unattended-upgrades config, last run, next scheduled, recent reboots required. | MU |
| 61 | `sk-snap-audit` | linux-package-management | [NEW] | List snaps with revision, refresh date, auto-update state; flag stale revisions. | USG |

---

## Tier 3 — Specialized (install per skill only when needed, 27 scripts)

These are only installed on servers that actually need them — a web-only
server won't install the mail or DNS scripts, etc.

### Theme F — Networking (5 scripts)

| # | Script | Skill | Status | Purpose | Source |
|---|---|---|---|---|---|
| 62 | `sk-net-status` | linux-network-admin | [NEW] | All interfaces, addresses, routes, default gateway, DNS servers, listening ports in one report. | NAG, USG |
| 63 | `sk-netplan-apply` | linux-network-admin | [NEW] | Validate netplan YAML, `netplan try` with timeout, `netplan apply` on confirm, rollback on timeout. | USG |
| 64 | `sk-port-check` | linux-network-admin | [NEW] | Test TCP/UDP port from localhost and (if given) from an external reflector; show path with traceroute. | NAG |
| 65 | `sk-dns-check` | linux-network-admin | [NEW] | Forward + reverse lookup for a domain, compare with /etc/hosts, test from local resolver and public (1.1.1.1). | NAG |
| 66 | `sk-ntp-sync` | linux-network-admin | [NEW] | chrony/systemd-timesyncd sync state, offset from upstream, peer list. | NAG |

### Theme G — DNS server (2 scripts)

| # | Script | Skill | Status | Purpose | Source |
|---|---|---|---|---|---|
| 67 | `sk-dns-zone-check` | linux-dns-server | [NEW] | Validate a BIND zone file (`named-checkzone`), dump current SOA/NS/A/MX, diff against previous. | NAG |
| 68 | `sk-bind-reload` | linux-dns-server | [NEW] | `named-checkconf`, `named-checkzone` for each zone, `rndc reload`, verify serial bumped. | NAG |

### Theme H — Mail server (4 scripts)

| # | Script | Skill | Status | Purpose | Source |
|---|---|---|---|---|---|
| 69 | `sk-mx-check` | linux-mail-server | [NEW] | MX records for domain, preference order, reverse DNS, reachability, TLS cert. | NAG |
| 70 | `sk-spf-dkim-dmarc` | linux-mail-server | [NEW] | Audit SPF, DKIM, DMARC records for a domain; report missing/misaligned. | NAG |
| 71 | `sk-mail-queue` | linux-mail-server | [NEW] | Postfix/Exim queue inspection: depth, oldest, stuck, by recipient domain. | NAG |
| 72 | `sk-smtp-test` | linux-mail-server | [NEW] | EHLO/STARTTLS/auth/mail-from/rcpt-to test against a remote SMTP; reports each step. | NAG |

### Theme I — Virtualization (4 scripts)

| # | Script | Skill | Status | Purpose | Source |
|---|---|---|---|---|---|
| 73 | `sk-lxd-list` | linux-virtualization | [NEW] | All containers with state, IPs, memory, disk, uptime. | USG |
| 74 | `sk-lxd-snapshot` | linux-virtualization | [NEW] | Create / list / restore LXD container snapshots with naming convention. | USG |
| 75 | `sk-lxd-backup` | linux-virtualization | [NEW] | Full LXD container export to tar, with restore metadata. | USG |
| 76 | `sk-docker-inspect` | linux-virtualization | [NEW] | Containers, images, volumes, networks, health status, disk usage. | MU |

### Theme J — Cloud-init & autoinstall (2 scripts)

| # | Script | Skill | Status | Purpose | Source |
|---|---|---|---|---|---|
| 77 | `sk-cloud-init-validate` | linux-cloud-init | [NEW] | Validate cloud-init user-data YAML (schema, module list), optional dry render. | USG |
| 78 | `sk-cloud-init-debug` | linux-cloud-init | [NEW] | Extract /var/log/cloud-init*.log errors, module pass/fail, timeline of the boot run. | USG |

### Theme K — Config management & observability (6 scripts)

| # | Script | Skill | Status | Purpose | Source |
|---|---|---|---|---|---|
| 79 | `sk-drift-check` | linux-config-management | [NEW] | Compare key config files and package lists against the git-tracked declared state; report drift. | MSA |
| 80 | `sk-ansible-dry-run` | linux-config-management | [NEW] | Run an Ansible playbook in check mode against localhost with nice summary of changes. | MSA |
| 81 | `sk-etc-track` | linux-config-management | [NEW] | Verify /etc is clean against a git snapshot; optionally auto-stage + commit. | MSA |
| 82 | `sk-node-exporter-install` | linux-observability | [NEW] | Install Prometheus node_exporter as systemd service, expose on localhost, register firewall rule. | MSA |
| 83 | `sk-health-endpoint` | linux-observability | [NEW] | Create/verify a standard `/health` endpoint for a vhost: checks db, disk, services, returns JSON. | MSA |
| 84 | `sk-log-forward-setup` | linux-observability | [NEW] | Configure rsyslog/fluent-bit to forward to a central collector with TLS. | MSA |

### Theme L — Secrets & disaster recovery (4 scripts)

| # | Script | Skill | Status | Purpose | Source |
|---|---|---|---|---|---|
| 85 | `sk-secret-scan` | linux-secrets | [NEW] | Scan a repo or filesystem path for credentials, API keys, private keys using trufflehog-style rules. | MSA |
| 86 | `sk-secret-rotate` | linux-secrets | [NEW] | Rotate a managed credential file, update dependent services, verify before and after. | MSA |
| 87 | `sk-restore-wizard` | linux-disaster-recovery | [NEW] | Interactive guided restore: pick backup set, pick restore target, preview, confirm, execute. | EX |
| 88 | `sk-emergency-mode` | linux-disaster-recovery | [NEW] | Toggle maintenance mode: drop Nginx to 503 page, stop non-essential services, show live status. | MU |

---

## Themes at a glance

| Theme | Tier 1 | Tier 2 | Tier 3 | Total |
|---|---:|---:|---:|---:|
| Foundation (health, audit, essentials) | 15 | 0 | 0 | 15 |
| Hardening & access control | 0 | 11 | 0 | 11 |
| Web stack & site deployment | 0 | 10 | 0 | 10 |
| Databases & backups | 0 | 9 | 0 | 9 |
| Services, disk, troubleshooting | 0 | 11 | 0 | 11 |
| Provisioning & packages | 0 | 5 | 0 | 5 |
| Networking | 0 | 0 | 5 | 5 |
| DNS server | 0 | 0 | 2 | 2 |
| Mail server | 0 | 0 | 4 | 4 |
| Virtualization | 0 | 0 | 4 | 4 |
| Cloud-init | 0 | 0 | 2 | 2 |
| Config mgmt & observability | 0 | 0 | 6 | 6 |
| Secrets & DR | 0 | 0 | 4 | 4 |
| **Total** | **15** | **46** | **27** | **88** |

## Build order for next session

Build in tier order. Within a tier, build by theme to keep context coherent.

1. **Foundation first** — `common.sh`, `install-skills-bin`, then tier 1 in
   numerical order (starting with migrating existing `server-audit.sh` →
   `sk-audit`).
2. **Workhorse next** — tier 2 theme by theme. Each theme ends with a
   shellcheck + dry-run smoke test before moving on.
3. **Specialized last** — tier 3 only after tier 1 and 2 are solid.

## Scripts explicitly out of scope

These appeared in the book research but are cut from v1:

- **Desktop/OS X tooling** (from Wicked Cool Shell Scripts) — not relevant.
- **Bash pedagogical helpers** (regex tester, loop template, function wrapper
  from Vickler / PB) — these become examples in `linux-bash-scripting/references/`
  rather than standalone binaries.
- **`sk-text-processing` skill cluster** (sed/awk tools from SSB) — the idioms
  go into `linux-bash-scripting` docs; no standalone scripts needed.
- **GitHub user lookups, web page diff trackers, URL extractors** (from WCS) —
  hobby tooling, not server management.
- **RAID-specific scripts** — AIDE and `sk-audit` cover the monitoring need;
  mdadm/ZFS deep management deferred to a future v2.
- **Kubernetes tooling** — out of scope; if we go there, it becomes its own
  repo.
