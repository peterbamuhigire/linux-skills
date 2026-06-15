# Threat Model — Ubuntu/Debian Web Server

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

The threat model that sits behind the 10-layer security analysis. This file
describes the typical attack surface of a public Ubuntu/Debian server
running Nginx + PHP-FPM + MySQL/MariaDB + Redis, applies STRIDE to each
layer, calls out what this skill can detect versus what it can't, and
prioritizes findings by real-world exploitability rather than theoretical
risk. Read this before you tell an operator a CRITICAL is urgent — or
before you wave off a LOW.

## Table of contents

- [The system we are protecting](#the-system-we-are-protecting)
- [Assumptions and trust boundaries](#assumptions-and-trust-boundaries)
- [Attack surface inventory](#attack-surface-inventory)
- [STRIDE applied to the stack](#stride-applied-to-the-stack)
- [What this skill detects — and what it doesn't](#what-this-skill-detects--and-what-it-doesnt)
- [Prioritization: CRITICAL in theory vs in practice](#prioritization-critical-in-theory-vs-in-practice)
- [Attack chains seen in the wild](#attack-chains-seen-in-the-wild)
- [Sources](#sources)

## The system we are protecting

The canonical host this threat model targets:

```
Internet
  |
  | 22/tcp, 80/tcp, 443/tcp
  v
+-----------------------------+
| Ubuntu 22.04 / 24.04 server |
|                             |
|  nginx  (80, 443)           |
|  php-fpm (unix socket)      |
|  mysql  (127.0.0.1:3306)    |
|  redis  (127.0.0.1:6379)    |
|  fail2ban + auditd          |
|  ufw (deny incoming)        |
|  sshd (22, key only)        |
|                             |
|  /var/www/html              |
|  /var/backups (encrypted)   |
+-----------------------------+
  |
  | rclone push (HTTPS)
  v
Off-host object storage (gdrive / B2 / S3)
```

Any deviation from this shape — a second exposed port, a second database, a
Docker bridge that leaks to the host, a dev tool listening on `0.0.0.0` —
expands the attack surface and should be surfaced during the audit.

## Assumptions and trust boundaries

**Assume true (your baseline):**

- The operator owns SSH and root. An attacker does not yet.
- The internet routes packets to ports 22, 80, and 443 of this host.
- The web app is multi-tenant or at least serves untrusted users over HTTP.
- Backups live off-host on storage the attacker does not control.

**Trust boundaries — where attacker-controlled data crosses privilege:**

1. **Internet → Nginx**: every header, URI, cookie, and request body is
   attacker-controlled. Nginx terminates TLS and must not leak anything.
2. **Nginx → PHP-FPM**: inputs flow through as FastCGI variables. PHP runs
   as `www-data`. Untrusted data becomes `$_GET`, `$_POST`, `$_COOKIE`.
3. **PHP-FPM → MySQL/Redis**: the web app builds queries. This boundary
   bleeds via SQL injection or unsafe Redis `EVAL`.
4. **www-data → root**: every SUID binary, every cron job running as root
   that touches files `www-data` can write, every systemd unit with
   `NoNewPrivileges=no` — these are privilege escalation bridges.
5. **Operator workstation → sshd**: SSH keys, passphrases, and
   `known_hosts` entries defend this boundary.
6. **Host → off-host backup**: `rclone.conf` or S3 credentials. If these
   leak, the attacker can also wipe backups.

Any control that spans two of these boundaries with no check is a
vulnerability in waiting.

## Attack surface inventory

### Exposed services

| Port   | Service    | Who can reach it | What goes wrong                        |
|--------|------------|------------------|----------------------------------------|
| 22     | sshd       | Everyone         | Brute force, leaked key, weak KEX      |
| 80     | nginx HTTP | Everyone         | Redirect must go to 443, not serve app |
| 443    | nginx TLS  | Everyone         | Cert issues, weak TLS, webapp RCE      |
| 3306   | MySQL      | 127.0.0.1 only   | CRITICAL if ever on 0.0.0.0            |
| 6379   | Redis      | 127.0.0.1 only   | CRITICAL if ever on 0.0.0.0 no auth    |
| 25/465/587 | Postfix | 127.0.0.1 only  | Open relay, spam source                |

Every other listener on the box is a finding until proven otherwise.

### Authentication surface

- **SSH keys** in `~/.ssh/authorized_keys` — the master key to the host.
- **Sudoers entries** — anyone with sudo is effectively root.
- **Webapp login form** — usually the single highest-volume brute force
  target, guarded by fail2ban + rate limits at Nginx.
- **MySQL users** — especially `root@localhost` and any `user@%`.
- **Redis `requirepass`** — the only thing between a `FLUSHALL` and your
  data if Redis is ever reachable.
- **Cloud provider panel** — out of scope for this threat model, but if it
  falls the attacker gets the VM.

### Web app layer

- Input vectors: query string, path, form body, JSON body, cookies,
  headers (User-Agent, Referer, X-Forwarded-For).
- File upload endpoints — every one is a potential RCE if the uploaded
  file lands under a path Nginx will execute as PHP.
- Session tokens — must be `HttpOnly`, `Secure`, and `SameSite=Lax|Strict`.
- CSRF surface — any state-changing request missing an anti-CSRF token.
- Server-side template injection — Twig, Blade, Smarty all have history.

### Database

- Unparameterized queries → SQL injection → data exfiltration → RCE via
  `INTO OUTFILE` if `secure_file_priv` is empty.
- Anon/empty-password accounts (`''@'localhost'`).
- `root@%` granting root access from anywhere.
- User-defined functions (UDFs) that wrap shell commands.

### Backups

- Backup files stored on the same host that was just compromised — useless.
- Unencrypted backups on shared cloud buckets — data breach waiting.
- Backup credentials on the web server — if the server falls, the attacker
  reaches into backups and deletes them (ransomware pattern).

### Supply chain (packages, PPAs, scripts)

- Third-party PPAs pull unverified debs into the install path.
- `curl | bash` installers that run as root and leave behind cron jobs.
- NPM/Composer/PyPI dependencies with post-install scripts.
- Container images pulled with `:latest` tag and never rebuilt.

## STRIDE applied to the stack

**STRIDE** = Spoofing, Tampering, Repudiation, Information disclosure,
Denial of service, Elevation of privilege. For each, the concrete
expression on this stack and the primary defense:

### Spoofing identity

| Manifestation | Defense |
|---|---|
| Brute force SSH password | Key-only auth, fail2ban, AllowUsers |
| Stolen web session cookie | `Secure`, `HttpOnly`, `SameSite`, short expiry |
| Forged source IP on DB port | Bind to 127.0.0.1, rp_filter, firewall |
| Phishing an operator for SSH key passphrase | Hardware token, passphrase, separate break-glass key |
| Expired/revoked TLS cert replaced with rogue | HSTS preload, certbot auto-renewal |

### Tampering with data

| Manifestation | Defense |
|---|---|
| SQL injection | Parameterized queries, least-privilege DB users |
| Local file write via path traversal | `open_basedir`, canonicalize paths |
| Attacker overwrites a PHP file in `/var/www` | File perms 644, write only for deploy user, AIDE |
| Attacker tampers with logs to hide tracks | Remote log shipping, append-only with `chattr +a` |
| Backup tampered so restore reinstalls a backdoor | Encrypted, signed, off-host, tested restores |

### Repudiation

| Manifestation | Defense |
|---|---|
| "It wasn't me" — no way to trace action to user | auditd with uid tracking, sudo logging, remote log sink |
| Web app has no audit log of privileged admin actions | App-level audit log to a separate DB, signed entries |

### Information disclosure

| Manifestation | Defense |
|---|---|
| PHP error page leaks `/var/www/html/database.php` path | `display_errors=Off`, `log_errors=On`, custom 500 page |
| `server_tokens on` reveals Nginx version | `server_tokens off`; PHP `expose_php=Off` |
| `/etc/shadow` world-readable | 640 root:shadow |
| Backup file browsable at `https://host/backup.sql.gz` | Never store backups in webroot; deny dotfiles and `*.sql*` |
| Git history exposed at `/.git/` | Nginx location block blocking `/\.git` |
| Directory listing turned on | `autoindex off` |

### Denial of service

| Manifestation | Defense |
|---|---|
| SYN flood exhausts sockets | `net.ipv4.tcp_syncookies=1`, SYN cookies |
| PHP-FPM worker exhaustion | `pm.max_children` sized to RAM, rate limit at Nginx |
| Slowloris | Nginx `client_body_timeout`, `client_header_timeout`, `send_timeout` |
| Redis `FLUSHALL` wipe | Rename dangerous commands, require password |
| Log disk fill wiping journal | logrotate, `journald SystemMaxUse=` |

### Elevation of privilege

| Manifestation | Defense |
|---|---|
| RCE as `www-data` → cron job running as root touches `/var/www` | Never script root cron to process files writable by www-data |
| RCE as `www-data` → SUID binary in `/tmp` | `noexec` on `/tmp` mount, SUID audit |
| User with sudo NOPASSWD on `vi` → `:!sh` → root | Whitelist exact commands in sudoers, not editors |
| Kernel LPE via unpatched CVE | Timely patches, unattended-upgrades with auto-reboot window |
| AppArmor profile in complain mode | Put profiles in enforce, monitor DENIED in kern.log |

## What this skill detects — and what it doesn't

**This skill (`linux-security-analysis`) detects:**

- Misconfiguration at the OS, kernel, network, firewall, web server,
  database, and file-permission layers.
- Missing security controls (no fail2ban, no AIDE, no auditd).
- Pending security updates and unreachable backup targets.
- Dangerous defaults left on (expose_php, display_errors, test DB).
- Accounts without passwords, duplicate UIDs, SUID sprawl.
- TLS certificate expiry and accepted protocol versions.

**This skill explicitly does NOT detect:**

- **Application-layer vulnerabilities** (SQL injection, XSS, CSRF, IDOR,
  SSRF, broken access control). That is the job of a web app scanner
  (OWASP ZAP, Burp, sqlmap) or a WAF in front of the site.
- **Zero-days**. If the CVE is not yet in the Ubuntu security feed,
  `apt list --upgradable` will not warn.
- **Malware** already installed as root. For that use `chkrootkit`, `rkhunter`,
  `debsums`, and AIDE baseline comparison. This skill covers the
  prerequisites (AIDE installed, auditd rules loaded), not the scan result.
- **Compromised upstream packages** (supply chain). If an attacker ships a
  backdoor through a legit PPA, `apt` will cheerfully install it.
- **Insider threats**. An operator with sudo can do anything. This skill
  verifies the sudoers file is not obviously permissive, nothing more.
- **Physical attacks**. Cold-boot on an unencrypted disk, console access,
  USB rubber ducky. Call FDE, BIOS password, and physical security.
- **Cloud control plane misconfiguration**. If the cloud provider's IAM
  lets an attacker detach your disk, this skill cannot see that.

Draw the line clearly in the report. "We looked for the things we look
for. Here are the ones we don't."

## Prioritization: CRITICAL in theory vs in practice

Not every CRITICAL is created equal. When prioritizing findings for an
operator who has limited time, order them by what attackers actually
exploit, not by raw CVSS.

### Top 5 that get exploited in the wild, every time

1. **Redis bound to 0.0.0.0 with no password.** There is a botnet
   (`RedisWannaMine` lineage) whose sole job is scanning for this. Typical
   time to compromise after exposing such an instance: **under 5 minutes**.
   If you find this, unplug the network cable first, then fix. Treat as a
   breach until proven otherwise.

2. **MySQL/MariaDB on 0.0.0.0 with weak `root` password.** Same pattern.
   Credential stuffing kicks in within hours. Data exfil follows in days.

3. **SSH with `PasswordAuthentication yes` and no fail2ban.** Brute force
   will succeed eventually if any user has a weak password. Observed
   success against an 8-char alphanumeric password in under 2 weeks.

4. **PHP `display_errors=On` + any SQL injection.** The error page reveals
   the database path and often leaks credentials from an echoed PDO DSN. A
   scanner that otherwise wouldn't find anything now has a map.

5. **File upload with no MIME/extension whitelist under a path Nginx
   executes as PHP.** The classic PHP webshell drop. Months pass undetected
   because the file is tiny and mimics legitimate site files.

### Top 5 CRITICALs that are more theoretical than practical

1. **`kernel.kptr_restrict=0`** — helps exploit writers, but nobody owns a
   box through this alone. Fix it, but don't panic.

2. **`X11Forwarding yes` on a server with no X11 installed.** It's a LOW
   in practice. The attacker needs to already have a shell.

3. **`kernel.sysrq=1`**. Physical console only.

4. **No GRUB password.** Physical attack.

5. **An unknown SUID under `/usr/libexec/`.** Almost always a legitimate
   distro binary you didn't know about. Check with `dpkg -S` before raising
   the alarm.

### What matters more than severity

For every CRITICAL, ask:

- **Is it network-reachable right now?** Redis on `127.0.0.1` without a
  password is merely MEDIUM. Redis on `0.0.0.0` without a password is
  CRITICAL and immediate.
- **Is there a public exploit?** Check the CVE feed. "CVE with PoC" is a
  different story from "CVE disclosed last week".
- **Does the attacker already have to be local?** Local-only CRITICALs
  become HIGHs unless the box has multiple users.
- **Is anything monitoring for attempts?** A hardened-but-unexpected
  finding on a host with auditd + remote logging is less urgent than the
  same finding on a silent host.

This triage — network reach × exploit availability × monitoring coverage —
is more honest than severity alone.

## Attack chains seen in the wild

Real campaigns combine low-severity findings into a compromise. A few
patterns worth teaching:

**Chain 1 — Redis wipe via SSRF**
1. App has SSRF (low priority finding, not in scope here).
2. Attacker makes the app open `http://127.0.0.1:6379/CONFIG SET dir /var/www/html`.
3. Redis on `127.0.0.1` with no password happily obeys.
4. Attacker writes a webshell to `/var/www/html/shell.php`.
5. Game over.

Our audit catches step 3 (Redis no password). The app bug is invisible to us.

**Chain 2 — PHP info leak → SSH user enum → brute force**
1. `phpinfo.php` left in webroot reveals `/home/deploy` path.
2. Attacker now knows the deploy user exists.
3. `PasswordAuthentication yes` + no `AllowUsers` limit.
4. fail2ban tuned too leniently (`maxretry = 10`).
5. Password eventually falls.

Our audit catches steps 3 and 4. We don't see step 1 unless we also probe
the site, which this skill does not.

**Chain 3 — Deploy key → source code → RCE**
1. `~/.ssh/id_ed25519` on the web server, no passphrase.
2. Backup credentials stored in `deploy@git:~/.config/rclone/rclone.conf`
   mode 644 (should be 600).
3. Attacker with `www-data` reads the key and the config.
4. Pulls source from private repo, finds an endpoint with a hardcoded
   admin token.
5. Owns the app.

Our audit catches step 2 (mode 644 credentials). The rest is the operator's
deployment pipeline.

## Sources

- *Mastering Linux Security and Hardening*, Donald A. Tevault, 3rd Edition,
  Packt Publishing — Chapter 1 threat landscape, Chapter 12 scanning and
  auditing, Chapter 14 vulnerability scanning and IDS.
- *Practical Linux Security Cookbook*, Tajinder Kalsi, Packt Publishing —
  real-world recipe for post-compromise triage and baseline auditing.
- *Ubuntu Server Guide*, Canonical — "Security" chapter on trust
  boundaries, users and groups, console, updates, and AppArmor.
- Microsoft STRIDE threat modeling methodology (Howard & Lipner, *The
  Security Development Lifecycle*, 2006) — the STRIDE categories and their
  mapping to web-stack concerns.
- OWASP Top 10 (2021) — used as the canonical list of application-layer
  vulnerabilities explicitly outside the scope of this skill.
- MITRE ATT&CK for Linux — used for the real-world attack chain examples.
