# AIDE: file integrity monitoring

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

> `[GROUNDING-GAP: AIDE — grounded on upstream docs + CIS Benchmark PDFs;
> deepen on purchase]`
>
> AIDE is **absent from the book corpus** this engine is grounded on. The
> content below is authored from the AIDE upstream documentation
> (aide.github.io), the `aide(1)`/`aide.conf(5)` man pages, the Debian/Ubuntu
> `aide-common` packaging, and the file-integrity requirements in CIS
> Benchmark PDFs. Verify exact paths and the new-DB filename against your
> distro's packaged version before relying on them, and deepen with a
> book-grounded source when promoting this to fully-grounded.

AIDE (Advanced Intrusion Detection Environment) answers *which files have
changed since we last knew they were good?* It hashes every file in the
watched paths into a baseline database, then on each run compares the live
filesystem against that database and reports drift. It is the **drift** layer
of compliance auditing — pair it with **attribution** (`linux-auditd-rules`,
auditd) and **benchmark scoring** (`linux-benchmark-scanning`, OpenSCAP/Lynis).

## Table of contents

- [Packaging and paths: Debian vs RHEL](#packaging-and-paths-debian-vs-rhel)
- [Install and initialize](#install-and-initialize)
- [Tuning the config](#tuning-the-config)
- [Running a check](#running-a-check)
- [Reading the report](#reading-the-report)
- [Triage flow](#triage-flow)
- [Updating the baseline after legitimate changes](#updating-the-baseline-after-legitimate-changes)
- [Scheduling nightly checks](#scheduling-nightly-checks)
- [Storing the baseline DB safely off-box](#storing-the-baseline-db-safely-off-box)
- [Sources](#sources)

---

## Packaging and paths: Debian vs RHEL

The two families wrap AIDE quite differently — this is the main portability
gotcha.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Package | `aide aide-common` | `aide` |
| Config | `/etc/aide/aide.conf` + `/etc/aide/aide.conf.d/` drop-ins | single `/etc/aide.conf` |
| Regenerate config | `update-aide.conf` (assembles drop-ins) | edit `/etc/aide.conf` directly |
| Build baseline | `aideinit` (helper wrapper) | `aide --init` |
| New DB written to | `/var/lib/aide/aide.db.new` | `/var/lib/aide/aide.db.new.gz` |
| Trusted DB | `/var/lib/aide/aide.db` | `/var/lib/aide/aide.db.gz` |

On Debian the helper scripts hide the raw `aide --init`; on RHEL you call AIDE
directly and the DB is gzip-compressed (note the `.gz` suffix).

---

## Install and initialize

> **Critical:** run the init on a server you *know* is clean — right after
> provisioning, before it is ever exposed to the internet. Initialising on a
> compromised server just baselines the compromise as "normal."

```bash
# Debian/Ubuntu
sudo apt install aide aide-common
sudo aideinit                  # 1-10 min depending on server size
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# RHEL family
sudo dnf install aide
sudo aide --init
sudo cp /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
```

The Debian package installs:

- `/usr/bin/aide` — the checker binary.
- `/etc/aide/aide.conf` — the main config.
- `/etc/aide/aide.conf.d/` — drop-in snippets `update-aide.conf` assembles.
- `/var/lib/aide/aide.db` — the trusted baseline (after init).

### Smoke test

```bash
sudo aide --check
# Expected: "AIDE found NO differences between database and filesystem."

sudo touch /etc/test-aide
sudo aide --check                 # should report /etc/test-aide as added
sudo rm /etc/test-aide
```

---

## Tuning the config

### Rule syntax

A rule line pairs a path with a named check group:

```
/etc/ssh/    NORMAL
!/var/log/mail.log
/var/log/    Logs
```

- **`/path`** — the directory or file to watch.
- **`GroupName`** — a named set of checks. Common groups:
  - `NORMAL` — permissions, owner, group, size, mtime, ctime, hashes.
  - `Logs` — perms and owner only (logs rotate and grow legitimately).
  - `ConfFiles` — content must not change; strict.
  - `DataDir` — dirs; structure, not every file.
- **`!/path`** — **ignore** this path (the `!` prefix).
- **`=path`** — check only this directory, not recursively.

### Define your own group (Debian drop-in)

```bash
sudo tee /etc/aide/aide.conf.d/99-linux-skills > /dev/null <<'EOF'
# Strict group for content-critical files
ContentStrict = p+u+g+n+s+b+m+c+sha256

# Loose group for directories that legitimately change
Structure = p+u+g+ftype

# Identity, auth, SSH, sudo
/etc/ssh/sshd_config ContentStrict
/etc/ssh/sshd_config.d/ ContentStrict
/etc/sudoers ContentStrict
/etc/sudoers.d/ ContentStrict
/etc/passwd ContentStrict
/etc/shadow ContentStrict
/etc/group ContentStrict
/etc/gshadow ContentStrict

# Service config
/etc/nginx/ ContentStrict
/etc/apache2/ ContentStrict
/etc/php/ ContentStrict
/etc/mysql/ ContentStrict

# System binaries — hash drift here is the canary for a trojaned binary
/usr/bin/ ContentStrict
/usr/sbin/ ContentStrict
/usr/local/bin/ ContentStrict
/usr/local/sbin/ ContentStrict
/bin/ ContentStrict
/sbin/ ContentStrict

# Web root: structure only — content changes legitimately on deploy
/var/www/ Structure

# Logs: perms/owner only
/var/log/ Logs

# Ignore dynamic files that would flag every run
!/var/log/journal
!/var/log/wtmp
!/var/log/btmp
!/var/log/lastlog
!/var/log/nginx/access.log
!/var/log/nginx/error.log
!/var/log/apache2/access.log
!/var/log/apache2/error.log
!/var/log/mysql/
!/var/lib/php/sessions
!/var/cache
!/var/tmp
!/tmp
!/run
!/proc
!/sys
!/dev
EOF

sudo update-aide.conf
```

On the RHEL family, paste the same group definitions and rules directly into
`/etc/aide.conf` (no `update-aide.conf` step; adjust paths — `/etc/httpd/`
instead of `/etc/apache2/`).

### Validate the config

```bash
# Debian
sudo aide --config=/var/lib/aide/aide.conf --config-check
# RHEL
sudo aide --config=/etc/aide.conf --config-check
```

---

## Running a check

```bash
sudo aide --check
```

### Exit codes

| Code | Meaning |
|---|---|
| `0` | No differences. |
| `1..15` | Differences found (the bitmask indicates which categories). |
| `16..255` | AIDE error (config, I/O, missing database). |

### Quiet mode (cron) and single-path checks

```bash
sudo aide --check --log-level=warning
sudo aide --check --limit='^/etc/ssh'
```

---

## Reading the report

```
AIDE found differences between database and filesystem!!

Summary:
  Total number of entries:      24817
  Added entries:                1
  Removed entries:              0
  Changed entries:              3

Added entries:
f++++++++++++++++: /etc/test-aide

Changed entries:
f   ...    .C.. : /etc/ssh/sshd_config
f   ...    .C.. : /etc/sudoers
f>  s...    .C.. : /var/log/wtmp
```

### Decoding the flag string (`f   ...    .C..`)

Each column is a check result:

- `f` — file type (here: regular file); `d` directory, `l` symlink.
- `+` added · `-` removed · `.` unchanged.
- `C` content (hash) changed · `p` perms · `u` owner · `g` group ·
  `s` size · `m` mtime · `c` ctime.

The column order is group-dependent — read the legend at the top of the
report.

---

## Triage flow

1. **Hash change in `/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`,
   `/usr/local/bin`, `/usr/local/sbin`** → **CRITICAL.** Assume compromise.
   Compare against a fresh copy from the package:
   ```bash
   # Debian
   dpkg -S /usr/bin/ssh
   debsums /usr/bin/ssh           # if debsums installed
   # RHEL family
   rpm -qf /usr/bin/ssh
   rpm -V openssh-clients         # verify against package manifest
   ```
   If they differ, the binary was replaced — move to incident response, and
   pull auditd to find who/when (`ausearch -f /usr/bin/ssh -i`).

2. **Change to `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`,
   `/etc/ssh/sshd_config`** → **HIGH.** Correlate with auditd
   (`linux-auditd-rules`) to find *who*.

3. **`/etc/nginx/`, `/etc/php/`, `/etc/mysql/`** → **MEDIUM.** Usually a
   deploy/config update. Confirm with the deployer, then accept the baseline.

4. **`/var/www/`** → expected on deploy. In `Structure` mode only structure
   changes report; more means reconfigure or investigate.

5. **`/var/log/`** → should be filtered by `!` rules. Still seeing log noise?
   refine the ignore list.

---

## Updating the baseline after legitimate changes

```bash
# Debian/Ubuntu
sudo aideinit
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# RHEL family
sudo aide --update
sudo cp /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

sudo aide --check        # expect: no differences
```

Record every accepted update so you know which changes were blessed:

```bash
echo "$(date -Iseconds) aide baseline updated after nginx upgrade" \
    | sudo tee -a /var/log/linux-skills/aide-baseline-updates.log
```

---

## Scheduling nightly checks

### cron (portable)

```bash
sudo tee /etc/cron.daily/aide-check > /dev/null <<'EOF'
#!/bin/bash
set -u
REPORT=$(aide --check 2>&1 || true)
if echo "$REPORT" | grep -q "found differences"; then
    echo "$REPORT" | mail -s "AIDE Report $(hostname) $(date +%Y-%m-%d)" root
fi
EOF
sudo chmod +x /etc/cron.daily/aide-check
sudo /etc/cron.daily/aide-check        # test
```

### systemd timer (alternative)

```bash
sudo tee /etc/systemd/system/aide-check.service > /dev/null <<'EOF'
[Unit]
Description=AIDE file integrity check
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'aide --check 2>&1 | mail -s "AIDE $(hostname)" root'
EOF
sudo tee /etc/systemd/system/aide-check.timer > /dev/null <<'EOF'
[Unit]
Description=Daily AIDE check
[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now aide-check.timer
sudo systemctl list-timers aide-check.timer
```

### Alert only on critical paths

If nightly reports are too noisy, filter for the paths that matter:

```bash
aide --check 2>&1 \
  | grep -E '^(f|d).*: /(etc|bin|sbin|usr/bin|usr/sbin|usr/local/bin|usr/local/sbin)' \
  | mail -s "AIDE CRITICAL $(hostname)" ops@example.com
```

Ensure an MTA (`msmtp` or similar) delivers root mail somewhere a human
reads — see `linux-mail-server`.

---

## Storing the baseline DB safely off-box

The trusted DB is the root of trust. An attacker who modifies a binary **and**
rewrites `/var/lib/aide/aide.db` produces a clean check — so the DB must live
where the host's root cannot silently edit it.

Options, roughly in order of strength:

1. **Copy off-box after every (re)baseline.** Push the DB to a separate,
   restricted host and compare a fresh local DB against it before trusting a
   check:
   ```bash
   sudo scp /var/lib/aide/aide.db.gz backup@vault:/aide/$(hostname)-$(date +%F).db.gz
   ```
2. **Read-only / immutable media.** Burn the DB to read-only storage, or set
   the immutable attribute so even root must clear it first:
   ```bash
   sudo chattr +i /var/lib/aide/aide.db        # root must chattr -i to alter
   ```
3. **Sign the DB** and verify the signature before a check, keeping the
   signing key off the host.

At minimum, restrict the DB to root and log every legitimate update (see
above) so an unexpected DB change is itself a signal.

---

## Sources

- AIDE upstream documentation: https://aide.github.io/
- Man pages: `aide(1)`, `aide.conf(5)`.
- Debian/Ubuntu `aide-common` packaging (`aideinit`, `update-aide.conf`,
  `/etc/aide/aide.conf.d/`).
- CIS Benchmark PDFs — file-integrity-monitoring control requirements (the
  source for the strict path list and off-box-DB guidance).
- `[GROUNDING-GAP: AIDE — grounded on upstream docs + CIS Benchmark PDFs;
  deepen on purchase]`
